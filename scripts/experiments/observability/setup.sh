#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/install-node-exporter.sh"
"${SCRIPT_DIR}/install-monitoring-stack.sh"
"${SCRIPT_DIR}/smoke-observability.sh"
