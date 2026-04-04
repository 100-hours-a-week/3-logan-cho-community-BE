#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws

QUEUE_URL="$(optional_tf_output sqs_queue_url)"
if [[ -n "${QUEUE_URL}" ]]; then
  purge_ok=0
  for _ in $(seq 1 12); do
    if aws sqs purge-queue --queue-url "${QUEUE_URL}" >/dev/null 2>&1; then
      purge_ok=1
      break
    fi
    sleep 5
  done
  if [[ "${purge_ok}" -ne 1 ]]; then
    printf 'failed to purge SQS queue within retry window: %s\n' "${QUEUE_URL}" >&2
    exit 1
  fi
  log "purged SQS queue"
fi

"${PROJECT_ROOT}/scripts/experiments/v1/reset-state.sh"
