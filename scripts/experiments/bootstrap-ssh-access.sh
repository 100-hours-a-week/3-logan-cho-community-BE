#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd aws
require_cmd ssh-keygen

KEY_PATH="${EXPERIMENT_SSH_KEY_PATH:-${HOME}/.ssh/experiment_image_pipeline_key}"
PUB_KEY_PATH="${KEY_PATH}.pub"

if [[ ! -f "${KEY_PATH}" ]]; then
  mkdir -p "$(dirname "${KEY_PATH}")"
  ssh-keygen -t ed25519 -N "" -f "${KEY_PATH}" >/dev/null
fi

ensure_file "${PUB_KEY_PATH}"
PUB_KEY_CONTENT="$(cat "${PUB_KEY_PATH}")"

INSTANCE_IDS=()
while IFS= read -r instance_id; do
  [[ -n "${instance_id}" ]] && INSTANCE_IDS+=("${instance_id}")
done < <(app_instance_ids)

db_id="$(db_instance_id)"
if [[ -n "${db_id}" && "${db_id}" != "null" ]]; then
  INSTANCE_IDS+=("${db_id}")
fi

INSTANCE_IDS+=("$(k6_instance_id)")

for instance_id in "${INSTANCE_IDS[@]}"; do
  command_id="$(ssm_send "${instance_id}" "install experiment ssh key" "[\"mkdir -p ~/.ssh\",\"touch ~/.ssh/authorized_keys\",\"grep -qxF '${PUB_KEY_CONTENT}' ~/.ssh/authorized_keys || echo '${PUB_KEY_CONTENT}' >> ~/.ssh/authorized_keys\",\"chmod 700 ~/.ssh\",\"chmod 600 ~/.ssh/authorized_keys\"]")"
  status="$(ssm_wait "${command_id}")"
  ssm_output "${command_id}"
  if [[ "${status}" != "Success" ]]; then
    printf 'failed to install ssh key on %s: %s\n' "${instance_id}" "${status}" >&2
    exit 1
  fi
done

log "ssh access bootstrapped for app, db, and k6 instances"
