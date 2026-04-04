# V3 Outbox Baseline Report

## Scope

이 문서는 `exp-v3-outbox` 기준선을 정리한다.

## Aggregated Results

| scenario | repeats | POST /posts p95 avg (ms) | error rate avg | image completion latency p95 avg (ms) | pending outbox avg | orphan pending posts avg |
|---|---:|---:|---:|---:|---:|---:|
| medium_10rps | 3 | 66.05 | 0.001716 | 2177.80 | 0.00 | 0.00 |
| heavy_20rps | 2 | 998.99 | 0.015588 | 47956.00 | n/a | n/a |

## Raw Files

- summary: `docs/experiments/results/exp-v3-outbox/summary.md`
- k6 summaries: `docs/experiments/results/exp-v3-outbox/k6/*-summary.json`
- queue metrics (auxiliary raw): `docs/experiments/results/exp-v3-outbox/metrics/queue-*.json`
- outbox metrics (auxiliary raw): `docs/experiments/results/exp-v3-outbox/metrics/outbox-*.json`

## Notes

- `V3`는 `medium_10rps` 3회, `heavy_20rps` 2회까지 수집됐다.
- `burst_5_to_30`은 App EC2가 `heavy` 이후 SSH/health 응답을 잃어 아직 미수집 상태다.
- `outbox-heavy_20rps-run2.json`은 부하 직후 snapshot 접속 실패로 `captureStatus=unavailable`만 남겼다.
