#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws
require_cmd python3
require_cmd scp
require_cmd ssh

BUCKET="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}"
APP_HOST="${APP_SSH_HOST_OVERRIDE:-$(app_ssh_host)}"
TEMP_PREFIX="${TEMP_PREFIX_OVERRIDE:-experiments/temp/}"
FINAL_PREFIX="${FINAL_PREFIX_OVERRIDE:-public/images/posts/}"
THUMB_PREFIX="${THUMB_PREFIX_OVERRIDE:-public/images/posts/thumbnails/}"
REMOTE_SCRIPT="~/remote-reset-v1.sh"
LOCAL_REMOTE_SCRIPT="/tmp/remote-reset-v1.sh"

delete_prefix() {
  local prefix="$1"
  python3 - "${BUCKET}" "${prefix}" <<'PY'
import json
import subprocess
import sys

bucket, prefix = sys.argv[1], sys.argv[2]

proc = subprocess.run(
    [
        "aws", "s3api", "list-object-versions",
        "--bucket", bucket,
        "--prefix", prefix,
        "--output", "json",
    ],
    check=True,
    capture_output=True,
    text=True,
)
payload = json.loads(proc.stdout)
objects = []
for key in ("Versions", "DeleteMarkers"):
    for obj in payload.get(key, []):
        objects.append({"Key": obj["Key"], "VersionId": obj["VersionId"]})

if not objects:
    sys.exit(0)

subprocess.run(
    [
        "aws", "s3api", "delete-objects",
        "--bucket", bucket,
        "--delete", json.dumps({"Objects": objects, "Quiet": True}),
    ],
    check=True,
)
PY
}

log "resetting S3 prefixes"
delete_prefix "${TEMP_PREFIX}"
delete_prefix "${FINAL_PREFIX}"
delete_prefix "${THUMB_PREFIX}"

cat > "${LOCAL_REMOTE_SCRIPT}" <<'EOF'
#!/bin/bash
set -euo pipefail
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl restart docker
sudo docker rm -f mysql mongo redis >/dev/null 2>&1 || true
sudo docker volume prune -f >/dev/null 2>&1 || true
sudo pkill -f '/opt/image-pipeline/app.jar' || true
sudo rm -f /opt/image-pipeline/app.log /opt/image-pipeline/app.pid || true
sudo docker run -d --name mysql \
  -e MYSQL_ROOT_PASSWORD=yourpw \
  -e MYSQL_DATABASE=millions \
  -e MYSQL_ROOT_HOST=% \
  -p 127.0.0.1:3306:3306 \
  mysql:8.4
sudo docker run -d --name mongo \
  -p 127.0.0.1:27017:27017 \
  mongo:latest
sudo docker run -d --name redis \
  -p 127.0.0.1:6379:6379 \
  redis:latest
for i in $(seq 1 60); do
  if sudo docker exec mysql mysqladmin ping -pyourpw --silent; then
    break
  fi
  sleep 2
done
if ! sudo docker exec mysql mysqladmin ping -pyourpw --silent; then
  exit 1
fi
sudo bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >/opt/image-pipeline/app.log 2>&1 < /dev/null' >/dev/null 2>&1 &
echo $! | sudo tee /opt/image-pipeline/app.pid >/dev/null
echo app_restart_started
EOF

chmod 700 "${LOCAL_REMOTE_SCRIPT}"
scp_to "${LOCAL_REMOTE_SCRIPT}" "${APP_HOST}" "${REMOTE_SCRIPT}"
ssh_run "${APP_HOST}" "chmod +x ${REMOTE_SCRIPT} && bash ${REMOTE_SCRIPT}"

APP_IP="${APP_PUBLIC_IP_OVERRIDE:-$(app_public_ip)}"
for _ in $(seq 1 30); do
  if curl -fsS --max-time 5 "http://${APP_IP}:8080/api/health" >/dev/null 2>&1; then
    log "app health is ready after reset"
    log "v1 state reset completed"
    exit 0
  fi
  sleep 2
done

printf 'app health check did not become ready after reset: %s\n' "${APP_IP}" >&2
exit 1
