#!/usr/bin/env bash
# PreToolUse(Bash) guard. Blocks destructive commands and raw/streaming reads
# that bypass context discipline, and keeps crew's workers out of git.
#
# The command-shape patterns and the shared floor they enforce live in
# hooks/lib/guard-lib.sh, vendored byte-identically into every plugin that ships
# a Bash guard (validator §5, crew's copy canonical). What stays here is crew's
# own policy: which agents may run git, and what the messages tell them to do
# instead. The marked "shared guard" region below is the floor itself -- it is
# byte-synced with keymaker's copy so a standalone install of either plugin
# enforces the same rules in the same order.
#
# Fails closed: a guard that can't read its input must block, not pass the
# command through uninspected. jq is a documented dependency.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
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
# are refused for everyone; the watch/dev/serve block is scoped to agent
# sessions, since the user's own session may legitimately run a dev server.
guard_block_destructive
[ -n "$agent_type" ] && guard_block_watch_commands
guard_block_raw_reads
# --- END shared guard: floor ---

# Workers never touch git -- morpheus is the sole git owner (branching and
# per-step commits; see AGENTS.md "How the crew works"). Any git invocation at
# a command position is blocked for the Bash-capable workers (seraph carries no
# Bash tool, so it needs no entry).
# crew-roster: no-git -- validator §9 keeps the arm below in lockstep with the
# agents' frontmatter `owns-git`. Every Bash-capable agent that doesn't own git
# belongs here. Load-bearing shape: this marker, then the `case` header, then the
# `a|b|c)` arm on the very next line. §9 parses exactly that and reports the
# roster unverifiable if it changes -- it will not scan on to a later `case`.
case "$agent_type" in
  tank|trinity|oracle|dozer|neo)
    if [[ $guard_cmd =~ $GUARD_RE_GIT_AT_CMD ]]; then
      echo "Blocked: ${agent_type} never runs git — morpheus owns branching and commits. Return your result; morpheus commits verified steps." >&2
      exit 2
    fi ;;
esac

# Any other agent (morpheus, other plugins' agents) must not commit onto a
# protected base branch -- crew work happens on feature branches (morpheus owns
# branching). Scoped via agent_type so a normal main session (no agent_type) is
# never intercepted.
guard_block_protected_branch_commit "$agent_type" \
  "Work on a feature branch (morpheus owns branching)."

exit 0
