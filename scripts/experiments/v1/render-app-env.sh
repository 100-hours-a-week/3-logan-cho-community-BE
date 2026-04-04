#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws
require_cmd python3

OUT_PATH="${1:-/tmp/experiment-app-env.sh}"
PARAM_PATH="${PARAM_STORE_PATH:-/millions/backend}"
BUCKET_OVERRIDE="${S3_BUCKET_NAME_OVERRIDE:-}"

aws ssm get-parameters-by-path \
  --path "${PARAM_PATH}" \
  --with-decryption \
  --recursive \
  --output json > /tmp/image-pipeline-params.json

python3 - "${OUT_PATH}" "${PARAM_PATH}" "${BUCKET_OVERRIDE}" <<'PY'
import json
import os
import shlex
import sys

out_path = sys.argv[1]
param_path = sys.argv[2].rstrip("/")
bucket_override = sys.argv[3]

with open("/tmp/image-pipeline-params.json", "r", encoding="utf-8") as f:
    payload = json.load(f)

values = {}
prefix = f"{param_path}/"
for entry in payload["Parameters"]:
    key = entry["Name"]
    if key.startswith(prefix):
        values[key[len(prefix):]] = entry["Value"]

values["PROFILE"] = "prod"
values["SPRING_CLOUD_AWS_PARAMETERSTORE_ENABLED"] = "false"
values["SPRING_CONFIG_IMPORT"] = ""
values["DB_HOST"] = "jdbc:mysql://127.0.0.1:3306/millions?allowPublicKeyRetrieval=true&useSSL=false&serverTimezone=Asia/Seoul"
values["MONGO_URL"] = "mongodb://127.0.0.1:27017/millions?replicaSet=rs0&directConnection=true"
values["REDIS_HOST"] = "127.0.0.1"
values["REDIS_PORT"] = "6379"
values["IS_ELASTIC_CACHE"] = "false"
values["JAVA_TOOL_OPTIONS"] = "-Duser.timezone=Asia/Seoul"
if bucket_override:
    values["AWS_S3_BUCKET_NAME"] = bucket_override

optional_keys = [
    "IMAGE_PIPELINE_ASYNC_ENABLED",
    "IMAGE_PIPELINE_QUEUE_URL",
    "IMAGE_PIPELINE_CALLBACK_BASE_URL",
    "IMAGE_PIPELINE_CALLBACK_SECRET",
    "IMAGE_PIPELINE_OUTBOX_ENABLED",
    "IMAGE_PIPELINE_OUTBOX_RELAY_ENABLED",
    "IMAGE_PIPELINE_OUTBOX_RELAY_FIXED_DELAY_MS",
    "IMAGE_PIPELINE_OUTBOX_RELAY_BATCH_SIZE",
]
for key in optional_keys:
    value = os.environ.get(key)
    if value:
        values[key] = value

with open(out_path, "w", encoding="utf-8") as f:
    f.write("#!/bin/bash\n")
    f.write("set -a\n")
    for key in sorted(values):
      value = values[key]
      if "\n" in value:
          marker = f"__EOF_{key}__"
          f.write(f"{key}=$(cat <<'{marker}'\n{value}\n{marker}\n)\n")
          f.write(f"export {key}\n")
      else:
          f.write(f"export {key}={shlex.quote(value)}\n")
    f.write("set +a\n")

os.chmod(out_path, 0o700)
PY

log "rendered app env: ${OUT_PATH}"
