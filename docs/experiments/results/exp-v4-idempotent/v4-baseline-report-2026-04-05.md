# V4 Idempotent Baseline Report

## Scope

이 문서는 `exp-v4-idempotent` 기준선을 정리한다.
현재 표는 2026-04-07 multi-ASG 분리 인프라 재실행 결과를 기준으로 갱신했다.

## Aggregated Results

| scenario | repeats | POST /posts p95 avg (ms) | error rate avg | image completion latency p95 avg (ms) | duplicate side effect avg | DLQ count avg |
|---|---:|---:|---:|---:|---:|---:|
| medium_10rps | 1 | 67.48 | 0.000066 | 36349.60 | 0.00 | 0.00 |
| heavy_20rps | 1 | 87.96 | 0.000000 | 76560.70 | 0.00 | 0.00 |
| burst_5_to_30 | 1 | 65.36 | 0.000344 | 68516.45 | 0.00 | 0.00 |

## Raw Files

- summary: `docs/experiments/results/exp-v4-idempotent/summary.md`
- k6 summaries: `docs/experiments/results/exp-v4-idempotent/k6/*-summary.json`
- metrics: `docs/experiments/results/exp-v4-idempotent/metrics/*.json`

## Notes

- 이번 결과는 `db EC2 + app ASG 2대 + ALB` 분리 인프라에서 시나리오별 1회 재실행한 값이다.
- 목적은 multi-node callback/idempotent consumer 정합성을 확인하고, high-load completion 병목을 다시 측정하는 것이었다.
- `duplicate side effect count`, `DLQ count`는 전 시나리오에서 0을 유지했다.
- request path p95는 `V3`보다 안정적이지만, completion latency는 여전히 길다.
