#!/usr/bin/env bash

set -euo pipefail

BENCH_DB="${BENCH_DB:-likes_bench}"
MYSQL_PORT="${MYSQL_PORT:-13306}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpw}"
BUFFER_POOL_MB="${BUFFER_POOL_MB:-48}"
MYSQL_MEMORY_LIMIT="${MYSQL_MEMORY_LIMIT:-768m}"
MYSQL_CPU_LIMIT="${MYSQL_CPU_LIMIT:-2.0}"
ROW_COUNT="${ROW_COUNT:-1000000}"
DIST_MODE="${DIST_MODE:-uniform}"
POST_ID_BYTES="${POST_ID_BYTES:-12}"
PROBE_COUNT="${PROBE_COUNT:-100000}"
POST_ID_START="${POST_ID_START:-10000000}"
MEMBER_ID_START="${MEMBER_ID_START:-500000}"
POST_LIKE_ID_START="${POST_LIKE_ID_START:-50000000}"
NUM_POSTS="${NUM_POSTS:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

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
  ensure_defaults
  log "initializing dataset (rows=${ROW_COUNT}, dist=${DIST_MODE}, post_id_bytes=${POST_ID_BYTES}, posts=${NUM_POSTS})"

  mysql_admin "DROP DATABASE IF EXISTS ${BENCH_DB}; CREATE DATABASE ${BENCH_DB};"

  init_numbers_table "${ROW_COUNT}"

  mysql_query "CREATE TABLE bench_posts (
    post_seq BIGINT NOT NULL PRIMARY KEY,
    post_id_bin BINARY(${POST_ID_BYTES}) NOT NULL,
    UNIQUE KEY uk_post_id_bin (post_id_bin)
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_posts (post_seq, post_id_bin)
SELECT src.post_seq,
       UNHEX(
         CONCAT(
           LPAD(HEX(${POST_ID_START} + src.post_seq - 1), 8, '0'),
           SUBSTRING(SHA2(CONCAT('oid-', ${POST_ID_START} + src.post_seq - 1), 256), 1, (${POST_ID_BYTES} - 4) * 2)
         )
       )
FROM (
  SELECT n AS post_seq
  FROM bench_numbers
  WHERE n <= ${NUM_POSTS}
) AS src
ORDER BY src.post_seq;"

  mysql_query "CREATE TABLE bench_pairs (
    source_id BIGINT NOT NULL PRIMARY KEY,
    post_id BINARY(${POST_ID_BYTES}) NOT NULL,
    member_id BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uk_post_member (post_id, member_id),
    KEY idx_member (member_id)
  ) ENGINE=InnoDB;"

  if [[ "${DIST_MODE}" == "skew" ]]; then
    mysql_query "INSERT INTO bench_pairs (source_id, post_id, member_id, created_at)
SELECT src.source_id,
       p.post_id_bin,
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
JOIN bench_posts p ON p.post_seq = src.post_seq
ORDER BY src.source_id;"
  else
    mysql_query "INSERT INTO bench_pairs (source_id, post_id, member_id, created_at)
SELECT src.source_id,
       p.post_id_bin,
       ${MEMBER_ID_START} + src.source_id - 1,
       TIMESTAMP('2025-01-01 00:00:00') + INTERVAL src.source_id SECOND
FROM (
  SELECT bn.n AS source_id,
         1 + MOD(CRC32(CONCAT('pu-', bn.n)), ${NUM_POSTS}) AS post_seq
  FROM bench_numbers bn
  WHERE bn.n <= ${ROW_COUNT}
) AS src
JOIN bench_posts p ON p.post_seq = src.post_seq
ORDER BY src.source_id;"
  fi

  mysql_query "CREATE TABLE bench_probe_keys (
    probe_id BIGINT NOT NULL PRIMARY KEY,
    post_id BINARY(${POST_ID_BYTES}) NOT NULL,
    member_id BIGINT NOT NULL,
    KEY idx_post_member (post_id, member_id)
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_probe_keys (probe_id, post_id, member_id)
SELECT src.probe_id, bp.post_id, bp.member_id
FROM (
  SELECT bn.n AS probe_id,
         1 + MOD(CRC32(CONCAT('probe-', bn.n)), ${ROW_COUNT}) AS source_id
  FROM bench_numbers bn
  WHERE bn.n <= ${PROBE_COUNT}
) AS src
JOIN bench_pairs bp ON bp.source_id = src.source_id
ORDER BY src.probe_id;"
}

level_common_indexes() {
  local level="$1"
  case "${level}" in
    L0) cat <<'EOF'

EOF
      ;;
    L1) cat <<'EOF'
  KEY idx_member (member_id)
EOF
      ;;
    L2) cat <<'EOF'
  KEY idx_member (member_id),
  KEY idx_created (created_at)
EOF
      ;;
    L3) cat <<'EOF'
  KEY idx_member (member_id),
  KEY idx_created (created_at),
  KEY idx_post_created (post_id, created_at)
EOF
      ;;
    L4) cat <<'EOF'
  KEY idx_member (member_id),
  KEY idx_created (created_at),
  KEY idx_post_created (post_id, created_at),
  KEY idx_member_created (member_id, created_at)
EOF
      ;;
    L5) cat <<'EOF'
  KEY idx_member (member_id),
  KEY idx_created (created_at),
  KEY idx_post_created (post_id, created_at),
  KEY idx_member_created (member_id, created_at),
  KEY idx_created_member (created_at, member_id)
EOF
      ;;
    *)
      echo "invalid level: ${level}" >&2
      exit 1
      ;;
  esac
}

create_case_table() {
  local case_id="$1"
  local level="$2"
  local common_indexes

  common_indexes="$(level_common_indexes "${level}")"
  log "creating case table: ${case_id}/${level}"

  case "${case_id}" in
    C)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_id BINARY(${POST_ID_BYTES}) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (post_id, member_id)$(if [[ -n "${common_indexes}" ]]; then printf ',\n%s' "${common_indexes}"; fi)
) ENGINE=InnoDB;"
      ;;
    S)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_like_id BIGINT NOT NULL AUTO_INCREMENT,
  post_id BINARY(${POST_ID_BYTES}) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (post_like_id),
  UNIQUE KEY uk_post_member (post_id, member_id)$(if [[ -n "${common_indexes}" ]]; then printf ',\n%s' "${common_indexes}"; fi)
) ENGINE=InnoDB AUTO_INCREMENT=${POST_LIKE_ID_START};"
      ;;
    *)
      echo "invalid case: ${case_id}" >&2
      exit 1
      ;;
  esac
}

load_case_data() {
  local case_id="$1"
  log "loading case data: ${case_id}"

  case "${case_id}" in
    C)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at)
SELECT post_id, member_id, created_at
FROM bench_pairs
ORDER BY source_id;"
      ;;
    S)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at)
SELECT post_id, member_id, created_at
FROM bench_pairs
ORDER BY source_id;"
      ;;
    *)
      echo "invalid case: ${case_id}" >&2
      exit 1
      ;;
  esac
}

capture_status() {
  local output_file="$1"
  mysql_query "SHOW GLOBAL STATUS WHERE Variable_name IN (
    'Innodb_buffer_pool_reads',
    'Innodb_buffer_pool_read_requests',
    'Innodb_data_reads',
    'Innodb_rows_read',
    'Innodb_rows_inserted',
    'Innodb_pages_written',
    'Innodb_data_writes'
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

table_size_row() {
  mysql_query "ANALYZE TABLE post_likes_case;" >/dev/null
  mysql_query "SELECT ROUND(data_length / 1024 / 1024, 3), ROUND(index_length / 1024 / 1024, 3)
FROM information_schema.tables
WHERE table_schema = '${BENCH_DB}'
  AND table_name = 'post_likes_case';"
}

collect_index_stats() {
  local output_file="$1"
  local row_count
  row_count="$(mysql_query "SELECT COUNT(*) FROM post_likes_case;" | tail -n1)"

  mysql_query "SELECT index_name, stat_name, stat_value
FROM mysql.innodb_index_stats
WHERE database_name='${BENCH_DB}'
  AND table_name='post_likes_case'
  AND stat_name IN ('size', 'n_leaf_pages', 'n_diff_pfx01')
ORDER BY index_name, stat_name;" > "${output_file}.raw"

  local page_size
  page_size="$(mysql_query "SELECT @@innodb_page_size;" | tail -n1)"

  awk -F'\t' -v ps="${page_size}" -v rows="${row_count}" '
BEGIN {
  print "index_name\tsize_pages\tsize_mb\tn_leaf_pages\tn_diff_pfx01\trows_per_leaf_page";
}
function flush() {
  if (cur == "") return;
  size_mb = (size_pages * ps) / 1024 / 1024;
  rows_per_leaf = (leaf_pages > 0 ? rows / leaf_pages : 0);
  printf "%s\t%d\t%.3f\t%d\t%d\t%.3f\n", cur, size_pages, size_mb, leaf_pages, n_diff, rows_per_leaf;
}
{
  idx = $1;
  st = $2;
  val = $3 + 0;

  if (idx != cur) {
    flush();
    cur = idx;
    size_pages = 0;
    leaf_pages = 0;
    n_diff = 0;
  }

  if (st == "size") size_pages = val;
  else if (st == "n_leaf_pages") leaf_pages = val;
  else if (st == "n_diff_pfx01") n_diff = val;
}
END { flush(); }
' "${output_file}.raw" > "${output_file}"
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

probe_pair() {
  mysql_query "SELECT HEX(post_id), member_id
FROM bench_probe_keys
ORDER BY probe_id
LIMIT 1;" | tail -n1
}

run_exact_lookup_probe() {
  local before_file after_file output elapsed_us
  before_file="$(mktemp)"
  after_file="$(mktemp)"
  capture_status "${before_file}"

  output="$(mysql_query "SET @bench_start = NOW(6);
SELECT COUNT(*)
FROM bench_probe_keys q
JOIN post_likes_case pl
  ON pl.post_id = q.post_id
 AND pl.member_id = q.member_id;
SELECT TIMESTAMPDIFF(MICROSECOND, @bench_start, NOW(6));")"

  capture_status "${after_file}"
  elapsed_us="$(echo "${output}" | tail -n1)"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${elapsed_us}" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_buffer_pool_reads")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_buffer_pool_read_requests")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_data_reads")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_rows_read")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_pages_written")" \
    "$(status_delta "${before_file}" "${after_file}" "Innodb_data_writes")"

  rm -f "${before_file}" "${after_file}"
}

write_single_lookup_explain() {
  local output_file="$1"
  local probe_hex member_id
  local pair
  pair="$(probe_pair)"
  probe_hex="$(echo "${pair}" | awk -F'\t' '{print $1}')"
  member_id="$(echo "${pair}" | awk -F'\t' '{print $2}')"

  mysql_query "EXPLAIN ANALYZE
SELECT 1
FROM post_likes_case
WHERE post_id = X'${probe_hex}'
  AND member_id = ${member_id}
LIMIT 1;" > "${output_file}"
}
