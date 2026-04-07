#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

QUEUE_URL="$(optional_tf_output sqs_queue_url)"
if [[ -z "${QUEUE_URL}" ]]; then
  printf 'sqs_queue_url is missing. apply v4 terraform first.\n' >&2
  exit 1
fi

export IMAGE_PIPELINE_ASYNC_ENABLED=true
export IMAGE_PIPELINE_QUEUE_URL="${QUEUE_URL}"
export IMAGE_PIPELINE_CALLBACK_BASE_URL="$(app_base_url)"
export IMAGE_PIPELINE_CALLBACK_SECRET="$(ensure_callback_secret)"
export IMAGE_PIPELINE_OUTBOX_ENABLED=true
export IMAGE_PIPELINE_OUTBOX_RELAY_ENABLED=true
export IMAGE_PIPELINE_OUTBOX_RELAY_FIXED_DELAY_MS="${IMAGE_PIPELINE_OUTBOX_RELAY_FIXED_DELAY_MS:-1000}"
export IMAGE_PIPELINE_OUTBOX_RELAY_BATCH_SIZE="${IMAGE_PIPELINE_OUTBOX_RELAY_BATCH_SIZE:-20}"
export IMAGE_PIPELINE_IDEMPOTENCY_ENABLED=true

"${PROJECT_ROOT}/scripts/experiments/v1/deploy-app.sh"
