# V1 Baseline Report

## Scope

이 문서는 `exp-v1-sync` 기준선을 2026-04-04에 다시 수집한 결과를 정리한다.

이번 재수집의 목적:
- `V1` 동기 압축 구조의 한계를 같은 조건에서 다시 고정
- 이후 `V2/V3/V4` 비교에 사용할 기준선 확보
- 실험 제어 경로를 `SSH`로 전환한 뒤 결과를 다시 고정

실행 환경:
- App EC2: 단일 인스턴스
- k6 EC2: 단일 인스턴스
- App/k6 제어: `SSH`
- 메트릭 기준:
  - 본지표: `k6`
  - 보조 수단: `Prometheus + Grafana`

## Scenarios

- `medium_10rps`
- `heavy_20rps`
- `burst_5_to_30`

각 시나리오는 3회 반복했다.

## Aggregated Results

| scenario | repeats | POST /posts p95 avg (ms) | p95 min | p95 max | error rate avg |
|---|---:|---:|---:|---:|---:|
| medium_10rps | 3 | 44479.14 | 43823.33 | 45159.52 | 0.324838 |
| heavy_20rps | 3 | 60000.50 | 60000.37 | 60000.65 | 0.329398 |
| burst_5_to_30 | 3 | 60000.32 | 60000.20 | 60000.51 | 0.328990 |

## Key Reading

- `medium_10rps`에서도 `p95`가 이미 `44.5s` 수준이다.
- `heavy_20rps`, `burst_5_to_30`에서는 `p95`가 사실상 `60s` timeout ceiling에 붙는다.
- 평균 에러율은 세 시나리오 모두 `32%` 전후다.
- 즉 `V1`은 대표 시나리오 전체에서 동기 이미지 처리 비용을 요청 경로 안에서 감당하지 못한다.

## What This Baseline Means

- 이후 `V2`는 최소한 아래 두 가지를 개선해야 한다.
- `POST /posts p95`
- `API error rate`

이 문서의 숫자는 `V2/V3/V4` 결과를 비교할 때 기준선으로 사용한다.

## Raw Files

`medium_10rps`
- `docs/experiments/results/exp-v1-sync/k6/medium_10rps-run1-summary.json`
- `docs/experiments/results/exp-v1-sync/k6/medium_10rps-run2-summary.json`
- `docs/experiments/results/exp-v1-sync/k6/medium_10rps-run3-summary.json`

`heavy_20rps`
- `docs/experiments/results/exp-v1-sync/k6/heavy_20rps-run1-summary.json`
- `docs/experiments/results/exp-v1-sync/k6/heavy_20rps-run2-summary.json`
- `docs/experiments/results/exp-v1-sync/k6/heavy_20rps-run3-summary.json`

`burst_5_to_30`
- `docs/experiments/results/exp-v1-sync/k6/burst_5_to_30-run1-summary.json`
- `docs/experiments/results/exp-v1-sync/k6/burst_5_to_30-run2-summary.json`
- `docs/experiments/results/exp-v1-sync/k6/burst_5_to_30-run3-summary.json`
