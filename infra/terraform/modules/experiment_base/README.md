# experiment_base

공통 실험 인프라 모듈.

## 포함 리소스

- App EC2
- k6 EC2
- Security Group
- IAM Role / Instance Profile
- S3 bucket 또는 실험용 정책
- temp lifecycle rule
- Prometheus/Grafana 접근 포트와 node_exporter scrape 경로
- 공통 환경 변수 전달

## 사용 버전

- `v1`
- `v2`
- `v3`
- `v4`

## 설계 원칙

- 버전 간 비교를 위해 스펙을 고정한다
- 운영형 확장 구성을 넣지 않는다
- 실험 수행에 필요한 최소 출력만 제공한다
