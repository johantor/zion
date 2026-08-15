#!/usr/bin/env bash
# Behavior tests for turn-budget.sh — the PostToolUse advisor that counts an
# agent's tool calls against its turn budget and warns at 75% and 90%. Unlike
# the guards, this hook is stateful by design (a per-instance counter file);
# the tests drive it through the CREW_TURN_BUDGET_DIR override so state lives
# under the fixture root. It is also advisory: every can't-count path must fail
# OPEN (exit 0), the opposite polarity of the fail-closed guards.
# shellcheck source=plugins/crew/tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# payload_post <agent_type> <transcript_path>  — minimal PostToolUse payload.
# Pass "" to omit a field (jq drops empty strings via the alternative below).
payload_post() {
  jq -nc --arg a "$1" --arg t "$2" \
    '{tool_name: "Read"}
     + (if $a != "" then {agent_type: $a} else {} end)
     + (if $t != "" then {transcript_path: $t} else {} end)'
}

# call_n <n> <agent_type> <transcript_path> — run the hook n times, keeping
# only the last call's _status/_stderr (drives the counter to a chosen value).
call_n() {
  local n="$1" i
  for ((i = 0; i < n; i++)); do
    run_hook turn-budget.sh "$(payload_post "$2" "$3")"
  done
}

# assert_quiet <label> <payload> — a silent call must be exit 0 AND say nothing:
# a regression that still prints a warning but exits 0 must fail here, so this
# is stricter than assert_allow (which only checks the exit code).
assert_quiet() {
  run_hook turn-budget.sh "$2"
  if [ "$_status" -eq 0 ] && [ -z "$_stderr" ]; then
    _pass
  else
    _fail "$1: expected exit 0 with no stderr, got exit $_status${_stderr:+ — stderr: $_stderr}"
  fi
}

CREW_TURN_BUDGET_DIR="$(new_tmpdir)"
export CREW_TURN_BUDGET_DIR

# --- Thresholds (seraph: budget 40 -> wind-down at 30, stop at 36) -------------
# Keyed to seraph's `maxTurns`, which validator §8 keeps in lockstep with the
# hook's table — a budget change lands here too, or these thresholds go stale.
# Calls 1-29: silent.
call_n 29 seraph /tmp/t/seraph-a.jsonl
if [ "$_status" -eq 0 ] && [ -z "$_stderr" ]; then _pass; else _fail "silent below 75%: expected exit 0 with no stderr, got exit $_status — $_stderr"; fi
# Call 30 (75%): wind-down warning, once.
assert_block "wind-down warning at 75%" turn-budget.sh "$(payload_post seraph /tmp/t/seraph-a.jsonl)" "Turn budget: ~30/40"
# Calls 31-35: silent again — the 75% warning fires exactly once. Asserted per
# call, not in bulk: a regression that re-fires the warning mid-window has to
# fail here, and call_n keeps only the last call's status.
for _n in 31 32 33 34 35; do
  assert_quiet "call $_n silent between the 75% and 90% thresholds" "$(payload_post seraph /tmp/t/seraph-a.jsonl)"
done
# Call 36 (90%): stop-now warning, once; 37+: silent.
assert_block "stop-now warning at 90%" turn-budget.sh "$(payload_post seraph /tmp/t/seraph-a.jsonl)" "Stop now"
assert_quiet "call 37 silent after the 90% warning fired once" "$(payload_post seraph /tmp/t/seraph-a.jsonl)"

# --- Instance isolation: a different transcript keeps its own counter ----------
assert_quiet "fresh transcript starts a fresh counter" "$(payload_post seraph /tmp/t/seraph-b.jsonl)"

# --- Fail-open paths ------------------------------------------------------------
assert_allow "no agent_type (user session) is never warned" turn-budget.sh "$(payload_post "" /tmp/t/user.jsonl)"
assert_allow "unknown agent_type (other plugin) is never warned" turn-budget.sh "$(payload_post keymaker /tmp/t/km.jsonl)"
assert_allow "no transcript/session key -> fail open" turn-budget.sh "$(payload_post seraph "")"
assert_allow "unparseable payload -> fail open" turn-budget.sh 'not json'
# No state may be written for non-crew sessions (the two allow-cases above).
found=""
for f in "$CREW_TURN_BUDGET_DIR"/crew-turn-budget.*.keymaker; do [ -e "$f" ] && found="$f"; done
if [ -n "$found" ]; then _fail "state file written for an unknown agent_type"; else _pass; fi

# --- Corrupt counter state is treated as fresh, not a crash ---------------------
corrupt="$CREW_TURN_BUDGET_DIR/corrupt-probe.jsonl"
run_hook turn-budget.sh "$(payload_post tank "$corrupt")"
state_file=""
for f in "$CREW_TURN_BUDGET_DIR"/crew-turn-budget.*.tank; do [ -e "$f" ] && state_file="$f"; done
if [ -n "$state_file" ]; then _pass; else _fail "expected a tank state file after one counted call"; fi
printf 'garbage not-a-number\n' > "$state_file"
assert_allow "corrupt state resets cleanly" turn-budget.sh "$(payload_post tank "$corrupt")"
if [ -n "$state_file" ] && read -r c s < "$state_file" && [ "$c" = "1" ] && [ "$s" = "0" ]; then
  _pass
else
  _fail "corrupt state should restart the counter at '1 0', got '${c:-?} ${s:-?}'"
fi

# --- Unwritable state dir -> fail open ------------------------------------------
ro_dir="$(new_tmpdir)"
chmod a-w "$ro_dir"
if [ -w "$ro_dir" ]; then
  # Running as root (some CI containers): the dir stays writable, so this path
  # can't be exercised here — skip rather than assert what the environment
  # can't set up.
  chmod u+w "$ro_dir"
else
  _status=0
  printf '%s' "$(payload_post seraph /tmp/t/ro.jsonl)" \
    | ( cd "$(new_tmpdir)" && CREW_TURN_BUDGET_DIR="$ro_dir" exec "$HOOKS_DIR/turn-budget.sh" ) 2>/dev/null || _status=$?
  if [ "$_status" -eq 0 ]; then _pass; else _fail "unwritable state dir should fail open, got exit $_status"; fi
  chmod u+w "$ro_dir"
fi

finish
