#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

STATE_DIR=".ai/state"
TODO_FILE="$STATE_DIR/02_todo.md"
TROUBLE_FILE="$STATE_DIR/03_trouble.md"
RESOLVED_FILE="$STATE_DIR/99_resolved.md"

ALLOWED_STATE_FILES=(
  "$STATE_DIR/00_objective.md"
  "$STATE_DIR/01_current.md"
  "$STATE_DIR/02_todo.md"
  "$STATE_DIR/03_trouble.md"
  "$STATE_DIR/99_resolved.md"
)

MODE="staged"
BASE_REF=""

fail() {
  echo "[state-guard] $*" >&2
  exit 1
}

is_allowed_state_file() {
  local path="$1"
  local f
  for f in "${ALLOWED_STATE_FILES[@]}"; do
    [[ "$path" == "$f" ]] && return 0
  done
  return 1
}

base_has_file() {
  local target="$1"
  if [[ "$MODE" == "staged" ]]; then
    git cat-file -e "HEAD:$target" 2>/dev/null
  else
    git cat-file -e "${BASE_REF}:$target" 2>/dev/null
  fi
}

diff_name_status() {
  if [[ "$MODE" == "staged" ]]; then
    git diff --cached --name-status -- "$STATE_DIR"
  else
    git diff --name-status "${BASE_REF}...HEAD" -- "$STATE_DIR"
  fi
}

diff_unified() {
  local target="$1"
  if [[ "$MODE" == "staged" ]]; then
    git diff --cached --unified=0 -- "$target"
  else
    git diff --unified=0 "${BASE_REF}...HEAD" -- "$target"
  fi
}

file_changed() {
  local target="$1"
  if [[ "$MODE" == "staged" ]]; then
    ! git diff --cached --quiet -- "$target"
  else
    ! git diff --quiet "${BASE_REF}...HEAD" -- "$target"
  fi
}

get_old_resolved() {
  if [[ "$MODE" == "staged" ]]; then
    git rev-parse --verify HEAD >/dev/null 2>&1 || fail "HEAD가 없어 resolved 이력 검증을 할 수 없다."
    git cat-file -e "HEAD:$RESOLVED_FILE" 2>/dev/null || fail "HEAD에 $RESOLVED_FILE 이 없다."
    git show "HEAD:$RESOLVED_FILE"
  else
    git cat-file -e "${BASE_REF}:$RESOLVED_FILE" 2>/dev/null || fail "$BASE_REF 에 $RESOLVED_FILE 이 없다."
    git show "${BASE_REF}:$RESOLVED_FILE"
  fi
}

get_new_resolved() {
  if [[ "$MODE" == "staged" ]]; then
    git cat-file -e ":$RESOLVED_FILE" 2>/dev/null || fail "staged index에 $RESOLVED_FILE 이 없다."
    git show ":$RESOLVED_FILE"
  else
    git cat-file -e "HEAD:$RESOLVED_FILE" 2>/dev/null || fail "HEAD에 $RESOLVED_FILE 이 없다."
    git show "HEAD:$RESOLVED_FILE"
  fi
}

if [[ "${1:-}" == "--base-ref" ]]; then
  [[ -n "${2:-}" ]] || fail "--base-ref <git-ref> 형식이 필요하다."
  MODE="range"
  BASE_REF="$2"
fi

while IFS=$'\t' read -r status p1 p2; do
  [[ -z "${status:-}" ]] && continue

  case "$status" in
    R*|C*)
      fail "state 파일 이름 변경/복사 금지: $p1 -> $p2"
      ;;
    A*)
      if is_allowed_state_file "$p1" && ! base_has_file "$p1"; then
        continue
      fi
      fail "state 하위 새 파일 생성 금지: $p1"
      ;;
    D*)
      fail "state 파일 삭제 금지: $p1"
      ;;
    T*)
      fail "state 파일 타입 변경 금지: $p1"
      ;;
    M*)
      if ! is_allowed_state_file "$p1"; then
        fail "허용되지 않은 state 파일 변경: $p1"
      fi
      ;;
    *)
      if [[ "$p1" == "$STATE_DIR/"* ]] && ! is_allowed_state_file "$p1"; then
        fail "허용되지 않은 state 파일 변경: $p1"
      fi
      ;;
  esac
done < <(diff_name_status)

if file_changed "$RESOLVED_FILE"; then
  if ! base_has_file "$RESOLVED_FILE"; then
    bootstrap_file="$(mktemp)"
    trap 'rm -f "$bootstrap_file"' EXIT

    get_new_resolved > "$bootstrap_file"
    if ! diff -u <(printf '# Resolved\n\n- \n') "$bootstrap_file" >/dev/null; then
      fail "초기 99_resolved.md 형식이 올바르지 않다"
    fi

    echo "[state-guard] OK"
    exit 0
  fi

  removed_lines="$(diff_unified "$RESOLVED_FILE" | grep '^-' | grep -v '^--- ' || true)"
  [[ -z "$removed_lines" ]] || fail "99_resolved.md 기존 라인 삭제/수정 감지"

  old_file="$(mktemp)"
  new_file="$(mktemp)"
  trap 'rm -f "$old_file" "$new_file"' EXIT

  get_old_resolved > "$old_file"
  get_new_resolved > "$new_file"

  old_lines="$(wc -l < "$old_file" | tr -d ' ')"
  if ! diff -u "$old_file" <(head -n "$old_lines" "$new_file") >/dev/null; then
    fail "99_resolved.md는 append-only다. 기존 이력 수정 금지"
  fi

  added_lines="$(diff_unified "$RESOLVED_FILE" | grep '^+' | grep -v '^+++ ' || true)"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^\+\-\ \[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]\ .+$ ]]; then
      fail "99_resolved.md 추가 라인 형식 오류: $line"
    fi
  done <<< "$added_lines"

  todo_removed="$(diff_unified "$TODO_FILE" | grep '^-' | grep -v '^--- ' || true)"
  trouble_removed="$(diff_unified "$TROUBLE_FILE" | grep '^-' | grep -v '^--- ' || true)"
  if [[ -z "$todo_removed" && -z "$trouble_removed" ]]; then
    fail "resolved 변경 시 todo/trouble 항목 제거가 함께 필요하다. .ai/scripts/update-state.sh를 사용하라"
  fi
fi

echo "[state-guard] OK"
