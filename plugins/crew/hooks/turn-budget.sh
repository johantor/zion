#!/usr/bin/env bash
# PostToolUse(*) advisor. Counts a crew agent's tool calls against its turn
# budget (the agent's frontmatter maxTurns) and warns it — once at 75%, once at
# 90% — so near-budget work ends as an orderly hand-back with a `remaining:`
# line instead of a mid-task truncation. Exit 2 on PostToolUse feeds stderr
# back to the agent without blocking anything (the tool already ran).
#
# Tool calls >= turns (one turn may batch several calls), so the count is a
# conservative heuristic that errs early — a warning slightly before it's
# needed beats a truncation. See AGENTS.md "How the crew works" and
# agents/morpheus.md "A truncated return is not a finished step".
#
# Unlike bash-safety (an enforcement guard that fails closed), this hook is
# advisory: on any path where it can't count — missing jq, unparseable payload,
# unknown agent, unwritable state — it must fail OPEN (exit 0). A broken
# advisor must never block or nag real work.
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
# Fast path, no subprocess. This hook is wired to PostToolUse `*`, so it runs
# after every tool call in every session — overwhelmingly the user's own, where
# it always exits 0 at the agent_type case below. A payload without an
# `agent_type` key can only reach that same exit, so bail here rather than
# forking jq for it. A payload that merely mentions the key in its tool input
# falls through to the normal parse, so this only ever saves work.
case "$payload" in
  *'"agent_type"'*) ;;
  *) exit 0 ;;
esac

rs=$'\x1e'
# transcript_path (fallback session_id) keys the counter per agent *instance*;
# agent_type is last so the harness-controlled small value anchors the split
# (same trusted-field-last rule as bash-safety).
if ! fields="$(printf '%s' "$payload" | jq -j --arg rs "$rs" \
  '(.transcript_path // .session_id // "") + $rs + (.agent_type // "")' 2>/dev/null)"; then
  exit 0
fi
key_src="${fields%"$rs"*}"
agent_type="${fields##*"$rs"}"
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
  seraph) budget=20 ;;
  neo) budget=48 ;;
  *) exit 0 ;;
esac

# Counter state: "<count> <stage>" per agent instance. cksum (POSIX, also on
# BSD/macOS) keeps the filename short and safe; /tmp files are tiny and the OS
# reclaims them. Concurrent tool calls may lose an update and undercount by
# one — fine for a heuristic. CREW_TURN_BUDGET_DIR is a test override.
state_dir="${CREW_TURN_BUDGET_DIR:-${TMPDIR:-/tmp}}"
[ -d "$state_dir" ] && [ -w "$state_dir" ] || exit 0
key="$(printf '%s' "$key_src" | cksum | tr -s ' \t' '--')"
state_file="$state_dir/crew-turn-budget.$key.$agent_type"

count=0 stage=0
if [ -f "$state_file" ]; then
  read -r count stage < "$state_file" 2>/dev/null || { count=0; stage=0; }
  case "$count" in *[!0-9]*|'') count=0 ;; esac
  case "$stage" in *[!0-9]*|'') stage=0 ;; esac
fi
count=$((count + 1))

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
