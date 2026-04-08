#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SRC_DIR="${SCRIPT_DIR}/lambda"
BUILD_DIR="${PROJECT_ROOT}/build/experiments/v2/lambda"
PACKAGE_PATH="${PROJECT_ROOT}/build/experiments/v2/image-processor-v2.zip"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "${cmd}" >&2
    exit 1
  fi
}

require_cmd python3

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

python3 -m pip install \
  --quiet \
  --target "${BUILD_DIR}" \
  --only-binary=:all: \
  Pillow==10.4.0

cp "${SRC_DIR}/image_processor.py" "${BUILD_DIR}/image_processor.py"
python3 - "${BUILD_DIR}" "${PACKAGE_PATH}" <<'PY'
import pathlib
import sys
import zipfile

build_dir = pathlib.Path(sys.argv[1])
package_path = pathlib.Path(sys.argv[2])
package_path.parent.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(package_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in build_dir.rglob("*"):
        if path.is_file():
            archive.write(path, path.relative_to(build_dir))
PY

printf '%s\n' "${PACKAGE_PATH}"
