#!/usr/bin/env bash
# Per-agent file-write lane enforcement for PreToolUse(Edit|Write). Routes on the
# `agent_type` the harness adds to the payload; plugin agents can't carry their
# own hooks, so the lanes are centralized here.

# Fail closed: a guard that can't read its input must block, not allow.
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
# Note: .cshtml is intentionally NOT denied to either tank or trinity. Razor is
# shared by concern (trinity = markup/DOM in server-rendered mode, tank = C#/server
# logic), and the mode/concern split is enforced by the agent prompts, not here —
# file globs can't see inside a file.
case "$agent_type" in
  tank)    mode="--deny";  patterns='*.ts *.tsx *.jsx *.js *.mjs *.scss *.css *.html' ;;
  trinity) mode="--deny";  patterns='*.cs *.csproj' ;;
  oracle)  mode="--allow"; patterns='**/*Tests/** **/*.Tests.* tests/**' ;;
  dozer)   mode="--allow"; patterns='cypress/** e2e/** **/*.cy.* **/*.spec.*' ;;
  # neo is the express-lane generalist — small changes across any lane — so it has
  # no lane restriction by design. Explicit here (rather than falling through to the
  # default) to document that all-lane access is intentional, not an oversight.
  neo)     exit 0 ;;
  # seraph is a read-only reviewer with no edit/write tools, so it never reaches
  # this Edit|Write hook — no lane entry needed.
  *) exit 0 ;;  # main session or any agent without a lane: no restriction
esac

# set -f keeps $patterns as literal globs for [[ ]] instead of expanding them
# against the filesystem. The */ prefix lets repo-relative patterns (tests/**)
# match an absolute file_path; the ./ prefix lets **/-anchored patterns
# (**/*Tests/**) match a repo-relative file_path (** needs a leading component
# to consume); in [[ ]] a single * already spans '/'.
set -f
match=0
for g in $patterns; do
  # shellcheck disable=SC2053
  if [[ "$path" == $g || "$path" == */$g || "./$path" == $g ]]; then
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
