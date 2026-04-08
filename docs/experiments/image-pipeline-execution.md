# Image Pipeline Experiment Runbook

## 개요

이 문서는 이미지 처리 아키텍처 실험의 실제 실행 순서를 정리한 runbook이다.
구현, 인프라 적용, 실험 수행, 결과 기록, 태그 생성은 이 순서를 따른다.

참조 문서:

- [image-pipeline-evolution.md](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/image-pipeline-evolution.md)
- [observability.md](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/observability.md)
- [infra/terraform/README.md](/home/cho/projects/3-logan-cho-community-BE/infra/terraform/README.md)

## 디렉토리 기준

```text
docs/
└─ experiments/
   ├─ image-pipeline-evolution.md
   ├─ image-pipeline-execution.md
   ├─ results/
   │  ├─ exp-v1-sync/
   │  ├─ exp-v2-async/
   │  ├─ exp-v3-outbox/
   │  └─ exp-v4-idempotent/
   └─ checklists/
      ├─ pre-run.md
      └─ fixed-conditions.md
```

## 단계별 실행 흐름

### 0. 실험 브랜치 준비

1. `origin/develop` 기준으로 실험 브랜치 생성
2. 브랜치명은 `experiment/image-pipeline-evolution`
3. 실험 관련 구현, Terraform, k6 스크립트, 실험 문서는 이 브랜치에서만 누적 관리

참고:
- 현재 작업 중간에는 하위 기능 브랜치를 사용할 수 있다
- 단, 실험 기준점은 항상 `experiment/image-pipeline-evolution`에 모인다

### 1. v1 구현 및 실험

구현 범위:

- temp 업로드 prefix
- 동기 이미지 압축
- 썸네일 생성
- 최소 상태 필드
- 기본 관측 포인트

실험:

- `Medium / 10 RPS steady`
- `Heavy / 20 RPS steady`
- `5 -> 30 RPS burst`

결과 기록:

- `POST /posts p95`
- `API error rate`
- `Spring CPU`

메트릭 해석:

- 주 비교는 `k6` 결과 파일 기준 `성공률`과 `응답시간`
- `Spring CPU`와 EC2 메트릭은 Prometheus/Grafana에서 필요 시 확인

완료 후:

- 결과를 `docs/experiments/results/exp-v1-sync/`에 저장
- 태그 `exp-v1-sync` 생성

### v1 반복 실행 스크립트

`v1`은 아래 스크립트로 반복 실행한다.

- `scripts/experiments/v1/publish-app-artifacts.sh`
  - Spring Boot JAR 빌드
  - App 실행용 env 스크립트 생성
  - 실험용 S3 bucket `artifacts/` prefix 업로드
- `scripts/experiments/v1/deploy-app.sh`
  - App EC2에 JAR 배포
  - MySQL/Mongo/Redis 로컬 컨테이너 기동
  - `java -jar`로 Spring 앱 기동
  - `/api/health` readiness 확인
- `scripts/experiments/v1/reset-state.sh`
  - MySQL `millions` DB 재생성
  - Mongo `millions` DB 초기화
  - 실험용 S3 prefix 정리
- `scripts/experiments/v1/bootstrap-access-token.sh`
  - 테스트 회원가입
  - 로그인
  - k6에서 사용할 access token 발급
- `scripts/experiments/v1/run-k6.sh`
  - k6 EC2에서 `presigned -> upload -> POST /posts` 시나리오 실행
  - 결과를 `docs/experiments/results/exp-v1-sync/k6/`에 저장
- `Spring CPU`
  - `scripts/experiments/v1/*`에서 직접 수집하지 않는다
  - `Prometheus + Grafana`에서 동일 대시보드 기준으로 캡처한다

예시:

```bash
scripts/experiments/observability/setup.sh
scripts/experiments/v1/publish-app-artifacts.sh
scripts/experiments/v1/deploy-app.sh
scripts/experiments/v1/reset-state.sh
ACCESS_TOKEN="$(scripts/experiments/v1/bootstrap-access-token.sh)"
ACCESS_TOKEN="${ACCESS_TOKEN}" SCENARIO=smoke scripts/experiments/v1/run-k6.sh
```

### 2. v2 구현 및 실험

구현 범위:

- SQS 추가
- Lambda 추가
- Spring 요청 경로에서 이미지 처리 제거

실험:

- v1과 동일 시나리오 재사용
- completion latency 측정 추가

결과 기록:

- `POST /posts p95`
- `API error rate`
- `Spring CPU`
- `image completion latency p95`
- `SQS oldest message age`

완료 후:

- 결과를 `docs/experiments/results/exp-v2-async/`에 저장
- 태그 `exp-v2-async` 생성

### 3. v3 구현 및 실험

구현 범위:

- Transactional Outbox
- 앱 내부 relay

실험:

- direct publish 실패 주입
- relay 지연/중단 재현

결과 기록:

- `orphan pending post count`
- `lost job count`

완료 후:

- 결과를 `docs/experiments/results/exp-v3-outbox/`에 저장
- 태그 `exp-v3-outbox` 생성

### 4. v4 구현 및 실험

구현 범위:

- idempotent consumer
- DLQ
- processed jobs 저장소

실험:

- duplicate delivery
- poison message
- DLQ 이동 및 재처리

결과 기록:

- `duplicate side effect count`
- `DLQ count`

완료 후:

- 결과를 `docs/experiments/results/exp-v4-idempotent/`에 저장
- 태그 `exp-v4-idempotent` 생성

## 실험 전 체크리스트

아래 항목은 모든 실험 전에 수행한다.

- Mongo 테스트 데이터 정리
- outbox 컬렉션 정리
- processed jobs 컬렉션 정리
- SQS queue 비우기
- S3 실험용 prefix 정리
- App EC2, k6 EC2 스펙 재확인
- Java 버전, JVM 옵션 재확인
- 테스트 이미지 세트 확인
- 압축 정책 확인

## 고정 조건 체크리스트

아래 항목은 실험 도중 바꾸지 않는다.

- 리전
- App EC2 타입
- k6 EC2 타입
- Mongo 환경
- 테스트 이미지 세트
- 이미지 압축 정책
- k6 시나리오 정의
- Lambda memory/timeout/concurrency/batch size/runtime
- SQS queue type/visibility timeout/retention

## 결과 저장 규칙

실험 결과는 태그명 기준으로 저장한다.

예시:

```text
docs/experiments/results/
├─ exp-v1-sync/
│  ├─ summary.md
│  ├─ k6/
│  ├─ metrics/
│  └─ screenshots/
├─ exp-v2-async/
├─ exp-v3-outbox/
└─ exp-v4-idempotent/
```

각 버전 디렉토리에는 최소 아래를 남긴다.

- 요약 문서
- k6 raw 결과
- 핵심 지표 캡처
- 실험 환경 정보
- 태그명

## Git 실행 순서

```text
origin/develop
  -> experiment/image-pipeline-evolution
     -> v1 구현 / 실험 / exp-v1-sync
     -> v2 구현 / 실험 / exp-v2-async
     -> v3 구현 / 실험 / exp-v3-outbox
     -> v4 구현 / 실험 / exp-v4-idempotent
```

원칙:

- 실험이 끝나도 바로 `develop`이나 `main`으로 merge하지 않는다
- fault injection, 임시 로그, 실험 전용 스크립트는 선별 정리 후 필요한 것만 `develop`에 반영한다
- 최종 안정 코드만 `main`에 반영한다

## 다음 작업 기준

앞으로 이미지 처리 관련 작업 요청을 받으면 아래 순서로 진행한다.

1. 현재 작업이 `v1/v2/v3/v4` 중 어느 단계인지 먼저 명시
2. 이 변경이 비교 변수 통제를 깨는지 확인
3. 코드 변경과 Terraform 변경이 필요한지 분리
4. 실험 전 초기화 항목과 결과 저장 위치를 함께 정리
5. 완료 시 태그 대상인지 확인
