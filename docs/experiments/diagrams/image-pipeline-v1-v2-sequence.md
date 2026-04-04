# Image Pipeline V1 vs V2 Sequence Diagrams

## V1 Sync

```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant Spring as Spring Server
    participant S3
    participant DB as MySQL / MongoDB
    participant Obs as k6 / Prometheus

    Note over Client,DB: V1은 요청 응답 안에서 이미지 처리 전체가 끝나야 한다

    Client->>Spring: POST /api/posts/images/presigned-url
    Spring-->>Client: presigned URL + objectKey
    Client->>S3: PUT temp image
    S3-->>Client: 200 / 204
    Client->>Spring: POST /api/posts\n(title, content, temp image key)
    Spring->>S3: temp 이미지 다운로드
    S3-->>Spring: 원본 이미지 bytes
    Note over Spring: resize / compress / thumbnail\nSpring 프로세스 내부 처리
    Spring->>S3: final / thumbnail 업로드
    Spring->>DB: 게시글 메타데이터 저장
    Spring-->>Client: 200 OK\n이미지 처리 완료 후 응답

    Obs->>Spring: k6 부하 인가
    Obs->>Spring: Prometheus scrape\n:9100 /actuator/prometheus
```

## V2 Async

```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant Spring as Spring Server
    participant SQS
    participant Lambda
    participant S3
    participant DB as MySQL / MongoDB
    participant Obs as k6 / Prometheus

    Note over Client,DB: V2는 요청 응답과 이미지 완료 처리를 분리한다

    Client->>Spring: POST /api/posts/images/presigned-url
    Spring-->>Client: presigned URL + objectKey
    Client->>S3: PUT temp image
    S3-->>Client: 200 / 204
    Client->>Spring: POST /api/posts\n(title, content, temp image key)
    Spring->>DB: 게시글 PENDING 저장
    Spring->>SQS: image job 발행
    Spring-->>Client: 200 OK\npostId + PENDING

    SQS->>Lambda: image job 전달
    Lambda->>S3: temp 이미지 다운로드
    S3-->>Lambda: 원본 이미지 bytes
    Note over Lambda: compress / thumbnail\n비동기 워커 처리
    Lambda->>S3: final / thumbnail 업로드
    Lambda->>Spring: callback\n/api/posts/internal/image-jobs/{postId}
    Spring->>DB: COMPLETED / FAILED 저장
    Client->>Spring: detail polling\nimageStatus 확인
    Spring-->>Client: COMPLETED / FAILED 상태 응답

    Obs->>Spring: k6 create + polling
    Obs->>Spring: Prometheus scrape
```

## Reading Guide

- `V1`: 응답시간 안에 이미지 처리 비용이 직접 포함된다.
- `V2`: 요청 응답은 빨라지지만, 완료 지연은 비동기 처리 구간으로 이동한다.
- 두 버전 모두 실제 시작점은 `presigned URL 발급 -> temp 업로드 -> create`다.
- 포트폴리오 본문 비교는 `POST /posts p95`, `API error rate`를 주지표로 사용한다.
- `image completion latency`와 observability는 구조 해석용 보조 지표다.
