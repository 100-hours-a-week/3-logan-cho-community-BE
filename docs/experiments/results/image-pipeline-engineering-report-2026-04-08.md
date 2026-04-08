# Image Pipeline Engineering Report

## 개요

이 문서는 이미지 업로드 파이프라인을 `V1 Sync -> V2 Async -> V3 Outbox -> V4 Idempotent + DLQ`로 단계적으로 개선하면서, 각 단계에서 어떤 가설을 세웠고 무엇을 검증했으며 결과가 무엇을 의미했는지 정리한 보고서다.

핵심 원칙은 두 가지였다.
- 성능 문제와 correctness 문제를 섞어서 보지 않는다.
- 구조를 바꿀 때마다 "왜 이 버전이 필요한가"를 실험으로 남긴다.

## 1. 문제 정의

초기 질문은 단순했다.

- 이미지 압축이 `POST /posts` 요청 경로 안에 들어가 있으면 실제 부하에서 어떻게 무너지는가?
- 요청 경로를 비동기로 분리하면 성능은 좋아지지만, reliability 문제는 어떤 형태로 남는가?
- 그 reliability 문제를 막기 위해 `outbox`, `idempotent consumer`, `DLQ` 같은 패턴을 넣었을 때 실제로 무엇이 달라지는가?

이 질문에 답하기 위해 실험을 두 축으로 나눴다.

- 성능 축:
  - `POST /posts p95`
  - `API error rate`
- 안정성 축:
  - `image completion latency p95`
  - orphan `PENDING` post
  - duplicate side effect
  - `DLQ count`

성능 비교의 1차 기준은 항상 `k6` 결과였고, Prometheus/Grafana는 병목을 해석하는 보조 수단으로만 사용했다.

## 2. 가설 1: 동기 이미지 처리가 요청 경로 병목일 것이다

### 가설

`V1`에서는 이미지 다운로드, 압축, 썸네일 생성, 업로드가 모두 요청 경로 안에 있다.  
이 구조라면 부하가 조금만 올라가도 API 응답시간과 실패율이 급격히 악화될 것이라고 가정했다.

### 검증 방법

- 구현:
  - `V1 Sync`
- 실험:
  - `medium_10rps`, `heavy_20rps`, `burst_5_to_30`
  - 시나리오별 3회 반복
- 문서:
  - [exp-v1-sync/summary.md](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v1-sync/summary.md)

### 결과

- `medium_10rps`: `POST /posts p95 = 44479.14ms`, `error rate = 0.324838`
- `heavy_20rps`: `POST /posts p95 = 60000.50ms`, `error rate = 0.329398`
- `burst_5_to_30`: `POST /posts p95 = 60000.32ms`, `error rate = 0.328990`

### 의미

가설은 맞았다.

- `medium`부터 이미 p95가 약 `44.5s`까지 올라갔다.
- `heavy`, `burst`에서는 사실상 `60s timeout ceiling`에 붙었다.
- 에러율도 세 시나리오 모두 약 `32%` 수준으로 유지됐다.

즉 `V1`의 핵심 문제는 "이미지 처리가 느리다"가 아니라, "무거운 이미지 처리를 요청 경로에 묶어둔 구조"였다.

## 3. 가설 2: 요청 경로에서 이미지 처리를 제거하면 API 성능은 회복될 것이다

### 가설

`V2`에서 Spring은 `PENDING` 게시글만 저장하고 SQS에 작업을 던진 뒤 응답하면, 요청 경로 p95와 에러율은 크게 낮아질 것이라고 봤다.

### 검증 방법

- 구현:
  - `V2 Async`
- 실험:
  - 같은 `medium`, `heavy`, `burst` 시나리오
- 문서:
  - [exp-v2-async/summary.md](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v2-async/summary.md)

### 결과

- baseline `medium_10rps`: `p95 = 85.38ms`, `error rate = 0.000000`, `completion p95 = 1232.00ms`
- baseline `heavy_20rps`: `p95 = 342.48ms`, `error rate = 0.000010`, `completion p95 = 27039.52ms`
- baseline `burst_5_to_30`: `p95 = 155.05ms`, `error rate = 0.000015`, `completion p95 = 36575.00ms`

### 의미

가설도 맞았고, 여기서 가장 큰 구조 개선이 일어났다.

- `V1 -> V2`에서 요청 경로 p95는 수십 초에서 수십~수백 ms대로 떨어졌다.
- API 실패율도 사실상 `0`에 가깝게 줄었다.

하지만 새로운 현상도 같이 생겼다.

- `completion latency`는 여전히 길었다.
- 즉 병목이 사라진 게 아니라, 요청 경로에서 비동기 후단으로 이동했다.

이 시점의 결론은 명확했다.

- `V2`는 성능 문제를 해결한 버전이다.
- 하지만 correctness를 충분히 다루는 버전은 아니다.

## 4. 다음 질문: V2는 빨라졌지만, 정말 안전한가?

이 시점부터 질문이 바뀌었다.

성능은 좋아졌지만, 비동기 구조라면 다음 failure mode가 실제로 가능하다.

- `save -> publish` 사이 장애가 나면 어떻게 되는가?
- 같은 callback/message가 중복 전달되면 어떻게 되는가?
- 처리 불가능한 poison message는 어디로 가는가?

이건 "위험해 보인다" 수준으로 쓰면 포트폴리오가 약해진다.  
그래서 `V2`에 대해 작은 `fault injection`을 넣어 failure mode를 먼저 고정했다.

## 5. 가설 3: V2에는 save-publish gap, duplicate callback, poison message 취약점이 남아 있을 것이다

### 검증 방법

- 구현:
  - `V2 fault injection`
- 문서:
  - [v2-fault-injection-report-2026-04-08.md](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v2-async/v2-fault-injection-report-2026-04-08.md)

### 5-1. Save -> Publish Gap

#### 가설

Mongo 저장 직후 SQS publish 전에 장애가 나면, 게시글은 저장됐지만 큐에는 작업이 가지 않는 orphan `PENDING` post가 남을 것이다.

#### 실험

- `save` 직후 `publish` 전에 강제 예외를 주입
- 결과 파일:
  - [save-publish-gap.json](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v2-async/probes/save-publish-gap.json)

#### 결과

- create status: `500`
- post saved: `true`
- imageStatus: `PENDING`
- completedAt: `null`

#### 의미

이 실험으로 `V2`의 핵심 reliability gap이 실제로 재현됐다.

- 요청은 실패처럼 보이지만
- Mongo에는 게시글이 남고
- 이후 completion으로 갈 경로가 없다

즉 `save`와 `publish`가 분리되어 있는 구조에서는, 이 간극을 메우는 장치가 필요하다.

### 5-2. Duplicate Callback On Multiple Nodes

#### 가설

idempotency guard가 없다면, 같은 callback이 여러 app node에 다시 들어와도 각 노드가 모두 side effect를 적용할 수 있다.

#### 실험

- 정상 completion 이후 같은 callback payload를 app node 2대에 각각 다시 전송
- 결과 파일:
  - [duplicate-callback-multi-node.json](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v2-async/probes/duplicate-callback-multi-node.json)

#### 결과

- first status: `200`
- second status: `200`
- `completedAt before = 2026-04-08T03:25:15.818Z`
- `completedAt after = 2026-04-08T03:26:16.244Z`
- `sideEffectReapplied = true`

#### 의미

이건 "중복 전달이 와도 별일 없을 것"이 아니라,  
실제로 중복 callback이 받아들여지고 side effect가 다시 적용된다는 뜻이다.

즉 멀티 노드 환경에서 callback correctness를 앱이 직접 보호하지 않으면,  
같은 작업 완료가 여러 번 반영될 수 있다.

### 5-3. Poison Message Without DLQ

#### 가설

DLQ가 없으면 처리 불가능한 poison message는 메인 queue retry 경로에 계속 남을 것이다.

#### 실험

- 존재하지 않는 S3 key를 가진 payload를 main queue에 직접 주입
- 결과 파일:
  - [poison-message-no-dlq.json](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v2-async/probes/poison-message-no-dlq.json)

#### 결과

- `DLQ configured = false`
- `t=0..25s` 동안 `notVisible=1` 유지

#### 의미

poison message가 격리되지 않고 메인 queue retry 경로 안에 남아 있다는 뜻이다.

즉 `V2`는:
- 요청 경로는 빨라졌지만
- reliability/correctness 문제는 그대로 안고 있다.

## 6. 선택지 비교: 이 문제들을 어떻게 해결할 것인가

이 시점에서 가능한 방향은 여러 개였다.

### 선택지 A. V2 유지

- 장점:
  - 구조가 단순하다
  - 요청 경로는 이미 충분히 빠르다
- 단점:
  - `save-publish gap`을 막지 못한다
  - duplicate callback에 취약하다
  - poison message를 격리하지 못한다

### 선택지 B. Outbox만 추가

- 장점:
  - `save-publish gap`을 줄일 수 있다
  - 발행 기록을 남길 수 있다
- 단점:
  - duplicate callback은 그대로 남는다
  - poison message는 여전히 별도 보호가 없다

### 선택지 C. Outbox + Idempotent Consumer + DLQ

- 장점:
  - 발행 경로와 소비 경로를 각각 분리해서 보호할 수 있다
  - 문제를 단계적으로 설명하기 좋다
- 단점:
  - 구조가 더 복잡하다
  - completion latency 자체를 줄이는 구조는 아니다

### 내가 선택한 방식

한 번에 모든 걸 바꾸지 않고 단계적으로 갔다.

- `V3`: outbox
- `V4`: idempotent consumer + DLQ

이렇게 나누면:
- `save-publish gap`은 `V3`가 해결하는 문제
- duplicate / poison은 `V4`가 해결하는 문제
로 역할을 분리할 수 있다.

즉 "패턴을 다 넣었다"가 아니라,  
"각 failure mode에 어떤 보호장치를 붙였는지"를 단계적으로 설명할 수 있다.

## 7. V3: Save -> Publish Gap을 줄이기 위한 선택

### 가설

게시글 저장과 발행 payload 기록을 같은 저장 경로에 남기면, publish 실패가 나도 발행 사실을 나중에 복구할 수 있다.

### 구현

- 게시글 저장과 함께 outbox 문서 저장
- relay가 outbox를 읽어 SQS publish

### 실험

- single-node baseline
- 이후 `db EC2 + app ASG + ALB` 멀티 노드 재실행
- 문서:
  - [v3-baseline-report-2026-04-05.md](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v3-outbox/v3-baseline-report-2026-04-05.md)

### 결과

multi-ASG 재실행 기준:

- `medium`: `p95 = 127.31ms`, `error rate = 0.000033`, `completion p95 = 48018.25ms`
- `heavy`: `p95 = 1140.08ms`, `error rate = 0.000017`, `completion p95 = 88290.75ms`
- `burst`: `p95 = 57.27ms`, `error rate = 0.000000`, `completion p95 = 74904.00ms`

### 의미

`V3`의 핵심은 성능 개선이 아니다.

- request path는 여전히 짧게 유지됐다
- 대신 게시글 저장과 발행 기록을 같이 보존할 수 있게 됐다

즉 `V3`는 `V2`의 `save-publish gap`에 대한 reliability 보강이다.

하지만 새로운 한계도 보였다.

- completion latency는 여전히 길다
- `burst`에선 orphan pending post가 남는다

즉 outbox는 "유실 방지"에는 도움되지만,  
"후단 처리량"까지 해결하진 않는다.

## 8. V4: Duplicate / Poison을 correctness 관점에서 막기 위한 선택

### 가설

callback 처리 전에 `processed jobs`로 `imageJobId`를 선점하고, poison message는 DLQ로 격리하면:

- duplicate side effect는 0으로 만들 수 있고
- poison message는 메인 retry 경로 밖으로 뺄 수 있다

### 구현

- callback 처리 전 `imageJobId` unique 기반 선점
- duplicate callback은 무시
- main queue에 DLQ 연결

### 실험

- duplicate probe
- poison probe
- multi-ASG 재실행
- 문서:
  - [v4-baseline-report-2026-04-05.md](/home/cho/projects/3-logan-cho-community-BE/docs/experiments/results/exp-v4-idempotent/v4-baseline-report-2026-04-05.md)

### 결과

multi-ASG 재실행 기준:

- `medium`: `p95 = 67.48ms`, `error rate = 0.000066`, `completion p95 = 36349.60ms`
- `heavy`: `p95 = 87.96ms`, `error rate = 0.000000`, `completion p95 = 76560.70ms`
- `burst`: `p95 = 65.36ms`, `error rate = 0.000344`, `completion p95 = 68516.45ms`

정합성 지표:

- `duplicate side effect count = 0`
- `DLQ count = 0` in rerun

기존 probe:

- duplicate probe: `duplicateIgnoredCount = 2`, `duplicateSideEffectCount = 0`
- poison probe: `DLQ count = 1`

### 의미

`V4`는 성능 최적화 버전이 아니다.

대신 correctness를 통제하는 버전이다.

- multi-node에서도 callback 중복을 side effect 없이 처리했다
- poison message도 메인 retry 경로 밖으로 격리할 수 있게 됐다

즉 `V4`는 `V2`에서 실제로 재현한 duplicate / poison failure mode에 대한 직접적인 대답이다.

## 9. 멀티 ASG 재실험이 의미한 것

single-node baseline만으로는 "패턴이 동작한다" 정도까지만 말할 수 있다.  
하지만 실제로는 Spring 노드가 여러 대인 상황에서 더 문제가 잘 드러난다.

그래서 `V3`, `V4`는:

- `db EC2 + app ASG 2대 + ALB`
- shared data
- callback via ALB

구조로 다시 돌렸다.

이 재실험이 보여준 건 두 가지다.

1. request path는 멀티 노드에서도 유지된다
- `V3`, `V4` 모두 API p95와 error rate는 구조적으로 버틴다

2. 병목은 여전히 async completion 쪽이다
- completion p95는 여전히 수십 초
- 즉 병목은 API 서버보다 후단 이미지 처리량에 있다

이건 중요한 엔지니어링 포인트였다.

- `V1`의 병목은 요청 경로
- `V2+`의 병목은 비동기 후단

즉 개선을 통해 병목을 없앤 것이 아니라,  
잘못된 병목 위치를 올바른 곳으로 이동시킨 것이다.

## 10. 최종 결론

이번 실험의 핵심 결론은 아래처럼 정리할 수 있다.

### 1. V1 -> V2

가설:
- 요청 경로에서 이미지 처리를 빼면 성능이 회복될 것이다.

검증 결과:
- 맞았다.

의미:
- 가장 큰 성능 개선은 이 구간에서 일어났다.

### 2. V2 -> V3

가설:
- `save-publish gap`은 outbox로 줄일 수 있다.

검증 결과:
- `V2`에서 orphan `PENDING` post를 실제로 재현했고,
- `V3`는 게시글 저장과 발행 기록을 함께 남기는 구조로 바뀌었다.

의미:
- `V3`는 성능 개선보다 publish reliability를 다루는 단계다.

### 3. V3 -> V4

가설:
- duplicate callback과 poison message는 idempotent consumer + DLQ로 통제할 수 있다.

검증 결과:
- `V2`에서 duplicate side effect 재적용과 poison retry 잔류를 재현했고,
- `V4`에서는 duplicate side effect와 DLQ 지표가 안정적으로 통제됐다.

의미:
- `V4`는 correctness를 보강하는 단계다.

## 11. 이 보고서를 포트폴리오에 넣을 때의 메시지

이 프로젝트를 포트폴리오에 넣을 때 가장 중요한 메시지는 아래다.

- 처음에는 요청 경로 안에 이미지 압축이 들어 있어 API가 medium 부하부터 무너졌다.
- 먼저 비동기화해서 성능 병목을 요청 경로에서 제거했다.
- 그 다음, 비동기 구조에 남는 `save-publish gap`, duplicate callback, poison message를 fault injection으로 실제 재현했다.
- 그 failure mode를 기준선으로 삼아 `V3`에서는 outbox, `V4`에서는 idempotent consumer와 DLQ를 추가했다.
- 마지막으로 멀티 ASG 환경에서도 request path와 correctness가 유지되는지 다시 확인했다.

즉 이 실험은 "패턴을 도입했다"가 아니라,
"어떤 failure mode가 있었고, 그것을 어떤 가설로 해결했으며, 실험으로 무엇이 달라졌는지를 단계적으로 검증했다"는 이야기로 읽혀야 한다.
