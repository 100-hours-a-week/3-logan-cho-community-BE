# 성능 테스트 및 개선 가이드

이 문서는 애플리케이션의 성능을 체계적으로 측정하고 개선하는 전체 프로세스를 설명합니다.

## 🖥️ 테스트 환경

본 성능 테스트는 다음 환경을 전제로 합니다:

- **테스트 실행 환경**: Ubuntu 24.04 EC2 인스턴스
- **테스트 대상**: 별도의 EC2 인스턴스에 배포된 애플리케이션
- **테스트 도구**: Docker Compose (k6 + InfluxDB + Grafana)
- **네트워크**: 같은 AWS 리전 내 VPC (네트워크 지연 최소화)

## 📋 목차

1. [3단계 테스트 전략](#3단계-테스트-전략)
2. [테스트 스크립트 개요](#테스트-스크립트-개요)
3. [사전 준비](#사전-준비)
4. [성능 개선 프로세스](#성능-개선-프로세스)
5. [Grafana 대시보드 설정](#grafana-대시보드-설정)
6. [테스트 스크립트 상세 설명](#테스트-스크립트-상세-설명)
7. [결과 분석 방법](#결과-분석-방법)

---

## 3단계 테스트 전략

본 프로젝트는 **사용자 분리 전략**을 통해 정확하고 재현 가능한 성능 테스트를 제공합니다.

### 사용자 패턴 구분

| 패턴 | 목적 | 개수 | 사용 단계 |
|------|------|------|----------|
| `dummy_user_{0-49}` | 배경 데이터 생성 | 50명 | Step 1 |
| `perf_tester_{0-29}` | 성능 테스트 | 30명 | Step 2 |

### 전략의 장점

1. **데이터 오염 방지**: 배경 데이터와 테스트 활동이 완전히 분리됩니다
2. **재현 가능성**: 동일한 배경 데이터로 여러 번 테스트 가능
3. **정확한 메트릭**: 좋아요 중복 등의 오류가 발생하지 않습니다

---

## 테스트 스크립트 개요

### Step 1: 배경 데이터 생성

| 스크립트 | 목적 | 실행 횟수 |
|---------|------|----------|
| `step1-seed-background.js` | 배경 데이터 생성 (dummy_user 패턴) | 최초 1회 |

### Step 2: 성능 측정

| 스크립트 | 목적 | 실행 시점 |
|---------|------|----------|
| `step2-baseline-test.js` | 베이스라인 성능 측정 | 개선 전/후 |
| `step2-endpoint-benchmark.js` | 각 엔드포인트별 성능 측정 | 개선 전/후 |
| `step2-bottleneck-analysis.js` | 병목 지점 탐지 | 개선 전 |
| `step2-realistic-load-test.js` | 실제 사용자 패턴 시뮬레이션 | 검증용 |

### Step 3: 결과 분석

| 스크립트 | 목적 | 실행 시점 |
|---------|------|----------|
| `step3-compare-results.js` | 개선 전/후 비교 | 개선 후 |

---

## 사전 준비

### 1. 테스트 실행 EC2 인스턴스 설정

#### Docker 및 Docker Compose 설치 (Ubuntu 24.04)

```bash
# Docker 설치
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker 사용자 권한 설정
sudo usermod -aG docker $USER
newgrp docker

# 설치 확인
docker --version
docker compose version
```

#### 프로젝트 클론 및 디렉토리 설정

```bash
# Git 클론
git clone <repository-url>
cd <project-directory>/k6-script

# 결과 저장 디렉토리 생성
mkdir -p performance-results

# Node.js 설치 (결과 비교 스크립트용)
sudo apt-get install -y nodejs npm
```

### 2. 테스트 대상 애플리케이션 확인

#### 애플리케이션 서버 정보 확인

테스트 대상 EC2 인스턴스의 주소와 포트를 확인합니다:

```bash
# 예시
# 프라이빗 IP: 10.0.1.100 (같은 VPC 내에서 권장)
# 퍼블릭 IP: 52.78.123.45 (외부에서 접근 시)
# 포트: 8080
```

**BASE_URL 환경변수 설정:**
```bash
# 프라이빗 IP 사용 (권장 - 같은 VPC 내)
export BASE_URL=http://10.0.1.100:8080

# 퍼블릭 IP 사용
export BASE_URL=http://52.78.123.45:8080

# 도메인 사용
export BASE_URL=https://api.your-domain.com
```

#### 이메일 검증 비활성화 확인

테스트 대상 서버의 `MemberService.java`에서 이메일 검증이 비활성화되어 있는지 확인:

```java
// emailVerifier.validateToken(...) // 주석 처리됨
```

### 3. 보안 그룹 설정

테스트 실행 EC2 → 애플리케이션 EC2 간 통신을 허용해야 합니다:

```bash
# 애플리케이션 EC2의 보안 그룹 인바운드 규칙에 추가:
# Type: Custom TCP
# Port: 8080
# Source: <테스트 실행 EC2의 보안 그룹 ID> 또는 프라이빗 IP
```

### 4. InfluxDB와 Grafana 시작

```bash
# k6-script 디렉토리에서 실행
cd k6-script

# InfluxDB와 Grafana 컨테이너 시작
docker compose up -d influxdb grafana

# 컨테이너 상태 확인
docker compose ps

# 로그 확인
docker compose logs -f grafana
```

**접속 정보:**
- Grafana: http://<EC2-Public-IP>:3000
- 기본 계정: admin / admin
- InfluxDB: http://localhost:8086

---

## 성능 개선 프로세스

### 전체 프로세스 흐름

```
Step 1: 배경 데이터 생성 (dummy_user 패턴)
   ↓
Step 2: 성능 측정 (perf_tester 패턴)
   ├─ 베이스라인 측정 (개선 전)
   ├─ 엔드포인트 벤치마크 (개선 전)
   └─ 병목 분석
   ↓
코드 리팩토링 및 개선
   ↓
Step 2: 성능 측정 (개선 후)
   ├─ 베이스라인 측정 (개선 후)
   └─ 엔드포인트 벤치마크 (개선 후)
   ↓
Step 3: 결과 비교 및 성능 개선 수치화
```

### 단계별 실행 명령어

**환경변수 설정 (테스트 시작 전 필수):**
```bash
# 테스트 대상 서버 주소 설정 (프라이빗 IP 권장)
export BASE_URL=http://10.0.1.100:8080

# 또는 퍼블릭 IP
export BASE_URL=http://52.78.123.45:8080
```

#### Step 1: 배경 데이터 생성

```bash
docker compose run --rm k6 run \
  --env BASE_URL=$BASE_URL \
  /scripts/step1-seed-background.js
```

**생성되는 데이터:**
- 사용자 50명 (`dummy_user_0@test.com` ~ `dummy_user_49@test.com`)
- 게시글 150개
- 댓글 약 450개 (게시글당 평균 3개)
- 좋아요 약 750개 (게시글당 평균 5개)

**특징:**
- 4개의 시나리오가 병렬로 실행되어 빠른 데이터 생성
- 성능 메트릭 수집 없음 (순수 데이터 생성)
- **최초 1회만 실행** (배경 데이터는 모든 테스트에서 재사용)

---

#### Step 2-1: 베이스라인 측정 (개선 전)

```bash
docker compose run --rm k6 run \
  --env BASE_URL=$BASE_URL \
  --env TEST_LABEL=before \
  /scripts/step2-baseline-test.js
```

**특징:**
- setup() 단계에서 `perf_tester_{0-29}` 패턴으로 30명의 테스트 사용자 생성
- 생성된 Access Token을 테스트에서 재사용 (중복 로그인 없음)
- 배경 데이터 확인 후 성능 측정 시작
- `amILiking` 필드를 확인하여 좋아요/취소 처리 (400 오류 방지)
- **메트릭이 InfluxDB에 자동 저장되어 Grafana에서 실시간 모니터링 가능**

**결과 파일:** `performance-results/before-YYYY-MM-DD.json`

---

#### Step 2-2: 엔드포인트 벤치마크 (개선 전)

```bash
docker compose run --rm k6 run \
  --env BASE_URL=$BASE_URL \
  --env TEST_LABEL=endpoint-before \
  /scripts/step2-endpoint-benchmark.js
```

**특징:**
- setup() 단계에서 20명의 테스트 사용자 생성
- 각 엔드포인트를 개별적으로 1분씩 벤치마크
- 총 6분 소요

---

#### Step 2-3: 병목 분석

```bash
docker compose run --rm k6 run \
  --env BASE_URL=$BASE_URL \
  --env TEST_LABEL=bottleneck \
  /scripts/step2-bottleneck-analysis.js
```

**특징:**
- setup() 단계에서 20명의 테스트 사용자 생성
- 4가지 병목 시나리오 실행 (동시 좋아요, 대량 조회, 대량 쓰기, N+1 쿼리)
- `amILiking` 체크로 정확한 race condition 테스트

**주의 사항:**
- 이 테스트는 의도적으로 서버에 높은 부하를 주므로 프로덕션 환경에서는 실행하지 마세요.
- 테스트 중 로그를 확인하여 병목 지점을 파악하세요.

---

#### 코드 리팩토링

병목 분석 결과를 바탕으로 코드를 개선합니다.

**주요 개선 포인트:**

1. **동시성 이슈 해결**
   - 좋아요 기능의 race condition 해결 (DB 유니크 제약조건, 낙관적 락 등)
   - 회원가입 이메일 중복 체크 개선

2. **쿼리 최적화**
   - N+1 쿼리 문제 해결 (Batch Fetch, Join Fetch)
   - 인덱스 추가
   - 불필요한 쿼리 제거

3. **캐싱 전략**
   - Redis 캐시 적용 (회원 프로필, 인기 게시글 등)
   - 로컬 캐시 활용 (조회수 카운팅)

4. **DB 커넥션 풀 튜닝**
   - HikariCP 설정 최적화
   - 커넥션 타임아웃 조정

---

#### Step 2-4: 베이스라인 측정 (개선 후)

```bash
docker compose run --rm k6 run \
  --env BASE_URL=$BASE_URL \
  --env TEST_LABEL=after \
  /scripts/step2-baseline-test.js
```

**중요:**
- 배경 데이터(dummy_user)는 그대로 유지
- 새로운 perf_tester 사용자들이 setup()에서 생성됨
- 동일한 배경 데이터로 테스트하여 비교 가능

**결과 파일:** `performance-results/after-YYYY-MM-DD.json`

---

#### Step 2-5: 엔드포인트 벤치마크 (개선 후)

```bash
docker compose run --rm k6 run \
  --env BASE_URL=$BASE_URL \
  --env TEST_LABEL=endpoint-after \
  /scripts/step2-endpoint-benchmark.js
```

---

#### Step 3: 결과 비교

```bash
node step3-compare-results.js \
  performance-results/before-2024-01-01.json \
  performance-results/after-2024-01-01.json
```

**출력:**
- 각 메트릭별 개선율
- 유의미한 개선 사항 (10% 이상)
- 성능 저하 항목 (5% 이상)
- 전반적인 성능 개선률
- 마크다운 보고서 파일 생성

---

## Grafana 대시보드 설정

### 1. Grafana 접속

브라우저에서 http://<EC2-Public-IP>:3000 접속

**기본 로그인 정보:**
- Username: `admin`
- Password: `admin`

### 2. InfluxDB 데이터소스 확인

InfluxDB 데이터소스는 자동으로 프로비저닝됩니다.

1. 좌측 메뉴 > Configuration > Data sources
2. InfluxDB가 기본 데이터소스로 설정되어 있는지 확인
   - URL: `http://influxdb:8086`
   - Database: `k6`

### 3. K6 대시보드 Import

Grafana에서 공식 K6 대시보드를 import합니다.

**방법 1: Grafana 대시보드 ID 사용**

1. 좌측 메뉴 > Dashboards > Import
2. Dashboard ID 입력: `2587` (공식 k6 Load Testing Results 대시보드)
3. Load 클릭
4. InfluxDB 데이터소스 선택
5. Import 클릭

**방법 2: JSON 파일 사용**

1. https://grafana.com/grafana/dashboards/2587 접속
2. Download JSON 클릭
3. Grafana > Dashboards > Import
4. Upload JSON file 선택
5. 다운로드한 JSON 파일 업로드
6. InfluxDB 데이터소스 선택
7. Import 클릭

### 4. 대시보드 활용

테스트 실행 중 Grafana 대시보드에서 실시간으로 다음 메트릭을 확인할 수 있습니다:

- **Virtual Users (VUs)**: 현재 활성 가상 사용자 수
- **Request Rate**: 초당 요청 수
- **Response Time**: 응답 시간 (p50, p95, p99)
- **Error Rate**: 에러 발생률
- **HTTP Req Duration**: HTTP 요청별 소요 시간
- **Custom Metrics**: 각 테스트 스크립트의 커스텀 메트릭

### 5. 대시보드 필터링

대시보드 상단의 변수를 사용하여 특정 테스트 결과만 필터링할 수 있습니다:

- **Test Label**: `before`, `after`, `bottleneck` 등으로 필터링
- **Endpoint**: 특정 엔드포인트별 결과 확인

---

## 테스트 스크립트 상세 설명

### step2-baseline-test.js

**목적:** 전체적인 애플리케이션 성능을 일정한 부하로 측정

**테스트 조건:**
- VU (Virtual Users): 30명
- 지속 시간: 5분
- 모든 주요 기능을 순차적으로 테스트

**측정 메트릭:**
- `baseline_list_posts_duration`: 게시글 목록 조회 시간
- `baseline_post_detail_duration`: 게시글 상세 조회 시간
- `baseline_create_post_duration`: 게시글 작성 시간
- `baseline_create_comment_duration`: 댓글 작성 시간
- `baseline_like_action_duration`: 좋아요 처리 시간
- 각 기능의 성공률

**사용 시기:**
- 코드 변경 전 베이스라인 측정
- 코드 변경 후 개선 효과 확인

### step2-endpoint-benchmark.js

**목적:** 각 엔드포인트를 개별적으로 집중 테스트

**테스트 시나리오:**
- 각 엔드포인트를 1분씩 순차적으로 테스트
- 총 6분 소요

**측정 엔드포인트:**
1. 게시글 목록 조회 (20 VU)
2. 게시글 상세 조회 (20 VU)
3. 게시글 작성 (10 VU)
4. 좋아요/취소 (20 VU)
5. 댓글 작성 (15 VU)
6. 댓글 목록 조회 (20 VU)

**사용 시기:**
- 특정 엔드포인트의 성능 문제 파악
- 개별 기능의 처리량(throughput) 측정

### step2-bottleneck-analysis.js

**목적:** 병목 지점을 찾아내기 위한 스트레스 테스트

**테스트 시나리오:**

1. **동시 좋아요 테스트** (0~2분)
   - 100명이 동시에 같은 게시글에 좋아요/취소 반복
   - Race condition 검출

2. **대량 조회 테스트** (2분 30초~4분 30초)
   - 초당 100개 조회 요청
   - 캐시 효율성 측정

3. **대량 쓰기 테스트** (5분~7분)
   - 초당 30개 쓰기 요청
   - DB 커넥션 풀 병목 검출

4. **N+1 쿼리 감지** (7분 30초~9분)
   - 게시글 목록 조회 시 쿼리 수 분석

**사용 시기:**
- 개선 전 문제점 파악
- 개선 후 문제 해결 확인

### step2-realistic-load-test.js

**목적:** 실제 사용자 행동 패턴 시뮬레이션

**사용자 행동 비율:**
- 게시글 목록 조회: 50%
- 게시글 상세 조회: 25%
- 게시글 작성: 10%
- 댓글 작성: 10%
- 좋아요: 5%

**부하 단계:**
1. 워밍업: 10명 (30초)
2. 안정 부하: 30명 (5분)
3. 고부하: 50명 (5분)
4. 피크: 100명 (3분)
5. 쿨다운: 0명 (1분)

**사용 시기:**
- 전체 시스템의 실전 검증
- 예상 트래픽 처리 능력 확인

---

## 결과 분석 방법

### 주요 지표 해석

#### 1. 응답 시간 (Duration)

```
p50: 중앙값 - 50%의 요청이 이 시간 안에 완료
p95: 95번째 백분위수 - 95%의 요청이 이 시간 안에 완료
p99: 99번째 백분위수 - 99%의 요청이 이 시간 안에 완료
```

**좋은 기준:**
- p50 < 500ms: 우수
- p95 < 2000ms: 양호
- p99 < 5000ms: 허용 가능

#### 2. 성공률 (Success Rate)

```
95% 이상: 양호
90~95%: 개선 필요
90% 미만: 심각한 문제
```

#### 3. 처리량 (Throughput)

```
req/s (초당 요청 수)
값이 높을수록 좋음
```

### 병목 지점 판단 기준

#### 동시성 문제

```
✅ 정상: concurrent_like_errors < 10
⚠️  주의: concurrent_like_errors 10~50
❌ 문제: concurrent_like_errors > 50
```

**해결 방법:**
- DB 유니크 제약조건 추가
- 낙관적 락 (Optimistic Lock) 적용
- 트랜잭션 격리 수준 조정

#### 캐시 효율성

```
✅ 정상: cache_hit_rate > 70%
⚠️  주의: cache_hit_rate 50~70%
❌ 문제: cache_hit_rate < 50%
```

**해결 방법:**
- Redis 캐시 적용
- 캐시 만료 시간 조정
- 캐시 워밍업 전략

#### DB 병목

```
✅ 정상: db_connection_errors = 0
❌ 문제: db_connection_errors > 0
```

**해결 방법:**
- 커넥션 풀 크기 증가
- 쿼리 최적화
- 인덱스 추가
- Read Replica 도입

#### N+1 쿼리

```
게시글 1개당 평균 응답 시간 > 100ms → 의심
```

**해결 방법:**
- Batch Fetch 적용
- Join Fetch 사용
- EntityGraph 활용

---

## 팁 및 주의사항

### ✅ 베스트 프랙티스

1. **테스트 전 DB 백업**
   ```bash
   # 애플리케이션 서버에서 실행
   mysqldump -u root -p kaboocam_db > backup.sql
   ```

2. **일관된 테스트 환경**
   - 동일한 배경 데이터로 테스트
   - 동일한 서버 리소스
   - 동일한 부하 조건

3. **여러 번 테스트 후 평균값 사용**
   ```bash
   # 3번 반복 후 평균 계산
   for i in {1..3}; do
     docker compose run --rm k6 run \
       --env BASE_URL=$BASE_URL \
       --env TEST_LABEL=before-$i \
       /scripts/step2-baseline-test.js
     sleep 30  # 각 테스트 사이 30초 대기
   done
   ```

4. **모니터링 병행**
   - Grafana에서 실시간 메트릭 확인
   - 서버 CPU/메모리 사용률 확인
   - DB 쿼리 로그 분석
   - 애플리케이션 로그 확인

5. **Grafana 대시보드 스냅샷 저장**
   ```
   Grafana 대시보드에서 Share > Snapshot 클릭
   개선 전/후 비교를 위해 스냅샷 URL 저장
   ```

### ⚠️ 주의사항

1. **프로덕션 환경에서 테스트 금지**
   - 높은 부하로 인한 서비스 장애 가능

2. **테스트 후 데이터 정리**
   ```sql
   -- 테스트 계정만 삭제 (배경 데이터는 유지)
   DELETE FROM member WHERE email LIKE 'perf_tester_%@test.com';

   -- 배경 데이터까지 모두 삭제
   DELETE FROM member WHERE email LIKE 'dummy_user_%@test.com';
   DELETE FROM member WHERE email LIKE 'perf_tester_%@test.com';
   ```

   **권장:** 배경 데이터(dummy_user)는 유지하고 테스트 계정(perf_tester)만 삭제

3. **네트워크 대역폭 고려**
   - 로컬 테스트 시 네트워크 병목 가능
   - 가능하면 같은 VPC 내에서 테스트

4. **Docker 리소스 정리**
   ```bash
   # 테스트 완료 후 컨테이너 정리
   docker compose down

   # 볼륨까지 삭제 (InfluxDB 데이터 삭제됨)
   docker compose down -v

   # 이미지 정리
   docker image prune -a
   ```

---

## 트러블슈팅

### InfluxDB 연결 실패

```bash
# InfluxDB 컨테이너 로그 확인
docker compose logs influxdb

# InfluxDB 재시작
docker compose restart influxdb
```

### Grafana 대시보드가 데이터를 표시하지 않음

1. InfluxDB 데이터소스 확인
2. k6 테스트 실행 시 `K6_OUT` 환경변수 확인
3. InfluxDB에 데이터가 들어왔는지 확인:
   ```bash
   docker compose exec influxdb influx
   > use k6
   > show measurements
   ```

### k6 컨테이너에서 애플리케이션 서버 연결 실패

```bash
# 네트워크 연결 테스트
docker compose run --rm k6 sh -c "curl -I $BASE_URL"

# BASE_URL이 올바른지 확인
echo $BASE_URL
```

---

## 추가 리소스

- [K6 공식 문서](https://k6.io/docs/)
- [K6 메트릭 가이드](https://k6.io/docs/using-k6/metrics/)
- [InfluxDB 공식 문서](https://docs.influxdata.com/influxdb/v1.8/)
- [Grafana 대시보드 갤러리](https://grafana.com/grafana/dashboards/)
- [HikariCP 설정 가이드](https://github.com/brettwooldridge/HikariCP#configuration-knobs-baby)

---

## 문의

성능 테스트 관련 문의사항은 팀 리드에게 연락하세요.