#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

EXP_ID="05"
OUT_DIR="${RESULTS_DIR}/${EXP_ID}"
mkdir -p "${OUT_DIR}"

: "${BASE_URL_A:=}"
: "${BASE_URL_B:=}"
: "${REDIS_HOST:=127.0.0.1}"
: "${REDIS_PORT:=6379}"
: "${K6_VUS:=30}"
: "${K6_DURATION:=4m}"
: "${K6_SCENARIO:=list_profile}"
: "${LIST_USE_PIPELINE_A:=true}"
: "${LIST_USE_PIPELINE_B:=false}"

run_case() {
  local label="$1"
  local base_url="$2"
  local out_dir="$3"
  local list_use_pipeline="$4"

  log "${label} 환경 리스트 조회 실행 (${base_url})"
  if ! run_k6 "${K6_DIR}/post-workload.js" "${out_dir}" \
    -e BASE_URL="${base_url}" \
    -e WORKLOAD="${K6_SCENARIO}" \
    -e USERS="${K6_USERS:-20}" \
    -e VUS="${K6_VUS}" \
    -e DURATION="${K6_DURATION}" \
    -e POST_ID="${K6_POST_ID:-}" \
    -e AUTH_EMAIL_PREFIX="${AUTH_EMAIL_PREFIX:-perf-user}" \
    -e LIST_USE_PIPELINE="${list_use_pipeline}"; then
    warn "${label} 환경 임계치 위반 또는 실행 실패가 발생했지만 지표는 수집했습니다."
  fi

  if command -v redis-cli >/dev/null 2>&1; then
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" info commandstats | grep -E "^cmdstat_mget|^cmdstat_setex" > "${out_dir}/redis-commandstats-${label}.txt"
  fi

  local list_p95 failed
  list_p95="$(extract_k6_metric "${out_dir}/k6-summary.json" list_list_duration 'p(95)' || true)"
  failed="$(extract_k6_metric "${out_dir}/k6-summary.json" http_req_failed rate || true)"
  echo "${label},${list_p95:-},${failed:-}" >> "${OUT_DIR}/raw-05.csv"

  append_log "${OUT_DIR}/run.log" "${label} raw saved at ${out_dir}"
}

if [[ -z "${BASE_URL_A}" || -z "${BASE_URL_B}" ]]; then
  warn "BASE_URL_A / BASE_URL_B 필요. N+1 전/후 버전 또는 실험 대상 URL을 분리해 주세요."
  exit 1
fi

write_metadata "${OUT_DIR}/metadata.txt" "${EXP_ID}" "Redis Pipeline A/B 비교"
: > "${OUT_DIR}/raw-05.csv"
run_case "A" "${BASE_URL_A}" "${OUT_DIR}/A" "${LIST_USE_PIPELINE_A}"
run_case "B" "${BASE_URL_B}" "${OUT_DIR}/B" "${LIST_USE_PIPELINE_B}"

python3 - "${OUT_DIR}" <<'PY'
import pathlib
import re
import sys

base = pathlib.Path(sys.argv[1])

def mget_count(path):
    if not path.exists():
        return 0
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('cmdstat_mget:'):
            m = re.search(r'calls=(\d+)', line)
            return int(m.group(1)) if m else 0
    return 0

def setex_count(path):
    if not path.exists():
        return 0
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('cmdstat_setex:'):
            m = re.search(r'calls=(\d+)', line)
            return int(m.group(1)) if m else 0
    return 0

raw_path = base / 'raw-05.csv'
raw_data = {}
if raw_path.exists():
    for line in raw_path.read_text(encoding='utf-8').strip().splitlines():
        if not line.strip():
            continue
        parts = line.split(',')
        raw_data[parts[0]] = {
            'p95': float(parts[1] or 0),
            'failed': float(parts[2] or 0),
        }

a = raw_data.get('A', {})
b = raw_data.get('B', {})
a_p95 = a.get('p95', 0)
b_p95 = b.get('p95', 0)
a_failed = a.get('failed', 0)
b_failed = b.get('failed', 0)

a_mget = mget_count(base / 'A/redis-commandstats-A.txt')
a_setex = setex_count(base / 'A/redis-commandstats-A.txt')
b_mget = mget_count(base / 'B/redis-commandstats-B.txt')
b_setex = setex_count(base / 'B/redis-commandstats-B.txt')

p95_improve = ((a_p95 - b_p95) / a_p95 * 100) if a_p95 > 0 else 0
mget_improve = ((a_mget - b_mget) / a_mget * 100) if a_mget > 0 else 0
failed_improve = ((a_failed - b_failed) / a_failed * 100) if a_failed > 0 else 0

with open(base / 'summary.md', 'w', encoding='utf-8') as f:
    f.write('## 근본 목적\n\n목록 조회 시 Redis Pipeline 유무(또는 버전 차이)에 따른 mget/setex 호출과 응답 지연 변화 정량화\n\n')
    f.write('## 비목적\n\nRedis 정책 자체 변경(만료/키 설계)는 제외\n\n')
    f.write(f'- A 환경 mget calls: {a_mget}\n')
    f.write(f'- A 환경 setex calls: {a_setex}\n')
    f.write(f'- B 환경 mget calls: {b_mget}\n')
    f.write(f'- B 환경 setex calls: {b_setex}\n')
    f.write(f'- A 환경 목록 조회 p95: {a_p95}\n')
    f.write(f'- B 환경 목록 조회 p95: {b_p95}\n')
    f.write(f'- 목록 조회 p95 개선률: {p95_improve:.2f}%\n')
    f.write(f'- mget 감소율(가정): {mget_improve:.2f}%\n')
    f.write(f'- 실패율 A: {a_failed}\n')
    f.write(f'- 실패율(A/B) 개선률: {failed_improve:.2f}%\n')
PY

log "실험 05 완료: ${OUT_DIR}"
