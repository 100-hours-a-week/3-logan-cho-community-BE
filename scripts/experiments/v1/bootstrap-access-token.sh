#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd python3

APP_URL="${APP_URL:-http://$(app_public_ip):8080}"
DEVICE_ID="${DEVICE_ID:-experiment-device}"
USER_SUFFIX="${USER_SUFFIX:-$(date +%s)}"
EMAIL="${EMAIL:-exp-v1-${USER_SUFFIX}@example.com}"
PASSWORD="${PASSWORD:-Abcd1234!}"
DISPLAY_NAME="${DISPLAY_NAME:-V1AB}"

REGISTER_PAYLOAD="$(python3 - <<PY
import json
print(json.dumps({
  "email": "${EMAIL}",
  "password": "${PASSWORD}",
  "name": "${DISPLAY_NAME}",
  "imageObjectKey": None,
  "emailVerifiedToken": "load-test-bypass"
}))
PY
)"

LOGIN_PAYLOAD="$(python3 - <<PY
import json
print(json.dumps({
  "email": "${EMAIL}",
  "password": "${PASSWORD}",
  "deviceId": "${DEVICE_ID}"
}))
PY
)"

python3 - "${APP_URL}" "${REGISTER_PAYLOAD}" "${LOGIN_PAYLOAD}" <<'PY'
import json
import sys
import urllib.error
import urllib.request

base_url, register_payload, login_payload = sys.argv[1:4]

def request(method, path, payload=None):
    data = None
    headers = {"Content-Type": "application/json"}
    if payload is not None:
        data = payload.encode("utf-8")
    req = urllib.request.Request(
        f"{base_url}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")

status, body = request("POST", "/api/members", register_payload)
if status not in (200, 409):
    print(body, file=sys.stderr)
    sys.exit(1)

status, body = request("POST", "/api/auth", login_payload)
if status != 200:
    print(body, file=sys.stderr)
    sys.exit(1)

payload = json.loads(body)
token = payload["data"]["accessJwt"]
print(token)
PY
