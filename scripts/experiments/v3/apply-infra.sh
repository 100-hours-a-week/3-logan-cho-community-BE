#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd terraform

LAMBDA_PACKAGE_PATH="$("${PROJECT_ROOT}/scripts/experiments/v2/build-lambda-package.sh")"
CALLBACK_SECRET="$(ensure_callback_secret)"

terraform -chdir="${TERRAFORM_EXPERIMENT_DIR}" apply -auto-approve \
  -var-file=versions/v3.tfvars \
  -var="lambda_package_path=${LAMBDA_PACKAGE_PATH}" \
  -var='lambda_handler=image_processor.handler' \
  -var='lambda_runtime=python3.12' \
  -var='lambda_reserved_concurrency=-1' \
  -var="lambda_environment={IMAGE_PIPELINE_CALLBACK_SECRET=\"${CALLBACK_SECRET}\"}"

log "v3 infrastructure applied"
