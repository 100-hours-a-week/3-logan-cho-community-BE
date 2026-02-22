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
FEED_IN_SIZE="${FEED_IN_SIZE:-50}"

DIST_MODE="skew"
ID_PATTERN="objectid"

RESULT_DIR="${SCRIPT_DIR}/results/phase1_covering_${SCALE}"
META_TXT="${RESULT_DIR}/metadata.txt"
SUMMARY_TSV="${RESULT_DIR}/summary.tsv"

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
require_cmd sed

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
}

create_case_table() {
  local case_id="$1"
  log "creating case table: ${case_id}"
  case "${case_id}" in
    C)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (post_id, member_id),
  UNIQUE KEY uk_member_post_deleted (member_id, post_id, deleted_at),
  KEY idx_feed_deleted_post_member (deleted_at, post_id, member_id),
  KEY idx_member (member_id)
) ENGINE=InnoDB;"
      ;;
    S_rand)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  id BINARY(12) NOT NULL,
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_member_post_deleted (member_id, post_id, deleted_at),
  KEY idx_feed_deleted_post_member (deleted_at, post_id, member_id),
  KEY idx_member (member_id)
) ENGINE=InnoDB;"
      ;;
    S_ai)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  id BIGINT NOT NULL AUTO_INCREMENT,
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_member_post_deleted (member_id, post_id, deleted_at),
  KEY idx_feed_deleted_post_member (deleted_at, post_id, member_id),
  KEY idx_member (member_id)
) ENGINE=InnoDB;"
      ;;
    *)
      echo "invalid case: ${case_id}" >&2
      exit 1
      ;;
  esac
}

insert_case_data() {
  local case_id="$1"
  log "inserting case data: ${case_id}"
  case "${case_id}" in
    C)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT p.post_id_bin, s.member_id, s.created_at, NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq
ORDER BY p.post_id_bin, s.member_id;"
      ;;
    S_rand)
      mysql_query "INSERT INTO post_likes_case (id, post_id, member_id, created_at, deleted_at)
SELECT UNHEX(SUBSTRING(SHA2(CONCAT('pk-', s.source_id), 256), 1, 24)),
       p.post_id_bin,
       s.member_id,
       s.created_at,
       NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq;"
      ;;
    S_ai)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT p.post_id_bin, s.member_id, s.created_at, NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq;"
      ;;
  esac
}

feed_list() {
  mysql_query "SET SESSION group_concat_max_len=1000000;
SELECT GROUP_CONCAT(CONCAT(\"X'\", HEX(p.post_id_bin), \"'\") ORDER BY p.post_seq SEPARATOR ',')
FROM (
  SELECT post_seq, post_id_bin
  FROM bench_posts
  ORDER BY CRC32(CONCAT('feed-', post_seq))
  LIMIT ${FEED_IN_SIZE}
) AS p;" | tail -n1
}

pick_existing_pair() {
  mysql_query "SELECT member_id, HEX(post_id)
FROM post_likes_case
WHERE deleted_at IS NULL
LIMIT 1;" | tail -n1
}

traditional_explain_row() {
  local sql="$1"
  local out_file="$2"
  local row_file="$3"
  local explain_output
  explain_output="$(mysql_query "EXPLAIN ${sql}")"
  printf '%s\n' "${explain_output}" > "${out_file}"
  printf '%s\n' "${explain_output}" | awk 'NF > 0 {line=$0} END {print line}' > "${row_file}"
}

write_analyze() {
  local sql="$1"
  local out_file="$2"
  mysql_query "EXPLAIN ANALYZE ${sql}" > "${out_file}"
}

append_summary() {
  local case_id="$1"
  local query_id="$2"
  local row_file="$3"
  local key extra using_index
  key="$(awk -F'\t' '{print $7}' "${row_file}")"
  extra="$(awk -F'\t' '{print $12}' "${row_file}")"
  if [[ -z "${extra}" || "${extra}" == "NULL" ]]; then
    extra="(none)"
  fi
  if echo "${extra}" | grep -qi "Using index"; then
    using_index="yes"
  else
    using_index="no"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "${case_id}" "${query_id}" "${key}" "${using_index}" "${extra}" >> "${SUMMARY_TSV}"
}

run_case_phase1() {
  local case_id="$1"
  local feed_in dup_pair dup_member dup_post_hex
  local feed_sql exists_sql bulk_update_sql bulk_probe_sql
  local out_prefix

  create_case_table "${case_id}"
  insert_case_data "${case_id}"

  feed_in="$(feed_list)"
  dup_pair="$(pick_existing_pair)"
  dup_member="$(echo "${dup_pair}" | awk -F'\t' '{print $1}')"
  dup_post_hex="$(echo "${dup_pair}" | awk -F'\t' '{print $2}')"

  out_prefix="${RESULT_DIR}/${case_id}"

  feed_sql="SELECT pl.post_id,
       COUNT(*) AS like_count,
       MAX(CASE WHEN pl.member_id = ${dup_member} THEN TRUE ELSE FALSE END) AS amILiking
FROM post_likes_case pl
WHERE pl.post_id IN (${feed_in})
  AND pl.deleted_at IS NULL
GROUP BY pl.post_id"

  exists_sql="SELECT 1
FROM post_likes_case
WHERE post_id = X'${dup_post_hex}'
  AND member_id = ${dup_member}
  AND deleted_at IS NULL
LIMIT 1"

  bulk_update_sql="UPDATE post_likes_case
SET deleted_at = CURRENT_TIMESTAMP(6)
WHERE member_id = ${dup_member}
  AND deleted_at IS NULL"

  bulk_probe_sql="SELECT post_id
FROM post_likes_case
WHERE member_id = ${dup_member}
  AND deleted_at IS NULL"

  traditional_explain_row "${feed_sql}" "${out_prefix}_explain_feed.txt" "${out_prefix}_row_feed.txt"
  write_analyze "${feed_sql}" "${out_prefix}_analyze_feed.txt"
  append_summary "${case_id}" "feed_aggregate" "${out_prefix}_row_feed.txt"

  traditional_explain_row "${exists_sql}" "${out_prefix}_explain_exists.txt" "${out_prefix}_row_exists.txt"
  write_analyze "${exists_sql}" "${out_prefix}_analyze_exists.txt"
  append_summary "${case_id}" "exists_check" "${out_prefix}_row_exists.txt"

  traditional_explain_row "${bulk_update_sql}" "${out_prefix}_explain_bulk_update.txt" "${out_prefix}_row_bulk_update.txt"
  write_analyze "${bulk_probe_sql}" "${out_prefix}_analyze_bulk_probe.txt"
  append_summary "${case_id}" "bulk_update_path" "${out_prefix}_row_bulk_update.txt"
}

main() {
  mkdir -p "${RESULT_DIR}"

  cat > "${META_TXT}" <<EOF
run_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
scale=${SCALE}
dist=${DIST_MODE}
id_pattern=${ID_PATTERN}
feed_in_size=${FEED_IN_SIZE}
buffer_pool_mb=${BUFFER_POOL_MB}
mysql_memory_limit=${MYSQL_MEMORY_LIMIT}
mysql_cpu_limit=${MYSQL_CPU_LIMIT}
num_posts=${NUM_POSTS}
num_members=${NUM_MEMBERS}
num_likes=${NUM_LIKES}
cases=C,S_rand,S_ai
EOF

  printf 'case\tquery_id\tkey\tusing_index\textra\n' > "${SUMMARY_TSV}"

  compose_up_mysql
  init_dataset
  run_case_phase1 "C"
  run_case_phase1 "S_rand"
  run_case_phase1 "S_ai"

  log "phase1 completed"
  log "summary: ${SUMMARY_TSV}"
  log "metadata: ${META_TXT}"
}

main "$@"
