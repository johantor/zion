#!/usr/bin/env bash
# PostToolUse(*) advisor. Counts a crew agent's tool calls against its
# frontmatter maxTurns and warns at 75% and 90%, so near-budget work hands back
# a `remaining:` line instead of truncating. Exit 2 here feeds stderr to the
# agent without blocking (the tool already ran). Tool calls >= turns, so the
# count errs early on purpose.
#
# Advisory, not a guard: every can't-count path (missing jq, bad payload,
# unknown agent, unwritable state) must fail OPEN. See AGENTS.md, "How the
# crew works".
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# Fast path, no subprocess. This hook is wired to PostToolUse `*`, so it runs
# after every tool call in every session — overwhelmingly the user's own, where
# it always exits 0 at the agent_type case below. A payload without an
# `agent_type` key can only reach that same exit, so bail here rather than
# forking jq for it. A payload that merely mentions the key in its tool input
# falls through to the normal parse, so this only ever saves work.
case "$guard_payload" in
  *'"agent_type"'*) ;;
  *) exit 0 ;;
esac

# transcript_path (fallback session_id) keys the counter per agent *instance*;
# agent_type is the trusted field that anchors the split (see guard_jq2).
guard_jq2 '(.transcript_path // .session_id // "")' '.agent_type // ""' || exit 0
key_src="$guard_untrusted"
agent_type="$guard_trusted"
[ -n "$key_src" ] || exit 0

# Budget per agent = that agent's frontmatter maxTurns. validate-plugin.sh §8
# keeps this table in lockstep with plugins/crew/agents/*.md and depends on the
# exact `<name>) budget=<n> ;;` line shape — keep it when editing. Any other
# agent_type (the user's own session, other plugins) is none of our business.
case "$agent_type" in
  morpheus) budget=96 ;;
  tank) budget=72 ;;
  trinity) budget=72 ;;
  oracle) budget=56 ;;
  dozer) budget=56 ;;
  seraph) budget=40 ;;
  neo) budget=48 ;;
  sentinel) budget=40 ;;
  *) exit 0 ;;
esac

# Counter state: "<count> <stage>" per agent instance, named and swept by
# guard_state_path (stale counters age out rather than accumulating one tiny
# file per agent instance forever). Concurrent tool calls may lose an update and
# undercount by one — fine for a heuristic. CREW_TURN_BUDGET_DIR is a test
# override. An unusable state dir means "can't count", which fails OPEN.
guard_state_path "${CREW_TURN_BUDGET_DIR:-${TMPDIR:-/tmp}}" \
  "crew-turn-budget" "$key_src" "$agent_type" || exit 0
state_file="$guard_state_path"

guard_read_counter "$state_file"
count=$((guard_count + 1))
stage="$guard_stage"

wind_down=$((budget * 75 / 100))
stop_now=$((budget * 90 / 100))

if [ "$stage" -lt 2 ] && [ "$count" -ge "$stop_now" ]; then
  printf '%s %s\n' "$count" 2 > "$state_file" 2>/dev/null || exit 0
  echo "Turn budget: ~${count}/${budget} tool calls used (90%). Stop now: return your summary with its completion marker and a \`remaining:\` line for everything unfinished — do not make further edits." >&2
  exit 2
fi
if [ "$stage" -lt 1 ] && [ "$count" -ge "$wind_down" ]; then
  printf '%s %s\n' "$count" 1 > "$state_file" 2>/dev/null || exit 0
  echo "Turn budget: ~${count}/${budget} tool calls used (75%). Wind down: finish only the sub-task in flight, bring the work to a safe boundary, and return your summary with a \`remaining:\` line for anything unfinished. Do not start new sub-tasks." >&2
  exit 2
fi

printf '%s %s\n' "$count" "$stage" > "$state_file" 2>/dev/null
exit 0
