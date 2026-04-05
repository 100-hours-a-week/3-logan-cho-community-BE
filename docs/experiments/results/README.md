# Image Pipeline Results Index

## Stage Documents

### V1 Sync

- 요약: `docs/experiments/results/exp-v1-sync/summary.md`
- 상세 리포트: `docs/experiments/results/exp-v1-sync/v1-baseline-report-2026-04-04.md`
- raw k6: `docs/experiments/results/exp-v1-sync/k6/*`

### V2 Async

- 요약: `docs/experiments/results/exp-v2-async/summary.md`
- 상세 리포트: `docs/experiments/results/exp-v2-async/v2-baseline-report-2026-04-04.md`
- raw k6: `docs/experiments/results/exp-v2-async/k6/*`
- raw queue: `docs/experiments/results/exp-v2-async/metrics/queue-*.json`

### V3 Outbox

- 요약: `docs/experiments/results/exp-v3-outbox/summary.md`
- 상세 리포트: `docs/experiments/results/exp-v3-outbox/v3-baseline-report-2026-04-05.md`
- raw k6: `docs/experiments/results/exp-v3-outbox/k6/*`
- raw queue/outbox: `docs/experiments/results/exp-v3-outbox/metrics/*.json`

### V4 Idempotent + DLQ

- 요약: `docs/experiments/results/exp-v4-idempotent/summary.md`
- 상세 리포트: `docs/experiments/results/exp-v4-idempotent/v4-baseline-report-2026-04-05.md`
- raw k6: `docs/experiments/results/exp-v4-idempotent/k6/*`
- raw metrics: `docs/experiments/results/exp-v4-idempotent/metrics/*.json`
- probe evidence: `docs/experiments/results/exp-v4-idempotent/probes/*.json`

## Cross-Version Notes

- `t3.large` high-load rerun 비교: `docs/experiments/results/t3large-high-load-rerun-2026-04-05.md`

## Reading Order

1. `exp-v1-sync/summary.md`
2. `exp-v2-async/summary.md`
3. `exp-v3-outbox/summary.md`
4. `exp-v4-idempotent/summary.md`
5. `t3large-high-load-rerun-2026-04-05.md`

## Primary Metrics

- 1차 비교 지표: `POST /posts p95`, `API error rate`
- 보조 지표:
  - `image completion latency p95`
  - `queue oldest age`
  - `pending outbox`, `orphan pending post`
  - `duplicate ignored count`, `duplicate side effect count`
  - `DLQ count`
