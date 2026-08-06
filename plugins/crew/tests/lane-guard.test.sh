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

# --- Marker detection when the stacks are unset --------------------------------
# With no CLAUDE.md, the guard walks the repo for markers to decide whether the
# extension regime can separate tank from trinity at all. A miss there fails
# silently — the same-language guard just doesn't fire — so the probe needs its
# own coverage rather than being inferred from the pinned-stack cases above.
# "detected a Node backend" appears only in the ambiguity message, so asserting
# on it distinguishes a real detection from the extension regime's own block.

node_react="$(make_tree 'package.json:{"dependencies":{"express":"^4","react":"^18"}}')"
assert_block "detected node backend + frontend → fail closed" \
  "$HOOK" "$(payload_file tank src/app.ts)" "detected a Node backend" "$node_react"

# Backend-only Node repo: tank owns the whole tree, trinity has no lane in it.
node_only="$(make_tree 'package.json:{"dependencies":{"fastify":"^4"}}')"
assert_allow "tank owns a detected backend-only Node repo" \
  "$HOOK" "$(payload_file tank src/app.ts)" "$node_only"
assert_block "trinity has no lane in a detected backend-only Node repo" \
  "$HOOK" "$(payload_file trinity src/app.ts)" "backend-only Node repo" "$node_only"

# The package.json scan is workspace-aware — a nested backend still counts.
workspace="$(make_tree \
  'package.json:{"private":true}' \
  'apps/api/package.json:{"dependencies":{"koa":"^2"}}' \
  'apps/web/package.json:{"dependencies":{"next":"^14"}}')"
assert_block "nested workspace backend + frontend → fail closed" \
  "$HOOK" "$(payload_file tank apps/api/server.ts)" "detected a Node backend" "$workspace"

# A frontend also registers from a bare JSX/TSX file, with no framework dep.
tsx_only="$(make_tree 'package.json:{"dependencies":{"hono":"^4"}}' 'src/App.tsx:export default null')"
assert_block "a TSX file alone counts as a frontend marker" \
  "$HOOK" "$(payload_file tank src/server.ts)" "detected a Node backend" "$tsx_only"

# A .NET project means extensions *can* tell the lanes apart, so the ambiguity
# guard must stay quiet even with a Node backend alongside it.
mixed="$(make_tree 'Api.csproj:<Project />' 'package.json:{"dependencies":{"express":"^4","react":"^18"}}')"
assert_block "dotnet present → extension regime denies tank a .tsx" \
  "$HOOK" "$(payload_file tank src/App.tsx)" "out of" "$mixed"
assert_allow "dotnet present → extension regime allows tank a .cs" \
  "$HOOK" "$(payload_file tank Api/Foo.cs)" "$mixed"

# One fixture per entry in the hook's framework allowlists: dropping an entry
# turns a silent detection gap into a failing assertion here.
for fw in @nestjs/core @nestjs/common express fastify koa @hapi/hapi hapi \
          @feathersjs/feathers restify @adonisjs/core hono elysia @trpc/server; do
  dir="$(make_tree "package.json:{\"dependencies\":{\"$fw\":\"^1\",\"react\":\"^18\"}}")"
  assert_block "backend framework '$fw' is detected" \
    "$HOOK" "$(payload_file tank src/app.ts)" "detected a Node backend" "$dir"
done

for fw in react react-dom next nuxt vue svelte @sveltejs/kit @angular/core \
          solid-js preact astro gatsby @remix-run/react react-router @builder.io/qwik; do
  dir="$(make_tree "package.json:{\"dependencies\":{\"express\":\"^4\",\"$fw\":\"^1\"}}")"
  assert_block "frontend framework '$fw' is detected" \
    "$HOOK" "$(payload_file tank src/app.ts)" "alongside a frontend" "$dir"
done

# --- Detection is cached per session_id ----------------------------------------
# The tree walk is the hook's one expensive step, so it runs once per session
# rather than once per Edit. Point TMPDIR at the fixture root first, so the cache
# file is torn down with it and can't collide with a previous run's.
TMPDIR="$(new_tmpdir)"
export TMPDIR

# payload_session <agent_type> <file_path> <session_id>
payload_session() {
  jq -nc --arg a "$1" --arg f "$2" --arg s "$3" \
    '{agent_type: $a, tool_input: {file_path: $f}, session_id: $s}'
}
sid="crew-lane-guard-test-$$"

assert_block "first call probes the tree and caches the verdict" \
  "$HOOK" "$(payload_session tank Foo.cs "$sid")" "detected a Node backend" "$node_react"
# Same session, an empty cwd with no markers of its own: still blocked, which is
# only possible from the cached verdict.
assert_block "the cached verdict is reused for the same session" \
  "$HOOK" "$(payload_session tank Foo.cs "$sid")" "detected a Node backend"
# A different session re-probes, so the empty cwd falls back to extensions and
# .cs is tank's own lane.
assert_allow "a different session re-probes instead of reusing the cache" \
  "$HOOK" "$(payload_session tank Foo.cs "$sid-other")"

finish
