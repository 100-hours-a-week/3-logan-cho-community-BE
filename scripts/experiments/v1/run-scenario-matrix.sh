#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

SCENARIOS=(medium_10rps heavy_20rps burst_5_to_30)
REPEATS="${REPEATS:-3}"

for scenario in "${SCENARIOS[@]}"; do
  for repeat in $(seq 1 "${REPEATS}"); do
    label="${scenario}-run${repeat}"
    log "starting ${label}"
    "${SCRIPT_DIR}/reset-state.sh"
    access_token="$("${SCRIPT_DIR}/bootstrap-access-token.sh")"
    ACCESS_TOKEN="${access_token}" SCENARIO="${scenario}" RUN_LABEL="run${repeat}" "${SCRIPT_DIR}/run-k6.sh"
    log "completed ${label}"
  done
done

"${SCRIPT_DIR}/generate-summary.sh"
