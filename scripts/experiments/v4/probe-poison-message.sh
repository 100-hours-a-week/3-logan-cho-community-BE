#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd python3
require_cmd timeout

APP_URL="${APP_URL:-http://$(app_public_ip):8080}"
APP_HOST="${APP_SSH_HOST_OVERRIDE:-$(app_ssh_host)}"
QUEUE_URL="$(optional_tf_output sqs_queue_url)"
DLQ_URL="$(optional_tf_output dlq_url)"
BUCKET="$(bucket_name)"
OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v4-idempotent/probes"
OUT_PATH="${OUT_DIR}/poison-message.json"

if [[ -z "${QUEUE_URL}" || -z "${DLQ_URL}" ]]; then
  printf 'queue or dlq url is missing. apply v4 terraform first.\n' >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
access_token="$(APP_URL="${APP_URL}" "${PROJECT_ROOT}/scripts/experiments/v1/bootstrap-access-token.sh")"

python3 - "${APP_URL}" "${access_token}" "${PROJECT_ROOT}/docs/images/write-post.png" > /tmp/v4-poison-post.json <<'PY'
import json
import sys
import urllib.request

base_url, token, image_path = sys.argv[1:4]
def request(method, path, payload=None, content_type="application/json"):
    req = urllib.request.Request(f"{base_url}{path}", data=payload, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")
presign_body = json.dumps({"files": [{"fileName": "poison-probe.png", "mimeType": "image/png"}]}).encode()
presign = json.loads(request("POST", "/api/posts/images/presigned-url", presign_body))
presigned_url = presign["data"]["urls"][0]["presignedUrl"]
object_key = presign["data"]["urls"][0]["objectKey"]
with open(image_path, "rb") as handle:
    upload_req = urllib.request.Request(presigned_url, data=handle.read(), method="PUT")
    upload_req.add_header("Content-Type", "image/png")
    with urllib.request.urlopen(upload_req, timeout=30):
        pass
create_body = json.dumps({
    "title": "v4 poison probe",
    "content": "poison message probe",
    "imageObjectKeys": [object_key],
}).encode()
create_res = json.loads(request("POST", "/api/posts", create_body))
print(json.dumps({"postId": create_res["data"]["postId"]}))
PY

post_id="$(python3 - <<'PY'
import json
print(json.load(open('/tmp/v4-poison-post.json'))['postId'])
PY
)"

json_payload="$(
  python3 - "${APP_HOST}" "${post_id}" "${BUCKET}" "${APP_URL}" <<'PY'
import pathlib
import subprocess
import sys
import time

app_host, post_id, bucket, app_url = sys.argv[1:5]
base_cmd = [
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{app_host}",
]
script = """sudo docker exec mongo mongosh 'mongodb://127.0.0.1:27017/millions?replicaSet=rs0&directConnection=true' --quiet --eval '
const post = db.getSiblingDB("millions").posts.findOne({_id: "%s"});
if (!post) { quit(2); }
print(JSON.stringify({
  imageJobId: post.imageJobId,
  postId: post._id,
  bucket: "%s",
  tempImageKeys: ["experiments/temp/missing-poison-key"],
  callbackUrl: "%s/api/posts/internal/image-jobs/%s",
  requestedAt: new Date().toISOString()
}));
'""" % (post_id, bucket, app_url, post_id)
for _ in range(20):
    try:
        print(subprocess.check_output(base_cmd + [script], text=True, timeout=20).strip())
        sys.exit(0)
    except Exception:
        time.sleep(1)
raise SystemExit("post payload lookup did not converge")
PY
)"

python3 - "${APP_HOST}" "${QUEUE_URL}" "${json_payload}" <<'PY'
import pathlib
import subprocess
import sys

app_host, queue_url, payload = sys.argv[1:4]
base_cmd = [
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{app_host}",
]
remote = f"aws sqs send-message --queue-url {queue_url!r} --message-body {payload!r} >/dev/null"
subprocess.check_call(base_cmd + [remote], timeout=20)
PY

python3 - "${DLQ_URL}" "${OUT_PATH}" <<'PY'
import json
import subprocess
import sys
import time

dlq_url, out_path = sys.argv[1:3]
for _ in range(45):
    payload = json.loads(subprocess.check_output([
        "aws", "sqs", "get-queue-attributes",
        "--queue-url", dlq_url,
        "--attribute-names", "ApproximateNumberOfMessages",
        "--output", "json",
    ], text=True))
    count = int(payload.get("Attributes", {}).get("ApproximateNumberOfMessages", "0"))
    if count >= 1:
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump({"dlqApproximateMessageCount": count}, handle, ensure_ascii=False, indent=2)
        print(out_path)
        sys.exit(0)
    time.sleep(10)
raise SystemExit("poison message did not reach DLQ in time")
PY
