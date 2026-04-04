# V1 Sync Current Architecture

## Current Deployment

현재 실험 환경은 EC2 3대 분리가 아니다.
실제로는 아래처럼 2대의 EC2에 역할을 나눠 올린 상태다.

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

즉, 현재는 아래와 같다.

- load generator: 별도 EC2
- target application: 별도 EC2
- monitoring server: 별도 EC2 아님
- monitoring stack은 `k6 EC2`에 함께 배치

실험 목적상 분리한 기준은 다음이다.

- 부하 발생기는 앱과 분리해서 측정 오염을 줄인다
- 앱은 단일 인스턴스로 유지해 `v1` 병목을 그대로 드러낸다
- 모니터링은 보조 수단이므로 별도 EC2를 늘리지 않고 `k6 EC2`에 함께 둔다

## Draw.io

- source: `docs/experiments/diagrams/v1-sync-current-architecture.drawio`

## Request Flow

`v1`의 핵심은 이미지 처리 경로가 요청 응답 안에 직접 들어 있다는 점이다.

1. Client sends `POST /posts`
2. Spring receives metadata + temp image reference
3. Spring downloads temp image from S3
4. Spring resizes/compresses image in-process
5. Spring uploads final image and thumbnail to S3
6. Spring writes post metadata to MySQL and MongoDB
7. Spring returns response

이 구조에서는 이미지 처리 비용이 전부 `POST /posts` latency 안에 포함된다.
그래서 `p95`와 `error rate`가 직접 악화된다.

## Monitoring Flow

- Prometheus runs on `k6 EC2`
- Prometheus scrapes:
  - `app-node`: App EC2 `private IP:9100`
  - `app-spring`: App EC2 `private IP:8080/actuator/prometheus`
- Grafana runs on `k6 EC2`
- 주요 비교 지표는 여전히 `k6` 결과다
- Prometheus/Grafana는 CPU, heap, scrape health 해석용이다

## Branch Strategy

실험 브랜치 전략은 현재 아래 기준으로 운용 중이다.

- `main`
  - 최종 안정 코드만 유지
  - 실험 중간 산출물 직접 반영 금지
- `develop`
  - 일반 개발 통합 브랜치
  - 실험 검증이 끝난 묶음만 PR로 반영
- `experiment/image-pipeline-evolution`
  - 이번 실험 전용 브랜치
  - `v1 -> v2 -> v3 -> v4`를 이 브랜치에서 순차 누적

현재 상태:

- `v1` 구현, 실험 스크립트, Terraform, 관측 스택, 기준선 결과는 `experiment/image-pipeline-evolution`에 올라가 있음
- 1차 PR: `develop <- experiment/image-pipeline-evolution`
- PR: `#79`

## How Tests Are Run

현재 `v1` 실험은 SSH 기반으로 수행한다.
반복 제어에서 SSM queue delay가 변수로 들어오던 문제를 줄이기 위해 바꿨다.

실행 순서:

1. `scripts/experiments/observability/smoke-observability.sh`
2. `scripts/experiments/v1/reset-state.sh`
3. `scripts/experiments/v1/deploy-app.sh`
4. `scripts/experiments/v1/run-scenario-matrix.sh`

`run-scenario-matrix.sh` 내부 흐름:

1. `medium_10rps`, `heavy_20rps`, `burst_5_to_30` 순서로 진행
2. 각 시나리오를 3회 반복
3. 매 반복마다:
   - reset state
   - bootstrap access token
   - run k6
4. 마지막에 `generate-summary.sh`로 집계

## Current Test Status

현재까지 완료된 것은 아래와 같다.

- `./gradlew compileJava`
- observability smoke check
- `reset-state.sh`
- `deploy-app.sh`
- `run-scenario-matrix.sh`
- `exp-v1-sync` 결과 문서화

결과 산출물:

- summary: `docs/experiments/results/exp-v1-sync/summary.md`
- detailed report: `docs/experiments/results/exp-v1-sync/v1-baseline-report-2026-04-04.md`
- raw metrics: `docs/experiments/results/exp-v1-sync/k6/*-summary.json`
- raw run logs: `docs/experiments/results/exp-v1-sync/k6/*-stdout.log`
