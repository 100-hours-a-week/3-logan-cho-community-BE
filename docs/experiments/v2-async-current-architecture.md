# V2 Async Current Architecture

## Current Deployment

`v2`도 현재 실험 환경은 EC2 3대 완전 분리가 아니다.
역할 배치는 아래와 같다.

- App EC2 1대
  - Spring Boot application
  - MySQL Docker container
  - MongoDB Docker container
  - Redis Docker container
  - `node_exporter`
- k6 EC2 1대
  - `k6` load generator
  - Prometheus Docker container
  - Grafana Docker container
- Lambda / SQS
  - SQS main queue
  - SQS-triggered image processor Lambda

즉, `v1` 대비 핵심 차이는 이미지 처리 워커가 App EC2 밖으로 빠졌다는 점이다.

## Request Flow

`v2`의 핵심은 이미지 압축과 썸네일 생성이 요청 응답 경로 밖으로 이동한다는 점이다.

1. Client uploads temp image to S3
2. Client sends `POST /api/posts`
3. Spring validates temp image and saves post as `PENDING`
4. Spring publishes image job to SQS
5. Spring returns create response immediately
6. Lambda consumes SQS message
7. Lambda downloads temp image from S3
8. Lambda generates final image and thumbnail
9. Lambda uploads final assets to S3
10. Lambda calls Spring callback endpoint
11. Spring updates post to `COMPLETED` or `FAILED`

이 구조에서는 `POST /posts` latency와 이미지 처리 완료 시간이 분리된다.

## Metrics

- 1차 비교 지표:
  - `k6` 기준 `POST /posts p95`
  - `k6` 기준 `API error rate`
- 보조 지표:
  - `k6` 기준 `image completion latency p95`
  - Prometheus/Grafana
  - `queue-*.json` raw queue samples

포트폴리오 본문 비교표에는 `k6` 기준 수치만 사용한다.

## Infra Notes

- App EC2는 기존 실험 인스턴스를 재사용한다
- k6/Prometheus/Grafana도 기존 실험 인스턴스를 재사용한다
- `v2`에서 추가된 AWS 리소스는 주로 아래다
  - SQS queue
  - SQS event source mapping
  - image processor Lambda
  - Lambda IAM permissions

## Test Flow

실행 순서:

1. `scripts/experiments/v2/reset-state.sh`
2. `scripts/experiments/v2/deploy-app.sh`
3. `scripts/experiments/v2/run-scenario-matrix.sh`
4. `scripts/experiments/v2/generate-summary.sh`

`run-scenario-matrix.sh` 내부 흐름:

1. `medium_10rps`, `heavy_20rps`, `burst_5_to_30`
2. 시나리오별 3회 반복
3. 매 반복마다:
   - purge queue
   - reset local stores
   - bootstrap access token
   - run `image-pipeline-v2.js`
   - capture auxiliary queue metrics

## Current Test Status

현재까지 완료된 것은 아래와 같다.

- `./gradlew compileJava`
- `v2` infra apply
- async smoke
- `run-scenario-matrix.sh`
- `exp-v2-async` 결과 문서화

결과 산출물:

- summary: `docs/experiments/results/exp-v2-async/summary.md`
- detailed report: `docs/experiments/results/exp-v2-async/v2-baseline-report-2026-04-04.md`
- raw metrics: `docs/experiments/results/exp-v2-async/k6/*-summary.json`
- raw run logs: `docs/experiments/results/exp-v2-async/k6/*-stdout.log`
- auxiliary queue metrics: `docs/experiments/results/exp-v2-async/metrics/queue-*.json`
