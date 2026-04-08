# Experiment Terraform Environment

이 경로는 이미지 처리 아키텍처 실험용 Terraform 엔트리 포인트다.

## 역할

- `experiment/image-pipeline-evolution` 브랜치에서 사용하는 실험 전용 환경
- `v1 ~ v4` 버전 실험을 동일 베이스 위에서 점진 확장
- 태그 기준 실험 재현에 필요한 입력값 관리

## 예상 파일

- `main.tf`: 공통 모듈 호출
- `variables.tf`: 실험 공통 변수 정의
- `outputs.tf`: SSH, endpoint, queue, bucket 등 최소 출력
- `terraform.tfvars.example`: 공통 샘플 변수
- `versions/v1.tfvars` ~ `versions/v4.tfvars`: 단계별 활성화 옵션

## 실행 방식

예시:

```bash
cd infra/terraform/envs/experiment
terraform init
terraform plan -var-file=versions/v1.tfvars
terraform apply -var-file=versions/v1.tfvars
```

## 원칙

- tfvars는 버전 간 차이를 드러내는 최소 입력만 다르게 둔다
- App EC2, k6 EC2, Mongo 환경은 버전 간 고정한다
- 실험 이름 suffix와 prefix는 버전별로 구분 가능해야 한다
