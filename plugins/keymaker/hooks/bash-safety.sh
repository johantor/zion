#!/usr/bin/env bash
# PreToolUse(Bash) guard for the keymaker crew. Blocks destructive commands,
# git misuse (twins never run git; no commits on a protected branch),
# never-terminating watch/dev/serve commands, and raw/streaming reads.
#
# The command-shape patterns and the shared floor they enforce live in
# hooks/lib/guard-lib.sh, vendored byte-identically from crew (validator §5), so
# a standalone keymaker install keeps the same floor. What stays here is
# keymaker's own policy: twins never run git, and keymaker owns branching. Both
# plugins installed means both guards fire: redundant, fine.
#
# Fails closed: a guard that can't read its input must block, not pass the
# command through uninspected. jq is a documented dependency.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/keymaker/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
if ! . "$_lib" 2>/dev/null; then
  echo "Blocked: bash-safety could not load its guard library ($_lib)." >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: bash-safety needs jq to inspect commands." >&2
  exit 2
fi

guard_read_payload
# The command is the untrusted field (arbitrary text, possibly containing the
# separator byte); agent_type is the harness-controlled one. See guard_jq2.
if ! guard_jq2 '.tool_input.command // ""' '.agent_type // ""'; then
  echo "Blocked: bash-safety could not parse the hook payload." >&2
  exit 2
fi
agent_type="$guard_trusted"
guard_normalize "$guard_untrusted"

# --- BEGIN shared guard: floor ---
# The floor every plugin's Bash guard enforces, in this order. Destructive ops
# are refused for everyone; the watch/dev/serve and file-write blocks are scoped
# to agent sessions, since the user's own session may legitimately run a dev
# server, and is not write-guarded on the Edit|Write path either.
guard_block_destructive
[ -n "$agent_type" ] && guard_block_watch_commands
guard_block_raw_reads
[ -n "$agent_type" ] && guard_block_file_writes
# --- END shared guard: floor ---

# Twins never run git -- keymaker owns branching and per-batch commits
# (twin.md operating rules). Any git invocation at a command position is
# blocked.
if [ "$agent_type" = "twin" ] && [[ $guard_cmd =~ $GUARD_RE_GIT_AT_CMD ]]; then
  echo "Blocked: twin never runs git — keymaker owns branching and commits. Return your batch result; keymaker commits verified batches." >&2
  exit 2
fi

# No agent commits onto a protected branch -- keymaker works on a chore/debt-*
# branch it creates first. Scoped via agent_type so a normal main session (no
# agent_type) is never intercepted.
guard_block_protected_branch_commit "$agent_type" \
  "Create the work branch first (keymaker owns branching)."

exit 0
