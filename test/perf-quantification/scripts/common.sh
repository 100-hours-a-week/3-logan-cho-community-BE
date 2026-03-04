#!/usr/bin/env bash

set -euo pipefail

PERF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${PERF_ROOT}/results"
K6_DIR="${PERF_ROOT}/k6"
TIMESTAMP="$(date -u +'%Y%m%dT%H%M%SZ')"

log() {
  printf '[%s] [INFO] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

warn() {
  printf '[%s] [WARN] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

error() {
  printf '[%s] [ERROR] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    error "Required command missing: ${cmd}"
    return 1
  fi
}

run_k6() {
  local script_path="$1"
  local out_dir="$2"
  local run_log="${out_dir}/run.log"
  local extra_args=("${@:3}")
  mkdir -p "${out_dir}"
  local k6_runner="$(command -v k6 2>/dev/null || true)"

  local summary_path="${out_dir}/k6-summary.json"
  log "k6 run: ${script_path}"

  if [[ -n "${k6_runner}" ]]; then
    "${k6_runner}" run --summary-export "${summary_path}" "${extra_args[@]}" "${script_path}" \
      2>&1 | tee -a "${run_log}"
    return
  fi

  require_cmd docker
  docker run --rm -i \
    -v "${PERF_ROOT}:${PERF_ROOT}" \
    --name "k6-run-$(date +%s%N)" \
    grafana/k6:latest \
    run --summary-export "${summary_path}" "${extra_args[@]}" "${script_path}" \
    2>&1 | tee -a "${run_log}"
}

mysql_metric() {
  local query="$1"
  MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
  MYSQL_PORT="${MYSQL_PORT:-3306}"
  MYSQL_USER="${MYSQL_USER:-root}"
  MYSQL_PASSWORD="${MYSQL_PASSWORD:-rootpw}"
  MYSQL_DB="${MYSQL_DB:-perfcmp}"

  mysql --protocol=TCP -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" ${MYSQL_PASSWORD:+-p"${MYSQL_PASSWORD}"} -N -B -e "${query}" "${MYSQL_DB}"
}

mysql_status_value() {
  local var_name="$1"
  local value
  value="$(mysql_metric "SHOW GLOBAL STATUS LIKE '${var_name}';" | awk '{print $2}' | tr -d '\r\n')"
  echo "${value:-0}"
}

write_metadata() {
  local out_file="$1"
  local exp_id="$2"
  local message="$3"

  cat > "${out_file}" <<EOF2
Experiment: ${exp_id}
Date: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Runner: $(basename "$0")
Host: $(hostname)
Note: ${message}
Environment:
  BASE_URL=${BASE_URL:-}
  MYSQL_HOST=${MYSQL_HOST:-}
  MYSQL_PORT=${MYSQL_PORT:-}
  MYSQL_DB=${MYSQL_DB:-}
  MONGO_URI=${MONGO_URI:-}
  REDIS_HOST=${REDIS_HOST:-}
EOF2
}

extract_k6_metric() {
  local summary_file="$1"
  local metric_name="$2"
  local field="$3"
  node - <<'NODE' "${summary_file}" "${metric_name}" "${field}"
const fs = require('fs');
const summaryFile = process.argv[2];
const metricName = process.argv[3];
const field = process.argv[4];
const data = JSON.parse(fs.readFileSync(summaryFile, 'utf8'));
const metricData = data?.metrics?.[metricName];
let value = metricData?.[field];

if (value === undefined && metricData?.values) {
  value = metricData.values?.[field];
}

if (value === undefined || value === null || Number.isNaN(Number(value))) {
  const stats = data?.stats || {};
  if (stats && typeof stats === 'object') {
    if (metricName === 'list_list_duration' && field === 'p(95)' && stats.list_p95 != null) {
      value = stats.list_p95;
    } else if (metricName === 'detail_duration' && field === 'p(95)' && stats.detail_p95 != null) {
      value = stats.detail_p95;
    } else if (metricName === 'http_req_failed' && field === 'rate' && stats.failed_rate != null) {
      value = stats.failed_rate;
    }
  }
}

if (value === undefined || value === null || Number.isNaN(Number(value))) {
  if (metricName === 'http_req_failed' && field === 'rate' && metricData && metricData.value != null) {
    value = metricData.value;
  }
}

if (value === undefined || value === null || Number.isNaN(Number(value))) {
  process.exit(1);
}

console.log(value.toString());
NODE
}

append_log() {
  local log_file="$1"
  printf '%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $2" >> "${log_file}"
}
