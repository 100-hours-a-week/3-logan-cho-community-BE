# t3.large High-Load Rerun Notes

## Scope

- 일시: `2026-04-05`
- 환경: `App EC2 t3.large`, `k6 EC2 t3.small`
- 목적: `V2`, `V3`, `V4`를 같은 상향 스펙에서 다시 비교해, 구조 변화와 인스턴스 스케일업의 효과를 분리해서 읽는다.
- 1차 지표: `POST /posts p95`, `API error rate`
- 보조 지표: `image completion latency p95`, `dropped iterations`, `pending outbox`, `duplicate side effect`, `DLQ count`

## Aggregated Snapshot

| version | scenario | POST /posts p95 (ms) | error rate | image completion p95 (ms) | dropped iterations | note |
|---|---|---:|---:|---:|---:|---|
| V2 async | heavy_20rps | 612.42 | 0.000000 | 42421.00 | 438 | API는 안정, completion backlog 유지 |
| V2 async | burst_5_to_30 | 237.40 | 0.000000 | 36787.40 | 614 | 요청 경로는 짧고 queue 대기만 길어짐 |
| V3 outbox | heavy_20rps | 1100.66 | 0.000906 | 109644.00 | 1554 | outbox 잔여 263, orphan pending 282 |
| V3 outbox | burst_5_to_30 | 194.36 | 0.000109 | 83331.70 | 1499 | burst에서는 outbox 잔여 0까지 수렴 |
| V4 idempotent | heavy_20rps | 1052.95 | 0.000847 | 107657.00 | 1506 | duplicate side effect 0, DLQ 0 |
| V4 idempotent | burst_5_to_30 | 231.85 | 0.000114 | 78163.80 | 1469 | duplicate side effect 0, DLQ 0 |

## Engineering Reading

### 1. 스케일업만으로는 `V2`의 completion latency를 해결하지 못했다

- `V2`는 이미 요청 경로에서 이미지 처리를 제거했기 때문에, App EC2를 `t3.large`로 올려도 `POST /posts`는 이미 충분히 짧았다.
- 반면 `image completion latency p95`는 `heavy 42.4s`, `burst 36.8s`로 여전히 길다.
- 해석: 이 구간의 병목은 App CPU보다 queue backlog와 후단 처리량에 더 가깝다.

### 2. `V3`는 스케일업 후에도 성능보다 정합성용 구조라는 점이 더 분명해졌다

- `V3`는 `heavy`, `burst`를 끝까지 수집할 수 있게 됐지만, `POST /posts p95`는 `V2`보다 높고 completion tail도 더 길다.
- `heavy`에서는 `pending outbox 263`, `orphan pending posts 282`가 남아 후단 처리량 부족이 수치로 드러난다.
- 해석: outbox는 "발행 누락 방지"와 "추적 가능성"을 위한 비용 있는 구조다. 성능 버전이 아니라 reliability 버전이다.

### 3. `V4`의 핵심 가치는 latency가 아니라 correctness 유지다

- `V4`의 `heavy`, `burst` 수치는 `V3`와 거의 같은 계열이다.
- 대신 `processed jobs` 기준 `duplicate side effect count = 0`, `DLQ count = 0`을 유지했다.
- 해석: `V4`는 고부하에서도 중복 callback이 side effect를 늘리지 않도록 만드는 안전장치 계층이다.

### 4. 가장 큰 구조적 개선은 여전히 `V1 -> V2`였다

- `V1`의 핵심 문제는 이미지 처리 자체가 요청 경로를 막는 것이었다.
- `V2` 이후에는 API 실패율과 요청 p95가 급격히 안정됐다.
- 그 다음 단계인 `V3`, `V4`는 "더 빠르게"보다 "더 잃어버리지 않게, 더 중복 반영되지 않게" 만드는 단계다.

## Portfolio-Ready Points

- 동기 이미지 처리 구조를 비동기화해 `POST /posts` 응답 경로를 이미지 압축 비용에서 분리했고, `heavy/burst`에서도 API error rate를 사실상 `0`에 가깝게 유지했다.
- 단순 스케일업과 구조 개선의 효과를 분리해서 검증했다. `V2`는 `t3.large`에서도 completion latency가 크게 줄지 않았고, 이는 병목이 App CPU가 아니라 queue backlog와 worker throughput에 있음을 보여준다.
- `V3`에서는 outbox를 넣어 "저장 성공했는데 publish 실패" 문제를 구조적으로 추적 가능하게 바꿨다. 대신 pending outbox와 orphan pending post를 수치로 남겨 reliability 비용을 가시화했다.
- `V4`에서는 idempotent consumer와 DLQ를 추가해 duplicate callback과 poison message를 통제했다. 고부하에서도 `duplicate side effect count = 0`, `DLQ count = 0`을 확인해 correctness를 증명했다.
- 실험 자동화도 함께 정리했다. 동일한 EC2 환경과 같은 부하 스크립트에서 버전만 바꿔 재실행 가능하게 만들고, raw `k6`, queue, outbox, processed, DLQ 결과를 전부 repo에 남겨 재해석 가능한 증거 세트를 구성했다.

## Raw References

- `docs/experiments/results/exp-v2-async/k6/*-t3large-rerun1-summary.json`
- `docs/experiments/results/exp-v3-outbox/k6/*-t3large-fixed1-summary.json`
- `docs/experiments/results/exp-v4-idempotent/k6/*-t3large-fixed1-summary.json`
- `docs/experiments/results/exp-v3-outbox/metrics/*.json`
- `docs/experiments/results/exp-v4-idempotent/metrics/*.json`
