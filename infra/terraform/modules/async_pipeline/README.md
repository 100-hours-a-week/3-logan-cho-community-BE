# async_pipeline

비동기 이미지 처리 실험 인프라 모듈.

## 포함 리소스

- SQS Standard Queue
- Lambda
- Lambda IAM Role
- CloudWatch Log Group
- 선택적 DLQ

## 사용 버전

- `v2`
- `v3`
- `v4`

## 설계 원칙

- `v2 ~ v4` 동안 Lambda 핵심 설정은 고정한다
- `v4`에서만 DLQ를 활성화한다
- queue/lambda 이름은 버전 및 실험 구분이 가능해야 한다
