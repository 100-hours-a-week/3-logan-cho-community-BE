#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

EXP_ID="01"
OUT_DIR="${RESULTS_DIR}/${EXP_ID}"
mkdir -p "${OUT_DIR}"
LOG_FILE="${OUT_DIR}/run.log"

: "${MYSQL_HOST:=127.0.0.1}"
: "${MYSQL_PORT:=3306}"
: "${MYSQL_USER:=root}"
: "${MYSQL_PASSWORD:=rootpw}"
: "${MYSQL_DB:=perfcmp}"
: "${MYSQL_DEFAULT_AUTH:=}"

: "${NEXTKEY_TABLE:=next_key_likes_lock_test}"
: "${NEXTKEY_ROWS:=5000000}"
: "${NEXTKEY_UNIQUE_MEMBERS:=100000}"
: "${NEXTKEY_HOLD_SECONDS:=8}"
: "${NEXTKEY_INSERT_REPEAT:=300}"
: "${NEXTKEY_INSERT_INTERVAL_SEC:=0.01}"
: "${NEXTKEY_LOCK_TIMEOUT_SECONDS:=3}"
: "${NEXTKEY_WITHDRAW_CONCURRENCIES:=100,250,500}"
: "${NEXTKEY_DATA_BLOCK_SIZE:=5000}"
: "${NEXTKEY_SAMPLE_INTERVAL_SEC:=0.2}"
: "${NEXTKEY_HOLD_MEMBER_STRIDE:=10000}"

require_cmd mysql
write_metadata "${OUT_DIR}/metadata.txt" "${EXP_ID}" "next-key lock repro with large dataset"

mysql_exec() {
  local auth_opts=()
  if [[ -n "${MYSQL_DEFAULT_AUTH}" ]]; then
    auth_opts+=("--default-auth=${MYSQL_DEFAULT_AUTH}")
  fi
  mysql --protocol=TCP -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" ${MYSQL_PASSWORD:+-p"${MYSQL_PASSWORD}"} "${auth_opts[@]}" -N -B -e "$1" "${MYSQL_DB}"
}

mysql_value() {
  local query="$1"
  local value
  value="$(mysql_exec "${query}" 2>/dev/null | tr -d '\r')"
  if [[ -z "${value}" ]]; then
    echo "0"
    return
  fi
  echo "${value}"
}

ensure_int() {
  local raw="$1"
  if ! [[ "${raw}" =~ ^[0-9]+$ ]]; then
    echo 0
    return
  fi
  echo "${raw}"
}

has_index() {
  local index_name="$1"
  mysql_value "SELECT COUNT(*) FROM information_schema.statistics WHERE TABLE_SCHEMA='${MYSQL_DB}' AND TABLE_NAME='${NEXTKEY_TABLE}' AND INDEX_NAME='${index_name}'" | tr -d '\r'
}

mysql_status_value() {
  ensure_int "$(mysql_value "SHOW GLOBAL STATUS LIKE '$1';" | awk '{print $2}')"
}

safe_watch_query() {
  local query="$1"
  local value
  value="$(mysql_exec "${query}" 2>/dev/null || true | tr -d '\r' | awk 'NF{print $1; exit}')"
  if [[ -z "${value}" ]]; then
    echo "0"
  else
    echo "${value}"
  fi
}

prepare_schema() {
  log "테이블 생성 및 대량 데이터 적재: rows=${NEXTKEY_ROWS}, users=${NEXTKEY_UNIQUE_MEMBERS}"
  mysql_exec "DROP TABLE IF EXISTS ${NEXTKEY_TABLE};"
  mysql_exec "CREATE TABLE ${NEXTKEY_TABLE} (
    like_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    member_id BIGINT NOT NULL,
    post_id BIGINT NOT NULL,
    deleted_at DATETIME(6) NULL,
    KEY idx_member_deleted (deleted_at, member_id)
  ) ENGINE=InnoDB;"

  local block_size="${NEXTKEY_DATA_BLOCK_SIZE}"
  local batches=$(( (NEXTKEY_ROWS + block_size - 1) / block_size ))
  if (( block_size < 2 )); then
    block_size=1000
  fi
  if (( batches < 2 )); then
    batches=2
  fi

  local seq_a="${NEXTKEY_TABLE}_seq_a"
  local seq_b="${NEXTKEY_TABLE}_seq_b"
  local seq_a_values=""
  local seq_b_values=""
  local i

  # 0..(block_size-1) 시퀀스
  mysql_exec "DROP TABLE IF EXISTS ${seq_a};"
  mysql_exec "CREATE TABLE ${seq_a} (n INT PRIMARY KEY) ENGINE=MEMORY;"
  for ((i = 0; i < block_size; i += 1)); do
    if (( i == 0 )); then
      seq_a_values+="(${i})"
    else
      seq_a_values+=",(${i})"
    fi
  done
  seq_a_values+=";"
  mysql_exec "INSERT INTO ${seq_a} (n) VALUES ${seq_a_values}"

  # 0..(batches-1) 시퀀스
  mysql_exec "DROP TABLE IF EXISTS ${seq_b};"
  mysql_exec "CREATE TABLE ${seq_b} (n INT PRIMARY KEY) ENGINE=MEMORY;"
  for ((i = 0; i < batches; i += 1)); do
    if (( i == 0 )); then
      seq_b_values+="(${i})"
    else
      seq_b_values+=",(${i})"
    fi
  done
  seq_b_values+=";"
  mysql_exec "INSERT INTO ${seq_b} (n) VALUES ${seq_b_values}"

  mysql_exec "INSERT INTO ${NEXTKEY_TABLE} (member_id, post_id)
  SELECT
    (seed_row % ${NEXTKEY_UNIQUE_MEMBERS}) + 1 AS member_id,
    (seed_row % 1000000) + 1 AS post_id
  FROM (
    SELECT (b.n * ${block_size} + a.n) AS seed_row
    FROM ${seq_a} a
    JOIN ${seq_b} b
  ) AS rows_seed
  WHERE seed_row < ${NEXTKEY_ROWS};"

  mysql_exec "SELECT COUNT(*) FROM ${NEXTKEY_TABLE};"
  mysql_exec "DROP TABLE IF EXISTS ${seq_a};"
  mysql_exec "DROP TABLE IF EXISTS ${seq_b};"
}

apply_index() {
  local mode="$1"
  if (( "$(has_index 'idx_member_deleted')" > 0 )); then
    mysql_exec "ALTER TABLE ${NEXTKEY_TABLE} DROP INDEX idx_member_deleted;"
  fi
  if (( "$(has_index 'idx_member_only')" > 0 )); then
    mysql_exec "ALTER TABLE ${NEXTKEY_TABLE} DROP INDEX idx_member_only;"
  fi

  if [[ "${mode}" == "with_idx" ]]; then
    mysql_exec "ALTER TABLE ${NEXTKEY_TABLE} ADD INDEX idx_member_deleted (member_id, deleted_at);"
  fi
}

reset_deleted_flag() {
  mysql_exec "UPDATE ${NEXTKEY_TABLE} SET deleted_at = NULL;"
}

run_withdraw_holders() {
  local mode_label="$1"
  local concurrency="$2"
  local member_start="$3"
  local -n holder_pids_ref="$4"

  for idx in $(seq 0 $((concurrency - 1))); do
    local member_id=$((member_start + idx))
    (
      mysql_exec "SET autocommit = 0;
START TRANSACTION;
UPDATE ${NEXTKEY_TABLE}
SET deleted_at = NOW(6)
WHERE member_id = ${member_id}
  AND deleted_at IS NULL;
SELECT SLEEP(${NEXTKEY_HOLD_SECONDS});
COMMIT;"
    ) >/tmp/nextkey_${mode_label}_${member_id}.log 2>&1 || true &
    holder_pids_ref+=("$!")
  done
}

run_insert_probe() {
  local out_csv="$1"
  local inserts="$2"
  local mode_label="$3"

  : > "${out_csv}"
  printf '%s,%s,%s,%s\n' 'run_id' 'duration_ms' 'timeout' 'member_id' > "${out_csv}"

  for n in $(seq 1 "${inserts}"); do
    local member_id=$(( (n * 7) % NEXTKEY_UNIQUE_MEMBERS + 1 ))
    local post_id=$(( (n * 13) % 100000 + 1 ))
    local start_ns end_ns duration_ms rc
    start_ns="$(date +%s%N)"
    local sql="SET SESSION innodb_lock_wait_timeout = ${NEXTKEY_LOCK_TIMEOUT_SECONDS};
INSERT INTO ${NEXTKEY_TABLE} (member_id, post_id)
VALUES (${member_id}, ${post_id});"

    if mysql_exec "${sql}" >/dev/null 2>&1; then
      rc=0
    else
      rc=$?
    fi
    end_ns="$(date +%s%N)"
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
    if (( rc != 0 )); then
      printf '%s,%s,%s,%s\n' "${n}" "${duration_ms}" "1" "${member_id}" >> "${out_csv}"
    else
      printf '%s,%s,%s,%s\n' "${n}" "${duration_ms}" "0" "${member_id}" >> "${out_csv}"
    fi
    append_log "${LOG_FILE}" "[${mode_label}] insert ${n}/${inserts}: ${duration_ms}ms timeout=${rc}"
    if [[ -n "${NEXTKEY_INSERT_INTERVAL_SEC}" ]]; then
      sleep "${NEXTKEY_INSERT_INTERVAL_SEC}"
    fi
  done
}

watch_lock_wait_samples() {
  local out_csv="$1"
  local stop_token="$2"

  : > "${out_csv}"
  printf '%s,%s,%s,%s\n' 'ts' 'lock_wait_rows' 'lock_rows' 'trx_wait_count' > "${out_csv}"
  while [[ ! -f "${stop_token}" ]]; do
    local ts lock_wait_rows lock_rows trx_wait_rows
    ts="$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')"
    lock_wait_rows="$(safe_watch_query "SELECT COUNT(*) FROM information_schema.INNODB_LOCK_WAITS;")"
    lock_rows="$(safe_watch_query "SELECT COUNT(*) FROM information_schema.INNODB_LOCKS;")"
    trx_wait_rows="$(safe_watch_query "SELECT COUNT(*) FROM information_schema.INNODB_TRX WHERE trx_state='LOCK WAIT';")"
    printf '%s,%s,%s,%s\n' "${ts}" "${lock_wait_rows}" "${lock_rows}" "${trx_wait_rows}" >> "${out_csv}"
    sleep "${NEXTKEY_SAMPLE_INTERVAL_SEC}"
  done
}

compute_stats() {
  local insert_csv="$1"
  local sample_csv="$2"
  node - "${insert_csv}" "${sample_csv}" <<'NODE'
const fs = require('fs');
const insertPath = process.argv[2];
const samplePath = process.argv[3];

const parseCsv = (path) => {
  const raw = fs.readFileSync(path, 'utf8').trim().split(/\r?\n/);
  raw.shift();
  return raw.filter(Boolean).map((line) => {
    const parts = line.split(',');
    return {
      runId: Number(parts[0]),
      duration: Number(parts[1]),
      timeout: Number(parts[2]),
      memberId: Number(parts[3]),
    };
  }).filter((r) => Number.isFinite(r.duration));
};

const percentile = (arr, p) => {
  if (!arr.length) return 0;
  const idx = Math.floor((p / 100) * (arr.length - 1));
  const i = Math.max(0, Math.min(arr.length - 1, idx));
  return arr[i];
};

const rows = parseCsv(insertPath);
const durations = rows.map((r) => r.duration).sort((a, b) => a - b);
const timeoutCount = rows.reduce((acc, r) => acc + (r.timeout ? 1 : 0), 0);

const sampleRows = fs.readFileSync(samplePath, 'utf8')
  .trim()
  .split(/\r?\n/)
  .slice(1)
  .filter(Boolean)
  .map((line) => {
    const [ts, waits, lockRows, trx] = line.split(',');
    return { waits: Number(waits), lockRows: Number(lockRows), trx: Number(trx) };
  })
  .filter((x) => Number.isFinite(x.waits) && Number.isFinite(x.lockRows) && Number.isFinite(x.trx));

const avg = durations.length ? durations.reduce((a, b) => a + b, 0) / durations.length : 0;
const p50 = percentile(durations, 50);
const p90 = percentile(durations, 90);
const p95 = percentile(durations, 95);
const p99 = percentile(durations, 99);
const max = durations.length ? durations[durations.length - 1] : 0;

let maxWaitRows = 0;
let maxLockRows = 0;
let maxTrxWait = 0;
for (const row of sampleRows) {
  if (row.waits > maxWaitRows) maxWaitRows = row.waits;
  if (row.lockRows > maxLockRows) maxLockRows = row.lockRows;
  if (row.trx > maxTrxWait) maxTrxWait = row.trx;
}

console.log(`rows=${rows.length}`);
console.log(`timeout_count=${timeoutCount}`);
console.log(`timeout_rate=${rows.length === 0 ? 0 : (timeoutCount / rows.length).toFixed(4)}`);
console.log(`insert_avg_ms=${avg.toFixed(2)}`);
console.log(`insert_p50_ms=${p50.toFixed(2)}`);
console.log(`insert_p90_ms=${p90.toFixed(2)}`);
console.log(`insert_p95_ms=${p95.toFixed(2)}`);
console.log(`insert_p99_ms=${p99.toFixed(2)}`);
console.log(`insert_max_ms=${max.toFixed(2)}`);
console.log(`max_lock_wait_rows=${maxWaitRows}`);
console.log(`max_lock_rows=${maxLockRows}`);
console.log(`max_trx_wait=${maxTrxWait}`);
NODE
}

run_profile() {
  local mode_label="$1"
  local withdraw_concurrency="$2"
  local member_start="$3"
  local profile_idx="$4"

  local run_dir="${OUT_DIR}/${mode_label}/withdraw_${withdraw_concurrency}"
  mkdir -p "${run_dir}"

  local insert_csv="${run_dir}/insert_latencies.csv"
  local sample_csv="${run_dir}/lock_wait_samples.csv"
  local stop_token="${run_dir}/stop_watch"
  local holder_pids=()

  log "[${mode_label}] withdraw_concurrency=${withdraw_concurrency}, member_start=${member_start}"
  append_log "${LOG_FILE}" "start profile mode=${mode_label}, concurrency=${withdraw_concurrency}, member_start=${member_start}"

  local before_waits before_time before_status
  before_waits="$(mysql_status_value Innodb_row_lock_waits)"
  before_time="$(mysql_status_value Innodb_row_lock_time)"
  before_status="$(mysql_status_value Threads_running)"

  run_withdraw_holders "${mode_label}" "${withdraw_concurrency}" "${member_start}" holder_pids

  sleep 1
  watch_lock_wait_samples "${sample_csv}" "${stop_token}" &
  local watcher_pid="$!"

  local run_label="${mode_label}-${withdraw_concurrency}"
  run_insert_probe "${insert_csv}" "${NEXTKEY_INSERT_REPEAT}" "${run_label}"

  for pid in "${holder_pids[@]}"; do
    wait "${pid}" || true
  done

  touch "${stop_token}"
  wait "${watcher_pid}" || true
  rm -f "${stop_token}"

  local after_waits after_time after_status
  after_waits="$(mysql_status_value Innodb_row_lock_waits)"
  after_time="$(mysql_status_value Innodb_row_lock_time)"
  after_status="$(mysql_status_value Threads_running)"

  local rows timeout_count timeout_rate insert_avg_ms insert_p50_ms insert_p90_ms insert_p95_ms insert_p99_ms insert_max_ms
  local max_wait_rows max_lock_rows max_trx_wait

  while IFS='=' read -r key value; do
    case "${key}" in
      rows) rows="${value}" ;;
      timeout_count) timeout_count="${value}" ;;
      timeout_rate) timeout_rate="${value}" ;;
      insert_avg_ms) insert_avg_ms="${value}" ;;
      insert_p50_ms) insert_p50_ms="${value}" ;;
      insert_p90_ms) insert_p90_ms="${value}" ;;
      insert_p95_ms) insert_p95_ms="${value}" ;;
      insert_p99_ms) insert_p99_ms="${value}" ;;
      insert_max_ms) insert_max_ms="${value}" ;;
      max_lock_wait_rows) max_wait_rows="${value}" ;;
      max_lock_rows) max_lock_rows="${value}" ;;
      max_trx_wait) max_trx_wait="${value}" ;;
    esac
  done < <(compute_stats "${insert_csv}" "${sample_csv}")

  : "${rows:=0}"
  : "${timeout_count:=0}"
  : "${timeout_rate:=0}"
  : "${insert_avg_ms:=0}"
  : "${insert_p50_ms:=0}"
  : "${insert_p90_ms:=0}"
  : "${insert_p95_ms:=0}"
  : "${insert_p99_ms:=0}"
  : "${insert_max_ms:=0}"
  : "${max_wait_rows:=0}"
  : "${max_lock_rows:=0}"
  : "${max_trx_wait:=0}"

  local lock_waits_delta lock_time_delta
  lock_waits_delta=$((after_waits - before_waits))
  lock_time_delta=$((after_time - before_time))

  cat > "${run_dir}/run-summary.txt" <<EOF2
run_label: ${mode_label}-${withdraw_concurrency}-${profile_idx}
mode: ${mode_label}
withdraw_concurrency: ${withdraw_concurrency}
member_start: ${member_start}
insert_rows: ${rows}
insert_avg_ms: ${insert_avg_ms}
insert_p50_ms: ${insert_p50_ms}
insert_p90_ms: ${insert_p90_ms}
insert_p95_ms: ${insert_p95_ms}
insert_p99_ms: ${insert_p99_ms}
insert_max_ms: ${insert_max_ms}
timeout_count: ${timeout_count}
timeout_rate: ${timeout_rate}
innodb_row_lock_waits_delta: ${lock_waits_delta}
innodb_row_lock_time_delta: ${lock_time_delta}
max_lock_wait_rows: ${max_wait_rows}
max_lock_rows: ${max_lock_rows}
max_trx_wait_rows: ${max_trx_wait}
threads_running_before: ${before_status}
threads_running_after: ${after_status}
EOF2

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${mode_label}" "${withdraw_concurrency}" "${rows}" "${insert_avg_ms}" "${insert_p50_ms}" "${insert_p95_ms}" "${insert_p99_ms}" \
    "${insert_max_ms}" "${timeout_count}" "${timeout_rate}" "${lock_waits_delta}" "${lock_time_delta}" \
    "${max_wait_rows}" "${max_lock_rows}" "${max_trx_wait}" >> "${OUT_DIR}/raw-01.csv"
}

write_summary() {
  local out="${OUT_DIR}/summary.md"

  {
    echo "# 실험 01 요약"
    echo
    echo "## 근본 목적"
    echo "좋아요 삭제(탈퇴) 트랜잭션이 member_id 인덱스 미보유/보유 시 insert 지연과 락 대기 지표에 미치는 영향을 대용량 데이터에서 확인"
    echo
    echo "## 실험 조건"
    echo "- 테이블 행 수: \`${NEXTKEY_ROWS}\`"
    echo "- 고유 사용자 수: \`${NEXTKEY_UNIQUE_MEMBERS}\`"
    echo "- 동시 탈퇴 사용자 수: \`${NEXTKEY_WITHDRAW_CONCURRENCIES}\`"
    echo "- 락 보유 시간: \`${NEXTKEY_HOLD_SECONDS}s\`"
    echo "- insert 횟수(프로파일당): \`${NEXTKEY_INSERT_REPEAT}\`"
    echo "- insert 락 타임아웃: \`${NEXTKEY_LOCK_TIMEOUT_SECONDS}s\`"
    echo
    echo "## 원시 지표"
    echo
    echo "| mode | withdrawers | insert_avg_ms | insert_p50_ms | insert_p95_ms | insert_p99_ms | insert_timeout_rate | lock_waits_delta | lock_time_delta | max_innodb_lock_wait_rows | max_innodb_trx_wait_rows |"
    echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
  } > "${out}"

  while IFS=, read -r mode c rows avg p50 p95 p99 max timeout_count timeout_rate lock_wait_delta lock_time_delta max_wait_rows max_lock_rows max_trx_wait; do
    [[ "${mode}" == "mode" ]] && continue
    printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "${mode}" "${c}" "${avg}" "${p50}" "${p95}" "${p99}" "${timeout_rate}" "${lock_wait_delta}" "${lock_time_delta}" "${max_wait_rows}" "${max_trx_wait}" >> "${out}"
  done < "${OUT_DIR}/raw-01.csv"

  echo >> "${out}"
  echo "## A/B 비교(동일 컨커런시 기준)" >> "${out}"
  echo "" >> "${out}"
  echo "개선률은 with_idx를 without_idx 기준으로 계산(양수면 개선)." >> "${out}"
  echo "| withdrawers | with_idx/without_idx insert_p95(%) | with_idx/without_idx lock_waits_delta(%) |" >> "${out}"
  echo "|---:|---:|---:|" >> "${out}"

  local concurrencies_string="${NEXTKEY_WITHDRAW_CONCURRENCIES}"
  local oldIFS="${IFS}"
  IFS=',' read -r -a concurrencies <<< "${concurrencies_string}"
  IFS="${oldIFS}"
  local c
  for c in "${concurrencies[@]}"; do
    local w_line a_line
    w_line="$(awk -F, -v m="without_idx" -v c="${c}" '$1==m && $2+0==c {print}' "${OUT_DIR}/raw-01.csv" | tail -n1)"
    a_line="$(awk -F, -v m="with_idx" -v c="${c}" '$1==m && $2+0==c {print}' "${OUT_DIR}/raw-01.csv" | tail -n1)"
    if [[ -z "${w_line}" || -z "${a_line}" ]]; then
      printf '| %s | - | - |\n' "${c}" >> "${out}"
      continue
    fi
    IFS=',' read -r _ _ _ _ _ w95 _ _ _ _ w_delta _ _ _ <<< "${w_line}"
    IFS=',' read -r _ _ _ _ _ a95 _ _ _ _ a_delta _ _ _ <<< "${a_line}"
    local p95_improve=0 lock_improve=0
    if [[ "${w95}" != "0" && "${w95}" != "" && "${a95}" != "" ]]; then
      p95_improve=$(awk -v a="${a95}" -v b="${w95}" 'BEGIN{printf "%.2f", (b-a)/b*100}')
    fi
    if [[ "${w_delta}" != "0" && "${w_delta}" != "" && "${a_delta}" != "" ]]; then
      lock_improve=$(awk -v a="${a_delta}" -v b="${w_delta}" 'BEGIN{printf "%.2f", (b-a)/b*100}')
    fi
    printf '| %s | %s%% | %s%% |\n' "${c}" "${p95_improve}" "${lock_improve}" >> "${out}"
  done

  echo >> "${out}"
  echo "## 해석" >> "${out}"
    echo "- 프로파일별로 with_idx 모드의 삽입 p95가 낮고 Timeout 비율이 줄어들면 member_id 인덱스의 경합 완화 효과가 재현된 것으로 본다." >> "${out}"
  echo "- max_innodb_lock_wait_rows/max_innodb_trx_wait_rows는 락 대기 관측용 보조 지표다." >> "${out}"
}

main() {
  prepare_schema
  : > "${OUT_DIR}/raw-01.csv"
  echo "mode,concurrency,rows,avg,p50,p95,p99,max,timeout_count,timeout_rate,lock_wait_delta,lock_time_delta,max_wait_rows,max_lock_rows,max_trx_wait" > "${OUT_DIR}/raw-01.csv"

  local oldIFS="${IFS}"
  IFS=',' read -r -a profile_concurrencies <<< "${NEXTKEY_WITHDRAW_CONCURRENCIES}"
  IFS="${oldIFS}"

  local profile_index=0
  local concurrency member_start

  for concurrency in "${profile_concurrencies[@]}"; do
    if [[ -z "${concurrency}" ]]; then
      continue
    fi
    concurrency="$(echo "${concurrency}" | tr -d '[:space:]')"
    if ! [[ "${concurrency}" =~ ^[0-9]+$ ]] || (( concurrency <= 0 )); then
      warn "올바르지 않은 concurrency 값 무시: ${concurrency}"
      continue
    fi

    member_start=$((profile_index * NEXTKEY_HOLD_MEMBER_STRIDE + 1))
    if (( member_start + concurrency - 1 > NEXTKEY_UNIQUE_MEMBERS )); then
      warn "사용자 시작점이 범위를 초과해 1부터 재시작합니다: start=${member_start}, concurrency=${concurrency}"
      member_start=1
    fi

    for mode in without_idx with_idx; do
      reset_deleted_flag
      apply_index "${mode}"
      run_profile "${mode}" "${concurrency}" "${member_start}" "${profile_index}"
    done
    profile_index=$((profile_index + 1))
  done

  write_summary
  log "실험 01 완료: ${OUT_DIR}"
}

main
