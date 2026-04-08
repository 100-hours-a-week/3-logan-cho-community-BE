#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
RESULT_ROOT="docs/experiments/results/exp-v4-idempotent" "${ROOT_DIR}/scripts/experiments/v3/run-k6.sh"
