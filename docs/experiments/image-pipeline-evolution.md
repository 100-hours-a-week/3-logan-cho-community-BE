# Image Pipeline Evolution Charter

## 목적

이 문서는 이미지 처리 아키텍처 실험의 기준 문서다.
앞으로 관련 구현, 인프라 변경, 성능 측정, Git 운영은 이 문서를 기준으로 수행한다.

핵심 목적은 운영 서비스 배포가 아니라 아래를 재현 가능하게 증명하는 것이다.

- 동기 처리의 한계를 통제된 환경에서 정량 측정
- 비동기 전환 후 드러나는 정합성 문제를 실험으로 확인
- Transactional Outbox, idempotent consumer, DLQ로 안정성을 단계적으로 보강
- Terraform 기반 인프라와 Git 태그 기반 코드 버전으로 실험 재현성 확보

## 실험 단계

실험은 아래 순서로 순차 개선한다.

1. `v1`: 동기 방식
2. `v2`: 비동기 방식
3. `v3`: 비동기 안정화 - Transactional Outbox
4. `v4`: 비동기 추가 안정화 - idempotent consumer / DLQ

단계 간 비교에서 한 번에 바꾸는 핵심 변수는 하나여야 한다.

- `v1 -> v2`: 동기 압축 / 비동기 압축 차이
- `v2 -> v3`: direct publish / outbox 차이
- `v3 -> v4`: 중복 처리 및 실패 격리 차이

## 전체 운영 원칙

- 실험의 핵심은 구조 변화에 따른 효과 비교다.
- main, dev 브랜치는 실험 코드로 오염시키지 않는다.
- 환경은 단순하고 재현 가능해야 한다.
- 처음부터 다중 인스턴스, ALB, 오토스케일링 같은 운영형 구성을 도입하지 않는다.
- 인프라는 Terraform으로 관리한다.
- 오버엔지니어링을 피하고, 해당 단계 실험에 필요한 수준까지만 구성한다.
- EC2/애플리케이션 메트릭 수집 방식은 `Prometheus + Grafana`로 고정한다.

## 단계별 인프라 기준

### 공통 기본 구성

- Spring Boot 애플리케이션: EC2 단일 인스턴스
- k6 부하 발생기: 별도 EC2 단일 인스턴스
- MongoDB: 고정된 동일 환경 사용
- S3: 동일 버킷 사용 가능, 단 prefix는 버전별/실험별 분리
- 모든 리소스는 동일 리전 사용
- App EC2, k6 EC2, Mongo 환경은 버전 간 고정
- Prometheus, Grafana도 버전 간 동일 배치 원칙을 유지

### v1

- App EC2 1대
- k6 EC2 1대
- MongoDB
- S3
- SQS 없음
- Lambda 없음

목적:
- Spring이 요청 경로에서 이미지 압축/업로드를 직접 수행할 때 `POST /posts p95`, `Spring CPU`, `API error rate` 측정

### v2

- v1 환경 유지
- SQS Standard Queue 추가
- Lambda 추가

목적:
- 이미지 처리를 요청 경로에서 제거했을 때 `POST /posts p95`, `Spring CPU`, `completion latency` 특성 측정

### v3

- v2 환경 유지
- MongoDB 내부에 outbox 저장 구조 추가
- relay는 별도 서버를 두지 않고 Spring 애플리케이션 내부 스케줄러 또는 동일 앱 내부 컴포넌트로 구현

목적:
- 게시글 저장과 메시지 발행이 분리되며 발생하는 발행 누락 리스크를 줄이고 eventual publish 가능 여부 검증

### v4

- v3 환경 유지
- SQS DLQ 추가
- processed jobs 저장소를 MongoDB 컬렉션으로 추가

목적:
- at-least-once 전달 환경에서 중복 소비와 poison message를 안전하게 처리하는지 검증

## 버전 간 고정 조건

아래 항목은 버전 간 동일하게 유지한다.

- App EC2 타입
- k6 EC2 타입
- Java 버전
- JVM 옵션
- Spring 주요 설정
- MongoDB 환경
- 테스트 이미지 세트
- 이미지 압축 정책
- 테스트 시나리오
- AWS 리전
- S3 버킷 구조 원칙
- 메트릭 수집 스택

메트릭 수집 스택:

- Prometheus
- Grafana
- node_exporter
- Spring Actuator Prometheus endpoint

### Lambda 고정 조건

`v2 ~ v4`에서 아래 항목을 고정한다.

- memory
- timeout
- reserved concurrency
- batch size
- runtime

### SQS 고정 조건

`v2 ~ v4`에서 아래 항목을 고정한다.

- queue type
- visibility timeout
- retention

`v4`에서만 redrive 정책과 DLQ를 추가한다.
main queue 기본 조건은 유지한다.

## S3 규칙

- temp 이미지는 별도 temp prefix로 관리한다.
- 최종 이미지는 public prefix에 저장한다.
- temp 이미지는 S3 Lifecycle Rule로 정리되도록 Terraform에 포함한다.
- 버전/실험별 prefix를 분리해 실험 청소 범위가 명확해야 한다.

예시:

- `experiments/v1/temp/...`
- `experiments/v1/final/...`
- `experiments/v1/thumb/...`
- `experiments/v2/temp/...`

## 핵심 측정 지표

포트폴리오에 직접 사용할 핵심 지표만 수집한다.

### v1 / v2 공통

- `POST /posts p95`
- `API error rate`
- `Spring CPU`

수집 기준:

- `POST /posts p95`, `API error rate`: k6 raw 결과
- `Spring CPU`: Prometheus/Grafana

### v2 추가

- `image completion latency p95`
- `SQS oldest message age`

### v3 추가

- `orphan pending post count`
- `lost job count`

### v4 추가

- `duplicate side effect count`
- `DLQ count`

## 대표 실험 시나리오

아래 3개 시나리오만 대표로 사용한다.

1. `Medium / 10 RPS steady`
2. `Heavy / 20 RPS steady`
3. `5 -> 30 RPS burst`

공통 원칙:

- 각 시나리오는 최소 3회 반복
- 포트폴리오에는 p95 중심으로 정리
- 요청 latency와 completion latency는 분리 측정
- warm-up 구간과 본측정 구간을 분리

## Git 운영 전략

### 브랜치

`main`
- 최종 안정 코드만 유지
- 직접 커밋 금지
- 실험 중간 결과 merge 금지

`dev`
- 일반 제품 개발용 통합 브랜치
- 실험용 fault injection, 실험용 임시 로그, 실험용 스크립트 merge 금지

`experiment/image-pipeline-evolution`
- 이미지 처리 아키텍처 실험 전용 단일 브랜치
- `v1 -> v2 -> v3 -> v4`를 이 브랜치에서 순차적으로 누적 발전
- 단계별 체인 브랜치를 남발하지 않는다

### 태그

각 단계 실험 완료 시점에 아래 태그를 생성한다.

- `exp-v1-sync`
- `exp-v2-async`
- `exp-v3-outbox`
- `exp-v4-idempotent`

태그는 “이 코드 버전으로 실험했다”는 증거다.
포트폴리오 수치, 보고서, 스크린샷, 실험 로그는 반드시 태그 기준으로 연결한다.

### 이슈 운영

실험 추적을 위해 이슈는 아래 수준으로 관리한다.

- 상위 umbrella issue 1개
  - 전체 실험 목표, 산출물, 태그 목록, 비교 지표 관리
- 버전별 구현 issue 4개
  - `[Experiment/V1] Sync`
  - `[Experiment/V2] Async`
  - `[Experiment/V3] Outbox`
  - `[Experiment/V4] Idempotent-DLQ`
- 필요 시 인프라/실험 자동화 보조 issue
  - Terraform
  - k6
  - 실험 초기화 스크립트

원칙:

- 버전별 issue는 같은 실험 브랜치에서 해결한다
- 포트폴리오 보고서에는 issue 번호보다 태그를 기준점으로 사용한다

## Terraform 원칙

Terraform으로 아래 리소스를 관리한다.

- App EC2
- k6 EC2
- Security Group
- IAM Role / Instance Profile
- S3 Bucket과 lifecycle rule
- SQS Queue
- DLQ
- Lambda
- Lambda 실행 Role
- 필요한 CloudWatch Log Group
- 실험용 환경 변수 주입에 필요한 기본 구성

설계 원칙:

- `v1 ~ v4`를 하나의 공통 베이스 위에서 점진 확장 가능하게 구성
- 모듈은 과도하게 나누지 않는다
- 변수와 출력값은 실험 수행에 필요한 최소 수준만 둔다
- 버전별 리소스 구분이 가능하도록 이름을 명확히 짓는다

## 실험 전 초기화 원칙

모든 실험 실행 전에 아래를 정리한다.

- Mongo 테스트 데이터 정리
- outbox 컬렉션 정리
- processed jobs 컬렉션 정리
- SQS queue 비우기
- S3 실험용 prefix 정리

## 최종 산출물

반드시 아래 결과를 유지한다.

1. 전체 실험 환경 설명 문서
2. 단계별 인프라 구성 문서
3. Git 브랜치/태그 운영 문서
4. Terraform 디렉토리 구조 및 적용 가이드
5. 단계별 실험 실행 순서 문서
6. 실험 전 초기화 체크리스트
7. 단계별 고정 조건 목록
8. 포트폴리오용 핵심 지표 수집 계획
9. `v1 ~ v4` 태그 기준 비교 가능 구조 설명

## 작업 기준

앞으로 이미지 처리 아키텍처 관련 작업은 아래 순서로 판단한다.

1. 이 변경이 현재 버전 실험 목적에 직접 필요한가
2. 버전 간 비교 변수 통제를 깨지 않는가
3. main/dev를 오염시키지 않는가
4. Terraform과 실행 문서에 반영 가능한가
5. 태그 기준 재현이 가능한가

위 조건을 만족하지 않으면 구현 범위를 줄이거나 다음 버전으로 미룬다.
