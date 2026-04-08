# Experiment Observability

이미지 처리 아키텍처 실험의 메트릭 수집 기준은 `Prometheus + Grafana`로 고정한다.

## 원칙

- EC2/애플리케이션 메트릭의 기준 수집원은 `Prometheus`
- 실험 중 비교용 스크린샷과 수치 확인은 `Grafana`
- 실험의 1차 비교 지표는 `k6` 기반 `성공률`과 `응답시간`이다
- Prometheus/Grafana는 병목과 이상 징후를 해석할 때 보는 보조 수단이다
- `pidstat`, `top`, `CloudWatch 단건 조회`, 수동 SSH 확인은 보조 진단용으로만 사용
- 포트폴리오에 쓰는 기준 수치는 항상 Prometheus/Grafana 기준으로 정리

## 수집 대상

### App EC2 Host

- EC2 host CPU
- EC2 host memory
- EC2 network

수집 방식:

- `node_exporter`를 App EC2에 설치
- Prometheus가 App EC2의 `:9100/metrics`를 scrape

### Spring Boot Application

- `POST /posts` 관련 애플리케이션 메트릭
- JVM 메모리
- Spring process CPU

수집 방식:

- Spring Boot Actuator Prometheus endpoint 사용
- Prometheus가 App EC2의 `/actuator/prometheus`를 scrape

핵심 지표:

- `Spring CPU`
  - 우선 `process_cpu_usage`
  - 필요 시 `system_cpu_usage`를 보조로 함께 본다

### k6 / 실험 실행

- k6 raw 결과는 기존처럼 summary JSON과 stdout 로그로 보관
- 요청 latency와 error rate는 k6 결과 파일 기준으로 정리
- Grafana는 EC2/App 상태 확인과 실험 시각 스냅샷 용도로 사용

## 배치 원칙

- Prometheus와 Grafana는 실험 전용 보조 스택으로 취급
- 별도 EC2를 늘리지 않고, 우선 `k6 EC2`에 함께 두는 것을 기본으로 한다
- App EC2에는 `node_exporter`와 Spring Actuator만 노출한다
- Prometheus scrape 대상은 App EC2 `private IP`를 사용한다

## 설치 기준

- App EC2: `scripts/experiments/observability/install-node-exporter.sh`
- k6 EC2: `scripts/experiments/observability/install-monitoring-stack.sh`
- 전체 설치 및 검증: `scripts/experiments/observability/setup.sh`

기본 대시보드:

- `Image Pipeline Experiment Overview`
- 패널: `App EC2 CPU`, `Spring Process CPU`, `JVM Heap Used`, `Scrape Status`

## 포트폴리오 기준

아래 항목은 Grafana 캡처 기준으로 남긴다.

- App EC2 CPU
- Spring CPU
- 실험 시각 범위

아래 항목은 k6 결과 파일 기준으로 남긴다.

- `POST /posts p95`
- `API error rate`
- `completion latency`

## 금지 사항

- 실험 비교표에 `pidstat` 수치를 직접 넣지 않는다
- 버전별로 메트릭 수집 방법을 바꾸지 않는다
- 어떤 버전은 CloudWatch, 어떤 버전은 Prometheus처럼 혼용하지 않는다
