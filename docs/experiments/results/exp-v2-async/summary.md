# exp-v2-async Summary

실행 일시:
- 2026-04-04

실행 기준:
- 브랜치: `experiment/image-pipeline-evolution`
- 반복: 시나리오별 3회
- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`
- 추가 지표: `image completion latency p95`

원본 결과:
- `docs/experiments/results/exp-v2-async/k6/*-summary.json`
- `docs/experiments/results/exp-v2-async/k6/*-stdout.log`
- `docs/experiments/results/exp-v2-async/metrics/queue-*.json`

## Scenario Results

### medium_10rps

- repeats: 3
- POST /posts p95 avg(ms): 85.38
- API error rate avg: 0.000000
- image completion latency p95 avg(ms): 1232.00

### heavy_20rps

- repeats: 3
- POST /posts p95 avg(ms): 342.48
- API error rate avg: 0.000010
- image completion latency p95 avg(ms): 27039.52

### burst_5_to_30

- repeats: 3
- POST /posts p95 avg(ms): 155.05
- API error rate avg: 0.000015
- image completion latency p95 avg(ms): 36575.00

## Interpretation

- `V2`는 이미지 처리를 요청 경로에서 제거해 `POST /posts` 기준 응답시간을 `V1`보다 낮추는 것이 목표다.
- 이미지 완료까지의 지연은 `image completion latency`로 별도 추적한다.
- `queue-*.json`은 보조 진단용 raw 자료로만 남기고, 본문 비교표의 1차 수치로 사용하지 않는다.

## t3.large High-Load Rerun

- 환경: `App EC2 t3.large`, `k6 EC2 t3.small`
- 목적: `V3`, `V4`와 같은 상향 스펙에서 `heavy`, `burst`를 다시 비교하기 위한 기준 고정
- 파일:
  - `docs/experiments/results/exp-v2-async/k6/heavy_20rps-t3large-rerun1-summary.json`
  - `docs/experiments/results/exp-v2-async/k6/burst_5_to_30-t3large-rerun1-summary.json`
  - `docs/experiments/results/exp-v2-async/metrics/queue-heavy_20rps-t3large-rerun1.json`
  - `docs/experiments/results/exp-v2-async/metrics/queue-burst_5_to_30-t3large-rerun1.json`

### heavy_20rps

- repeats: 1
- POST /posts p95(ms): 612.42
- API error rate: 0.000000
- image completion latency p95(ms): 42421.00
- dropped iterations: 438
- queue oldest age max(s): 48.00

### burst_5_to_30

- repeats: 1
- POST /posts p95(ms): 237.40
- API error rate: 0.000000
- image completion latency p95(ms): 36787.40
- dropped iterations: 614
- queue oldest age max(s): 75.00

### Rerun Interpretation

- `V2`는 `t3.large`에서도 API 실패 없이 `heavy`, `burst`를 처리했다.
- 다만 요청 경로 p95 자체가 크게 더 좋아지지는 않았고, 병목은 계속 queue backlog와 completion latency에 남았다.
- 즉 `V2`의 핵심 개선은 App 인스턴스 스케일업보다 "동기 경로 제거"에 있었다.
