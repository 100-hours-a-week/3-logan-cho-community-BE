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
- fault probes: `docs/experiments/results/exp-v2-async/probes/*.json`

## t3.large High-Load Rerun

| scenario | repeats | POST /posts p95 (ms) | error rate | image completion latency p95 (ms) | dropped iterations | queue oldest age max (s) |
|---|---:|---:|---:|---:|---:|---:|
| heavy_20rps | 1 | 612.42 | 0.000000 | 42421.00 | 438 | 48.00 |
| burst_5_to_30 | 1 | 237.40 | 0.000000 | 36787.40 | 614 | 75.00 |

메모:

- `t3.large` 재실행은 `V3`, `V4`와 동일한 App 스펙에서 고부하 비교선을 맞추기 위한 보강 수집이다.
- `V2`는 이미 구조적으로 요청 경로가 짧아서, 스케일업보다 queue backlog 쪽 지연이 더 지배적이었다.

## Fault Injection

- 리포트: `docs/experiments/results/exp-v2-async/v2-fault-injection-report-2026-04-08.md`
- `save -> publish` 사이에 강제 실패를 넣으면, `500` 응답과 함께 Mongo에는 `PENDING` post가 남고 publish는 되지 않는다.
- idempotency가 없는 상태에서 같은 callback을 app node 2대에 다시 보내면 둘 다 `200`을 반환하고 `completedAt`이 다시 갱신된다.
- DLQ가 없는 상태에서 poison message를 넣으면 메인 queue의 `notVisible` 카운트가 유지돼 retry 경로에 계속 머무른다.
