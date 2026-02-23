#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
LUA_SCRIPT="${SCRIPT_DIR}/sysbench/post_likes_insert.lua"

BENCH_DB="${BENCH_DB:-likes_bench}"
MYSQL_PORT="${MYSQL_PORT:-13306}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpw}"
BUFFER_POOL_MB="${BUFFER_POOL_MB:-48}"
MYSQL_MEMORY_LIMIT="${MYSQL_MEMORY_LIMIT:-768m}"
MYSQL_CPU_LIMIT="${MYSQL_CPU_LIMIT:-2.0}"
SCALE="${SCALE:-medium}"
LEVEL="${LEVEL:-L2}"

RUNS="${RUNS:-5}"
THREADS="${THREADS:-4}"
PREFILL_RATIO="${PREFILL_RATIO:-0.70}"
EVENTS_PER_RUN="${EVENTS_PER_RUN:-auto}"

DIST_MODE="skew"
ID_PATTERN="objectid"

RESULT_DIR="${SCRIPT_DIR}/results/phase3_sysbench_${SCALE}_${LEVEL}_cs"
META_TXT="${RESULT_DIR}/metadata.txt"
RAW_TSV="${RESULT_DIR}/raw.tsv"
CASE_SUMMARY_TSV="${RESULT_DIR}/case_summary.tsv"
IO_COMPARE_TSV="${RESULT_DIR}/io_compare.tsv"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing command: ${cmd}" >&2
    exit 1
  fi
}

log() {
  printf '[%s] %s\n' "$(date -u +"%H:%M:%S")" "$1"
}

case "${SCALE}" in
  small)
    NUM_POSTS=60000
    NUM_MEMBERS=120000
    NUM_LIKES=300000
    ;;
  medium)
    NUM_POSTS=140000
    NUM_MEMBERS=260000
    NUM_LIKES=900000
    ;;
  large)
    NUM_POSTS=240000
    NUM_MEMBERS=420000
    NUM_LIKES=1800000
    ;;
  *)
    echo "invalid SCALE: ${SCALE} (expected: small|medium|large)" >&2
    exit 1
    ;;
esac

MAX_CANDIDATE_ROWS=$((NUM_LIKES * 4))

require_cmd docker
require_cmd mysql
require_cmd awk
require_cmd sysbench

MYSQL_BASE_CMD=(
  mysql
  --protocol=TCP
  -h 127.0.0.1
  -P "${MYSQL_PORT}"
  -u root
  --batch
  --raw
  --silent
)

mysql_admin() {
  MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQL_BASE_CMD[@]}" -e "$1"
}

mysql_query() {
  MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" "${MYSQL_BASE_CMD[@]}" -D "${BENCH_DB}" -e "$1"
}

wait_mysql_ready() {
  local i=0
  until mysql_admin "SELECT 1" >/dev/null 2>&1; do
    i=$((i + 1))
    if (( i > 120 )); then
      echo "mysql is not ready" >&2
      exit 1
    fi
    sleep 1
  done
}

compose_up_mysql() {
  log "starting mysql container (buffer_pool=${BUFFER_POOL_MB}M, mem_limit=${MYSQL_MEMORY_LIMIT})"
  BUFFER_POOL_SIZE="${BUFFER_POOL_MB}M" \
  MYSQL_MEMORY_LIMIT="${MYSQL_MEMORY_LIMIT}" \
  MYSQL_CPU_LIMIT="${MYSQL_CPU_LIMIT}" \
  MYSQL_PORT="${MYSQL_PORT}" \
  MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
  BENCH_DB="${BENCH_DB}" \
  docker compose -f "${COMPOSE_FILE}" up -d mysql >/dev/null
  wait_mysql_ready
}

init_dataset() {
  log "initializing dataset (scale=${SCALE}, dist=${DIST_MODE}, id_pattern=${ID_PATTERN})"
  mysql_admin "DROP DATABASE IF EXISTS ${BENCH_DB}; CREATE DATABASE ${BENCH_DB};"

  mysql_query "CREATE TABLE bench_numbers (n BIGINT NOT NULL PRIMARY KEY) ENGINE=InnoDB;"
  mysql_query "INSERT INTO bench_numbers (n) VALUES (1);"

  local current_max=1
  while (( current_max < MAX_CANDIDATE_ROWS )); do
    mysql_query "INSERT INTO bench_numbers (n) SELECT n + ${current_max} FROM bench_numbers;"
    current_max=$((current_max * 2))
  done
  mysql_query "DELETE FROM bench_numbers WHERE n > ${MAX_CANDIDATE_ROWS};"

  mysql_query "CREATE TABLE bench_posts (
    post_seq INT NOT NULL PRIMARY KEY,
    post_id_bin BINARY(12) NOT NULL,
    UNIQUE KEY uk_post_bin (post_id_bin)
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_posts (post_seq, post_id_bin)
SELECT src.n, UNHEX(src.hex24)
FROM (
  SELECT n,
         CONCAT(LPAD(HEX(n), 8, '0'), SUBSTRING(SHA2(CONCAT('oid-', n), 256), 1, 16)) AS hex24
  FROM bench_numbers
  WHERE n <= ${NUM_POSTS}
) AS src
ORDER BY src.n;"

  mysql_query "CREATE TABLE bench_likes_source (
    source_id BIGINT NOT NULL AUTO_INCREMENT,
    member_id BIGINT NOT NULL,
    post_seq INT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (source_id),
    UNIQUE KEY uk_member_post_seq (member_id, post_seq),
    KEY idx_post_seq_member (post_seq, member_id)
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_likes_source (member_id, post_seq, created_at)
SELECT picked.member_id,
       picked.post_seq,
       TIMESTAMP('2025-01-01 00:00:00') + INTERVAL picked.first_n SECOND
FROM (
  SELECT gen.member_id, gen.post_seq, MIN(gen.n) AS first_n
  FROM (
    SELECT bn.n,
           1 + MOD(CRC32(CONCAT('m-', bn.n)), ${NUM_MEMBERS}) AS member_id,
           1 + FLOOR(
             POW(CRC32(CONCAT('ps-', bn.n)) / 4294967295.0, 2.8) * (${NUM_POSTS} - 1)
           ) AS post_seq
    FROM bench_numbers bn
    WHERE bn.n <= ${MAX_CANDIDATE_ROWS}
  ) AS gen
  GROUP BY gen.member_id, gen.post_seq
  ORDER BY first_n
  LIMIT ${NUM_LIKES}
) AS picked;"

  mysql_query "CREATE TABLE bench_likes_enriched (
    source_id BIGINT NOT NULL PRIMARY KEY,
    member_id BIGINT NOT NULL,
    post_id BINARY(12) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    KEY idx_member (member_id),
    KEY idx_post (post_id)
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_likes_enriched (source_id, member_id, post_id, created_at)
SELECT s.source_id, s.member_id, p.post_id_bin, s.created_at
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq
ORDER BY s.source_id;"
}

create_case_table() {
  local case_id="$1"
  log "creating case table: ${LEVEL}/${case_id}"

  local common_idx_l1 common_idx_l2 common_idx_l3 common_indexes
  common_idx_l1="UNIQUE KEY uk_member_post_deleted (member_id, post_id, deleted_at),
  KEY idx_member (member_id)"
  common_idx_l2=",
  KEY idx_created (created_at),
  KEY idx_deleted_created (deleted_at, created_at)"
  common_idx_l3=",
  KEY idx_post_created (post_id, created_at),
  KEY idx_member_created (member_id, created_at),
  KEY idx_deleted_member (deleted_at, member_id)"

  case "${LEVEL}" in
    L1)
      common_indexes="${common_idx_l1}"
      ;;
    L2)
      common_indexes="${common_idx_l1}${common_idx_l2}"
      ;;
    L3)
      common_indexes="${common_idx_l1}${common_idx_l2}${common_idx_l3}"
      ;;
    *)
      echo "invalid LEVEL: ${LEVEL} (expected: L1|L2|L3)" >&2
      exit 1
      ;;
  esac

  case "${case_id}" in
    C)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (post_id, member_id),
  ${common_indexes}
) ENGINE=InnoDB;"
      ;;
    S)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  id BIGINT NOT NULL AUTO_INCREMENT,
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  ${common_indexes},
  KEY idx_feed_deleted_post_member (deleted_at, post_id, member_id)
) ENGINE=InnoDB;"
      ;;
    *)
      echo "invalid case: ${case_id}" >&2
      exit 1
      ;;
  esac
}

prefill_case_data() {
  local case_id="$1"
  local prefill_rows="$2"
  log "prefill case data: ${case_id} (rows<=${prefill_rows})"

  case "${case_id}" in
    C)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT post_id, member_id, created_at, NULL
FROM bench_likes_enriched
WHERE source_id <= ${prefill_rows}
ORDER BY source_id;"
      ;;
    S)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT post_id, member_id, created_at, NULL
FROM bench_likes_enriched
WHERE source_id <= ${prefill_rows}
ORDER BY source_id;"
      ;;
  esac
}

capture_status() {
  local output_file="$1"
  mysql_query "SHOW GLOBAL STATUS WHERE Variable_name IN (
    'Innodb_buffer_pool_reads',
    'Innodb_pages_written',
    'Innodb_data_reads',
    'Innodb_data_writes',
    'Innodb_rows_inserted'
  );" > "${output_file}"
}

status_delta() {
  local before_file="$1"
  local after_file="$2"
  local var_name="$3"
  local before_value after_value
  before_value="$(awk -F'\t' -v v="${var_name}" '$1 == v { print $2; found=1; exit } END { if (!found) print 0 }' "${before_file}")"
  after_value="$(awk -F'\t' -v v="${var_name}" '$1 == v { print $2; found=1; exit } END { if (!found) print 0 }' "${after_file}")"
  echo $((after_value - before_value))
}

parse_hist_percentiles() {
  local out_file="$1"
  awk '
/^Latency histogram/ { in_hist=1; next }
in_hist && NF == 0 { in_hist=0 }
in_hist && $1 ~ /^[0-9.]+$/ && $NF ~ /^[0-9]+$/ {
  n++;
  v[n] = $1 + 0;
  c[n] = $NF + 0;
  total += c[n];
}
END {
  if (total == 0) {
    printf "0.000 0.000 0.000";
    exit;
  }

  t50 = total * 0.50;
  t95 = total * 0.95;
  t99 = total * 0.99;

  for (i = 1; i <= n; i++) {
    cum += c[i];
    if (p50 == 0 && cum >= t50) p50 = v[i];
    if (p95 == 0 && cum >= t95) p95 = v[i];
    if (p99 == 0 && cum >= t99) p99 = v[i];
  }

  printf "%.3f %.3f %.3f", p50, p95, p99;
}' "${out_file}"
}

run_sysbench_once() {
  local case_id="$1"
  local run_idx="$2"
  local sid_min="$3"
  local sid_max="$4"
  local events_count="$5"
  local before_file after_file out_file
  local eps avg_latency p95_report total_events p50_hist p95_hist p99_hist
  local bp_reads_delta pages_written_delta data_reads_delta data_writes_delta rows_inserted_delta row_count

  before_file="$(mktemp)"
  after_file="$(mktemp)"
  out_file="${RESULT_DIR}/${case_id}_run${run_idx}.out"

  capture_status "${before_file}"

  sysbench "${LUA_SCRIPT}" \
    --db-driver=mysql \
    --mysql-host=127.0.0.1 \
    --mysql-port="${MYSQL_PORT}" \
    --mysql-user=root \
    --mysql-password="${MYSQL_ROOT_PASSWORD}" \
    --mysql-db="${BENCH_DB}" \
    --threads="${THREADS}" \
    --time=0 \
    --events="${events_count}" \
    --histogram=on \
    --report-interval=0 \
    --case_id="${case_id}" \
    --sid_min="${sid_min}" \
    --sid_max="${sid_max}" \
    --sid_step="${THREADS}" \
    run > "${out_file}" 2>&1

  capture_status "${after_file}"

  eps="$(awk '/transactions:/{line=$0; sub(/^.*\(/, "", line); sub(/ per sec\.\).*$/, "", line); gsub(/ /, "", line); print line; exit}' "${out_file}")"
  avg_latency="$(awk -F':' '/Latency/{lat=1; next} lat && /avg:/{gsub(/ /, "", $2); print $2; exit}' "${out_file}")"
  p95_report="$(awk -F':' '/Latency/{lat=1; next} lat && /95th percentile:/{gsub(/ /, "", $2); print $2; exit}' "${out_file}")"
  total_events="$(awk '/total number of events:/{print $NF; exit}' "${out_file}")"
  read -r p50_hist p95_hist p99_hist <<< "$(parse_hist_percentiles "${out_file}")"

  if [[ -z "${eps}" ]]; then eps="0.000"; fi
  if [[ -z "${avg_latency}" ]]; then avg_latency="0.000"; fi
  if [[ -z "${p95_report}" ]]; then p95_report="0.000"; fi
  if [[ -z "${total_events}" ]]; then total_events="0"; fi

  if [[ "${p50_hist}" == "0.000" && "${p95_hist}" == "0.000" && "${p99_hist}" == "0.000" ]]; then
    p50_hist="${avg_latency}"
    if [[ "${p95_report}" != "0.000" && "${p95_report}" != "0.00" && "${p95_report}" != "0" ]]; then
      p95_hist="${p95_report}"
    else
      p95_hist="${avg_latency}"
    fi
    p99_hist="${avg_latency}"
  fi

  bp_reads_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_buffer_pool_reads")"
  pages_written_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_pages_written")"
  data_reads_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_data_reads")"
  data_writes_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_data_writes")"
  rows_inserted_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_rows_inserted")"

  row_count="$(mysql_query "SELECT COUNT(*) FROM post_likes_case;" | tail -n1)"

  rm -f "${before_file}" "${after_file}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${case_id}" "${run_idx}" "${total_events}" "${eps}" "${avg_latency}" "${p50_hist}" "${p95_hist}" "${p99_hist}" "${p95_report}" \
    "${bp_reads_delta}" "${pages_written_delta}" "${data_reads_delta}" "${data_writes_delta}" "${rows_inserted_delta}" "${row_count}" \
    >> "${RAW_TSV}"
}

aggregate_case_summary() {
  awk -F'\t' '
NR == 1 { next }
{
  c = $1;
  n[c]++;

  eps_sum[c] += $4;
  eps_sq[c] += ($4 * $4);

  avg_sum[c] += $5;
  avg_sq[c] += ($5 * $5);

  p50_sum[c] += $6;
  p95_sum[c] += $7;
  p99_sum[c] += $8;

  bp_sum[c] += $10;
  pages_sum[c] += $11;
  reads_sum[c] += $12;
  writes_sum[c] += $13;
  rows_sum[c] += $14;

  if ($15 > row_max[c]) row_max[c] = $15;
}
END {
  print "case\truns\teps_mean\teps_sd\tavg_ms_mean\tavg_ms_sd\tavg_ms_cv_pct\tavg_ms_ci95\tp50_ms_mean\tp95_ms_mean\tp99_ms_mean\tinnodb_buffer_pool_reads_mean\tinnodb_pages_written_mean\tinnodb_data_reads_mean\tinnodb_data_writes_mean\tinnodb_rows_inserted_mean\tbp_reads_per_insert\tdata_reads_per_insert\tpages_written_per_insert\tdata_writes_per_insert\tfinal_row_count";

  split("C S", cases, " ");
  for (i = 1; i <= 2; i++) {
    c = cases[i];
    if (n[c] == 0) continue;

    eps_mean = eps_sum[c] / n[c];
    avg_mean = avg_sum[c] / n[c];
    p50_mean = p50_sum[c] / n[c];
    p95_mean = p95_sum[c] / n[c];
    p99_mean = p99_sum[c] / n[c];

    bp_mean = bp_sum[c] / n[c];
    pages_mean = pages_sum[c] / n[c];
    reads_mean = reads_sum[c] / n[c];
    writes_mean = writes_sum[c] / n[c];
    rows_mean = rows_sum[c] / n[c];

    if (rows_mean > 0) {
      bp_per_insert = bp_mean / rows_mean;
      reads_per_insert = reads_mean / rows_mean;
      pages_per_insert = pages_mean / rows_mean;
      writes_per_insert = writes_mean / rows_mean;
    } else {
      bp_per_insert = 0;
      reads_per_insert = 0;
      pages_per_insert = 0;
      writes_per_insert = 0;
    }

    if (n[c] > 1) {
      eps_var = (eps_sq[c] - n[c] * eps_mean * eps_mean) / (n[c] - 1);
      avg_var = (avg_sq[c] - n[c] * avg_mean * avg_mean) / (n[c] - 1);
      if (eps_var < 0) eps_var = 0;
      if (avg_var < 0) avg_var = 0;
      eps_sd = sqrt(eps_var);
      avg_sd = sqrt(avg_var);
    } else {
      eps_sd = 0;
      avg_sd = 0;
    }

    avg_cv = (avg_mean > 0 ? (avg_sd / avg_mean) * 100 : 0);
    avg_ci95 = (n[c] > 1 ? 1.96 * avg_sd / sqrt(n[c]) : 0);

    printf "%s\t%d\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.4f\t%.4f\t%.4f\t%.4f\t%d\n",
      c, n[c], eps_mean, eps_sd, avg_mean, avg_sd, avg_cv, avg_ci95, p50_mean, p95_mean, p99_mean,
      bp_mean, pages_mean, reads_mean, writes_mean, rows_mean,
      bp_per_insert, reads_per_insert, pages_per_insert, writes_per_insert,
      row_max[c];
  }
}' "${RAW_TSV}" > "${CASE_SUMMARY_TSV}"
}

build_io_compare() {
  awk -F'\t' '
NR == 1 { next }
{
  if ($1 == "C") {
    c_bp = $12 + 0;
    c_reads = $14 + 0;
    c_pages = $13 + 0;
    c_writes = $15 + 0;
    c_bp_per = $17 + 0;
    c_reads_per = $18 + 0;
    c_pages_per = $19 + 0;
    c_writes_per = $20 + 0;
  } else if ($1 == "S") {
    bp_red = (c_bp > 0 ? (c_bp - ($12 + 0)) / c_bp * 100 : 0);
    reads_red = (c_reads > 0 ? (c_reads - ($14 + 0)) / c_reads * 100 : 0);
    pages_red = (c_pages > 0 ? (c_pages - ($13 + 0)) / c_pages * 100 : 0);
    writes_red = (c_writes > 0 ? (c_writes - ($15 + 0)) / c_writes * 100 : 0);
    bp_per_red = (c_bp_per > 0 ? (c_bp_per - ($17 + 0)) / c_bp_per * 100 : 0);
    reads_per_red = (c_reads_per > 0 ? (c_reads_per - ($18 + 0)) / c_reads_per * 100 : 0);
    pages_per_red = (c_pages_per > 0 ? (c_pages_per - ($19 + 0)) / c_pages_per * 100 : 0);
    writes_per_red = (c_writes_per > 0 ? (c_writes_per - ($20 + 0)) / c_writes_per * 100 : 0);

    printf "%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\n", $1, bp_red, reads_red, pages_red, writes_red, bp_per_red, reads_per_red, pages_per_red, writes_per_red;
  }
}
' "${CASE_SUMMARY_TSV}" > "${IO_COMPARE_TSV}.tmp"

  {
    echo -e "variant\tbuffer_pool_reads_reduction_pct\tdata_reads_reduction_pct\tpages_written_reduction_pct\tdata_writes_reduction_pct\tbuffer_pool_reads_per_insert_reduction_pct\tdata_reads_per_insert_reduction_pct\tpages_written_per_insert_reduction_pct\tdata_writes_per_insert_reduction_pct"
    cat "${IO_COMPARE_TSV}.tmp"
  } > "${IO_COMPARE_TSV}"
  rm -f "${IO_COMPARE_TSV}.tmp"
}

run_case() {
  local case_id="$1"
  local prefill_rows="$2"
  local sid_min_global sid_max_global window_size sid_min sid_max range_size events_count
  local run_idx

  # Keep the exact same source distribution per case by re-initializing dataset.
  init_dataset

  create_case_table "${case_id}"
  prefill_case_data "${case_id}" "${prefill_rows}"

  sid_min_global=$((prefill_rows + 1))
  sid_max_global=${NUM_LIKES}
  window_size=$(((sid_max_global - sid_min_global + 1) / RUNS))
  if (( window_size <= 0 )); then
    echo "invalid sid window size" >&2
    exit 1
  fi

  for run_idx in $(seq 1 "${RUNS}"); do
    sid_min=$((sid_min_global + (run_idx - 1) * window_size))
    if (( run_idx < RUNS )); then
      sid_max=$((sid_min + window_size - 1))
    else
      sid_max=${sid_max_global}
    fi

    range_size=$((sid_max - sid_min + 1))
    if [[ "${EVENTS_PER_RUN}" == "auto" ]]; then
      events_count="${range_size}"
    else
      events_count="${EVENTS_PER_RUN}"
      if (( events_count > range_size )); then
        echo "EVENTS_PER_RUN (${events_count}) must be <= sid range size (${range_size}) for fixed-workload fairness" >&2
        exit 1
      fi
    fi

    log "sysbench run case=${case_id} run=${run_idx} sid=[${sid_min},${sid_max}] events=${events_count}"
    run_sysbench_once "${case_id}" "${run_idx}" "${sid_min}" "${sid_max}" "${events_count}"
  done
}

main() {
  local prefill_rows
  prefill_rows="$(awk -v n="${NUM_LIKES}" -v r="${PREFILL_RATIO}" 'BEGIN{printf "%d", n * r}')"
  if (( prefill_rows <= 0 || prefill_rows >= NUM_LIKES )); then
    echo "invalid PREFILL_RATIO: ${PREFILL_RATIO}" >&2
    exit 1
  fi

  mkdir -p "${RESULT_DIR}"

  cat > "${META_TXT}" <<EOF_META
run_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
scale=${SCALE}
level=${LEVEL}
dist=${DIST_MODE}
id_pattern=${ID_PATTERN}
buffer_pool_mb=${BUFFER_POOL_MB}
mysql_memory_limit=${MYSQL_MEMORY_LIMIT}
mysql_cpu_limit=${MYSQL_CPU_LIMIT}
num_posts=${NUM_POSTS}
num_members=${NUM_MEMBERS}
num_likes=${NUM_LIKES}
runs=${RUNS}
threads=${THREADS}
prefill_ratio=${PREFILL_RATIO}
prefill_rows=${prefill_rows}
run_mode=fixed_events
events_per_run=${EVENTS_PER_RUN}
cases=C,S
EOF_META

  printf 'case\trun\ttotal_events\tevents_per_sec\tavg_latency_ms\tp50_ms\tp95_ms\tp99_ms\tp95_report_ms\tinnodb_buffer_pool_reads_delta\tinnodb_pages_written_delta\tinnodb_data_reads_delta\tinnodb_data_writes_delta\tinnodb_rows_inserted_delta\trow_count_after_run\n' > "${RAW_TSV}"

  compose_up_mysql
  run_case "C" "${prefill_rows}"
  run_case "S" "${prefill_rows}"
  aggregate_case_summary
  build_io_compare

  log "phase3 completed"
  log "raw: ${RAW_TSV}"
  log "case summary: ${CASE_SUMMARY_TSV}"
  log "io compare: ${IO_COMPARE_TSV}"
  log "metadata: ${META_TXT}"
}

main "$@"
