# exp-v4-idempotent Summary

실행 일시:
- 2026-04-05
- 2026-04-07

실행 기준:
- 브랜치: `experiment/image-pipeline-evolution`
- 기준선 1: single app node baseline
- 기준선 2: `db EC2 + app ASG + ALB` 분리 인프라 재실행
- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`
- 추가 지표: `image completion latency p95`, `duplicate side effect count`, `DLQ count`

원본 결과:
- `docs/experiments/results/exp-v4-idempotent/k6/*-summary.json`
- `docs/experiments/results/exp-v4-idempotent/k6/*-stdout.log`
- `docs/experiments/results/exp-v4-idempotent/metrics/*.json`

## Scenario Results

### multi_asg_rerun_2026_04_07

- topology: `db EC2 1대 + app ASG 2대 + ALB 1개 + k6/observability 1대`
- repeats: 시나리오별 1회
- 목적: multi-node callback/idempotency 정합성과 high-load completion 병목 재확인

### medium_10rps

- repeats: 1
- POST /posts p95 avg(ms): 67.48
- API error rate avg: 0.000066
- image completion latency p95 avg(ms): 36349.60
- duplicate side effect count avg: 0.00
- duplicate callback ignored avg: 0.00
- DLQ count avg: 0.00
- dropped iterations: 710

### heavy_20rps

- repeats: 1
- POST /posts p95 avg(ms): 87.96
- API error rate avg: 0.000000
- image completion latency p95 avg(ms): 76560.70
- duplicate side effect count avg: 0.00
- duplicate callback ignored avg: 0.00
- DLQ count avg: 0.00
- dropped iterations: 1592

### burst_5_to_30

- repeats: 1
- POST /posts p95 avg(ms): 65.36
- API error rate avg: 0.000344
- image completion latency p95 avg(ms): 68516.45
- duplicate side effect count avg: 0.00
- duplicate callback ignored avg: 0.00
- DLQ count avg: 0.00
- dropped iterations: 2096

## Interpretation

- `V4`는 outbox 위에 idempotent consumer와 DLQ를 추가해 중복 소비와 poison message를 격리하는 단계다.
- `duplicate side effect count`는 processed jobs 저장소 기준으로 집계한다.
- `DLQ count`는 보조 안정성 지표이며, 본문 비교의 1차 지표는 여전히 `POST /posts p95`, `API error rate`다.
- multi-ASG 재실행에서도 request path p95와 API error rate는 안정적이었고, `duplicate side effect count`, `DLQ count`는 모두 0이었다.
- 반면 `completion p95`와 dropped iterations는 여전히 높아, correctness는 확보했지만 후단 처리량 병목은 남아 있음을 보여준다.
