#!/usr/bin/env bash
# Context-hygiene guard (not a security guard): blocks raw reads of very large
# files. It intentionally fails OPEN — if jq is missing or the path is absent /
# not a regular file, skip the check rather than block.
MAX_BYTES=65536
MAX_BOUNDED_LINES=2000
payload="$(cat)"
path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
if [ -z "$path" ] || [ ! -f "$path" ]; then
  exit 0
fi
# A Read with an explicit `limit` of at most MAX_BOUNDED_LINES lines is a
# bounded, targeted read — exactly the access context-discipline asks for — so
# it passes regardless of file size. A larger or non-numeric limit falls
# through to the size check: fail-open is for missing inputs, not for a bound
# the guard can't trust.
limit="$(printf '%s' "$payload" | jq -r '.tool_input.limit // empty' 2>/dev/null || true)"
case "$limit" in
  ''|*[!0-9]*) ;;
  *) if [ "$limit" -gt 0 ] && [ "$limit" -le "$MAX_BOUNDED_LINES" ]; then exit 0; fi ;;
esac
size=$(wc -c < "$path" 2>/dev/null || echo 0)
if [ "$size" -gt "$MAX_BYTES" ]; then
  echo "Blocked: $path is ${size} bytes. Don't read it raw — pass an explicit limit (<= ${MAX_BOUNDED_LINES} lines) for the slice you need, or grep/jq/script it and surface only the result (see context-discipline)." >&2
  exit 2
fi
exit 0
