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
