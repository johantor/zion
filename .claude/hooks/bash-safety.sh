#!/usr/bin/env bash
cmd="$(jq -r '.tool_input.command // empty')"
if echo "$cmd" | grep -Eq 'rm -rf (/|~|\*)|git push .*--force|>\s*\.env|/\.git/'; then
  echo "Blocked: unsafe command." >&2
  exit 2
fi
exit 0
