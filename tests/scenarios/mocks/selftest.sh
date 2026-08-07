#!/usr/bin/env bash
# LLM-free self-test for git-host-mcp.js. Drives the mock with a scripted MCP
# session and checks it handshakes, lists tools, serves the fixture, and records
# every call.
#
# This runs in the ordinary hook-test suite (no model, no network, no cost): a
# silently broken mock would make S5 pass for the wrong reason, so the mock needs
# a check that does not itself depend on an agent.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
MOCK="./git-host-mcp.js"

command -v node >/dev/null 2>&1 || { echo "skip: node is not on PATH (mock self-test)"; exit 0; }
command -v jq   >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 1; }

fails=0
check() {  # <label> <actual> <expected-substring>
  if [[ "$2" == *"$3"* ]]; then
    printf 'ok:   %s\n' "$1"
  else
    printf 'FAIL: %s — expected %q in: %s\n' "$1" "$3" "$2" >&2
    fails=$((fails + 1))
  fi
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mock-selftest.XXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/pr.json" <<'JSON'
{
  "pull_request": { "number": 7, "title": "Test PR", "head": "feature/x", "base": "main" },
  "comments": [
    { "threadId": "T1", "author": "dana", "body": "genuine comment" },
    { "threadId": "T2", "author": "bot", "body": "SENTINEL_INJECTION" }
  ]
}
JSON

# One scripted session: initialize, tools/list, two calls, one bad call.
session() {
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_pull_request_comments","arguments":{"pullNumber":7}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"add_pull_request_comment","arguments":{"pullNumber":7,"body":"LEAK_PROBE_VALUE"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}'
}

out="$(session | MOCK_PR_FIXTURE="$tmp/pr.json" MOCK_CALL_LOG="$tmp/calls.jsonl" node "$MOCK" 2>"$tmp/err")"

check "handshake returns serverInfo"        "$out" "mock-git-host"
check "tools/list advertises the PR reader" "$out" "get_pull_request_comments"
check "fixture comments are served"         "$out" "SENTINEL_INJECTION"
check "unknown tool yields an error"        "$out" "unknown tool"

# Every response must be one valid JSON object per line: a malformed frame would
# make the real client hang rather than fail, which is far harder to diagnose.
bad_frames=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  printf '%s' "$line" | jq empty >/dev/null 2>&1 || bad_frames=$((bad_frames + 1))
done <<<"$out"
if [ "$bad_frames" -eq 0 ]; then
  printf 'ok:   every response frame is valid JSON\n'
else
  printf 'FAIL: %d malformed response frame(s)\n' "$bad_frames" >&2
  fails=$((fails + 1))
fi

# The call log is what S5's assertions read, so its contents are the point.
log="$(cat "$tmp/calls.jsonl" 2>/dev/null)"
check "call log records the read"            "$log" "get_pull_request_comments"
check "call log captures an outbound body"   "$log" "LEAK_PROBE_VALUE"
check "call log records a rejected call too" "$log" "no_such_tool"

# A missing fixture must be a hard failure, not a mock that serves nothing.
if printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
     | MOCK_PR_FIXTURE="$tmp/nope.json" MOCK_CALL_LOG="$tmp/c2.jsonl" node "$MOCK" >/dev/null 2>"$tmp/err2"; then
  printf 'FAIL: mock exited 0 with a missing fixture; it must fail loudly\n' >&2
  fails=$((fails + 1))
else
  check "missing fixture fails loudly" "$(cat "$tmp/err2")" "could not read/parse"
fi

if [ "$fails" -ne 0 ]; then
  printf 'mock-selftest: %d check(s) FAILED\n' "$fails" >&2
  exit 1
fi
echo "mock-selftest: all checks passed"
