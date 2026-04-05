# V4 Idempotent Baseline Report

## Scope

이 문서는 `exp-v4-idempotent`의 초기 기준선과 안정성 probe 결과를 정리한다.
현재 범위는 `smoke`, `medium_10rps 1회`, `duplicate delivery`, `poison message -> DLQ` 확인까지다.

## Smoke Result

| probe | POST /posts p95 (ms) | error rate | image completion p95 (ms) | duplicate side effect count | DLQ count |
|---|---:|---:|---:|---:|---:|
| smoke | 769.96 | 0.000000 | 4095.00 | 0 | 0 |

## Medium Result

| scenario | repeats | POST /posts p95 (ms) | error rate | image completion p95 (ms) | processed jobs | duplicate ignored count | duplicate side effect count | DLQ count |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| medium_10rps | 1 | 62.32 | 0.001732 | 3158.85 | 1189 | 1 | 0 | 0 |

## Stability Probes

| probe | result |
|---|---|
| duplicate delivery | `duplicateIgnoredCount = 2`, `duplicateSideEffectCount = 0` |
| poison message | `NoSuchKey` 실패 주입 확인, `DLQ count = 1` 확인 |

## Interpretation

- `V4`의 주효과는 요청 경로 개선이 아니라 소비 안정성 보강이다.
- `medium_10rps`에서도 요청 p95는 낮게 유지됐고, processed jobs 저장소 기준으로 duplicate side effect는 발생하지 않았다.
- poison message는 최종적으로 `DLQ`로 격리됐다.

## Raw Files

- summary: `docs/experiments/results/exp-v4-idempotent/summary.md`
- k6 summaries: `docs/experiments/results/exp-v4-idempotent/k6/*-summary.json`
- metrics: `docs/experiments/results/exp-v4-idempotent/metrics/*.json`
- probes: `docs/experiments/results/exp-v4-idempotent/probes/*.json`
