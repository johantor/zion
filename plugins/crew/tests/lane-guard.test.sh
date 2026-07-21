#!/usr/bin/env bash
# Behavioral tests for hooks/lane-guard.sh.
# shellcheck source=plugins/crew/tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HOOK="lane-guard.sh"

# --- Default extension regime (no CLAUDE.md, stacks unresolved) ----------------
# In an empty cwd there are no markers, so tank/trinity fall back to file
# extensions: tank owns frontend-shaped files' opposite (backend), etc.
assert_block "tank denied a .tsx file"   "$HOOK" "$(payload_file tank Foo.tsx)"  "out of"
assert_allow "tank allowed a .cs file"   "$HOOK" "$(payload_file tank Foo.cs)"
assert_block "trinity denied a .cs file" "$HOOK" "$(payload_file trinity Foo.cs)" "out of"
assert_allow "trinity allowed a .tsx file" "$HOOK" "$(payload_file trinity Foo.tsx)"

# --- oracle / dozer confined to test paths ------------------------------------
assert_allow "oracle allowed a unit test"     "$HOOK" "$(payload_file oracle src/foo.test.ts)"
assert_block "oracle denied a non-test file"  "$HOOK" "$(payload_file oracle src/foo.ts)" "allowed paths"
assert_block "oracle denied an e2e spec (dozer's lane)" "$HOOK" "$(payload_file oracle e2e/foo.spec.ts)" "e2e lane"
assert_allow "dozer allowed an e2e spec"      "$HOOK" "$(payload_file dozer e2e/foo.spec.ts)"
assert_block "dozer denied a source file"     "$HOOK" "$(payload_file dozer src/foo.ts)" "allowed paths"

# --- Agents with no lane ------------------------------------------------------
assert_allow "seraph has no write lane restriction" "$HOOK" "$(payload_file seraph Foo.tsx)"
assert_allow "neo (express) is unrestricted"        "$HOOK" "$(payload_file neo Foo.tsx)"
assert_allow "no agent_type is unrestricted"        "$HOOK" "$(jq -nc --arg f Foo.tsx '{tool_input: {file_path: $f}}')"

# --- Same-language (Node) ambiguity: fail closed ------------------------------
node_fe="$(make_claude_md '- **Backend stack:** node
- **Frontend stack:** nextjs')"
assert_block "node backend + frontend, no lane paths → fail closed" \
  "$HOOK" "$(payload_file tank src/app.ts)" "can't tell them apart" "$node_fe"

# Both lane paths configured → route by directory, not extension.
both_lanes="$(make_claude_md '- **Backend stack:** node
- **Frontend stack:** nextjs
- **Backend lane path(s):** src/api
- **Frontend lane path(s):** src/web')"
assert_allow "tank allowed in its backend lane"  "$HOOK" "$(payload_file tank src/api/handler.ts)" "$both_lanes"
assert_block "tank denied in the frontend lane"  "$HOOK" "$(payload_file tank src/web/page.ts)" "out of" "$both_lanes"

# Only one lane path set → ambiguous → fail closed.
one_lane="$(make_claude_md '- **Backend stack:** node
- **Frontend stack:** nextjs
- **Backend lane path(s):** src/api')"
assert_block "only one lane path configured → fail closed" \
  "$HOOK" "$(payload_file tank src/api/handler.ts)" "only one of" "$one_lane"

finish
