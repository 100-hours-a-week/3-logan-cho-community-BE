#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws

purge_queue() {
  local queue_url="$1"
  local label="$2"
  if [[ -z "${queue_url}" ]]; then
    return 0
  fi

  local purge_ok=0
  for _ in $(seq 1 12); do
    if aws sqs purge-queue --queue-url "${queue_url}" >/dev/null 2>&1; then
      purge_ok=1
      break
    fi
    sleep 5
  done

  if [[ "${purge_ok}" -ne 1 ]]; then
    printf 'failed to purge %s within retry window: %s\n' "${label}" "${queue_url}" >&2
    exit 1
  fi

  log "purged ${label}"
}

purge_queue "$(optional_tf_output sqs_queue_url)" "main SQS queue"
purge_queue "$(optional_tf_output dlq_url)" "DLQ"

"${PROJECT_ROOT}/scripts/experiments/v1/reset-state.sh"
