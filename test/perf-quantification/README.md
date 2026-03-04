# 성능 정량화 실행 가이드 (Perf Quantification)

## 근본 목적

핵심 개선 실험 3개(01/03/05)를 동일 기준으로 재현 가능한 형태로 운영한다.

## 핵심 목적
핵심 개선 실험 3개를 같은 실행 체계에서 재현 가능한 방식으로 운영한다.
- `01` Next-Key Lock 범위 축소
- `03` 조회수 배치 반영 효과
- `05` Redis Pipeline (목록 조회 N+1 완화)

## 비목적
코드 리팩토링이나 인프라 변경 없이 계측 체계와 실행 스크립트만 유지한다.

`02`, `04`, `06` 스크립트는 보존되어 있으나 이번 실행에서는 기본 제외한다.

## 구성

```text
test/perf-quantification/
  ├─ README.md
  ├─ scripts/
  │  ├─ common.sh
  │  ├─ run-all.sh
  │  ├─ run-exp01-next-key-lock.sh
  │  ├─ run-exp03-view-counter-batch.sh
  │  ├─ run-exp05-redis-pipeline.sh
  │  ├─ run-exp02-mongo-vs-mysql.sh (보관)
  │  ├─ run-exp04-likes-benchmark.sh (보관)
  │  └─ run-exp06-image-cost.sh (보관)
  ├─ k6/
  │  ├─ common-workload.js
  │  ├─ post-workload.js
  │  └─ image-cost.js
  └─ results/
      ├─ 01/..
      ├─ 02/..
      ├─ 03/..
      ├─ 04/..
      ├─ 05/..
      └─ 06/..
```

## 실험 맵

| ID | 항목 | 실측 포인트 |
|---|---|---|
| `01` | Next-Key Lock 범위 축소 | MySQL 잠금 대기 및 insert 지연 |
| `03` | 조회수 배치 반영 효과 | MongoDB update 폭증/상세 p95 |
| `05` | Redis Pipeline | 목록 API p95, Redis commandstats |

## 실행 규칙

- 선행 설치: `k6`, `mysql`, `mongosh`, `redis-cli`, `node`
- 공통 실행 진입점: `scripts/run-all.sh`
- 기본 실행 대상: `RUN_EXPERIMENTS=01,03,05`
- 실험 환경 주의:
  - k6를 Docker로 실행할 때 `BASE_URL`은 `http://host.docker.internal:8080`로 설정해야 앱 접근이 가능
  - MongoDB 업데이트 계측은 `mongosh` 호출에서 `MONGO_URI=mongodb://127.0.0.1:27017` 사용 권장
  - Redis Pipeline A/B 분리는 동일 URL이어도 실행 가능하도록 `LIST_USE_PIPELINE_A/B`를 사용 (`true`/`false`)

```bash
cd test/perf-quantification
./scripts/run-all.sh
``` 

```bash
RUN_EXPERIMENTS="01,03" ./scripts/run-all.sh
```

## 실험별 지표 정의

### 01) Next-Key Lock
- 지표:
  - `Innodb_row_lock_waits`, `Innodb_row_lock_time`
  - 락 보유 중 insert 지연 평균/분위수
  - `information_schema.INNODB_LOCK_WAITS`, `INNODB_TRX`
- 실험 의도:
  - member_id 인덱스 유무에 따라 동시 탈퇴 트랜잭션과 insert 충돌이 완화되는지 정량 검증

### 03) 조회수 배치 반영
- 지표:
  - MongoDB `opcounters.update` 변화량
  - 상세 조회 p95
- 실험 의도:
  - 즉시 반영 vs 배치 반영 시 쓰기 폭증/응답 지연 차이 확인

### 05) Redis Pipeline
- 지표:
  - 목록 API p95
  - Redis `commandstats` 내 `mget`, `setex`
  - 요청 실패율(`http_req_failed rate`)
- 실험 의도:
  - N+1 구조 해소가 p95 및 redis 호출 횟수를 낮추는지 확인

## 결과 파일 규칙

각 실험 산출 폴더에는 최소 아래 파일을 남긴다.

- `summary.md` : 실험 의도/조건/결과/개선률
- `metadata.txt` : 실행 환경과 변수
- `run.log` : 실행 로그

`k6-summary.json`은 k6를 사용하는 실험만 생성된다 (`03`, `05`).

## 실행 예시

- 01번(Next-Key):

```bash
cd test/perf-quantification
./scripts/run-exp01-next-key-lock.sh
```

- 03번(조회수 배치):

```bash
cd test/perf-quantification
./scripts/run-exp03-view-counter-batch.sh
```

- 05번(Redis Pipeline):

```bash
cd test/perf-quantification
./scripts/run-exp05-redis-pipeline.sh
```
