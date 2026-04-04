# Fixed Conditions

## 공통

- Region
- App EC2 instance type
- k6 EC2 instance type
- MongoDB environment
- Java version
- JVM options
- Spring 주요 설정
- 테스트 이미지 세트
- 이미지 압축 정책
- 대표 실험 시나리오
- Metric collection stack: `Prometheus + Grafana`
- App host metrics: `node_exporter`
- Spring app metrics: `/actuator/prometheus`

## Lambda

- Memory
- Timeout
- Reserved concurrency
- Batch size
- Runtime

## SQS

- Queue type
- Visibility timeout
- Retention

참고:
- DLQ는 `v4`에서만 추가한다
- main queue 기본 조건은 버전 간 유지한다
