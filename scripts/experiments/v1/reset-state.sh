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

wait_for_app_recovery() {
  local instance_id
  instance_id="$(app_instance_id)"

  aws ec2 wait instance-status-ok --instance-ids "${instance_id}"

  for _ in $(seq 1 30); do
    if ssh_run "${APP_HOST}" "echo ssh_ready" >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done

  printf 'app ssh did not become ready after reboot: %s\n' "${APP_HOST}" >&2
  exit 1
}

ensure_app_ssh_available() {
  if ssh_run "${APP_HOST}" "echo ssh_ready" >/dev/null 2>&1; then
    return 0
  fi

  log "app ssh is unavailable; requesting EC2 reboot for recovery"
  aws ec2 reboot-instances --instance-ids "$(app_instance_id)" >/dev/null
  wait_for_app_recovery
}

delete_prefix() {
  local prefix="$1"
  python3 - "${BUCKET}" "${prefix}" <<'PY'
import json
import subprocess
import sys

bucket, prefix = sys.argv[1], sys.argv[2]

def list_page(key_marker=None, version_marker=None):
    cmd = [
        "aws", "s3api", "list-object-versions",
        "--bucket", bucket,
        "--prefix", prefix,
        "--output", "json",
    ]
    if key_marker:
        cmd.extend(["--key-marker", key_marker])
    if version_marker:
        cmd.extend(["--version-id-marker", version_marker])

    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return json.loads(proc.stdout)


def batched(items, size):
    for i in range(0, len(items), size):
        yield items[i:i + size]


key_marker = None
version_marker = None
deleted_any = False

while True:
    payload = list_page(key_marker, version_marker)
    objects = []
    for key in ("Versions", "DeleteMarkers"):
        for obj in payload.get(key, []):
            objects.append({"Key": obj["Key"], "VersionId": obj["VersionId"]})

    for batch in batched(objects, 500):
        subprocess.run(
            [
                "aws", "s3api", "delete-objects",
                "--bucket", bucket,
                "--delete", json.dumps({"Objects": batch, "Quiet": True}),
            ],
            check=True,
        )
        deleted_any = True

    if not payload.get("IsTruncated"):
        break

    key_marker = payload.get("NextKeyMarker")
    version_marker = payload.get("NextVersionIdMarker")

if not deleted_any:
    sys.exit(0)
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
  mongo:latest --replSet rs0 --bind_ip_all
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
for i in $(seq 1 60); do
  if sudo docker exec mongo mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1; then
    break
  fi
  sleep 2
done
sudo docker exec mongo mongosh --quiet --eval 'try { rs.status().ok } catch (e) { rs.initiate({_id:"rs0", members:[{_id:0, host:"127.0.0.1:27017"}]}) }' >/dev/null 2>&1 || true
for i in $(seq 1 60); do
  if sudo docker exec mongo mongosh --quiet --eval 'try { print(rs.status().ok) } catch (e) { print(0) }' | grep -q 1; then
    break
  fi
  sleep 2
done
sudo bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >/opt/image-pipeline/app.log 2>&1 < /dev/null' >/dev/null 2>&1 &
echo $! | sudo tee /opt/image-pipeline/app.pid >/dev/null
echo app_restart_started
EOF

chmod 700 "${LOCAL_REMOTE_SCRIPT}"
ensure_app_ssh_available
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
