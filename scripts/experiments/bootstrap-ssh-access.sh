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

for instance_id in "$(app_instance_id)" "$(k6_instance_id)"; do
  command_id="$(ssm_send "${instance_id}" "install experiment ssh key" "[\"mkdir -p ~/.ssh\",\"touch ~/.ssh/authorized_keys\",\"grep -qxF '${PUB_KEY_CONTENT}' ~/.ssh/authorized_keys || echo '${PUB_KEY_CONTENT}' >> ~/.ssh/authorized_keys\",\"chmod 700 ~/.ssh\",\"chmod 600 ~/.ssh/authorized_keys\"]")"
  status="$(ssm_wait "${command_id}")"
  ssm_output "${command_id}"
  if [[ "${status}" != "Success" ]]; then
    printf 'failed to install ssh key on %s: %s\n' "${instance_id}" "${status}" >&2
    exit 1
  fi
done

log "ssh access bootstrapped for app and k6 instances"
