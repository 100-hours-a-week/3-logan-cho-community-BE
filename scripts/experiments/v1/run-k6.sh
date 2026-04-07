#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd scp
require_cmd ssh

SCENARIO="${SCENARIO:-smoke}"
RUN_LABEL="${RUN_LABEL:-}"
APP_URL="${APP_URL:-$(app_base_url)}"
ACCESS_TOKEN="${ACCESS_TOKEN:-}"
K6_HOST="${K6_SSH_HOST_OVERRIDE:-$(k6_ssh_host)}"
IMAGE_PATH="${IMAGE_PATH:-${PROJECT_ROOT}/docs/images/write-post.png}"
REMOTE_DIR="/opt/image-pipeline-k6"
FILE_PREFIX="${SCENARIO}"

if [[ -n "${RUN_LABEL}" ]]; then
  FILE_PREFIX="${SCENARIO}-${RUN_LABEL}"
fi

if [[ -z "${ACCESS_TOKEN}" ]]; then
  printf 'ACCESS_TOKEN is required\n' >&2
  exit 1
fi

ensure_file "${IMAGE_PATH}"
ensure_file "${PROJECT_ROOT}/test/k6-script/image-pipeline-v1.js"

ssh_run "${K6_HOST}" "sudo mkdir -p ${REMOTE_DIR} && sudo chown -R $(ssh_user):$(ssh_user) ${REMOTE_DIR}"
scp_to "${PROJECT_ROOT}/test/k6-script/image-pipeline-v1.js" "${K6_HOST}" "${REMOTE_DIR}/image-pipeline-v1.js"
scp_to "${IMAGE_PATH}" "${K6_HOST}" "${REMOTE_DIR}/sample-image"

ssh_run "${K6_HOST}" "
set -euo pipefail
if ! command -v k6 >/dev/null 2>&1; then
  sudo dnf install -y https://dl.k6.io/rpm/repo.rpm
  sudo dnf install -y k6
fi
cd ${REMOTE_DIR}
BASE_URL='${APP_URL}' ACCESS_TOKEN='${ACCESS_TOKEN}' IMAGE_PATH='${REMOTE_DIR}/sample-image' SCENARIO='${SCENARIO}' \
  k6 run ${REMOTE_DIR}/image-pipeline-v1.js --summary-export ${REMOTE_DIR}/summary.json > ${REMOTE_DIR}/stdout.log 2>&1
tail -n 120 ${REMOTE_DIR}/stdout.log
"

mkdir -p "${PROJECT_ROOT}/docs/experiments/results/exp-v1-sync/k6"
scp -i "$(ssh_key_path)" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
  -o ConnectTimeout=10 \
  "$(ssh_user)@${K6_HOST}:${REMOTE_DIR}/summary.json" \
  "${PROJECT_ROOT}/docs/experiments/results/exp-v1-sync/k6/${FILE_PREFIX}-summary.json" >/dev/null
scp -i "$(ssh_key_path)" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
  -o ConnectTimeout=10 \
  "$(ssh_user)@${K6_HOST}:${REMOTE_DIR}/stdout.log" \
  "${PROJECT_ROOT}/docs/experiments/results/exp-v1-sync/k6/${FILE_PREFIX}-stdout.log" >/dev/null

log "k6 result saved under docs/experiments/results/exp-v1-sync/k6/"
