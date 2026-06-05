#!/usr/bin/env bash
# Validates the plugin's structure so manifest/file drift fails fast.
# Runnable locally (`.claude/scripts/validate-plugin.sh`) and in CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
ok()  { echo "ok:   $*"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# 1. Every JSON file parses.
while IFS= read -r f; do
  if jq empty "$f" >/dev/null 2>&1; then
    ok "valid JSON: $f"
  else
    err "invalid JSON: $f"
  fi
done < <(git ls-files '*.json')

manifest=".claude-plugin/plugin.json"
if [ -f "$manifest" ]; then
  # 2. Manifest declares the required identity fields.
  for key in name version; do
    if [ "$(jq -r --arg k "$key" 'has($k)' "$manifest")" != "true" ]; then
      err "$manifest missing required key: $key"
    else
      ok "$manifest has key: $key"
    fi
  done

  # 3. Component paths the manifest points at actually exist.
  for key in commands agents skills hooks; do
    path="$(jq -r --arg k "$key" '.[$k] // empty' "$manifest")"
    [ -z "$path" ] && continue
    if [ -e "$path" ]; then
      ok "$key -> $path exists"
    else
      err "$key -> $path declared in $manifest but not found"
    fi
  done
else
  err "$manifest not found"
fi

# 4. Hook scripts are syntactically valid and executable.
while IFS= read -r h; do
  if bash -n "$h" 2>/dev/null; then
    ok "syntax: $h"
  else
    err "bash syntax error: $h"
  fi
  if [ -x "$h" ]; then
    ok "executable: $h"
  else
    err "not executable (chmod +x): $h"
  fi
done < <(git ls-files '.claude/hooks/*.sh')

if [ "$fail" -ne 0 ]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "Plugin validation passed."
