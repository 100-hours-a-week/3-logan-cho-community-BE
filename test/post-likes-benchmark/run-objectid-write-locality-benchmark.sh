#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

BENCH_DB="${BENCH_DB:-likes_bench}"
MYSQL_PORT="${MYSQL_PORT:-13306}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpw}"
BUFFER_POOL_MB="${BUFFER_POOL_MB:-48}"
MYSQL_MEMORY_LIMIT="${MYSQL_MEMORY_LIMIT:-768m}"
MYSQL_CPU_LIMIT="${MYSQL_CPU_LIMIT:-2.0}"
ROW_COUNT="${ROW_COUNT:-1000000}"
DIST_LIST="${DIST_LIST:-uniform}"
INDEX_MODES="${INDEX_MODES:-base}"
RUNS="${RUNS:-3}"
NUM_POSTS="${NUM_POSTS:-0}"
POST_ID_START="${POST_ID_START:-10000000}"
MEMBER_ID_START="${MEMBER_ID_START:-500000}"

RESULT_DIR="${SCRIPT_DIR}/results/objectid_write_locality"
META_TXT="${RESULT_DIR}/metadata.txt"
SUMMARY_TSV="${RESULT_DIR}/summary.tsv"
RAW_TSV="${RESULT_DIR}/insert_runs.tsv"

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

ensure_defaults() {
  if (( NUM_POSTS <= 0 )); then
    NUM_POSTS=$((ROW_COUNT / 10))
    if (( NUM_POSTS < 10000 )); then
      NUM_POSTS=10000
    fi
  fi
}

capture_status() {
  local output_file="$1"
  mysql_query "SHOW GLOBAL STATUS WHERE Variable_name IN (
    'Innodb_buffer_pool_reads',
    'Innodb_buffer_pool_read_requests',
    'Innodb_data_reads',
    'Innodb_pages_written',
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

init_numbers_table() {
  local max_n="$1"
  mysql_query "CREATE TABLE bench_numbers (n BIGINT NOT NULL PRIMARY KEY) ENGINE=InnoDB;"
  mysql_query "INSERT INTO bench_numbers (n) VALUES (1);"

  local current_max=1
  while (( current_max < max_n )); do
    mysql_query "INSERT INTO bench_numbers (n) SELECT n + ${current_max} FROM bench_numbers;"
    current_max=$((current_max * 2))
  done
  mysql_query "DELETE FROM bench_numbers WHERE n > ${max_n};"
}

init_dataset() {
  local dist="$1"
  ensure_defaults
  log "initializing dataset (rows=${ROW_COUNT}, dist=${dist}, posts=${NUM_POSTS})"

  mysql_admin "DROP DATABASE IF EXISTS ${BENCH_DB}; CREATE DATABASE ${BENCH_DB};"
  init_numbers_table "${ROW_COUNT}"

  mysql_query "CREATE TABLE bench_posts (
    post_seq BIGINT NOT NULL PRIMARY KEY,
    post_id_varchar VARCHAR(24) NOT NULL,
    post_id_bin BINARY(12) NOT NULL,
    UNIQUE KEY uk_post_id_varchar (post_id_varchar),
    UNIQUE KEY uk_post_id_bin (post_id_bin)
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_posts (post_seq, post_id_varchar, post_id_bin)
SELECT src.post_seq,
       src.hex24,
       UNHEX(src.hex24)
FROM (
  SELECT n AS post_seq,
         CONCAT(
           LPAD(HEX(${POST_ID_START} + n - 1), 8, '0'),
           SUBSTRING(SHA2(CONCAT('oid-', ${POST_ID_START} + n - 1), 256), 1, 16)
         ) AS hex24
  FROM bench_numbers
  WHERE n <= ${NUM_POSTS}
) AS src
ORDER BY src.post_seq;"

  mysql_query "CREATE TABLE bench_pairs (
    source_id BIGINT NOT NULL PRIMARY KEY,
    post_seq BIGINT NOT NULL,
    member_id BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_post_seq_member (post_seq, member_id)
  ) ENGINE=InnoDB;"

  if [[ "${dist}" == "skew" ]]; then
    mysql_query "INSERT INTO bench_pairs (source_id, post_seq, member_id, created_at)
SELECT src.source_id,
       src.post_seq,
       ${MEMBER_ID_START} + src.source_id - 1,
       TIMESTAMP('2025-01-01 00:00:00') + INTERVAL src.source_id SECOND
FROM (
  SELECT bn.n AS source_id,
         1 + FLOOR(
           POW(CRC32(CONCAT('ps-', bn.n)) / 4294967295.0, 2.8) * (${NUM_POSTS} - 1)
         ) AS post_seq
  FROM bench_numbers bn
  WHERE bn.n <= ${ROW_COUNT}
) AS src
ORDER BY src.source_id;"
  else
    mysql_query "INSERT INTO bench_pairs (source_id, post_seq, member_id, created_at)
SELECT src.source_id,
       src.post_seq,
       ${MEMBER_ID_START} + src.source_id - 1,
       TIMESTAMP('2025-01-01 00:00:00') + INTERVAL src.source_id SECOND
FROM (
  SELECT bn.n AS source_id,
         1 + MOD(CRC32(CONCAT('pu-', bn.n)), ${NUM_POSTS}) AS post_seq
  FROM bench_numbers bn
  WHERE bn.n <= ${ROW_COUNT}
) AS src
ORDER BY src.source_id;"
  fi

  mysql_query "CREATE TABLE bench_insert_base (
    source_id BIGINT NOT NULL PRIMARY KEY,
    post_id_varchar VARCHAR(24) NOT NULL,
    post_id_bin BINARY(12) NOT NULL,
    member_id BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_insert_base (source_id, post_id_varchar, post_id_bin, member_id, created_at)
SELECT bp.source_id, p.post_id_varchar, p.post_id_bin, bp.member_id, bp.created_at
FROM bench_pairs bp
JOIN bench_posts p ON p.post_seq = bp.post_seq
ORDER BY bp.source_id;"

  mysql_query "CREATE TABLE bench_insert_ordered (
    seq BIGINT NOT NULL PRIMARY KEY,
    post_id_varchar VARCHAR(24) NOT NULL,
    post_id_bin BINARY(12) NOT NULL,
    member_id BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_insert_ordered (seq, post_id_varchar, post_id_bin, member_id, created_at)
SELECT src.seq, src.post_id_varchar, src.post_id_bin, src.member_id, src.created_at
FROM (
  SELECT ROW_NUMBER() OVER (ORDER BY post_id_varchar, member_id) AS seq,
         post_id_varchar,
         post_id_bin,
         member_id,
         created_at
  FROM bench_insert_base
) AS src
ORDER BY src.seq;"

  mysql_query "CREATE TABLE bench_insert_shuffled (
    seq BIGINT NOT NULL PRIMARY KEY,
    post_id_varchar VARCHAR(24) NOT NULL,
    post_id_bin BINARY(12) NOT NULL,
    member_id BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_insert_shuffled (seq, post_id_varchar, post_id_bin, member_id, created_at)
SELECT src.seq, src.post_id_varchar, src.post_id_bin, src.member_id, src.created_at
FROM (
  SELECT ROW_NUMBER() OVER (ORDER BY CRC32(CONCAT('shuf-', source_id))) AS seq,
         post_id_varchar,
         post_id_bin,
         member_id,
         created_at
  FROM bench_insert_base
) AS src
ORDER BY src.seq;"
}

case_suffix() {
  local case_id="$1"
  local index_mode="$2"
  if [[ "${index_mode}" == "base" ]]; then
    printf '%s' "${case_id}"
  else
    printf '%s_%s' "${case_id}" "${index_mode}"
  fi
}

create_case_table() {
  local case_id="$1"
  local index_mode="$2"
  local extra_index=""
  log "creating case table: ${case_id}/${index_mode}"

  case "${index_mode}" in
    base)
      extra_index=""
      ;;
    post_created)
      extra_index=",\n  KEY idx_post_created (post_id, created_at)"
      ;;
    *)
      echo "invalid index mode: ${index_mode}" >&2
      exit 1
      ;;
  esac

  case "${case_id}" in
    S_T|S_R)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_id VARCHAR(24) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (post_id, member_id)$(printf '%b' "${extra_index}")
) ENGINE=InnoDB;"
      ;;
    B_T|B_R)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (post_id, member_id)$(printf '%b' "${extra_index}")
) ENGINE=InnoDB;"
      ;;
    *)
      echo "invalid case: ${case_id}" >&2
      exit 1
      ;;
  esac
}

insert_sql_for_case() {
  local case_id="$1"
  case "${case_id}" in
    S_T)
      cat <<'SQL'
INSERT INTO post_likes_case (post_id, member_id, created_at)
SELECT post_id_varchar, member_id, created_at
FROM bench_insert_ordered
ORDER BY seq;
SQL
      ;;
    S_R)
      cat <<'SQL'
INSERT INTO post_likes_case (post_id, member_id, created_at)
SELECT post_id_varchar, member_id, created_at
FROM bench_insert_shuffled
ORDER BY seq;
SQL
      ;;
    B_T)
      cat <<'SQL'
INSERT INTO post_likes_case (post_id, member_id, created_at)
SELECT post_id_bin, member_id, created_at
FROM bench_insert_ordered
ORDER BY seq;
SQL
      ;;
    B_R)
      cat <<'SQL'
INSERT INTO post_likes_case (post_id, member_id, created_at)
SELECT post_id_bin, member_id, created_at
FROM bench_insert_shuffled
ORDER BY seq;
SQL
      ;;
  esac
}

run_insert_once() {
  local case_id="$1"
  local before_file after_file sql_insert output elapsed_us
  before_file="$(mktemp)"
  after_file="$(mktemp)"
  capture_status "${before_file}"
  sql_insert="$(insert_sql_for_case "${case_id}")"

  output="$(mysql_query "SET @bench_start = NOW(6);
${sql_insert}
SELECT TIMESTAMPDIFF(MICROSECOND, @bench_start, NOW(6));")"

  capture_status "${after_file}"
  elapsed_us="$(echo "${output}" | tail -n1)"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${elapsed_us}" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_buffer_pool_reads")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_buffer_pool_read_requests")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_data_reads")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_pages_written")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_data_writes")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_rows_inserted")"

  rm -f "${before_file}" "${after_file}"
}

collect_table_stats() {
  local output_file="$1"
  local row_count page_size

  mysql_query "ANALYZE TABLE post_likes_case;" >/dev/null
  row_count="$(mysql_query "SELECT COUNT(*) FROM post_likes_case;" | tail -n1)"
  page_size="$(mysql_query "SELECT @@innodb_page_size;" | tail -n1)"

  mysql_query "SELECT n_rows, clustered_index_size, sum_of_other_index_sizes
FROM mysql.innodb_table_stats
WHERE database_name='${BENCH_DB}'
  AND table_name='post_likes_case';" | awk -F'\t' -v ps="${page_size}" -v rows="${row_count}" '
BEGIN {
  print "row_count\tn_rows_estimate\tclustered_pages\tother_pages\tclustered_mb\tother_mb\tprimary_rows_per_page\tother_rows_per_page_total";
}
{
  clustered_mb = ($2 * ps) / 1024 / 1024;
  other_mb = ($3 * ps) / 1024 / 1024;
  primary_rpp = ($2 > 0 ? rows / $2 : 0);
  other_rpp = ($3 > 0 ? rows / $3 : 0);
  printf "%d\t%d\t%d\t%d\t%.3f\t%.3f\t%.3f\t%.3f\n", rows, $1, $2, $3, clustered_mb, other_mb, primary_rpp, other_rpp;
}' > "${output_file}"
}

table_size_row() {
  mysql_query "ANALYZE TABLE post_likes_case;" >/dev/null
  mysql_query "SELECT ROUND(data_length / 1024 / 1024, 3), ROUND(index_length / 1024 / 1024, 3)
FROM information_schema.tables
WHERE table_schema = '${BENCH_DB}'
  AND table_name = 'post_likes_case';"
}

append_summary_row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$2" "${ROW_COUNT}" "${RUNS}" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" "${14}" "${15}" "${16}" \
    >> "${SUMMARY_TSV}"
}

run_case() {
  local dist="$1"
  local case_id="$2"
  local index_mode="$3"
  local case_key table_stats_file size_row
  local r1 r2 r3
  local avg_ms avg_bp_reads avg_bp_req avg_data_reads avg_pages_written avg_data_writes avg_rows_inserted

  case_key="$(case_suffix "${case_id}" "${index_mode}")"

  create_case_table "${case_id}" "${index_mode}"
  r1="$(run_insert_once "${case_id}")"
  create_case_table "${case_id}" "${index_mode}"
  r2="$(run_insert_once "${case_id}")"
  create_case_table "${case_id}" "${index_mode}"
  r3="$(run_insert_once "${case_id}")"

  printf '%s\t%s\t%s\t1\t%s\n' "${dist}" "${index_mode}" "${case_id}" "${r1}" >> "${RAW_TSV}"
  printf '%s\t%s\t%s\t2\t%s\n' "${dist}" "${index_mode}" "${case_id}" "${r2}" >> "${RAW_TSV}"
  printf '%s\t%s\t%s\t3\t%s\n' "${dist}" "${index_mode}" "${case_id}" "${r3}" >> "${RAW_TSV}"

  avg_ms="$(printf '%s\n%s\n%s\n' "${r1}" "${r2}" "${r3}" | awk -F'\t' '{s += $1 / 1000.0} END {printf "%.3f", s / NR}')"
  avg_bp_reads="$(printf '%s\n%s\n%s\n' "${r1}" "${r2}" "${r3}" | awk -F'\t' '{s += $2} END {printf "%.3f", s / NR}')"
  avg_bp_req="$(printf '%s\n%s\n%s\n' "${r1}" "${r2}" "${r3}" | awk -F'\t' '{s += $3} END {printf "%.3f", s / NR}')"
  avg_data_reads="$(printf '%s\n%s\n%s\n' "${r1}" "${r2}" "${r3}" | awk -F'\t' '{s += $4} END {printf "%.3f", s / NR}')"
  avg_pages_written="$(printf '%s\n%s\n%s\n' "${r1}" "${r2}" "${r3}" | awk -F'\t' '{s += $5} END {printf "%.3f", s / NR}')"
  avg_data_writes="$(printf '%s\n%s\n%s\n' "${r1}" "${r2}" "${r3}" | awk -F'\t' '{s += $6} END {printf "%.3f", s / NR}')"
  avg_rows_inserted="$(printf '%s\n%s\n%s\n' "${r1}" "${r2}" "${r3}" | awk -F'\t' '{s += $7} END {printf "%.3f", s / NR}')"

  table_stats_file="${RESULT_DIR}/${dist}_${case_key}_table_stats.tsv"
  collect_table_stats "${table_stats_file}"
  size_row="$(table_size_row)"

  append_summary_row \
    "${dist}/${index_mode}" \
    "${case_id}" \
    "$(echo "${size_row}" | awk -F'\t' '{print $1}')" \
    "$(echo "${size_row}" | awk -F'\t' '{print $2}')" \
    "$(awk 'NR == 2 { print $3 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $4 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $5 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $6 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $7 }' "${table_stats_file}")" \
    "${avg_ms}" \
    "${avg_bp_reads}" \
    "${avg_bp_req}" \
    "${avg_data_reads}" \
    "${avg_pages_written}" \
    "${avg_data_writes}" \
    "${avg_rows_inserted}"
}

main() {
  ensure_defaults
  mkdir -p "${RESULT_DIR}"

  cat > "${META_TXT}" <<EOF
run_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
row_count=${ROW_COUNT}
dist_list=${DIST_LIST}
index_modes=${INDEX_MODES}
runs=${RUNS}
num_posts=${NUM_POSTS}
post_id_start=${POST_ID_START}
member_id_start=${MEMBER_ID_START}
buffer_pool_mb=${BUFFER_POOL_MB}
mysql_memory_limit=${MYSQL_MEMORY_LIMIT}
mysql_cpu_limit=${MYSQL_CPU_LIMIT}
cases=S_T,S_R,B_T,B_R
EOF

  printf 'dist\tcase\trow_count\truns\tdata_mb\tindex_mb\tclustered_pages\tother_pages\tclustered_mb\tother_mb\tprimary_rows_per_page\tinsert_avg_ms\tinsert_bp_reads_avg\tinsert_bp_read_requests_avg\tinsert_data_reads_avg\tinsert_pages_written_avg\tinsert_data_writes_avg\tinsert_rows_inserted_avg\n' > "${SUMMARY_TSV}"
  printf 'dist\tindex_mode\tcase\trun\telapsed_us\tbp_reads_delta\tbp_read_requests_delta\tdata_reads_delta\tpages_written_delta\tdata_writes_delta\trows_inserted_delta\n' > "${RAW_TSV}"

  compose_up_mysql

  local dist
  local index_mode
  for dist in ${DIST_LIST}; do
    init_dataset "${dist}"
    for index_mode in ${INDEX_MODES}; do
      run_case "${dist}" "S_T" "${index_mode}"
      run_case "${dist}" "S_R" "${index_mode}"
      run_case "${dist}" "B_T" "${index_mode}"
      run_case "${dist}" "B_R" "${index_mode}"
    done
  done

  log "objectid write locality benchmark completed"
  log "summary: ${SUMMARY_TSV}"
  log "raw runs: ${RAW_TSV}"
  log "metadata: ${META_TXT}"
}

require_cmd docker
require_cmd mysql
require_cmd awk

main "$@"
