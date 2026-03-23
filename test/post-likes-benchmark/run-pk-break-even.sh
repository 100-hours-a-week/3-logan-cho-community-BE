#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="${SCRIPT_DIR}/lib/common.sh"

ROW_COUNTS="${ROW_COUNTS:-100000 300000 1000000}"
DIST_LIST="${DIST_LIST:-uniform skew}"
LEVELS="${LEVELS:-L0 L1 L2 L3 L4 L5}"
POST_ID_BYTES="${POST_ID_BYTES:-12}"
PROBE_COUNT="${PROBE_COUNT:-50000}"
RUNS="${RUNS:-2}"

RESULT_DIR="${SCRIPT_DIR}/results/pk_break_even_12b"
META_TXT="${RESULT_DIR}/metadata.txt"
SIZE_MATRIX_TSV="${RESULT_DIR}/size_matrix.tsv"
DENSITY_MATRIX_TSV="${RESULT_DIR}/density_matrix.tsv"
IO_MATRIX_TSV="${RESULT_DIR}/io_matrix.tsv"
BREAK_EVEN_SECONDARY_TSV="${RESULT_DIR}/break_even_by_secondary.tsv"
BREAK_EVEN_ROW_TSV="${RESULT_DIR}/break_even_by_row_count.tsv"

source "${LIB_FILE}"

require_cmd docker
require_cmd mysql
require_cmd awk

append_size_row() {
  local dist="$1"
  local level="$2"
  local case_id="$3"
  local size_row table_stats_file data_mb index_mb clustered_pages other_pages clustered_mb other_mb primary_rpp other_rpp

  table_stats_file="${RESULT_DIR}/${dist}_${level}_${case_id}_table_stats.tsv"
  collect_table_stats "${table_stats_file}"
  size_row="$(table_size_row)"
  data_mb="$(echo "${size_row}" | awk -F'\t' '{print $1}')"
  index_mb="$(echo "${size_row}" | awk -F'\t' '{print $2}')"
  clustered_pages="$(awk 'NR == 2 { print $3 }' "${table_stats_file}")"
  other_pages="$(awk 'NR == 2 { print $4 }' "${table_stats_file}")"
  clustered_mb="$(awk 'NR == 2 { print $5 }' "${table_stats_file}")"
  other_mb="$(awk 'NR == 2 { print $6 }' "${table_stats_file}")"
  primary_rpp="$(awk 'NR == 2 { print $7 }' "${table_stats_file}")"
  other_rpp="$(awk 'NR == 2 { print $8 }' "${table_stats_file}")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${ROW_COUNT}" "${dist}" "${level}" "${case_id}" \
    "${data_mb}" "${index_mb}" "${clustered_pages}" "${other_pages}" "${clustered_mb}" "${other_mb}" >> "${SIZE_MATRIX_TSV}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${ROW_COUNT}" "${dist}" "${level}" "${case_id}" \
    "${clustered_pages}" "${other_pages}" "${primary_rpp}" "${other_rpp}" >> "${DENSITY_MATRIX_TSV}"
}

append_io_rows() {
  local dist="$1"
  local level="$2"
  local case_id="$3"
  local run_idx result

  for run_idx in $(seq 1 "${RUNS}"); do
    result="$(run_exact_lookup_probe)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${ROW_COUNT}" "${dist}" "${level}" "${case_id}" "${run_idx}" "${result}" >> "${IO_MATRIX_TSV}"
  done
}

run_case() {
  local dist="$1"
  local level="$2"
  local case_id="$3"

  DIST_MODE="${dist}"
  init_dataset
  create_case_table "${case_id}" "${level}"
  load_case_data "${case_id}"
  append_size_row "${dist}" "${level}" "${case_id}"
  append_io_rows "${dist}" "${level}" "${case_id}"
}

build_break_even_secondary() {
  awk -F'\t' '
NR == 1 { next }
{
  key = $1 FS $2 FS $3 FS $4;
  data[key] = $0;
}
END {
  print "row_count\tdist\tbreak_even_level\tfirst_non_positive_delta_mb";
  split("100000 300000 1000000", rows, " ");
  split("uniform skew", dists, " ");
  split("L0 L1 L2 L3 L4 L5", levels, " ");

  for (ri in rows) {
    row = rows[ri];
    for (di in dists) {
      dist = dists[di];
      found = 0;
      for (li = 1; li <= 6; li++) {
        lvl = levels[li];
        kc = row FS dist FS lvl FS "C";
        ks = row FS dist FS lvl FS "S";
        if (!(kc in data) || !(ks in data)) continue;
        split(data[kc], c, FS);
        split(data[ks], s, FS);
        c_total = c[5] + c[6];
        s_total = s[5] + s[6];
        delta = s_total - c_total;
        if (!found && delta <= 0) {
          printf "%s\t%s\t%s\t%.3f\n", row, dist, lvl, delta;
          found = 1;
        }
      }
      if (!found) {
        printf "%s\t%s\t%s\t%s\n", row, dist, "none", "positive";
      }
    }
  }
}' "${SIZE_MATRIX_TSV}" > "${BREAK_EVEN_SECONDARY_TSV}"
}

build_break_even_row() {
  awk -F'\t' '
NR == 1 { next }
{
  key = $2 FS $3 FS $4;
  row[$1] = 1;
  data[$1 FS key] = $0;
}
END {
  print "dist\tlevel\tbreak_even_row_count\tfirst_non_positive_delta_mb";
  split("uniform skew", dists, " ");
  split("L0 L1 L2 L3 L4 L5", levels, " ");
  split("100000 300000 1000000", rows, " ");

  for (di in dists) {
    dist = dists[di];
    for (li = 1; li <= 6; li++) {
      lvl = levels[li];
      found = 0;
      for (ri = 1; ri <= 3; ri++) {
        rc = rows[ri];
        kc = rc FS dist FS lvl FS "C";
        ks = rc FS dist FS lvl FS "S";
        if (!(kc in data) || !(ks in data)) continue;
        split(data[kc], c, FS);
        split(data[ks], s, FS);
        c_total = c[5] + c[6];
        s_total = s[5] + s[6];
        delta = s_total - c_total;
        if (!found && delta <= 0) {
          printf "%s\t%s\t%s\t%.3f\n", dist, lvl, rc, delta;
          found = 1;
        }
      }
      if (!found) {
        printf "%s\t%s\t%s\t%s\n", dist, lvl, "none", "positive";
      }
    }
  }
}' "${SIZE_MATRIX_TSV}" > "${BREAK_EVEN_ROW_TSV}"
}

main() {
  mkdir -p "${RESULT_DIR}"

  cat > "${META_TXT}" <<EOF
run_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
row_counts=${ROW_COUNTS}
dist_list=${DIST_LIST}
levels=${LEVELS}
post_id_bytes=${POST_ID_BYTES}
probe_count=${PROBE_COUNT}
runs=${RUNS}
post_id_start=${POST_ID_START}
member_id_start=${MEMBER_ID_START}
post_like_id_start=${POST_LIKE_ID_START}
buffer_pool_mb=${BUFFER_POOL_MB}
mysql_memory_limit=${MYSQL_MEMORY_LIMIT}
mysql_cpu_limit=${MYSQL_CPU_LIMIT}
EOF

  printf 'row_count\tdist\tlevel\tcase\tdata_mb\tindex_mb\tclustered_pages\tother_pages\tclustered_mb\tother_mb\n' > "${SIZE_MATRIX_TSV}"
  printf 'row_count\tdist\tlevel\tcase\tclustered_pages\tother_pages\tprimary_rows_per_page\tother_rows_per_page_total\n' > "${DENSITY_MATRIX_TSV}"
  printf 'row_count\tdist\tlevel\tcase\trun\telapsed_us\tbp_reads_delta\tbp_read_requests_delta\tdata_reads_delta\trows_read_delta\tpages_written_delta\tdata_writes_delta\n' > "${IO_MATRIX_TSV}"

  compose_up_mysql

  local row_count dist level
  for row_count in ${ROW_COUNTS}; do
    ROW_COUNT="${row_count}"
    for dist in ${DIST_LIST}; do
      for level in ${LEVELS}; do
        run_case "${dist}" "${level}" "C"
        run_case "${dist}" "${level}" "S"
      done
    done
  done

  build_break_even_secondary
  build_break_even_row

  log "pk break-even completed"
  log "size matrix: ${SIZE_MATRIX_TSV}"
  log "density matrix: ${DENSITY_MATRIX_TSV}"
  log "io matrix: ${IO_MATRIX_TSV}"
}

main "$@"
