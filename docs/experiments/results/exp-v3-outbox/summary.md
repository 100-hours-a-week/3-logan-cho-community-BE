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

## t3.large High-Load Rerun

- 환경: `App EC2 t3.large`, `k6 EC2 t3.small`
- 목적: `heavy`, `burst`에서 `outbox` 구조의 실제 잔여 작업과 completion tail을 다시 고정
- 주의: `heavy_20rps-t3large-rerun1`은 앱이 존재하지 않는 queue를 바라보는 설정 불일치로 무효다. 비교에는 `t3large-fixed1`만 사용한다.
- 파일:
  - `docs/experiments/results/exp-v3-outbox/k6/heavy_20rps-t3large-fixed1-summary.json`
  - `docs/experiments/results/exp-v3-outbox/k6/burst_5_to_30-t3large-fixed1-summary.json`
  - `docs/experiments/results/exp-v3-outbox/metrics/outbox-heavy_20rps-t3large-fixed1.json`
  - `docs/experiments/results/exp-v3-outbox/metrics/outbox-burst_5_to_30-t3large-fixed1.json`

### heavy_20rps

- repeats: 1
- POST /posts p95(ms): 1100.66
- API error rate: 0.000906
- image completion latency p95(ms): 109644.00
- dropped iterations: 1554
- pending outbox count: 263
- orphan pending post count: 282
- queue oldest age max(s): 6.00

### burst_5_to_30

- repeats: 1
- POST /posts p95(ms): 194.36
- API error rate: 0.000109
- image completion latency p95(ms): 83331.70
- dropped iterations: 1499
- pending outbox count: 0
- orphan pending post count: 0
- queue oldest age max(s): 12.00

### Rerun Interpretation

- `t3.large`로 올리면 `V3`는 더 이상 App 인스턴스가 즉시 죽지 않고 `heavy`, `burst`를 끝까지 수집할 수 있다.
- 하지만 응답 경로 p95는 `V2`보다 높고, completion latency는 `80~110초`대로 길다.
- `outbox`는 발행 누락 방지와 추적성에는 유리하지만, 후단 처리량이 부족하면 `pending outbox`와 `orphan pending post`가 그대로 남는다.
