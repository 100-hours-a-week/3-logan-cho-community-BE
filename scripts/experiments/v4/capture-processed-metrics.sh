#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd python3
require_cmd timeout

SCENARIO="${SCENARIO:?SCENARIO is required}"
RUN_LABEL="${RUN_LABEL:?RUN_LABEL is required}"
APP_HOST="${APP_SSH_HOST_OVERRIDE:-$(app_ssh_host)}"
OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v4-idempotent/metrics"
OUT_PATH="${OUT_DIR}/processed-${SCENARIO}-${RUN_LABEL}.json"
mkdir -p "${OUT_DIR}"

if ! json_payload="$(
  timeout 20 ssh \
    -i "$(ssh_key_path)" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
    -o ConnectTimeout=10 \
    "$(ssh_user)@${APP_HOST}" "sudo docker exec mongo mongosh 'mongodb://127.0.0.1:27017/millions?replicaSet=rs0&directConnection=true' --quiet --eval '
const dbx = db.getSiblingDB(\"millions\");
const processed = dbx.image_job_processed;
let duplicateIgnoredCount = 0;
let duplicateSideEffectCount = 0;
processed.find({}).forEach(doc => {
  duplicateIgnoredCount += (doc.duplicateIgnoredCount || 0);
  duplicateSideEffectCount += Math.max((doc.sideEffectApplyCount || 0) - 1, 0);
});
print(JSON.stringify({
  totalProcessedJobCount: processed.countDocuments({}),
  duplicateIgnoredCount,
  duplicateSideEffectCount
}));
'"
)"; then
  python3 - "${OUT_PATH}" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"captureStatus": "unavailable"}, handle, ensure_ascii=False, indent=2)
PY
  printf '%s\n' "${OUT_PATH}"
  exit 0
fi

python3 - "${json_payload}" "${OUT_PATH}" <<'PY'
import json
import sys

with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(json.loads(sys.argv[1]), handle, ensure_ascii=False, indent=2)
PY

printf '%s\n' "${OUT_PATH}"
