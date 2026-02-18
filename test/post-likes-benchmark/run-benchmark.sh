#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

BENCH_DB="${BENCH_DB:-likes_bench}"
MYSQL_PORT="${MYSQL_PORT:-13306}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpw}"
BUFFER_POOL_MB="${BUFFER_POOL_MB:-48}"
MYSQL_MEMORY_LIMIT="${MYSQL_MEMORY_LIMIT:-384m}"
MYSQL_CPU_LIMIT="${MYSQL_CPU_LIMIT:-2.0}"
SCALE="${SCALE:-medium}"
REPEATS=3
WARMUP_COUNT=1

DIST_MODE="skew"
ID_PATTERN="objectid"
FEED_IN_SIZE=50
BENCH_MEMBER_ID=50038

RESULT_DIR="${SCRIPT_DIR}/results/${SCALE}_warm"
SUMMARY_CSV="${RESULT_DIR}/summary.csv"
META_TXT="${RESULT_DIR}/metadata.txt"

EXPLAIN_A_BIN="${RESULT_DIR}/explain_A_bin.txt"
EXPLAIN_D2_BIN="${RESULT_DIR}/explain_D2_bin.txt"
EXPLAIN_A_STR="${RESULT_DIR}/explain_A_str.txt"

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

average3() {
  awk -v a="$1" -v b="$2" -v c="$3" 'BEGIN { printf "%.3f", (a+b+c)/3.0 }'
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

capture_status() {
  local output_file="$1"
  mysql_query "SHOW GLOBAL STATUS WHERE Variable_name IN (
    'Innodb_buffer_pool_read_requests',
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
    post_id_varchar CHAR(24) NOT NULL,
    post_id_bin BINARY(12) NOT NULL,
    UNIQUE KEY uk_post_varchar (post_id_varchar),
    UNIQUE KEY uk_post_bin (post_id_bin)
  ) ENGINE=InnoDB;"

  mysql_query "INSERT INTO bench_posts (post_seq, post_id_varchar, post_id_bin)
SELECT src.n, src.hex24, UNHEX(src.hex24)
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
}

create_case_table() {
  local case_id="$1"
  log "creating case table: ${case_id}"
  case "${case_id}" in
    A_bin)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (post_id, member_id)
) ENGINE=InnoDB;"
      ;;
    D2_bin)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  id BIGINT NOT NULL AUTO_INCREMENT,
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_member_post (member_id, post_id),
  KEY idx_feed_deleted_post_member (deleted_at, post_id, member_id)
) ENGINE=InnoDB;"
      ;;
    A_str)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_id VARCHAR(24) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (post_id, member_id)
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
    A_bin|D2_bin)
      cat <<SQL
INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT p.post_id_bin, s.member_id, s.created_at, NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq
ORDER BY p.post_id_bin, s.member_id;
SQL
      ;;
    A_str)
      cat <<SQL
INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT p.post_id_varchar, s.member_id, s.created_at, NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq
ORDER BY p.post_id_varchar, s.member_id;
SQL
      ;;
  esac
}

feed_list_for_case() {
  local case_id="$1"
  if [[ "${case_id}" == "A_str" ]]; then
    mysql_query "SET SESSION group_concat_max_len=1000000;
SELECT GROUP_CONCAT(CONCAT(\"'\", p.post_id_varchar, \"'\") ORDER BY p.post_seq SEPARATOR ',')
FROM (
  SELECT post_seq, post_id_varchar
  FROM bench_posts
  ORDER BY CRC32(CONCAT('feed-', post_seq))
  LIMIT ${FEED_IN_SIZE}
) AS p;" | tail -n1
  else
    mysql_query "SET SESSION group_concat_max_len=1000000;
SELECT GROUP_CONCAT(CONCAT(\"X'\", HEX(p.post_id_bin), \"'\") ORDER BY p.post_seq SEPARATOR ',')
FROM (
  SELECT post_seq, post_id_bin
  FROM bench_posts
  ORDER BY CRC32(CONCAT('feed-', post_seq))
  LIMIT ${FEED_IN_SIZE}
) AS p;" | tail -n1
  fi
}

run_insert_once() {
  local case_id="$1"
  local before_file after_file output elapsed_us bp_delta rows_inserted_delta
  local sql_insert

  before_file="$(mktemp)"
  after_file="$(mktemp)"
  capture_status "${before_file}"
  sql_insert="$(insert_sql_for_case "${case_id}")"

  output="$(mysql_query "SET @bench_start = NOW(6);
${sql_insert}
SELECT TIMESTAMPDIFF(MICROSECOND, @bench_start, NOW(6));")"

  capture_status "${after_file}"
  elapsed_us="$(echo "${output}" | tail -n1)"
  bp_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_buffer_pool_read_requests")"
  rows_inserted_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_rows_inserted")"

  rm -f "${before_file}" "${after_file}"
  echo "${elapsed_us},${bp_delta},${rows_inserted_delta}"
}

run_feed_once() {
  local in_list="$1"
  local before_file after_file output elapsed_us bp_delta rows_inserted_delta

  before_file="$(mktemp)"
  after_file="$(mktemp)"
  capture_status "${before_file}"

  output="$(mysql_query "SET @bench_start = NOW(6);
SELECT COUNT(*) FROM (
  SELECT pl.post_id,
         COUNT(*) AS like_count,
         MAX(CASE WHEN pl.member_id = ${BENCH_MEMBER_ID} THEN TRUE ELSE FALSE END) AS amILiking
  FROM post_likes_case pl
  WHERE pl.post_id IN (${in_list})
    AND pl.deleted_at IS NULL
  GROUP BY pl.post_id
) AS q;
SELECT TIMESTAMPDIFF(MICROSECOND, @bench_start, NOW(6));")"

  capture_status "${after_file}"
  elapsed_us="$(echo "${output}" | tail -n1)"
  bp_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_buffer_pool_read_requests")"
  rows_inserted_delta="$(status_delta "${before_file}" "${after_file}" "Innodb_rows_inserted")"

  rm -f "${before_file}" "${after_file}"
  echo "${elapsed_us},${bp_delta},${rows_inserted_delta}"
}

write_explain() {
  local case_id="$1"
  local in_list="$2"
  local out_file="$3"
  mysql_query "EXPLAIN ANALYZE
SELECT pl.post_id,
       COUNT(*) AS like_count,
       MAX(CASE WHEN pl.member_id = ${BENCH_MEMBER_ID} THEN TRUE ELSE FALSE END) AS amILiking
FROM post_likes_case pl
WHERE pl.post_id IN (${in_list})
  AND pl.deleted_at IS NULL
GROUP BY pl.post_id;" > "${out_file}"
}

table_sizes() {
  mysql_query "ANALYZE TABLE post_likes_case;" >/dev/null
  mysql_query "SELECT ROUND(data_length / 1024 / 1024, 3), ROUND(index_length / 1024 / 1024, 3)
FROM information_schema.tables
WHERE table_schema = '${BENCH_DB}'
  AND table_name = 'post_likes_case';"
}

append_summary_row() {
  printf '%s,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f\n' \
    "$1" "$2" "${REPEATS}" "$3" "$4" "$5" "$6" "$7" >> "${SUMMARY_CSV}"
}

run_case() {
  local case_id="$1"
  local explain_file="$2"
  local ins1 ins2 ins3 sel1 sel2 sel3
  local in_list sizes data_mb index_mb
  local i1_ms i2_ms i3_ms i1_bp i2_bp i3_bp i1_rows i2_rows i3_rows
  local s1_ms s2_ms s3_ms s1_bp s2_bp s3_bp s1_rows s2_rows s3_rows
  local insert_avg_ms insert_avg_bp insert_avg_rows
  local select_avg_ms select_avg_bp select_avg_rows

  # INSERT 3회 평균: 매 회 테이블 재생성
  create_case_table "${case_id}"
  ins1="$(run_insert_once "${case_id}")"
  create_case_table "${case_id}"
  ins2="$(run_insert_once "${case_id}")"
  create_case_table "${case_id}"
  ins3="$(run_insert_once "${case_id}")"

  IFS=',' read -r i1_ms i1_bp i1_rows <<< "${ins1}"
  IFS=',' read -r i2_ms i2_bp i2_rows <<< "${ins2}"
  IFS=',' read -r i3_ms i3_bp i3_rows <<< "${ins3}"

  insert_avg_ms="$(average3 "$(awk -v u="${i1_ms}" 'BEGIN{print u/1000.0}')" "$(awk -v u="${i2_ms}" 'BEGIN{print u/1000.0}')" "$(awk -v u="${i3_ms}" 'BEGIN{print u/1000.0}')")"
  insert_avg_bp="$(average3 "${i1_bp}" "${i2_bp}" "${i3_bp}")"
  insert_avg_rows="$(average3 "${i1_rows}" "${i2_rows}" "${i3_rows}")"

  in_list="$(feed_list_for_case "${case_id}")"

  # warm-up 1회
  for _ in $(seq 1 "${WARMUP_COUNT}"); do
    run_feed_once "${in_list}" >/dev/null
  done

  # SELECT 3회 평균
  sel1="$(run_feed_once "${in_list}")"
  sel2="$(run_feed_once "${in_list}")"
  sel3="$(run_feed_once "${in_list}")"

  IFS=',' read -r s1_ms s1_bp s1_rows <<< "${sel1}"
  IFS=',' read -r s2_ms s2_bp s2_rows <<< "${sel2}"
  IFS=',' read -r s3_ms s3_bp s3_rows <<< "${sel3}"

  select_avg_ms="$(average3 "$(awk -v u="${s1_ms}" 'BEGIN{print u/1000.0}')" "$(awk -v u="${s2_ms}" 'BEGIN{print u/1000.0}')" "$(awk -v u="${s3_ms}" 'BEGIN{print u/1000.0}')")"
  select_avg_bp="$(average3 "${s1_bp}" "${s2_bp}" "${s3_bp}")"
  select_avg_rows="$(average3 "${s1_rows}" "${s2_rows}" "${s3_rows}")"

  sizes="$(table_sizes)"
  data_mb="$(echo "${sizes}" | awk -F'\t' '{print $1}')"
  index_mb="$(echo "${sizes}" | awk -F'\t' '{print $2}')"

  append_summary_row "${case_id}" "bulk_insert" "${insert_avg_ms}" "${insert_avg_bp}" "${insert_avg_rows}" "${data_mb}" "${index_mb}"
  append_summary_row "${case_id}" "feed_select_in50" "${select_avg_ms}" "${select_avg_bp}" "${select_avg_rows}" "${data_mb}" "${index_mb}"

  write_explain "${case_id}" "${in_list}" "${explain_file}"
}

main() {
  mkdir -p "${RESULT_DIR}"
  cat > "${META_TXT}" <<EOF
run_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
scale=${SCALE}
dist=${DIST_MODE}
id_pattern=${ID_PATTERN}
feed_in_size=${FEED_IN_SIZE}
repeats=${REPEATS}
warmup_count=${WARMUP_COUNT}
cases=A_bin,D2_bin,A_str
buffer_pool_mb=${BUFFER_POOL_MB}
mysql_memory_limit=${MYSQL_MEMORY_LIMIT}
mysql_cpu_limit=${MYSQL_CPU_LIMIT}
num_posts=${NUM_POSTS}
num_members=${NUM_MEMBERS}
num_likes=${NUM_LIKES}
EOF

  echo "case,operation,repeat_count,avg_elapsed_ms,avg_innodb_buffer_pool_read_requests_delta,avg_innodb_rows_inserted_delta,data_length_mb,index_length_mb" > "${SUMMARY_CSV}"
  : > "${EXPLAIN_A_BIN}"
  : > "${EXPLAIN_D2_BIN}"
  : > "${EXPLAIN_A_STR}"

  compose_up_mysql
  init_dataset

  run_case "A_bin" "${EXPLAIN_A_BIN}"
  run_case "D2_bin" "${EXPLAIN_D2_BIN}"
  run_case "A_str" "${EXPLAIN_A_STR}"

  log "benchmark completed"
  log "summary: ${SUMMARY_CSV}"
  log "metadata: ${META_TXT}"
}

main "$@"
