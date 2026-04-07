#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd python3
require_cmd timeout

APP_URL="${APP_URL:-$(app_base_url)}"
APP_HOST="${APP_SSH_HOST_OVERRIDE:-$(app_ssh_host)}"
QUEUE_URL="$(optional_tf_output sqs_queue_url)"
BUCKET="$(bucket_name)"
OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v4-idempotent/probes"
OUT_PATH="${OUT_DIR}/duplicate-delivery.json"
IMAGE_PATH="${IMAGE_PATH:-${PROJECT_ROOT}/docs/images/write-post.png}"

if [[ -z "${QUEUE_URL}" ]]; then
  printf 'sqs_queue_url is missing. apply v4 terraform first.\n' >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
access_token="$(APP_URL="${APP_URL}" "${PROJECT_ROOT}/scripts/experiments/v1/bootstrap-access-token.sh")"

python3 - "${APP_URL}" "${access_token}" "${IMAGE_PATH}" > /tmp/v4-duplicate-post.json <<'PY'
import json
import sys
import urllib.request

base_url, token, image_path = sys.argv[1:4]
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

def request(method, path, payload=None, content_type="application/json"):
    data = payload
    req = urllib.request.Request(f"{base_url}{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")

presign_body = json.dumps({
    "files": [{"fileName": "duplicate-probe.png", "mimeType": "image/png"}]
}).encode()
presign_res = json.loads(request("POST", "/api/posts/images/presigned-url", presign_body))
presigned_url = presign_res["data"]["urls"][0]["presignedUrl"]
object_key = presign_res["data"]["urls"][0]["objectKey"]

with open(image_path, "rb") as handle:
    upload_req = urllib.request.Request(presigned_url, data=handle.read(), method="PUT")
    upload_req.add_header("Content-Type", "image/png")
    with urllib.request.urlopen(upload_req, timeout=30):
        pass

create_body = json.dumps({
    "title": "v4 duplicate probe",
    "content": "duplicate delivery probe",
    "imageObjectKeys": [object_key],
}).encode()
create_res = json.loads(request("POST", "/api/posts", create_body))
print(json.dumps({"postId": create_res["data"]["postId"]}))
PY

post_id="$(python3 - <<'PY'
import json
print(json.load(open('/tmp/v4-duplicate-post.json'))['postId'])
PY
)"

json_payload="$(
  python3 - "${APP_HOST}" "${post_id}" "${BUCKET}" "${APP_URL}" <<'PY'
import json
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
  tempImageKeys: post.tempImageKeys,
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

python3 - "${APP_URL}" "${access_token}" "${post_id}" <<'PY'
import json
import sys
import time
import urllib.request

base_url, token, post_id = sys.argv[1:4]
for _ in range(60):
    req = urllib.request.Request(f"{base_url}/api/posts/{post_id}")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if payload["data"]["imageStatus"] == "COMPLETED":
        sys.exit(0)
    time.sleep(2)
raise SystemExit("post did not complete before duplicate replay")
PY

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
for _ in range(2):
    subprocess.check_call(base_cmd + [remote], timeout=20)
PY

python3 - "${APP_HOST}" "${post_id}" "${OUT_PATH}" <<'PY'
import json
import subprocess
import sys
import time

app_host, post_id, out_path = sys.argv[1:4]
base_cmd = [
    "ssh", "-i", str(__import__("pathlib").Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={__import__('pathlib').Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{app_host}",
]
script = """sudo docker exec mongo mongosh 'mongodb://127.0.0.1:27017/millions?replicaSet=rs0&directConnection=true' --quiet --eval '
const dbx = db.getSiblingDB("millions");
const post = dbx.posts.findOne({_id: "%s"});
const processed = dbx.image_job_processed.findOne({postId: "%s"});
print(JSON.stringify({
  imageStatus: post ? post.imageStatus : null,
  processedJobCount: dbx.image_job_processed.countDocuments({postId: "%s"}),
  duplicateIgnoredCount: processed ? (processed.duplicateIgnoredCount || 0) : 0,
  duplicateSideEffectCount: processed ? Math.max((processed.sideEffectApplyCount || 0) - 1, 0) : 0
}));
'""" % (post_id, post_id, post_id)
for _ in range(30):
    try:
        payload = subprocess.check_output(base_cmd + [script], text=True, timeout=20)
        result = json.loads(payload)
        if result.get("duplicateIgnoredCount", 0) >= 2:
            with open(out_path, "w", encoding="utf-8") as handle:
                json.dump(result, handle, ensure_ascii=False, indent=2)
            print(out_path)
            sys.exit(0)
    except Exception:
        pass
    time.sleep(2)
raise SystemExit("duplicate replay probe did not converge")
PY
