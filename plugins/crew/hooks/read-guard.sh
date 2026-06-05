#!/usr/bin/env bash
# Context-hygiene guard (not a security guard): blocks raw reads of very large
# files. It intentionally fails OPEN — if jq is missing or the path is absent /
# not a regular file, skip the check rather than block.
MAX_BYTES=65536
path="$(jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -z "$path" ] || [ ! -f "$path" ]; then
  exit 0
fi
size=$(wc -c < "$path" 2>/dev/null || echo 0)
if [ "$size" -gt "$MAX_BYTES" ]; then
  echo "Blocked: $path is ${size} bytes. Don't read it raw — grep/jq/script it and surface only what you need (see context-discipline)." >&2
  exit 2
fi
exit 0
