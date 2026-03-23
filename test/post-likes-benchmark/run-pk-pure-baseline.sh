#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="${SCRIPT_DIR}/lib/common.sh"

ROW_COUNT="${ROW_COUNT:-1000000}"
POST_ID_BYTES="${POST_ID_BYTES:-12}"
PROBE_COUNT="${PROBE_COUNT:-100000}"
DIST_LIST="${DIST_LIST:-uniform skew}"
RUNS="${RUNS:-3}"
LEVEL="${LEVEL:-L0}"

RESULT_DIR="${SCRIPT_DIR}/results/pk_pure_baseline_12b"
META_TXT="${RESULT_DIR}/metadata.txt"
SUMMARY_TSV="${RESULT_DIR}/summary.tsv"
LOOKUP_TSV="${RESULT_DIR}/lookup_probe.tsv"

source "${LIB_FILE}"

require_cmd docker
require_cmd mysql
require_cmd awk

run_lookup_trials() {
  local case_id="$1"
  local dist="$2"
  local explain_file="$3"
  local table_stats_file="$4"
  local size_row avg_ms avg_bp_reads avg_bp_req avg_data_reads avg_rows_read avg_pages_written avg_data_writes

  : > "${LOOKUP_TSV}.tmp"

  local run_idx result
  for run_idx in $(seq 1 "${RUNS}"); do
    result="$(run_exact_lookup_probe)"
    printf '%s\t%s\t%s\t%s\n' "${dist}" "${case_id}" "${run_idx}" "${result}" >> "${LOOKUP_TSV}.tmp"
  done

  avg_ms="$(awk -F'\t' '{s += $4 / 1000.0} END {printf "%.3f", s / NR}' "${LOOKUP_TSV}.tmp")"
  avg_bp_reads="$(awk -F'\t' '{s += $5} END {printf "%.3f", s / NR}' "${LOOKUP_TSV}.tmp")"
  avg_bp_req="$(awk -F'\t' '{s += $6} END {printf "%.3f", s / NR}' "${LOOKUP_TSV}.tmp")"
  avg_data_reads="$(awk -F'\t' '{s += $7} END {printf "%.3f", s / NR}' "${LOOKUP_TSV}.tmp")"
  avg_rows_read="$(awk -F'\t' '{s += $8} END {printf "%.3f", s / NR}' "${LOOKUP_TSV}.tmp")"
  avg_pages_written="$(awk -F'\t' '{s += $9} END {printf "%.3f", s / NR}' "${LOOKUP_TSV}.tmp")"
  avg_data_writes="$(awk -F'\t' '{s += $10} END {printf "%.3f", s / NR}' "${LOOKUP_TSV}.tmp")"

  cat "${LOOKUP_TSV}.tmp" >> "${LOOKUP_TSV}"
  rm -f "${LOOKUP_TSV}.tmp"

  write_single_lookup_explain "${explain_file}"
  collect_table_stats "${table_stats_file}"
  size_row="$(table_size_row)"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${dist}" "${case_id}" "${ROW_COUNT}" "${PROBE_COUNT}" \
    "$(echo "${size_row}" | awk -F'\t' '{print $1}')" \
    "$(echo "${size_row}" | awk -F'\t' '{print $2}')" \
    "$(awk 'NR == 2 { print $3 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $4 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $5 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $6 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $7 }' "${table_stats_file}")" \
    "$(awk 'NR == 2 { print $8 }' "${table_stats_file}")" \
    "${avg_ms}" "${avg_bp_reads}" "${avg_bp_req}" "${avg_data_reads}" "${avg_rows_read}" \
    >> "${SUMMARY_TSV}"
}

run_case_for_dist() {
  local dist="$1"
  local case_id="$2"
  local explain_file table_stats_file

  DIST_MODE="${dist}"
  init_dataset
  create_case_table "${case_id}" "${LEVEL}"
  load_case_data "${case_id}"

  explain_file="${RESULT_DIR}/${dist}_${case_id}_explain_lookup.txt"
  table_stats_file="${RESULT_DIR}/${dist}_${case_id}_table_stats.tsv"
  run_lookup_trials "${case_id}" "${dist}" "${explain_file}" "${table_stats_file}"
}

main() {
  mkdir -p "${RESULT_DIR}"

  cat > "${META_TXT}" <<EOF
run_at_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
row_count=${ROW_COUNT}
post_id_bytes=${POST_ID_BYTES}
probe_count=${PROBE_COUNT}
dist_list=${DIST_LIST}
runs=${RUNS}
level=${LEVEL}
post_id_start=${POST_ID_START}
member_id_start=${MEMBER_ID_START}
post_like_id_start=${POST_LIKE_ID_START}
buffer_pool_mb=${BUFFER_POOL_MB}
mysql_memory_limit=${MYSQL_MEMORY_LIMIT}
mysql_cpu_limit=${MYSQL_CPU_LIMIT}
EOF

  printf 'dist\tcase\trow_count\tprobe_count\tdata_mb\tindex_mb\tclustered_pages\tother_pages\tclustered_mb\tother_mb\tprimary_rows_per_page\tother_rows_per_page_total\tlookup_avg_ms\tlookup_bp_reads_avg\tlookup_bp_read_requests_avg\tlookup_data_reads_avg\tlookup_rows_read_avg\n' > "${SUMMARY_TSV}"
  printf 'dist\tcase\trun\telapsed_us\tbp_reads_delta\tbp_read_requests_delta\tdata_reads_delta\trows_read_delta\tpages_written_delta\tdata_writes_delta\n' > "${LOOKUP_TSV}"

  compose_up_mysql

  local dist
  for dist in ${DIST_LIST}; do
    run_case_for_dist "${dist}" "C"
    run_case_for_dist "${dist}" "S"
  done

  log "pk pure baseline completed"
  log "summary: ${SUMMARY_TSV}"
  log "lookup probe: ${LOOKUP_TSV}"
  log "metadata: ${META_TXT}"
}

main "$@"
