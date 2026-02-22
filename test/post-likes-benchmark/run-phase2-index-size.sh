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
SCALE="${SCALE:-medium}"

DIST_MODE="skew"
ID_PATTERN="objectid"

RESULT_DIR="${SCRIPT_DIR}/results/phase2_index_size_${SCALE}"
META_TXT="${RESULT_DIR}/metadata.txt"
SUMMARY_TSV="${RESULT_DIR}/summary.tsv"
BREAK_EVEN_TSV="${RESULT_DIR}/break_even.tsv"

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
  local level="$1"
  local case_id="$2"
  log "creating case table: ${level}/${case_id}"

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

  case "${level}" in
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
      echo "invalid level: ${level}" >&2
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
    S_rand)
      mysql_query "DROP TABLE IF EXISTS post_likes_case;
CREATE TABLE post_likes_case (
  id BINARY(12) NOT NULL,
  post_id BINARY(12) NOT NULL,
  member_id BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  deleted_at DATETIME(6) NULL,
  PRIMARY KEY (id),
  ${common_indexes},
  KEY idx_feed_deleted_post_member (deleted_at, post_id, member_id)
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

insert_case_data() {
  local case_id="$1"
  log "inserting case data: ${case_id}"
  case "${case_id}" in
    C)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT p.post_id_bin, s.member_id, s.created_at, NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq
ORDER BY s.source_id;"
      ;;
    S_rand)
      mysql_query "INSERT INTO post_likes_case (id, post_id, member_id, created_at, deleted_at)
SELECT UNHEX(SUBSTRING(SHA2(CONCAT('pk-', s.source_id), 256), 1, 24)),
       p.post_id_bin,
       s.member_id,
       s.created_at,
       NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq
ORDER BY s.source_id;"
      ;;
    S_ai)
      mysql_query "INSERT INTO post_likes_case (post_id, member_id, created_at, deleted_at)
SELECT p.post_id_bin, s.member_id, s.created_at, NULL
FROM bench_likes_source s
JOIN bench_posts p ON p.post_seq = s.post_seq
ORDER BY s.source_id;"
      ;;
  esac
}

common_index_names_for_level() {
  local level="$1"
  case "${level}" in
    L1)
      echo "uk_member_post_deleted idx_member"
      ;;
    L2)
      echo "uk_member_post_deleted idx_member idx_created idx_deleted_created"
      ;;
    L3)
      echo "uk_member_post_deleted idx_member idx_created idx_deleted_created idx_post_created idx_member_created idx_deleted_member"
      ;;
    *)
      echo ""
      ;;
  esac
}

collect_case_stats() {
  local level="$1"
  local case_id="$2"
  local common_names index_stats_raw index_stats_tsv page_size
  local data_mb index_mb primary_mb secondary_total_mb common_secondary_mb extra_single_mb index_count common_count

  mysql_query "ANALYZE TABLE post_likes_case;" >/dev/null

  index_stats_raw="${RESULT_DIR}/${level}_${case_id}_index_stats_raw.tsv"
  index_stats_tsv="${RESULT_DIR}/${level}_${case_id}_index_stats.tsv"

  mysql_query "SELECT index_name, stat_value
FROM mysql.innodb_index_stats
WHERE database_name='${BENCH_DB}'
  AND table_name='post_likes_case'
  AND stat_name='size'
ORDER BY index_name;" > "${index_stats_raw}"

  page_size="$(mysql_query "SELECT @@innodb_page_size;" | tail -n1)"

  awk -F'\t' -v ps="${page_size}" 'BEGIN { print "index_name\tpages\tsize_mb" }
  { printf "%s\t%s\t%.3f\n", $1, $2, ($2 * ps) / 1024 / 1024 }' "${index_stats_raw}" > "${index_stats_tsv}"

  read -r data_mb index_mb < <(
    mysql_query "SELECT ROUND(data_length / 1024 / 1024, 3), ROUND(index_length / 1024 / 1024, 3)
FROM information_schema.tables
WHERE table_schema = '${BENCH_DB}'
  AND table_name = 'post_likes_case';"
  )

  primary_mb="$(awk -F'\t' '$1 == "PRIMARY" { print $3 }' "${index_stats_tsv}")"
  if [[ -z "${primary_mb}" ]]; then
    primary_mb="0.000"
  fi

  secondary_total_mb="$(awk -F'\t' 'NR > 1 && $1 != "PRIMARY" { s += $3 } END { printf "%.3f", s + 0 }' "${index_stats_tsv}")"

  common_names="$(common_index_names_for_level "${level}")"
  common_secondary_mb="$(awk -F'\t' -v n="${common_names}" '
BEGIN {
  split(n, arr, " ");
  for (i in arr) if (arr[i] != "") m[arr[i]] = 1;
}
NR > 1 && ($1 in m) { s += $3 }
END { printf "%.3f", s + 0 }' "${index_stats_tsv}")"

  extra_single_mb="$(awk -F'\t' '$1 == "idx_feed_deleted_post_member" { print $3 }' "${index_stats_tsv}")"
  if [[ -z "${extra_single_mb}" ]]; then
    extra_single_mb="0.000"
  fi

  index_count="$(awk 'NR > 1 { c++ } END { print c + 0 }' "${index_stats_tsv}")"
  common_count="$(echo "${common_names}" | awk '{print NF}')"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${level}" "${case_id}" "${data_mb}" "${index_mb}" "${primary_mb}" "${secondary_total_mb}" \
    "${common_secondary_mb}" "${extra_single_mb}" "${index_count}" "${common_count}" >> "${SUMMARY_TSV}"
}

calculate_break_even() {
  awk -F'\t' '
NR == 1 { next }
{
  key = $1 FS $2;
  row[key] = $0;
}
END {
  print "level\tvariant\textra_single_cost_mb\tcommon_secondary_saving_total_mb\tsaving_per_secondary_mb\tcommon_secondary_count\tbreak_even_k\tover_break_even";

  n_levels = split("L1 L2 L3", levels, " ");
  n_vars = split("S_rand S_ai", vars, " ");

  for (li = 1; li <= n_levels; li++) {
    lvl = levels[li];
    split(row[lvl FS "C"], c, FS);

    for (vi = 1; vi <= n_vars; vi++) {
      v = vars[vi];
      split(row[lvl FS v], s, FS);

      common_count = s[10] + 0;
      extra = s[8] + 0;
      saving_total = (c[7] + 0) - (s[7] + 0);

      if (common_count > 0) {
        saving_per = saving_total / common_count;
      } else {
        saving_per = 0;
      }

      if (saving_per > 0) {
        break_even = int((extra / saving_per) + 0.999999);
        over = (common_count >= break_even ? "yes" : "no");
      } else {
        break_even = "inf";
        over = "no";
      }

      printf "%s\t%s\t%.3f\t%.3f\t%.3f\t%d\t%s\t%s\n",
        lvl, v, extra, saving_total, saving_per, common_count, break_even, over;
    }
  }
}' "${SUMMARY_TSV}" > "${BREAK_EVEN_TSV}"
}

run_level() {
  local level="$1"
  run_level_case "${level}" "C"
  run_level_case "${level}" "S_rand"
  run_level_case "${level}" "S_ai"
}

run_level_case() {
  local level="$1"
  local case_id="$2"
  create_case_table "${level}" "${case_id}"
  insert_case_data "${case_id}"
  collect_case_stats "${level}" "${case_id}"
}

main() {
  mkdir -p "${RESULT_DIR}"

  cat > "${META_TXT}" <<EOF
run_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
scale=${SCALE}
dist=${DIST_MODE}
id_pattern=${ID_PATTERN}
buffer_pool_mb=${BUFFER_POOL_MB}
mysql_memory_limit=${MYSQL_MEMORY_LIMIT}
mysql_cpu_limit=${MYSQL_CPU_LIMIT}
num_posts=${NUM_POSTS}
num_members=${NUM_MEMBERS}
num_likes=${NUM_LIKES}
levels=L1,L2,L3
cases=C,S_rand,S_ai
EOF

  printf 'level\tcase\tdata_mb\tindex_mb\tprimary_mb\tsecondary_total_mb\tcommon_secondary_mb\textra_single_mb\tindex_count\tcommon_index_count\n' > "${SUMMARY_TSV}"

  compose_up_mysql
  init_dataset
  run_level "L1"
  run_level "L2"
  run_level "L3"
  calculate_break_even

  log "phase2 completed"
  log "summary: ${SUMMARY_TSV}"
  log "break-even: ${BREAK_EVEN_TSV}"
  log "metadata: ${META_TXT}"
}

main "$@"
