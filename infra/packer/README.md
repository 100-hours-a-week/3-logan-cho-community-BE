# Kaboocam Golden AMI (Packer)

`infra/packer`는 ASG 인스턴스 부팅 시간을 줄이기 위한 Golden AMI 빌드 구조입니다.

포함 항목:
- Docker Engine + Compose Plugin
- AWS CLI v2
- Amazon SSM Agent 활성화
- Amazon ECR Credential Helper
- 모니터링 스택 기본 파일(Node Exporter, cAdvisor, Promtail)
- 앱 컨테이너 실행 기본 파일(`docker-compose.yml`, `app.service`)

## 디렉터리

```text
infra/packer/
├── build.pkr.hcl
├── variables.pkr.hcl
├── example.pkrvars.hcl
├── scripts/
│   ├── setup.sh
│   └── cleanup.sh
└── files/
    ├── app/
    │   ├── docker-compose.yml
    │   └── app.env.example
    ├── monitoring/
    │   ├── docker-compose.yml
    │   ├── monitoring.env.example
    │   └── promtail-config.yaml
    └── systemd/
        ├── app.service
        └── monitoring.service
```

## 빌드 방법

```bash
cd infra/packer
cp example.pkrvars.hcl dev.pkrvars.hcl
packer init .
packer validate -var-file=dev.pkrvars.hcl .
packer build -var-file=dev.pkrvars.hcl .
```

빌드가 끝나면 `manifest.json`에서 생성된 `artifact_id`의 AMI ID를 확인할 수 있습니다.

## Terraform 연동

1. `infra/terraform/environments/<env>/terraform.tfvars`의 `ami_id`에 빌드된 AMI ID를 설정합니다.
2. 인스턴스 런타임 환경파일(`/etc/default/kaboocam-app`) 생성을 위해 `app_user_data`를 설정합니다.
3. ASG 인스턴스에서 `app.service`를 활성화해 컨테이너를 기동합니다.

## 민감정보 정책

- 실제 빌드 변수 파일(`*.pkrvars.hcl`)은 커밋하지 않습니다.
- `example.pkrvars.hcl`, `*.env.example`만 버전 관리합니다.
- 실제 시크릿은 SSM Parameter Store/Secrets Manager로 주입하는 방식을 권장합니다.
