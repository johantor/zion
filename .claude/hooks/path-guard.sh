#!/usr/bin/env bash
mode="$1"
shift
patterns="$*"
path="$(jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -z "$path" ] && exit 0
match=0
for g in $patterns; do
  case "$path" in
    $g) match=1 ;;
  esac
done
if [ "$mode" = "--deny" ] && [ "$match" = 1 ]; then
  echo "Blocked: $path is out of this agent's lane." >&2
  exit 2
fi
if [ "$mode" = "--allow" ] && [ "$match" = 0 ]; then
  echo "Blocked: $path is outside the allowed paths." >&2
  exit 2
fi
exit 0
