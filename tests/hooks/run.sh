#!/usr/bin/env bash
# Runs every plugin's hook suite — each plugins/<plugin>/tests/*.test.sh — printing
# a per-file summary and exiting non-zero if any file reports a failure. Discovery
# is by glob, so a new plugin's tests run as soon as they exist; nothing here or in
# CI needs updating to add one. Runnable locally and in CI:
#   bash tests/hooks/run.sh
# A single plugin's suite is just a narrower glob:
#   for t in plugins/keymaker/tests/*.test.sh; do bash "$t"; done
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

# nullglob so a no-match glob expands to nothing (not the literal pattern), then
# fail loudly if there are no tests — a silent zero-iteration loop would print
# "all passed" having run nothing.
shopt -s nullglob
tests=(plugins/*/tests/*.test.sh)
shopt -u nullglob
if [ "${#tests[@]}" -eq 0 ]; then
  echo "No plugins/*/tests/*.test.sh files found in $(pwd)" >&2
  exit 1
fi

# Every plugin that ships hooks must ship tests for them: a hooks/ directory with
# no suite beside it is exactly the gap this runner exists to make visible, and a
# glob-driven runner would otherwise report success for a plugin it never tested.
overall=0
shopt -s nullglob
for hooks_dir in plugins/*/hooks; do
  plugin_dir="${hooks_dir%/hooks}"
  suite=("$plugin_dir"/tests/*.test.sh)
  if [ "${#suite[@]}" -eq 0 ]; then
    echo "No tests for ${plugin_dir}'s hooks — add plugins/$(basename "$plugin_dir")/tests/*.test.sh" >&2
    overall=1
  fi
done
shopt -u nullglob

for t in "${tests[@]}"; do
  echo "== $t =="
  bash "$t" || overall=1
done

echo
if [ "$overall" -ne 0 ]; then
  echo "Hook tests FAILED." >&2
  exit 1
fi
echo "All hook tests passed."
