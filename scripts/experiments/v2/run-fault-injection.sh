#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

log "applying v2 infrastructure"
"${SCRIPT_DIR}/apply-infra.sh"

log "bootstrapping SSH access"
"${PROJECT_ROOT}/scripts/experiments/bootstrap-ssh-access.sh"

log "running V2 save/publish gap probe"
"${SCRIPT_DIR}/probe-save-publish-gap.sh"

log "running V2 duplicate callback probe"
"${SCRIPT_DIR}/probe-duplicate-callback.sh"

log "running V2 poison message probe"
"${SCRIPT_DIR}/probe-poison-message.sh"

log "V2 fault injection probes completed"
