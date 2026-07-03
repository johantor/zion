#!/usr/bin/env bash
# PreToolUse(Edit|Write) allowlist for the keymaker orchestrator. keymaker
# never implements code itself — source edits are delegated to twins
# (keymaker.md operating rules). Its Write/Edit tools exist for the batch
# ledger (.claude/debt-<slug>.md), tier-2 outlines (.claude/plan-<slug>.md),
# and session notes, so writes are confined to .claude/ plus scratch/temp
# locations. Twins and the main session are not restricted here (a twin's
# file-list confinement is prose-enforced by its delegation contract).
#
# Fail closed: a guard that can't read its input must block, not allow.
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: write-guard needs jq to enforce keymaker's write allowlist." >&2
  exit 2
fi
payload="$(cat)"
# One jq call for both fields, joined with a record-separator byte and split
# on its first occurrence — safe because agent_type (the leading field) is a
# small, harness-controlled value that never contains it, regardless of what
# the path itself might contain. jq only computes the path for the keymaker
# agent, so no other session pays for the field lookup.
rs=$'\x1e'
if ! fields="$(printf '%s' "$payload" | jq -j --arg rs "$rs" '(.agent_type // "") as $at | $at + $rs + (if $at == "keymaker" then ((.tool_input.file_path // .tool_input.path) // "") else "" end)' 2>/dev/null)"; then
  echo "Blocked: write-guard could not parse the hook payload." >&2
  exit 2
fi
agent_type="${fields%%"$rs"*}"
path="${fields#*"$rs"}"

[ "$agent_type" = "keymaker" ] || exit 0
[ -z "$path" ] && exit 0

# Allowed: .claude/ (ledger, outlines, notes, agent memory) whether the path
# is repo-relative or absolute, plus temp/scratch locations. Everything else
# is a source edit that belongs to a twin. Variable expansions inside case
# patterns are quoted, so a TMPDIR value can't inject glob metacharacters.
case "$path" in
  .claude/*|*/.claude/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*|"${TMPDIR:-/tmp}"/*)
    exit 0 ;;
esac
echo "Blocked: keymaker never edits source files — delegate the fix to a twin. Write/Edit are for the batch ledger, outlines, and notes under .claude/ only." >&2
exit 2
