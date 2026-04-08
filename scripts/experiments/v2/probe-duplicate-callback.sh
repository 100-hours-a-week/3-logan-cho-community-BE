#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd python3

APP_URL="${APP_URL:-$(app_base_url)}"
DB_HOST="${DB_HOST_OVERRIDE:-$(db_ssh_host)}"
OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v2-async/probes"
OUT_PATH="${OUT_DIR}/duplicate-callback-multi-node.json"
IMAGE_PATH="${IMAGE_PATH:-${PROJECT_ROOT}/docs/images/write-post.png}"
CALLBACK_SECRET="$(ensure_callback_secret)"

mkdir -p "${OUT_DIR}"
"${SCRIPT_DIR}/reset-state.sh" >/dev/null
"${SCRIPT_DIR}/deploy-app.sh" >/dev/null

access_token="$(APP_URL="${APP_URL}" "${PROJECT_ROOT}/scripts/experiments/v1/bootstrap-access-token.sh")"

python3 - "${APP_URL}" "${access_token}" "${IMAGE_PATH}" > /tmp/v2-duplicate-post.json <<'PY'
import json
import sys
import time
import urllib.request

base_url, token, image_path = sys.argv[1:4]
title = f"v2 duplicate callback probe {int(time.time())}"

def request(method, path, payload=None, content_type="application/json"):
    req = urllib.request.Request(f"{base_url}{path}", data=payload, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status, resp.read().decode("utf-8")

presign_body = json.dumps({"files": [{"fileName": "duplicate-callback.png", "mimeType": "image/png"}]}).encode()
_, body = request("POST", "/api/posts/images/presigned-url", presign_body)
presign_res = json.loads(body)
presigned_url = presign_res["data"]["urls"][0]["presignedUrl"]
object_key = presign_res["data"]["urls"][0]["objectKey"]
with open(image_path, "rb") as handle:
    upload_req = urllib.request.Request(presigned_url, data=handle.read(), method="PUT")
    upload_req.add_header("Content-Type", "image/png")
    with urllib.request.urlopen(upload_req, timeout=30):
        pass
create_body = json.dumps({
    "title": title,
    "content": "v2 duplicate callback probe",
    "imageObjectKeys": [object_key],
}).encode()
_, body = request("POST", "/api/posts", create_body)
payload = json.loads(body)
print(json.dumps({"postId": payload["data"]["postId"], "title": title}))
PY

post_id="$(python3 - <<'PY'
import json
print(json.load(open('/tmp/v2-duplicate-post.json', encoding='utf-8'))['postId'])
PY
)"

python3 - "${APP_URL}" "${access_token}" "${post_id}" <<'PY'
import json
import sys
import time
import urllib.request

base_url, token, post_id = sys.argv[1:4]
for _ in range(90):
    req = urllib.request.Request(f"{base_url}/api/posts/{post_id}")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if payload["data"]["imageStatus"] == "COMPLETED":
        sys.exit(0)
    time.sleep(2)
raise SystemExit("post did not complete in time")
PY

python3 - "${DB_HOST}" "${post_id}" > /tmp/v2-duplicate-payload.json <<'PY'
import json
import pathlib
import subprocess
import sys

db_host, post_id = sys.argv[1:3]
base_cmd = [
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{db_host}",
]
script = """sudo docker exec mongo mongosh 'mongodb://127.0.0.1:27017/millions?replicaSet=rs0&directConnection=true' --quiet --eval '
const post = db.getSiblingDB("millions").posts.findOne({_id: "%s"});
print(JSON.stringify({
  postId: post._id,
  imageJobId: post.imageJobId,
  finalImageKeys: post.finalImageKeys,
  thumbnailKeys: post.thumbnailKeys,
  completedAt: post.completedAt
}));
'""" % post_id
print(subprocess.check_output(base_cmd + [script], text=True, timeout=20).strip())
PY

mapfile -t app_hosts < <(app_public_ips)
if [[ "${#app_hosts[@]}" -eq 0 ]]; then
  printf 'no app hosts found\n' >&2
  exit 1
fi
if [[ "${#app_hosts[@]}" -eq 1 ]]; then
  app_hosts+=("${app_hosts[0]}")
fi

python3 - "${CALLBACK_SECRET}" "${post_id}" "${app_hosts[0]}" "${app_hosts[1]}" > /tmp/v2-duplicate-result.json <<'PY'
import json
import pathlib
import subprocess
import sys

secret, post_id, host1, host2 = sys.argv[1:5]
payload = json.load(open('/tmp/v2-duplicate-payload.json', encoding='utf-8'))
body = json.dumps({
    "imageJobId": payload["imageJobId"],
    "imageStatus": "COMPLETED",
    "finalImageKeys": payload["finalImageKeys"],
    "thumbnailKeys": payload["thumbnailKeys"],
    "failureReason": None,
})
base = [
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
]

def send(host):
    remote = (
        "curl -s -o /tmp/dup.out -w '%{http_code}' "
        "-X POST "
        "-H 'Content-Type: application/json' "
        f"-H 'X-Experiment-Callback-Secret: {secret}' "
        f"--data {json.dumps(body)} "
        f"http://127.0.0.1:8080/api/posts/internal/image-jobs/{post_id}"
    )
    return subprocess.check_output(base + [f"ec2-user@{host}", remote], text=True, timeout=20).strip()

s1 = send(host1)
s2 = send(host2)
print(json.dumps({
    "firstNode": host1,
    "secondNode": host2,
    "firstStatus": int(s1),
    "secondStatus": int(s2),
    "completedAtBefore": payload["completedAt"],
}))
PY

sleep 2

python3 - "${DB_HOST}" "${post_id}" "${OUT_PATH}" <<'PY'
import json
import pathlib
import subprocess
import sys

db_host, post_id, out_path = sys.argv[1:4]
before = json.load(open('/tmp/v2-duplicate-result.json', encoding='utf-8'))
base_cmd = [
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{db_host}",
]
script = """sudo docker exec mongo mongosh 'mongodb://127.0.0.1:27017/millions?replicaSet=rs0&directConnection=true' --quiet --eval '
const post = db.getSiblingDB("millions").posts.findOne({_id: "%s"});
print(JSON.stringify({
  imageStatus: post.imageStatus,
  completedAt: post.completedAt
}));
'""" % post_id
after = json.loads(subprocess.check_output(base_cmd + [script], text=True, timeout=20).strip())
result = {
    "probe": "duplicate_callback_multi_node",
    "firstNode": before["firstNode"],
    "secondNode": before["secondNode"],
    "firstStatus": before["firstStatus"],
    "secondStatus": before["secondStatus"],
    "completedAtBefore": before["completedAtBefore"],
    "completedAtAfter": after["completedAt"],
    "imageStatus": after["imageStatus"],
    "duplicateAcceptedByBothNodes": before["firstStatus"] == 200 and before["secondStatus"] == 200,
    "sideEffectReapplied": before["completedAtBefore"] != after["completedAt"],
    "interpretation": "without idempotency guard, duplicate callback is accepted on multiple app nodes and re-applies completion side effects"
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
print(out_path)
PY
