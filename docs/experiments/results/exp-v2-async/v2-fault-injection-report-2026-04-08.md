# V2 Fault Injection Report

## Scope

이 문서는 `V2 Async` 구조에 대해 `V3`, `V4`에서 보강한 reliability/correctness 포인트를 작은 fault injection으로 먼저 재현한 결과를 정리한다.

실행 환경:
- `db EC2 1대 + app ASG 2대 + ALB 1개`
- `V2` 앱 배포
- app node 2대는 ALB 뒤에서 동일 jar를 실행

## Probes

### 1. Save -> Publish Gap

- 파일: `docs/experiments/results/exp-v2-async/probes/save-publish-gap.json`
- 방법:
  - `Mongo save` 직후 `SQS publish` 전에 강제 예외를 주입
  - probe 제목 prefix로만 fault가 발동되게 한정
- 결과:
  - create status: `500`
  - post saved: `true`
  - imageStatus: `PENDING`
  - completedAt: `null`
- 해석:
  - `V2`는 `save`와 `publish`가 원자적이지 않아서, 이 구간에서 장애가 나면 orphan `PENDING` post가 남을 수 있다.

### 2. Duplicate Callback On Multiple App Nodes

- 파일: `docs/experiments/results/exp-v2-async/probes/duplicate-callback-multi-node.json`
- 방법:
  - 정상 completion 이후 같은 callback payload를 app node 2대의 `localhost:8080`에 각각 다시 전송
- 결과:
  - first status: `200`
  - second status: `200`
  - completedAt before: `2026-04-08T03:25:15.818Z`
  - completedAt after: `2026-04-08T03:26:16.244Z`
  - sideEffectReapplied: `true`
- 해석:
  - `V2`에는 idempotency guard가 없어서, 같은 callback을 여러 노드가 받아도 그대로 side effect를 다시 적용한다.

### 3. Poison Message Without DLQ

- 파일: `docs/experiments/results/exp-v2-async/probes/poison-message-no-dlq.json`
- 방법:
  - 존재하지 않는 S3 key를 가진 poison payload를 main queue에 직접 주입
- 결과:
  - DLQ configured: `false`
  - queue samples:
    - `t=0..25s` 동안 `notVisible=1` 유지
- 해석:
  - `V2`에는 DLQ가 없어서 poison message가 메인 queue retry 경로에 그대로 남는다.

## Conclusion

- `V2`는 요청 경로 성능 개선에는 성공했지만, 다음 failure mode를 그대로 가진다.
  - `save -> publish` gap으로 인한 orphan `PENDING` post
  - duplicate callback 재적용
  - poison message의 무기한 retry 경향
- 이 문서를 기준선으로 두고 보면:
  - `V3`는 `save -> publish` gap을 outbox로 보강하는 단계
  - `V4`는 duplicate / poison을 idempotent consumer + DLQ로 보강하는 단계
