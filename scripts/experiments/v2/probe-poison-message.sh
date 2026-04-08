#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd python3

QUEUE_URL="$(optional_tf_output sqs_queue_url)"
LAMBDA_FUNCTION_NAME="$(optional_tf_output lambda_function_name)"
APP_URL="${APP_URL:-$(app_base_url)}"
APP_HOST="${APP_SSH_HOST_OVERRIDE:-$(app_ssh_host)}"
OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v2-async/probes"
OUT_PATH="${OUT_DIR}/poison-message-no-dlq.json"

if [[ -z "${QUEUE_URL}" ]]; then
  printf 'sqs_queue_url is missing. apply v2 terraform first.\n' >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
"${SCRIPT_DIR}/reset-state.sh" >/dev/null
"${SCRIPT_DIR}/deploy-app.sh" >/dev/null

python3 - "${APP_URL}" "${QUEUE_URL}" "${OUT_PATH}" "${APP_HOST}" <<'PY'
import json
import pathlib
import subprocess
import sys
import time

app_url, queue_url, out_path, app_host = sys.argv[1:5]
payload = json.dumps({
    "imageJobId": "fault-poison-job",
    "postId": "fault-poison-post",
    "bucket": "community-be-image-experiments-160885253413-apne2",
    "tempImageKeys": ["experiments/temp/missing-poison-key"],
    "callbackUrl": f"{app_url}/api/posts/internal/image-jobs/fault-poison-post",
    "requestedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
})

subprocess.check_call([
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{app_host}",
    f"aws sqs send-message --queue-url {queue_url!r} --message-body {payload!r} >/dev/null",
], stdout=subprocess.DEVNULL)

not_visible_seen = False
visible_seen = False
base_cmd = [
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{app_host}",
]

samples = []
for i in range(6):
    attrs = json.loads(subprocess.check_output(base_cmd + [
        (
            "aws sqs get-queue-attributes "
            f"--queue-url {queue_url!r} "
            "--attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible "
            "--output json"
        )
    ], text=True))
    visible = int(attrs.get("Attributes", {}).get("ApproximateNumberOfMessages", "0"))
    not_visible = int(attrs.get("Attributes", {}).get("ApproximateNumberOfMessagesNotVisible", "0"))
    visible_seen = visible_seen or visible > 0
    not_visible_seen = not_visible_seen or not_visible > 0
    samples.append({"t": i * 5, "visible": visible, "notVisible": not_visible})
    time.sleep(5)

result = {
    "probe": "poison_message_without_dlq",
    "dlqConfigured": False,
    "queueSamples": samples,
    "queueVisibleSeen": visible_seen,
    "queueNotVisibleSeen": not_visible_seen,
    "interpretation": "without DLQ, poison message stays on the main queue retry path instead of being quarantined",
}

with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)

print(out_path)
PY
