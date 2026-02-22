# Infra Directory Guide

이 디렉터리는 인프라 관련 코드와 문서를 관리합니다.

## 규칙
- Terraform 코드는 `infra/terraform/` 하위에서 관리합니다.
- 환경별 분리는 `infra/terraform/environments/<env>/` 형태를 사용합니다.
- 재사용 모듈은 `infra/terraform/modules/` 하위로 관리합니다.
- 환경 공통(도메인 비종속) 모듈은 `infra/terraform/shared/modules/` 하위로 관리합니다.
- Golden AMI(Packer) 빌드 코드는 `infra/packer/` 하위에서 관리합니다.
