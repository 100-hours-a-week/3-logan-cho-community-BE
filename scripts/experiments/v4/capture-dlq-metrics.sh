#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws
require_cmd python3

SCENARIO="${SCENARIO:?SCENARIO is required}"
RUN_LABEL="${RUN_LABEL:?RUN_LABEL is required}"
DLQ_URL="$(optional_tf_output dlq_url)"

if [[ -z "${DLQ_URL}" ]]; then
  printf 'dlq_url is missing\n' >&2
  exit 1
fi

OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v4-idempotent/metrics"
OUT_PATH="${OUT_DIR}/dlq-${SCENARIO}-${RUN_LABEL}.json"
mkdir -p "${OUT_DIR}"

python3 - "${DLQ_URL}" "${OUT_PATH}" <<'PY'
import json
import subprocess
import sys

dlq_url, out_path = sys.argv[1], sys.argv[2]
payload = json.loads(subprocess.check_output([
    "aws", "sqs", "get-queue-attributes",
    "--queue-url", dlq_url,
    "--attribute-names", "ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible",
    "--output", "json",
], text=True))
attrs = payload.get("Attributes", {})
result = {
    "dlqApproximateMessageCount": int(attrs.get("ApproximateNumberOfMessages", "0")),
    "dlqInFlightCount": int(attrs.get("ApproximateNumberOfMessagesNotVisible", "0")),
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
PY

printf '%s\n' "${OUT_PATH}"
