# Image Pipeline Test Flow

## Purpose

이 문서는 `V1`, `V2` 실험을 실제로 어떤 순서로 검증했고, 결과를 어디에 남겼는지 빠르게 확인하기 위한 테스트 안내서다.
아키텍처 문서와 분리해서, 실행 절차만 바로 찾을 수 있게 두었다.

## Common Test Shape

공통 조건:

- 브랜치: `experiment/image-pipeline-evolution`
- 시나리오: `medium_10rps`, `heavy_20rps`, `burst_5_to_30`
- 반복 횟수: 시나리오별 3회
- 주지표:
  - `POST /posts p95`
  - `API error rate`

공통 산출물:

- 요약 문서
- 상세 리포트
- raw k6 summary JSON
- raw k6 stdout log

## V1 Test Flow

실행 순서:

1. `scripts/experiments/observability/smoke-observability.sh`
2. `scripts/experiments/v1/reset-state.sh`
3. `scripts/experiments/v1/deploy-app.sh`
4. `scripts/experiments/v1/run-scenario-matrix.sh`

`run-scenario-matrix.sh` 내부:

1. state reset
2. access token bootstrap
3. k6 실행
4. 결과 저장
5. 마지막에 summary 생성

결과 위치:

- 요약: `docs/experiments/results/exp-v1-sync/summary.md`
- 상세: `docs/experiments/results/exp-v1-sync/v1-baseline-report-2026-04-04.md`
- raw: `docs/experiments/results/exp-v1-sync/k6/`

읽는 법:

- `POST /posts p95`가 직접 이미지 처리 비용을 포함한다
- 에러율이 높으면 요청 경로 자체가 이미 병목이라는 뜻이다

## V2 Test Flow

실행 순서:

1. `scripts/experiments/v2/reset-state.sh`
2. `scripts/experiments/v2/deploy-app.sh`
3. `scripts/experiments/v2/run-scenario-matrix.sh`
4. `scripts/experiments/v2/generate-summary.sh`

`run-scenario-matrix.sh` 내부:

1. queue purge
2. local store reset
3. access token bootstrap
4. k6 create 요청 + 상세조회 polling
5. queue raw capture
6. 마지막에 summary 생성

결과 위치:

- 요약: `docs/experiments/results/exp-v2-async/summary.md`
- 상세: `docs/experiments/results/exp-v2-async/v2-baseline-report-2026-04-04.md`
- raw: `docs/experiments/results/exp-v2-async/k6/`
- queue raw: `docs/experiments/results/exp-v2-async/metrics/`

읽는 법:

- `POST /posts p95`는 요청 경로 지연만 보여준다
- `image completion latency p95`는 비동기 완료 지연을 따로 보여준다
- 즉 `V1`과 `V2`는 응답시간과 완료시간을 분리해서 읽어야 한다

## UX Shortcut

빠르게 볼 때는 아래 순서로 열면 된다.

1. 아키텍처 문서
2. 요약 문서
3. 상세 리포트
4. 필요하면 raw JSON / stdout

추천 링크:

- `V1` 아키텍처: `docs/experiments/v1-sync-current-architecture.md`
- `V2` 아키텍처: `docs/experiments/v2-async-current-architecture.md`
- `V1` 결과: `docs/experiments/results/exp-v1-sync/summary.md`
- `V2` 결과: `docs/experiments/results/exp-v2-async/summary.md`
