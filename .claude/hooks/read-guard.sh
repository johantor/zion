#!/usr/bin/env bash
MAX_BYTES=65536
path="$(jq -r '.tool_input.file_path // empty')"
[ -z "$path" ] || [ ! -f "$path" ] && exit 0
size=$(wc -c < "$path" 2>/dev/null || echo 0)
if [ "$size" -gt "$MAX_BYTES" ]; then
  echo "Blocked: $path is ${size} bytes. Don't read it raw — grep/jq/script it and surface only what you need (see context-discipline)." >&2
  exit 2
fi
exit 0
