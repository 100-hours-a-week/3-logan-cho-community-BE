# Shared Terraform Modules

`infra/terraform/shared/modules`는 특정 서비스 도메인에 종속되지 않는 공통 모듈을 둡니다.

현재 포함 모듈:
- `private-content-delivery`: private S3 + CloudFront(OAC, Key Group)
- `iam-object-storage-policy`: S3 object prefix 기반 IAM 정책
- `iam-parameter-store-read-policy`: SSM Parameter Store 읽기 IAM 정책
- `ssm-parameters`: String/SecureString 파라미터 생성
