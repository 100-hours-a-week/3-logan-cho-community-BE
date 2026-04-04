# Terraform Workspace

이미지 처리 아키텍처 실험용 Terraform 기준 문서다.
이번 실험의 목적은 운영 서비스 배포가 아니라 버전 간 비교 가능한 재현 환경을 만드는 것이다.

## 설계 원칙

- 단일 리전, 단일 App EC2, 단일 k6 EC2를 기본으로 유지한다
- `v1 ~ v4`를 하나의 공통 베이스 위에서 점진 확장한다
- 과도한 모듈 분리를 피하고, 실험 수행에 필요한 수준까지만 구성한다
- main/dev용 인프라와 실험용 인프라를 혼합하지 않는다
- temp S3 lifecycle rule은 자연스럽게 포함한다

## 목표 리소스

Terraform으로 관리할 대상:

- App EC2
- k6 EC2
- Security Group
- IAM Role / Instance Profile
- S3 Bucket 및 lifecycle rule
- SQS Queue
- DLQ
- Lambda
- Lambda Role
- CloudWatch Log Group
- 실험용 환경 변수 주입에 필요한 최소 구성

## 권장 구조

```text
infra/terraform/
├─ README.md
├─ envs/
│  └─ experiment/
│     ├─ README.md
│     ├─ main.tf
│     ├─ variables.tf
│     ├─ outputs.tf
│     ├─ terraform.tfvars.example
│     └─ versions/
│        ├─ v1.tfvars
│        ├─ v2.tfvars
│        ├─ v3.tfvars
│        └─ v4.tfvars
└─ modules/
   ├─ experiment_base/
   │  └─ README.md
   └─ async_pipeline/
      └─ README.md
```

## 모듈 역할

### `modules/experiment_base`

공통 베이스를 담당한다.

- App EC2
- k6 EC2
- Security Group
- IAM Role / Instance Profile
- S3
- lifecycle rule
- 공통 환경 변수

이 모듈은 `v1 ~ v4` 모두에서 사용한다.

### `modules/async_pipeline`

비동기 실험에 필요한 AWS 리소스를 담당한다.

- SQS main queue
- Lambda
- Lambda log group
- 선택적 DLQ

이 모듈은 `v2 ~ v4`에서 사용한다.
`v4`에서는 DLQ 기능만 추가 활성화한다.

## 버전별 리소스 차이

### v1

- `experiment_base`만 사용
- SQS 없음
- Lambda 없음

### v2

- `experiment_base` 유지
- `async_pipeline` 추가
- SQS Standard Queue 추가
- Lambda 추가

### v3

- 인프라 수준은 `v2`와 동일
- Outbox는 애플리케이션/DB 구조 변경으로 처리

### v4

- `v3` 유지
- `async_pipeline`에서 DLQ 활성화

## 실험 전/후 정리 대상

실험 전 정리:

- Mongo 테스트 데이터
- outbox 컬렉션
- processed jobs 컬렉션
- SQS queue
- S3 실험 prefix

실험 후 기록:

- tfvars 버전
- 적용 시점 git tag
- 사용한 리전
- 사용한 EC2 타입
- Lambda 고정 설정
- SQS 고정 설정

## 실행 원칙

1. `envs/experiment` 기준으로 작업한다
2. `versions/v1.tfvars` ~ `versions/v4.tfvars`로 단계별 활성 리소스를 조정한다
3. 버전 간 공통 스펙은 tfvars에서 바꾸지 않는다
4. 버전 간 바뀌는 것은 활성 리소스와 일부 이름 suffix 정도로 제한한다

## 주의

- `v1 -> v2` 비교에서 EC2 타입, 리전, Mongo, 이미지 세트, 압축 정책을 바꾸지 않는다
- `v2 -> v3`는 인프라 차이가 아니라 애플리케이션 구조 차이여야 한다
- `v4`에서만 DLQ를 추가한다
