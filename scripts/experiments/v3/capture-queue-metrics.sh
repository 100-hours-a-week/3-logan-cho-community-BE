#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws
require_cmd python3

SCENARIO="${SCENARIO:?SCENARIO is required}"
RUN_LABEL="${RUN_LABEL:?RUN_LABEL is required}"
QUEUE_URL="$(optional_tf_output sqs_queue_url)"

if [[ -z "${QUEUE_URL}" ]]; then
  printf 'sqs_queue_url is missing\n' >&2
  exit 1
fi

QUEUE_NAME="${QUEUE_URL##*/}"
OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v3-outbox/metrics"
OUT_PATH="${OUT_DIR}/queue-${SCENARIO}-${RUN_LABEL}.json"
mkdir -p "${OUT_DIR}"

python3 - "${QUEUE_NAME}" "${OUT_PATH}" <<'PY'
import datetime as dt
import json
import subprocess
import sys

queue_name, out_path = sys.argv[1], sys.argv[2]
end = dt.datetime.utcnow()
start = end - dt.timedelta(minutes=5)

cmd = [
    "aws", "cloudwatch", "get-metric-statistics",
    "--namespace", "AWS/SQS",
    "--metric-name", "ApproximateAgeOfOldestMessage",
    "--dimensions", f"Name=QueueName,Value={queue_name}",
    "--statistics", "Maximum", "Average",
    "--start-time", start.isoformat() + "Z",
    "--end-time", end.isoformat() + "Z",
    "--period", "60",
    "--output", "json",
]
payload = json.loads(subprocess.check_output(cmd, text=True))
points = payload.get("Datapoints", [])
maximum = max((item.get("Maximum", 0.0) for item in points), default=0.0)
average = sum((item.get("Average", 0.0) for item in points), 0.0) / len(points) if points else 0.0

with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "queueName": queue_name,
            "sampleCount": len(points),
            "oldestAgeMaxSeconds": maximum,
            "oldestAgeAvgSeconds": average,
        },
        handle,
        ensure_ascii=False,
        indent=2,
    )
PY

printf '%s\n' "${OUT_PATH}"
