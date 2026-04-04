# V2 Async Baseline Report

## Scope

이 문서는 `exp-v2-async` 기준선을 정리한다.

## Aggregated Results

| scenario | repeats | POST /posts p95 avg (ms) | error rate avg | image completion latency p95 avg (ms) |
|---|---:|---:|---:|---:|
| medium_10rps | 3 | 85.38 | 0.000000 | 1232.00 |
| heavy_20rps | 3 | 342.48 | 0.000010 | 27039.52 |
| burst_5_to_30 | 3 | 155.05 | 0.000015 | 36575.00 |

## Raw Files

- summary: `docs/experiments/results/exp-v2-async/summary.md`
- k6 summaries: `docs/experiments/results/exp-v2-async/k6/*-summary.json`
- queue metrics (auxiliary raw): `docs/experiments/results/exp-v2-async/metrics/queue-*.json`
