# exp-v3-outbox Summary

실행 일시:
- 2026-04-05

실행 기준:
- 브랜치: `experiment/image-pipeline-evolution`
- 반복: 시나리오별 3회
- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`
- 추가 지표: `image completion latency p95`, `orphan pending post count`, `pending outbox count`

원본 결과:
- `docs/experiments/results/exp-v3-outbox/k6/*-summary.json`
- `docs/experiments/results/exp-v3-outbox/k6/*-stdout.log`
- `docs/experiments/results/exp-v3-outbox/metrics/queue-*.json`
- `docs/experiments/results/exp-v3-outbox/metrics/outbox-*.json`

## Scenario Results

### medium_10rps

- repeats: 3
- POST /posts p95 avg(ms): 66.05
- API error rate avg: 0.001716
- image completion latency p95 avg(ms): 2177.80
- outbox snapshot samples: 3
- pending outbox count avg: 0.00
- orphan pending post count avg: 0.00

### heavy_20rps

- repeats: 2
- POST /posts p95 avg(ms): 998.99
- API error rate avg: 0.015588
- image completion latency p95 avg(ms): 47956.00
- outbox snapshot samples: 0
- pending outbox count avg: n/a
- orphan pending post count avg: n/a

## Interpretation

- `V3`는 direct publish 대신 outbox relay를 도입해 게시글 저장과 발행 기록을 같이 보존한다.
- 본문 비교표는 여전히 `k6` 기준 응답시간과 에러율을 1차 지표로 사용한다.
- outbox/queue 수치는 발행 누락과 잔여 작업을 해석하는 보조 raw 자료다.
