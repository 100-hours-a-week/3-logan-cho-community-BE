#!/bin/bash

# 성능 테스트 실행 스크립트
# 사용법: ./run-performance-tests.sh [before|after|full]

set -e  # 에러 발생 시 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 환경 변수
BASE_URL="${BASE_URL:-http://localhost:8080}"
TEST_MODE="${1:-before}"

# 결과 디렉토리 생성
mkdir -p performance-results

echo -e "${BLUE}=== 성능 테스트 시작 ===${NC}"
echo -e "${BLUE}대상 서버: ${BASE_URL}${NC}"
echo -e "${BLUE}테스트 모드: ${TEST_MODE}${NC}\n"

# 서버 헬스 체크
echo -e "${YELLOW}서버 연결 확인 중...${NC}"
if curl -s "${BASE_URL}/actuator/health" > /dev/null; then
    echo -e "${GREEN}✓ 서버 연결 성공${NC}\n"
else
    echo -e "${RED}✗ 서버에 연결할 수 없습니다: ${BASE_URL}${NC}"
    echo -e "${RED}서버를 먼저 시작하세요.${NC}"
    exit 1
fi

# K6 설치 확인
if ! command -v k6 &> /dev/null; then
    echo -e "${RED}✗ K6가 설치되어 있지 않습니다.${NC}"
    echo -e "${YELLOW}설치 방법: brew install k6${NC}"
    exit 1
fi

# 함수: 목 데이터 생성
setup_mock_data() {
    echo -e "${YELLOW}목 데이터 생성 중...${NC}"
    k6 run --env BASE_URL="${BASE_URL}" mock-data-script.js
    echo -e "${GREEN}✓ 목 데이터 생성 완료${NC}\n"
}

# 함수: 베이스라인 테스트
run_baseline() {
    local label=$1
    echo -e "${YELLOW}베이스라인 테스트 실행 중 (${label})...${NC}"
    k6 run --env BASE_URL="${BASE_URL}" \
           --env TEST_LABEL="${label}" \
           baseline-test.js
    echo -e "${GREEN}✓ 베이스라인 테스트 완료${NC}\n"
}

# 함수: 엔드포인트 벤치마크
run_endpoint_benchmark() {
    local label=$1
    echo -e "${YELLOW}엔드포인트 벤치마크 실행 중 (${label})...${NC}"
    k6 run --env BASE_URL="${BASE_URL}" \
           --env TEST_LABEL="${label}" \
           endpoint-benchmark.js
    echo -e "${GREEN}✓ 엔드포인트 벤치마크 완료${NC}\n"
}

# 함수: 병목 분석
run_bottleneck_analysis() {
    echo -e "${YELLOW}병목 분석 실행 중...${NC}"
    echo -e "${RED}경고: 이 테스트는 서버에 높은 부하를 줍니다.${NC}"
    read -p "계속하시겠습니까? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        k6 run --env BASE_URL="${BASE_URL}" \
               --env TEST_LABEL="bottleneck" \
               bottleneck-analysis.js
        echo -e "${GREEN}✓ 병목 분석 완료${NC}\n"
    else
        echo -e "${YELLOW}병목 분석을 건너뜁니다.${NC}\n"
    fi
}

# 테스트 모드에 따른 실행
case $TEST_MODE in
    "before")
        echo -e "${BLUE}=== 개선 전 성능 측정 ===${NC}\n"

        # 목 데이터 확인
        read -p "목 데이터를 새로 생성하시겠습니까? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_mock_data
        fi

        # 베이스라인 측정
        run_baseline "before"

        # 엔드포인트 벤치마크
        run_endpoint_benchmark "endpoint-before"

        # 병목 분석
        run_bottleneck_analysis

        echo -e "${GREEN}=== 개선 전 측정 완료 ===${NC}"
        echo -e "${YELLOW}결과를 확인한 후 코드를 개선하고 'after' 모드로 다시 실행하세요.${NC}"
        ;;

    "after")
        echo -e "${BLUE}=== 개선 후 성능 측정 ===${NC}\n"

        # 베이스라인 측정
        run_baseline "after"

        # 엔드포인트 벤치마크
        run_endpoint_benchmark "endpoint-after"

        echo -e "${GREEN}=== 개선 후 측정 완료 ===${NC}"
        echo -e "${YELLOW}결과 비교를 위해 compare-results.js를 실행하세요.${NC}"

        # 결과 비교 제안
        read -p "지금 결과를 비교하시겠습니까? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Before 파일을 선택하세요:${NC}"
            select before_file in performance-results/before-*.json; do
                if [ -n "$before_file" ]; then
                    echo -e "${YELLOW}After 파일을 선택하세요:${NC}"
                    select after_file in performance-results/after-*.json; do
                        if [ -n "$after_file" ]; then
                            node compare-results.js "$before_file" "$after_file"
                            break 2
                        fi
                    done
                fi
            done
        fi
        ;;

    "full")
        echo -e "${BLUE}=== 전체 테스트 실행 ===${NC}\n"

        # 목 데이터 생성
        setup_mock_data

        # Before 측정
        echo -e "${BLUE}--- 개선 전 측정 ---${NC}\n"
        run_baseline "before"
        run_endpoint_benchmark "endpoint-before"
        run_bottleneck_analysis

        echo -e "${YELLOW}코드를 개선한 후 계속하려면 Enter를 누르세요...${NC}"
        read

        # After 측정
        echo -e "${BLUE}--- 개선 후 측정 ---${NC}\n"
        run_baseline "after"
        run_endpoint_benchmark "endpoint-after"

        echo -e "${GREEN}=== 전체 테스트 완료 ===${NC}"
        ;;

    *)
        echo -e "${RED}잘못된 테스트 모드: ${TEST_MODE}${NC}"
        echo -e "${YELLOW}사용법: $0 [before|after|full]${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}모든 테스트 완료!${NC}"
echo -e "${BLUE}결과 파일: performance-results/${NC}"