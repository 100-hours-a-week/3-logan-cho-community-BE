#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws
require_cmd python3
require_cmd scp
require_cmd ssh
require_cmd curl

BUCKET="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}"
TEMP_PREFIX="${TEMP_PREFIX_OVERRIDE:-experiments/temp/}"
FINAL_PREFIX="${FINAL_PREFIX_OVERRIDE:-public/images/posts/}"
THUMB_PREFIX="${THUMB_PREFIX_OVERRIDE:-public/images/posts/thumbnails/}"

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

    if not payload.get("IsTruncated"):
        break
    key_marker = payload.get("NextKeyMarker")
    version_marker = payload.get("NextVersionIdMarker")
PY
}

log "resetting S3 prefixes"
delete_prefix "${TEMP_PREFIX}"
delete_prefix "${FINAL_PREFIX}"
delete_prefix "${THUMB_PREFIX}"

if [[ -n "$(db_instance_id)" && "$(db_instance_id)" != "null" ]]; then
  "${SCRIPT_DIR}/deploy-db.sh"
else
  DB_HOST="${APP_SSH_HOST_OVERRIDE:-$(app_ssh_host)}"
  LOCAL_DB_RESET="/tmp/remote-reset-v1-single.sh"
  REMOTE_DB_RESET="~/remote-reset-v1-single.sh"
  cat > "${LOCAL_DB_RESET}" <<'EOF'
#!/bin/bash
set -euo pipefail
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl restart docker
sudo docker rm -f mysql mongo redis >/dev/null 2>&1 || true
sudo docker volume prune -f >/dev/null 2>&1 || true
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
for i in $(seq 1 60); do
  if sudo docker exec mongo mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1; then
    break
  fi
  sleep 2
done
sudo docker exec mongo mongosh --quiet --eval 'try { rs.status().ok } catch (e) { rs.initiate({_id:"rs0", members:[{_id:0, host:"127.0.0.1:27017"}]}) }' >/dev/null 2>&1 || true
EOF
  chmod 700 "${LOCAL_DB_RESET}"
  scp_to "${LOCAL_DB_RESET}" "${DB_HOST}" "${REMOTE_DB_RESET}"
  ssh_run "${DB_HOST}" "chmod +x ${REMOTE_DB_RESET} && bash ${REMOTE_DB_RESET}"
fi

LOCAL_APP_RESET="/tmp/remote-reset-v1-app.sh"
REMOTE_APP_RESET="~/remote-reset-v1-app.sh"
if [[ -n "$(app_asg_name)" && "$(app_asg_name)" != "null" ]]; then
cat > "${LOCAL_APP_RESET}" <<'EOF'
#!/bin/bash
set -euo pipefail
if sudo test -f /etc/systemd/system/experiment-app.service; then
  sudo systemctl restart experiment-app.service
else
  sudo pkill -f '/opt/image-pipeline/app.jar' || true
  sudo rm -f /opt/image-pipeline/app.log /opt/image-pipeline/app.pid || true
  sudo bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >/opt/image-pipeline/app.log 2>&1 < /dev/null' >/dev/null 2>&1 &
  echo $! | sudo tee /opt/image-pipeline/app.pid >/dev/null
fi
echo app_restart_started
EOF
else
cat > "${LOCAL_APP_RESET}" <<'EOF'
#!/bin/bash
set -euo pipefail
sudo pkill -f '/opt/image-pipeline/app.jar' || true
sudo rm -f /opt/image-pipeline/app.log /opt/image-pipeline/app.pid || true
sudo bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >/opt/image-pipeline/app.log 2>&1 < /dev/null' >/dev/null 2>&1 &
echo $! | sudo tee /opt/image-pipeline/app.pid >/dev/null
echo app_restart_started
EOF
fi

chmod 700 "${LOCAL_APP_RESET}"
while IFS= read -r app_host; do
  [[ -z "${app_host}" ]] && continue
  scp_to "${LOCAL_APP_RESET}" "${app_host}" "${REMOTE_APP_RESET}"
  ssh_run "${app_host}" "chmod +x ${REMOTE_APP_RESET} && bash ${REMOTE_APP_RESET}"
done < <(app_public_ips)

APP_URL="${APP_URL_OVERRIDE:-$(app_base_url)}"
for _ in $(seq 1 40); do
  if curl -fsS --max-time 5 "${APP_URL}/api/health" >/dev/null 2>&1; then
    if [[ -n "$(app_asg_name)" && "$(app_asg_name)" != "null" ]]; then
      target_group_arn="$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$(app_asg_name)" \
        --query 'AutoScalingGroups[0].TargetGroupARNs[0]' \
        --output text)"
      expected_targets="$(app_instance_ids | sed '/^$/d' | wc -l | tr -d ' ')"
      healthy_targets="$(aws elbv2 describe-target-health \
        --target-group-arn "${target_group_arn}" \
        --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
        --output text)"
      if [[ "${healthy_targets}" -lt "${expected_targets}" ]]; then
        sleep 3
        continue
      fi
    fi
    sleep 5
    log "app health is ready after reset"
    log "v1 state reset completed"
    exit 0
  fi
  sleep 3
done

printf 'app health check did not become ready after reset: %s\n' "${APP_URL}" >&2
exit 1
