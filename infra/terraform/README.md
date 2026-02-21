# Terraform Workspace

Terraform 코드는 `infra/terraform` 기준으로 환경 분리(dev/prod)와 모듈 재사용 구조를 따릅니다.

## 디렉터리 구조
```text
infra/terraform/
├─ backend.tf
├─ providers.tf
├─ versions.tf
├─ modules/
│  ├─ vpc/
│  ├─ nat-gateway/
│  ├─ security-group/
│  ├─ alb/
│  ├─ asg/
│  ├─ iam/
│  ├─ rds/
│  └─ elasticache/
└─ environments/
   ├─ dev/
   └─ prod/
```

## 사용 방법
- 각 환경 디렉터리에서 `backend.hcl.example`을 복사해 실제 backend 설정값을 채웁니다.
- 각 환경 디렉터리에서 `terraform.tfvars.example`을 복사해 환경값을 채웁니다.
- 초기화 예시:
  - `terraform -chdir=infra/terraform/environments/dev init -backend-config=backend.hcl`
  - `terraform -chdir=infra/terraform/environments/dev plan -var-file=terraform.tfvars`
