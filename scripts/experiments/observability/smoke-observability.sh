#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd curl
require_cmd python3

K6_IP="${K6_PUBLIC_IP_OVERRIDE:-$(k6_public_ip)}"

curl -fsS "http://${K6_IP}:9090/-/ready" >/dev/null
curl -fsS "http://${K6_IP}:3000/api/health" >/dev/null

for _ in $(seq 1 20); do
  if python3 - "$(curl -fsS "http://${K6_IP}:9090/api/v1/targets")" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
targets = payload["data"]["activeTargets"]
required = {"app-node": False, "app-spring": False}

for target in targets:
    job = target["labels"].get("job")
    if job in required and target.get("health") == "up":
        required[job] = True

missing = [job for job, ok in required.items() if not ok]
if missing:
    raise SystemExit(f"missing healthy scrape targets: {', '.join(missing)}")
PY
  then
    printf 'Grafana: http://%s:3000\n' "${K6_IP}"
    printf 'Prometheus: http://%s:9090\n' "${K6_IP}"
    exit 0
  fi
  sleep 3
done

printf 'observability smoke failed: scrape targets did not become healthy in time\n' >&2
exit 1
