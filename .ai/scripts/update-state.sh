#!/usr/bin/env bash
set -euo pipefail

AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TODO_FILE="$AI_DIR/state/02_todo.md"
TROUBLE_FILE="$AI_DIR/state/03_trouble.md"
RESOLVED_FILE="$AI_DIR/state/99_resolved.md"

fail() {
  echo "[update-state] $*" >&2
  exit 1
}

usage() {
  echo "사용법: .ai/scripts/update-state.sh \"메시지\"" >&2
  exit 1
}

remove_first_match() {
  local file="$1"
  local message="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v m="$message" '
    BEGIN { removed=0 }
    {
      if (!removed && ($0 == "- " m || $0 == m)) {
        removed=1
        next
      }
      print
    }
    END {
      if (!removed) exit 2
    }
  ' "$file" > "$tmp" || {
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  }

  mv "$tmp" "$file"
}

[[ $# -ge 1 ]] || usage
MESSAGE="$*"

[[ -n "${MESSAGE// }" ]] || fail "빈 메시지는 허용하지 않는다."
[[ "$MESSAGE" != *$'\n'* ]] || fail "메시지는 한 줄만 허용한다."

[[ -f "$TODO_FILE" ]] || fail "파일 없음: $TODO_FILE"
[[ -f "$TROUBLE_FILE" ]] || fail "파일 없음: $TROUBLE_FILE"
[[ -f "$RESOLVED_FILE" ]] || fail "파일 없음: $RESOLVED_FILE"

SOURCE=""
if remove_first_match "$TODO_FILE" "$MESSAGE"; then
  SOURCE="todo"
elif remove_first_match "$TROUBLE_FILE" "$MESSAGE"; then
  SOURCE="trouble"
else
  fail "todo/trouble에서 메시지를 찾지 못했다: $MESSAGE"
fi

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
printf -- "- [%s] %s\n" "$TS" "$MESSAGE" >> "$RESOLVED_FILE"

echo "[update-state] $SOURCE -> resolved 완료: $MESSAGE"
