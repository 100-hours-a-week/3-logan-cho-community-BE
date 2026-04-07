# V3 Outbox Baseline Report

## Scope

이 문서는 `exp-v3-outbox` 기준선을 정리한다.
현재 표는 2026-04-07 multi-ASG 분리 인프라 재실행 결과를 기준으로 갱신했다.

## Aggregated Results

| scenario | repeats | POST /posts p95 avg (ms) | error rate avg | image completion latency p95 avg (ms) | pending outbox avg | orphan pending posts avg |
|---|---:|---:|---:|---:|---:|---:|
| medium_10rps | 1 | 127.31 | 0.000033 | 48018.25 | 0.00 | 0.00 |
| heavy_20rps | 1 | 1140.08 | 0.000017 | 88290.75 | n/a | n/a |
| burst_5_to_30 | 1 | 57.27 | 0.000000 | 74904.00 | 0.00 | 529.00 |

## Raw Files

- summary: `docs/experiments/results/exp-v3-outbox/summary.md`
- k6 summaries: `docs/experiments/results/exp-v3-outbox/k6/*-summary.json`
- queue metrics (auxiliary raw): `docs/experiments/results/exp-v3-outbox/metrics/queue-*.json`
- outbox metrics (auxiliary raw): `docs/experiments/results/exp-v3-outbox/metrics/outbox-*.json`

## Notes

- 이번 결과는 `db EC2 + app ASG 2대 + ALB` 분리 인프라에서 시나리오별 1회 재실행한 값이다.
- 목적은 multi-node relay 정합성과 high-load completion 병목을 다시 확인하는 것이었다.
- request path는 유지됐지만, completion latency와 dropped iterations는 여전히 높다.
- `outbox-heavy_20rps-run1.json`은 snapshot은 남았지만 pending/outbox가 `n/a`로 기록된 구간이 있어 raw 파일 확인이 필요하다.
