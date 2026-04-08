# exp-v1-sync Summary

실행 일시:
- 2026-04-04

실행 기준:
- 브랜치: `experiment/image-pipeline-evolution`
- 반복: 시나리오별 3회
- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`
- 보조 해석 수단: `Prometheus + Grafana`

원본 결과:
- `docs/experiments/results/exp-v1-sync/k6/*-summary.json`
- `docs/experiments/results/exp-v1-sync/k6/*-stdout.log`
- 상세 해석: `docs/experiments/results/exp-v1-sync/v1-baseline-report-2026-04-04.md`

## Scenario Results

### medium_10rps

- repeats: 3
- POST /posts p95 avg(ms): 44479.14
- POST /posts p95 min(ms): 43823.33
- POST /posts p95 max(ms): 45159.52
- API error rate avg: 0.324838

### heavy_20rps

- repeats: 3
- POST /posts p95 avg(ms): 60000.50
- POST /posts p95 min(ms): 60000.37
- POST /posts p95 max(ms): 60000.65
- API error rate avg: 0.329398

### burst_5_to_30

- repeats: 3
- POST /posts p95 avg(ms): 60000.32
- POST /posts p95 min(ms): 60000.20
- POST /posts p95 max(ms): 60000.51
- API error rate avg: 0.328990

## Interpretation

- `V1`은 `medium_10rps`부터 이미 `POST /posts p95`가 약 `44.5s`로 매우 높다.
- `heavy_20rps`, `burst_5_to_30`에서는 `p95`가 사실상 `60s` timeout ceiling에 붙는다.
- 세 시나리오 모두 평균 에러율이 약 `32%` 수준으로 유지되어, 동기 압축 경로가 요청 처리 병목임을 기준선으로 삼을 수 있다.
