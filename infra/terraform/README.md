# Terraform Workspace

Terraform 코드는 이 경로를 기준으로 관리합니다.

## 권장 구조
```text
infra/terraform/
├─ envs/
│  ├─ dev/
│  ├─ stage/
│  └─ prod/
└─ modules/
```

## 운영 원칙
- 환경별 상태 파일은 분리해서 관리합니다.
- 공통 리소스 로직은 `modules/`로 분리합니다.
