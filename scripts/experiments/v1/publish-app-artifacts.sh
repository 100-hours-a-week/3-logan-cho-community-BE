#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws

BUCKET="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}"
JAR_PATH="${PROJECT_ROOT}/build/libs/kaboocamPostProject-0.0.1-SNAPSHOT.jar"
ENV_PATH="${ENV_SCRIPT_PATH:-/tmp/experiment-app-env.sh}"

ensure_file "${PROJECT_ROOT}/gradlew"
"${PROJECT_ROOT}/gradlew" bootJar >/dev/null
ensure_file "${JAR_PATH}"

S3_BUCKET_NAME_OVERRIDE="${BUCKET}" "${SCRIPT_DIR}/render-app-env.sh" "${ENV_PATH}"
ensure_file "${ENV_PATH}"

if ! aws s3 cp "${JAR_PATH}" "s3://${BUCKET}/artifacts/kaboocamPostProject-0.0.1-SNAPSHOT.jar" >/dev/null 2>&1; then
  upload_to_s3_via_instance_role "${JAR_PATH}" "$(app_ssh_host)" "s3://${BUCKET}/artifacts/kaboocamPostProject-0.0.1-SNAPSHOT.jar"
fi

if ! aws s3 cp "${ENV_PATH}" "s3://${BUCKET}/artifacts/experiment-app-env.sh" >/dev/null 2>&1; then
  upload_to_s3_via_instance_role "${ENV_PATH}" "$(app_ssh_host)" "s3://${BUCKET}/artifacts/experiment-app-env.sh"
fi

log "published app artifacts to s3://${BUCKET}/artifacts/"
