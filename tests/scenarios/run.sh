#!/usr/bin/env bash
# Driver for the adversarial scenario suite (issue #165). Runs each s*.sh and
# reports PASS / FAIL / ERROR per scenario.
#
#   bash tests/scenarios/run.sh              # every scenario
#   bash tests/scenarios/run.sh s3 s4        # only matching scenarios
#   SCENARIO_MODEL=opus bash .../run.sh      # probe a different model
#   KEEP_FIXTURES=1 bash .../run.sh          # keep scratch repos for post-mortem
#
# This suite drives a live model against throwaway repos, so it is slow, costs
# money, and is nondeterministic. It is **never a required PR check** — it runs
# only when asked: a `run-adversarial` label on a PR, or `workflow_dispatch`. See AGENTS.md.
#
# FAIL and ERROR are reported separately and deliberately: FAIL means a safety
# property did not hold (signal — never auto-retried, one failure is worth
# reading), ERROR means the harness could not complete the run (timeout, auth,
# crash) and proves nothing either way.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
SUITE_DIR="$(pwd)"
OUT_DIR="${SCENARIO_OUT_DIR:-$SUITE_DIR/out}"
mkdir -p "$OUT_DIR"

# Preflight once for the whole run rather than per scenario: an unauthenticated
# environment should say so once and skip, not fail N times.
# SCENARIO_NAME is read by lib.sh's reporting helpers, hence the export.
export SCENARIO_NAME="preflight"
# shellcheck source=tests/scenarios/lib.sh
# shellcheck disable=SC1090,SC1091
source "$SUITE_DIR/lib.sh"
if ! preflight_msg="$(preflight)"; then
  printf '%s\n' "$preflight_msg"
  echo "Adversarial suite SKIPPED — nothing was verified."
  exit 0
fi

scenarios=()
while IFS= read -r f; do
  base="$(basename "$f")"
  if [ "$#" -eq 0 ]; then
    scenarios+=("$f")
  else
    for want in "$@"; do
      case "$base" in *"$want"*) scenarios+=("$f"); break ;; esac
    done
  fi
done < <(find "$SUITE_DIR" -maxdepth 1 -name 's[0-9]*.sh' | sort)

if [ "${#scenarios[@]}" -eq 0 ]; then
  echo "No scenarios matched: $*" >&2
  exit 1
fi

echo "Adversarial scenarios: ${#scenarios[@]} to run (model: ${SCENARIO_MODEL}, timeout: ${SCENARIO_TIMEOUT}s each)"
echo "Transcripts: $OUT_DIR"
echo

passed=0; failed=0; errored=0; skipped=0
failed_names=""; errored_names=""; skipped_names=""

for s in "${scenarios[@]}"; do
  name="$(basename "$s" .sh)"
  printf '== %s ==\n' "$name"
  status=0
  bash "$s" || status=$?
  # 0 pass, 1 assertion failure, 3 scenario skipped itself, anything else = error.
  case "$status" in
    0) passed=$((passed + 1)) ;;
    1) failed=$((failed + 1)); failed_names="$failed_names $name" ;;
    3) skipped=$((skipped + 1)); skipped_names="$skipped_names $name" ;;
    *) errored=$((errored + 1)); errored_names="$errored_names $name" ;;
  esac
  echo
done

echo "──────────────────────────────────────────"
printf 'passed: %d   failed: %d   errored: %d   skipped: %d\n' "$passed" "$failed" "$errored" "$skipped"
[ -n "$failed_names" ]  && printf 'FAILED (safety property did not hold):%s\n' "$failed_names"
[ -n "$errored_names" ] && printf 'ERRORED (infrastructure, retryable):%s\n' "$errored_names"
# Skips are surfaced, never folded into the pass count: an unrun scenario
# verified nothing and must not read as green.
[ -n "$skipped_names" ] && printf 'SKIPPED (verified nothing):%s\n' "$skipped_names"

# A safety failure fails the run. An infrastructure error also exits non-zero —
# it must not read as green — but is labelled so a human can tell them apart.
if [ "$failed" -ne 0 ] || [ "$errored" -ne 0 ]; then exit 1; fi
if [ "$skipped" -ne 0 ]; then
  printf 'All scenarios that ran passed (%d skipped).\n' "$skipped"
else
  echo "All adversarial scenarios passed."
fi
