#!/usr/bin/env bash
# Centralized per-agent file-write lane enforcement.
#
# Runs as a single plugin/session-level PreToolUse(Edit|Write) hook and routes
# on the `agent_type` field the harness adds to the payload when a sub-agent
# makes the tool call. Plugin-shipped agents cannot carry hooks in their own
# frontmatter, so the lanes live here instead and apply equally to local dev
# (registered in .claude/settings.json) and installed use (hooks/hooks.json).

# Fail closed: a guard that can't read its input must block, not silently
# allow. Missing jq or an unparseable payload is treated as a denial.
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: lane-guard needs jq to enforce write lanes." >&2
  exit 2
fi
payload="$(cat)"
if ! printf '%s' "$payload" | jq empty >/dev/null 2>&1; then
  echo "Blocked: lane-guard could not parse the hook payload." >&2
  exit 2
fi
agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // empty')"
path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -z "$path" ] && exit 0

# agent_type -> mode + space-separated glob patterns.
case "$agent_type" in
  tank)    mode="--deny";  patterns='*.ts *.tsx *.jsx *.scss *.css' ;;
  trinity) mode="--deny";  patterns='*.cs *.cshtml *.csproj' ;;
  oracle)  mode="--allow"; patterns='**/*Tests/** **/*.Tests.* tests/**' ;;
  dozer)   mode="--allow"; patterns='cypress/** e2e/** **/*.cy.* **/*.spec.*' ;;
  seraph)  mode="--allow"; patterns='.claude/agent-memory-local/seraph/*' ;;
  *) exit 0 ;;  # main session or any agent without a lane: no restriction
esac

# Disable filename expansion so $patterns word-splits into literal glob
# patterns for [[ ]] below, instead of expanding against the filesystem.
set -f
match=0
for g in $patterns; do
  # In [[ ]] a single * already spans '/', so ** behaves the same as * here.
  # file_path is usually absolute, so also try the pattern with a leading */
  # — that lets repo-relative patterns like tests/** or cypress/** match an
  # absolute /abs/repo/tests/x path.
  # shellcheck disable=SC2053
  if [[ "$path" == $g || "$path" == */$g ]]; then
    match=1
    break
  fi
done
set +f

if [ "$mode" = "--deny" ] && [ "$match" = 1 ]; then
  echo "Blocked: $path is out of ${agent_type}'s lane." >&2
  exit 2
fi
if [ "$mode" = "--allow" ] && [ "$match" = 0 ]; then
  echo "Blocked: $path is outside ${agent_type}'s allowed paths." >&2
  exit 2
fi
exit 0
