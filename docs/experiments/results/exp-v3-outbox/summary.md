# exp-v3-outbox Summary

실행 일시:
- 2026-04-05
- 2026-04-07

실행 기준:
- 브랜치: `experiment/image-pipeline-evolution`
- 기준선 1: single app node baseline
- 기준선 2: `db EC2 + app ASG + ALB` 분리 인프라 재실행
- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`
- 추가 지표: `image completion latency p95`, `orphan pending post count`, `pending outbox count`

원본 결과:
- `docs/experiments/results/exp-v3-outbox/k6/*-summary.json`
- `docs/experiments/results/exp-v3-outbox/k6/*-stdout.log`
- `docs/experiments/results/exp-v3-outbox/metrics/queue-*.json`
- `docs/experiments/results/exp-v3-outbox/metrics/outbox-*.json`

## Scenario Results

### multi_asg_rerun_2026_04_07

- topology: `db EC2 1대 + app ASG 2대 + ALB 1개 + k6/observability 1대`
- repeats: 시나리오별 1회
- 목적: multi-node relay 정합성과 high-load completion 병목 재확인

### medium_10rps

- repeats: 1
- POST /posts p95 avg(ms): 127.31
- API error rate avg: 0.000033
- image completion latency p95 avg(ms): 48018.25
- outbox snapshot samples: 1
- pending outbox count avg: 0.00
- orphan pending post count avg: 0.00
- dropped iterations: 714

### heavy_20rps

- repeats: 1
- POST /posts p95 avg(ms): 1140.08
- API error rate avg: 0.000017
- image completion latency p95 avg(ms): 88290.75
- outbox snapshot samples: 1
- pending outbox count avg: n/a
- orphan pending post count avg: n/a
- dropped iterations: 1584

### burst_5_to_30

- repeats: 1
- POST /posts p95 avg(ms): 57.27
- API error rate avg: 0.000000
- image completion latency p95 avg(ms): 74904.00
- outbox snapshot samples: 1
- pending outbox count avg: 0.00
- orphan pending post count avg: 529.00
- dropped iterations: 2114

## Interpretation

- `V3`는 direct publish 대신 outbox relay를 도입해 게시글 저장과 발행 기록을 같이 보존한다.
- multi-ASG 재실행에서도 request path p95와 API error rate는 크게 무너지지 않았지만, completion latency와 dropped iterations는 여전히 높다.
- 특히 `heavy`, `burst` 구간에서 `completion p95`가 길고 orphan pending post가 남아, 병목이 request path보다 비동기 후단 처리량에 있음을 보여준다.
- 본문 비교표는 여전히 `k6` 기준 응답시간과 에러율을 1차 지표로 사용한다.
- outbox/queue 수치는 발행 누락과 잔여 작업을 해석하는 보조 raw 자료다.
