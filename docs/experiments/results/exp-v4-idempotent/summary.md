# exp-v4-idempotent Summary

실행 일시:
- 2026-04-05

실행 기준:
- 브랜치: `experiment/image-pipeline-evolution`
- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`
- 추가 안정성 지표: `duplicate side effect count`, `duplicate callback ignored count`, `DLQ count`
- 상태: `smoke + medium_10rps 1회 + stability probes`

원본 결과:
- `docs/experiments/results/exp-v4-idempotent/k6/*-summary.json`
- `docs/experiments/results/exp-v4-idempotent/k6/*-stdout.log`
- `docs/experiments/results/exp-v4-idempotent/metrics/*.json`
- `docs/experiments/results/exp-v4-idempotent/probes/*.json`

## Smoke

- `POST /posts p95`: `769.96ms`
- `API error rate`: `0.000000`
- `image completion p95`: `4095ms`
- `duplicate side effect count`: `0`
- `DLQ count`: `0`

## Medium

- 파일: `docs/experiments/results/exp-v4-idempotent/k6/medium_10rps-run1-summary.json`
- `POST /posts p95`: `62.32ms`
- `API error rate`: `0.001732`
- `image completion p95`: `3158.85ms`
- `processed job count`: `1189`
- `duplicate ignored count`: `1`
- `duplicate side effect count`: `0`
- `DLQ count`: `0`
- 해석: `V4`는 `medium_10rps`에서도 요청 경로 응답은 `V2/V3` 수준으로 유지하고, 중복 callback이 관찰돼도 side effect는 추가 반영되지 않았다.

## Probe Results

### duplicate delivery

- 파일: `docs/experiments/results/exp-v4-idempotent/probes/duplicate-delivery.json`
- `duplicateIgnoredCount`: `2`
- `duplicateSideEffectCount`: `0`
- 해석: 같은 `imageJobId` callback이 2회 추가로 들어와도 side effect는 1회만 반영됐다.

### poison message

- 파일: `docs/experiments/results/exp-v4-idempotent/probes/poison-message.json`
- 상태: 주입 및 redrive 확인 완료
- 증거:
  - Lambda log에서 `NoSuchKey` 실패 확인
  - main queue `in-flight` 후 `DLQ count = 1` 확인
- 해석: poison message는 main queue 안에서 무한 재시도되지 않고 최종적으로 `DLQ`로 격리됐다.

## Interpretation

- `V4`는 `outbox + relay` 위에 `processed jobs` 저장소를 추가해 callback 소비를 idempotent 하게 만들었다.
- duplicate replay에 대해 `duplicateIgnoredCount = 2`, `duplicateSideEffectCount = 0`을 확인했다.
- poison message는 실제로 Lambda 실패를 만들었고, 최종적으로 `DLQ`에 격리되는 것도 확인했다.
- 이번 문서는 `full load baseline`이 아니라 `stability-focused partial baseline`이다. 이후 `heavy`, `burst`는 같은 포맷으로 누적한다.
