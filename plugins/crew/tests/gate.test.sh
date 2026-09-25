#!/usr/bin/env bash
# Behavior tests for scripts/gate.sh, the review-gate runner (#245): start runs
# the command detached and records its exit code and log, poll reports that code,
# stop kills the whole process group, and a reused or malformed <id> is refused.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
GATE="$(dirname "${BASH_SOURCE[0]}")/../scripts/gate.sh"

# Ids are unique per run so parallel suites never share a /tmp directory.
id="t-$$-$RANDOM"; id2="${id}-b"
trap 'rm -rf "/tmp/crew-gate-$id" "/tmp/crew-gate-$id2"' EXIT

check() {  # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then _pass; else _fail "$1: expected [$2], got [$3]"; fi
}

check "start prints the gate dir" "/tmp/crew-gate-$id" "$(bash "$GATE" start "$id" 'echo built; exit 4')"
check "poll reports the command's exit code" "4" "$(bash "$GATE" poll "$id")"
check "the log holds the command's output" "built" "$(grep -o built "/tmp/crew-gate-$id/log")"

bash "$GATE" start "$id" 'true' >/dev/null 2>&1
check "a reused id is refused" "3" "$?"
bash "$GATE" start 'Bad_Id' 'true' >/dev/null 2>&1
check "a malformed id is refused" "2" "$?"
bash "$GATE" poll "$id-missing" >/dev/null 2>&1
check "polling an unknown gate fails" "3" "$?"

# A command that starts children: stop must take the whole group down.
bash "$GATE" start "$id2" 'sleep 300 & sleep 300' >/dev/null
check "stop kills the process group" "stopped" "$(bash "$GATE" stop "$id2")"

finish
