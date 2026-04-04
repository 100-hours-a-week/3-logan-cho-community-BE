#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

QUEUE_URL="$(optional_tf_output sqs_queue_url)"
if [[ -z "${QUEUE_URL}" ]]; then
  printf 'sqs_queue_url is missing. apply v2 terraform first.\n' >&2
  exit 1
fi

export IMAGE_PIPELINE_ASYNC_ENABLED=true
export IMAGE_PIPELINE_QUEUE_URL="${QUEUE_URL}"
export IMAGE_PIPELINE_CALLBACK_BASE_URL="http://$(app_public_ip):8080"
export IMAGE_PIPELINE_CALLBACK_SECRET="$(ensure_callback_secret)"

"${PROJECT_ROOT}/scripts/experiments/v1/deploy-app.sh"
