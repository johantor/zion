#!/usr/bin/env bash
# Runs every *.test.sh in this directory, printing a per-file summary and exiting
# non-zero if any file reports a failure. Runnable locally and in CI:
#   bash plugins/crew/tests/run.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# nullglob so a no-match glob expands to nothing (not the literal pattern), then
# fail loudly if there are no tests — a silent zero-iteration loop would print
# "all passed" having run nothing.
shopt -s nullglob
tests=(./*.test.sh)
shopt -u nullglob
if [ "${#tests[@]}" -eq 0 ]; then
  echo "No *.test.sh files found in $(pwd)" >&2
  exit 1
fi

overall=0
for t in "${tests[@]}"; do
  echo "== ${t#./} =="
  bash "$t" || overall=1
done

echo
if [ "$overall" -ne 0 ]; then
  echo "Hook tests FAILED." >&2
  exit 1
fi
echo "All hook tests passed."
