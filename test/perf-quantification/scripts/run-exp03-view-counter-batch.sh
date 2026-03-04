#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

EXP_ID="03"
OUT_DIR="${RESULTS_DIR}/${EXP_ID}"
mkdir -p "${OUT_DIR}"

: "${BASE_URL_TARGET:=}"
: "${K6_VUS:=20}"
: "${K6_DURATION:=3m}"
: "${K6_POST_ID:=}"
: "${K6_SCENARIO:=view_burst}"
: "${MONGO_DB:=kaboocamPost}"

run_env="${BASE_URL_TARGET:-${BASE_URL:-}}"
if [[ -z "${run_env}" ]]; then
  warn "BASE_URL 또는 BASE_URL_TARGET이 필요합니다."
  exit 1
fi

mongo_update_count() {
  if [[ -z "${MONGO_URI:-}" ]] || ! command -v mongosh >/dev/null 2>&1; then
    echo 0
    return
  fi
  mongosh "${MONGO_URI}" --quiet --eval "db = db.getSiblingDB('${MONGO_DB}'); print(db.serverStatus().opcounters.update)" 2>/dev/null | tr -dc '0-9' || echo 0
}

write_metadata "${OUT_DIR}/metadata.txt" "${EXP_ID}" "view count batch update write amplification 비교 준비"

before_update="$(mongo_update_count)"

  if ! run_k6 "${K6_DIR}/post-workload.js" "${OUT_DIR}" \
    -e BASE_URL="${run_env}" \
    -e WORKLOAD="${K6_SCENARIO}" \
    -e VUS="${K6_VUS}" \
    -e DURATION="${K6_DURATION}" \
    -e POST_ID="${K6_POST_ID}"; then
    warn "k6 임계치 위반 또는 실행 실패가 발생했지만 통계는 k6-summary.json에 남았습니다."
  fi

after_update="$(mongo_update_count)"
delta=$((after_update - before_update))
p95_detail="$(extract_k6_metric "${OUT_DIR}/k6-summary.json" detail_duration 'p(95)' || true)"

if [[ -n "${MONGO_URI:-}" ]] && command -v mongosh >/dev/null 2>&1; then
  cat > "${OUT_DIR}/summary.md" <<EOF2
## 근본 목적
조회수 즉시 반영 구조 대비 배치 반영 구조의 쓰기 수치 차이를 정량화

## 비목적
이미지 업로드/Redis TTL 정책 변경이나 앱 구조 리펙터링은 제외

## 측정 포인트
- k6 워크로드: 상세 조회 집중
- MongoDB update 카운터 delta: ${delta}
- 상세 조회 p95: ${p95_detail}
EOF2
else
  cat > "${OUT_DIR}/summary.md" <<EOF2
## 근본 목적
조회수 즉시 반영 구조 대비 배치 반영 구조의 쓰기 수치 차이를 정량화

## 비목적
이미지 업로드/Redis TTL 정책 변경이나 앱 구조 리펙터링은 제외

## 측정 포인트
- k6 워크로드: 상세 조회 집중
- MongoDB opcounters 업데이트 샘플링이 미리 설정되지 않았습니다. (mongosh 없음/URI 미설정)
- 실행 환경에서 k6 p95: ${p95_detail}
EOF2
fi

log "실험 03 완료: ${OUT_DIR}"
