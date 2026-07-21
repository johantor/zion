#!/usr/bin/env bash
# Runs every *.test.sh in this directory, printing a per-file summary and exiting
# non-zero if any file reports a failure. Runnable locally and in CI:
#   bash plugins/crew/tests/run.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

overall=0
for t in ./*.test.sh; do
  echo "== ${t#./} =="
  bash "$t" || overall=1
done

echo
if [ "$overall" -ne 0 ]; then
  echo "Hook tests FAILED." >&2
  exit 1
fi
echo "All hook tests passed."
