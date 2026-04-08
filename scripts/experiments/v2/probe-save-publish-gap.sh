#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd python3

APP_URL="${APP_URL:-$(app_base_url)}"
QUEUE_URL="$(optional_tf_output sqs_queue_url)"
DB_HOST="${DB_HOST_OVERRIDE:-$(db_ssh_host)}"
OUT_DIR="${PROJECT_ROOT}/docs/experiments/results/exp-v2-async/probes"
OUT_PATH="${OUT_DIR}/save-publish-gap.json"
IMAGE_PATH="${IMAGE_PATH:-${PROJECT_ROOT}/docs/images/write-post.png}"
FAULT_TITLE_PREFIX="${FAULT_TITLE_PREFIX:-[fault-save-publish]}"

mkdir -p "${OUT_DIR}"

restore_app() {
  unset IMAGE_PIPELINE_FAULT_FAIL_AFTER_SAVE_BEFORE_PUBLISH_ENABLED
  unset IMAGE_PIPELINE_FAULT_FAIL_AFTER_SAVE_TITLE_PREFIX
  "${SCRIPT_DIR}/deploy-app.sh" >/dev/null
}

trap restore_app EXIT

"${SCRIPT_DIR}/reset-state.sh" >/dev/null
export IMAGE_PIPELINE_FAULT_FAIL_AFTER_SAVE_BEFORE_PUBLISH_ENABLED=true
export IMAGE_PIPELINE_FAULT_FAIL_AFTER_SAVE_TITLE_PREFIX="${FAULT_TITLE_PREFIX}"
"${SCRIPT_DIR}/deploy-app.sh" >/dev/null

access_token="$(APP_URL="${APP_URL}" "${PROJECT_ROOT}/scripts/experiments/v1/bootstrap-access-token.sh")"
title="${FAULT_TITLE_PREFIX}-$(date +%s)"

python3 - "${APP_URL}" "${access_token}" "${IMAGE_PATH}" "${title}" > /tmp/v2-save-publish-gap.json <<'PY'
import json
import sys
import urllib.error
import urllib.request

base_url, token, image_path, title = sys.argv[1:5]

def request(method, path, payload=None, content_type="application/json"):
    req = urllib.request.Request(f"{base_url}{path}", data=payload, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")

presign_body = json.dumps({"files": [{"fileName": "save-publish-gap.png", "mimeType": "image/png"}]}).encode()
status, body = request("POST", "/api/posts/images/presigned-url", presign_body)
if status != 200:
    raise SystemExit(body)
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
    "content": "v2 save/publish gap fault injection",
    "imageObjectKeys": [object_key],
}).encode()
status, body = request("POST", "/api/posts", create_body)
print(json.dumps({
    "title": title,
    "createStatus": status,
    "createBody": body,
}))
PY

sleep 5

python3 - "${DB_HOST}" "${QUEUE_URL}" "${OUT_PATH}" <<'PY'
import json
import pathlib
import subprocess
import sys

db_host, queue_url, out_path = sys.argv[1:4]
probe = json.load(open('/tmp/v2-save-publish-gap.json', encoding='utf-8'))
title = probe["title"]

base_cmd = [
    "ssh", "-i", str(pathlib.Path.home() / ".ssh/experiment_image_pipeline_key"),
    "-o", "StrictHostKeyChecking=no",
    "-o", f"UserKnownHostsFile={pathlib.Path.home() / '.ssh/known_hosts'}",
    "-o", "ConnectTimeout=10",
    f"ec2-user@{db_host}",
]
script = """sudo docker exec mongo mongosh 'mongodb://127.0.0.1:27017/millions?replicaSet=rs0&directConnection=true' --quiet --eval '
const post = db.getSiblingDB("millions").posts.findOne({title: "%s"});
print(JSON.stringify({
  exists: !!post,
  postId: post ? post._id : null,
  imageStatus: post ? post.imageStatus : null,
  imageJobId: post ? post.imageJobId : null,
  completedAt: post ? post.completedAt : null
}));
'""" % title.replace('"', '\\"')
mongo_res = json.loads(subprocess.check_output(base_cmd + [script], text=True, timeout=20).strip())

queue_attrs = json.loads(subprocess.check_output([
    "aws", "sqs", "get-queue-attributes",
    "--queue-url", queue_url,
    "--attribute-names", "ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible",
    "--output", "json",
], text=True))

result = {
    "probe": "save_publish_gap",
    "createStatus": probe["createStatus"],
    "postSaved": mongo_res["exists"],
    "postId": mongo_res["postId"],
    "imageStatus": mongo_res["imageStatus"],
    "imageJobId": mongo_res["imageJobId"],
    "completedAt": mongo_res["completedAt"],
    "queueVisibleMessages": int(queue_attrs["Attributes"].get("ApproximateNumberOfMessages", "0")),
    "queueNotVisibleMessages": int(queue_attrs["Attributes"].get("ApproximateNumberOfMessagesNotVisible", "0")),
    "interpretation": "post is saved but publish did not happen if status is 500, postSaved=true, and queue counts stay 0"
}

with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
print(out_path)
PY
