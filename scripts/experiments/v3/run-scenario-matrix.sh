#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

SCENARIOS=(medium_10rps heavy_20rps burst_5_to_30)
REPEATS="${REPEATS:-3}"

for scenario in "${SCENARIOS[@]}"; do
  for repeat in $(seq 1 "${REPEATS}"); do
    run_label="run${repeat}"
    label="${scenario}-${run_label}"
    log "starting ${label}"
    "${SCRIPT_DIR}/reset-state.sh"
    access_token="$("${PROJECT_ROOT}/scripts/experiments/v1/bootstrap-access-token.sh")"
    ACCESS_TOKEN="${access_token}" SCENARIO="${scenario}" RUN_LABEL="${run_label}" "${SCRIPT_DIR}/run-k6.sh"
    SCENARIO="${scenario}" RUN_LABEL="${run_label}" "${SCRIPT_DIR}/capture-queue-metrics.sh"
    SCENARIO="${scenario}" RUN_LABEL="${run_label}" "${SCRIPT_DIR}/capture-outbox-metrics.sh"
    log "completed ${label}"
  done
done

"${SCRIPT_DIR}/generate-summary.sh"
