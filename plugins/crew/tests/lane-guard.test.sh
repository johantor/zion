#!/usr/bin/env bash
# Behavioral tests for hooks/lane-guard.sh.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="lane-guard.sh"

# --- Default extension regime (no CLAUDE.md, stacks unresolved) ----------------
# In an empty cwd there are no markers, so tank/trinity fall back to file
# extensions: tank owns frontend-shaped files' opposite (backend), etc.
assert_block "tank denied a .tsx file"   "$HOOK" "$(payload_file tank Foo.tsx)"  "out of"
assert_allow "tank allowed a .cs file"   "$HOOK" "$(payload_file tank Foo.cs)"
assert_block "trinity denied a .cs file" "$HOOK" "$(payload_file trinity Foo.cs)" "out of"
assert_allow "trinity allowed a .tsx file" "$HOOK" "$(payload_file trinity Foo.tsx)"

# --- Extension regime, the non-.NET backend stacks -----------------------------
# Python/Go/Rust/Java extensions are disjoint from the frontend's, so they need
# no lane paths: trinity's deny list is the union of every backend's extensions,
# and tank is denied only frontend-shaped files. A miss here is silent in
# production -- the guard would pass and the lanes would simply stop separating.
for _f in svc.py svc.pyi pyproject.toml requirements.txt \
          svc.go go.mod go.sum \
          svc.rs Cargo.toml Cargo.lock \
          Svc.java pom.xml build.gradle build.gradle.kts; do
  assert_block "trinity denied a backend file ($_f)" "$HOOK" "$(payload_file trinity "$_f")" "out of"
  assert_allow "tank allowed a backend file ($_f)"   "$HOOK" "$(payload_file tank "$_f")"
done
# The union is per-extension, not per-resolved-stack: a pinned Python backend
# still denies trinity a .rs file. Pinning a stack must not widen trinity's lane.
fm_python="$(make_crew_md 'backendStack: python
frontendStack: react')"
assert_block "trinity denied .rs under a pinned python backend" \
  "$HOOK" "$(payload_file trinity svc.rs)" "out of" "$fm_python"
assert_allow "trinity still allowed a .tsx under a pinned python backend" \
  "$HOOK" "$(payload_file trinity Foo.tsx)" "$fm_python"

# --- oracle / dozer confined to test paths ------------------------------------
assert_allow "oracle allowed a unit test"     "$HOOK" "$(payload_file oracle src/foo.test.ts)"
assert_block "oracle denied a non-test file"  "$HOOK" "$(payload_file oracle src/foo.ts)" "allowed paths"
assert_block "oracle denied an e2e spec (dozer's lane)" "$HOOK" "$(payload_file oracle e2e/foo.spec.ts)" "e2e lane"
# oracle's allow list is the union of every ecosystem's test convention; without
# these it cannot write a test in any of the four new stacks at all.
for _t in pkg/test_svc.py pkg/svc_test.py pkg/conftest.py \
          pkg/svc_test.go \
          tests/integration.rs \
          src/test/java/com/example/SvcTest.java app/src/test/resources/fixture.sql; do
  assert_allow "oracle allowed a test path ($_t)" "$HOOK" "$(payload_file oracle "$_t")"
done
assert_allow "oracle allowed a JUnit IT class" "$HOOK" "$(payload_file oracle SvcIT.java)"
# Production code in the new stacks stays out of oracle's lane.
for _p in pkg/svc.py pkg/svc.go src/lib.rs src/main/java/com/example/Svc.java; do
  assert_block "oracle denied production code ($_p)" "$HOOK" "$(payload_file oracle "$_p")" "allowed paths"
done
assert_allow "dozer allowed an e2e spec"      "$HOOK" "$(payload_file dozer e2e/foo.spec.ts)"
assert_block "dozer denied a source file"     "$HOOK" "$(payload_file dozer src/foo.ts)" "allowed paths"

# --- Agents with no lane ------------------------------------------------------
assert_allow "seraph has no write lane restriction" "$HOOK" "$(payload_file seraph Foo.tsx)"
assert_allow "neo (express) is unrestricted"        "$HOOK" "$(payload_file neo Foo.tsx)"
assert_allow "no agent_type is unrestricted"        "$HOOK" "$(jq -nc --arg f Foo.tsx '{tool_input: {file_path: $f}}')"

# --- Same-language (Node) ambiguity, configured in .claude/crew.md ------------
# The current source of configuration: YAML frontmatter, one key per slot.
fm_node_fe="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: unset
frontendLanePaths: unset')"
assert_block "frontmatter: node backend + frontend, no lane paths → fail closed" \
  "$HOOK" "$(payload_file tank src/app.ts)" "can't tell them apart" "$fm_node_fe"

fm_both="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: src/web')"
assert_allow "frontmatter: tank allowed in its backend lane" \
  "$HOOK" "$(payload_file tank src/api/handler.ts)" "$fm_both"
assert_block "frontmatter: tank denied in the frontend lane" \
  "$HOOK" "$(payload_file tank src/web/page.ts)" "out of" "$fm_both"

fm_one="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: unset')"
assert_block "frontmatter: only one lane path configured → fail closed" \
  "$HOOK" "$(payload_file tank src/api/handler.ts)" "only one of" "$fm_one"

# A quoted YAML scalar is the same value. Left unstripped it would build the glob
# `"src/api"/**`, which matches nothing, so tank would be silently unconfined.
fm_quoted="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: "src/api"
frontendLanePaths: '"'"'src/web'"'"'')"
# A .cs path is the discriminator here and in the two cases below: the extension
# regime tank falls back to when a lane path is unreadable leaves .cs alone, so
# only a real lane blocks this. An unreadable lane path fails *open* — the glob
# matches nothing, which reads as no lane at all.
assert_block "frontmatter: quoted lane paths still confine tank" \
  "$HOOK" "$(payload_file tank src/web/page.cs)" "out of" "$fm_quoted"

# A YAML inline comment is not part of the value. /crew:init writes none, but the
# file is hand-editable and the legacy block had its own comment convention.
fm_comment="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api # the service
frontendLanePaths: "src/web" # the app')"
assert_block "frontmatter: an inline comment is not part of the lane path" \
  "$HOOK" "$(payload_file tank src/web/page.cs)" "out of" "$fm_comment"

# ...but a `#` with no whitespace before it is an ordinary scalar character, so
# the comment scan must anchor on the space rather than on the first `#`.
fm_hash="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api#2
frontendLanePaths: src/web#2')"
assert_block "frontmatter: a bare # stays part of the lane path" \
  "$HOOK" "$(payload_file tank 'src/web#2/page.cs')" "out of" "$fm_hash"

# Every slot at its `unset` placeholder is not configuration: the guard must fall
# through to marker detection, not treat "unset" as a stack or a lane path.
fm_unset="$(make_crew_md 'backendStack: unset
frontendStack: unset
backendLanePaths: unset
frontendLanePaths: unset')"
assert_block "frontmatter: unset placeholders fall through to extensions" \
  "$HOOK" "$(payload_file tank Foo.tsx)" "out of" "$fm_unset"
assert_allow "frontmatter: unset placeholders leave tank its own extensions" \
  "$HOOK" "$(payload_file tank Foo.cs)" "$fm_unset"

# The body below the frontmatter is free prose and may quote an example block —
# /crew:init's own §1 does. A key matched there is not configuration.
fm_body="$(make_crew_md 'backendStack: unset
frontendStack: unset
backendLanePaths: unset
frontendLanePaths: unset' 'An example of what this file can hold:

```markdown
backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: src/web
```')"
# Again .cs: a leaked frontendLanePaths would put src/web out of tank's reach,
# while the extension regime the unset slots really mean leaves .cs to tank.
assert_allow "frontmatter: a slot quoted in the body is not read" \
  "$HOOK" "$(payload_file tank src/web/handler.cs)" "$fm_body"

# dozer: playwright widens to tests/**, and the frontend lane confines it there.
fm_dozer="$(make_crew_md 'frontendE2eTool: playwright
frontendLanePaths: apps/web')"
assert_allow "frontmatter: dozer allowed an e2e spec inside its frontend lane" \
  "$HOOK" "$(payload_file dozer apps/web/tests/checkout.spec.ts)" "$fm_dozer"
assert_block "frontmatter: dozer denied an e2e spec outside its frontend lane" \
  "$HOOK" "$(payload_file dozer apps/api/tests/checkout.spec.ts)" "outside" "$fm_dozer"

# --- Same-language (Node) ambiguity, legacy CLAUDE.md block -------------------
# Configuration written by an earlier /crew:init, before #198 moved the slots.
# Still read when .claude/crew.md is absent, so an unmigrated project is unaffected.
node_fe="$(make_claude_md '- **Backend stack:** node
- **Frontend stack:** nextjs')"
assert_block "legacy: node backend + frontend, no lane paths → fail closed" \
  "$HOOK" "$(payload_file tank src/app.ts)" "can't tell them apart" "$node_fe"

# Both lane paths configured → route by directory, not extension.
both_lanes="$(make_claude_md '- **Backend stack:** node
- **Frontend stack:** nextjs
- **Backend lane path(s):** src/api
- **Frontend lane path(s):** src/web')"
assert_allow "legacy: tank allowed in its backend lane" "$HOOK" "$(payload_file tank src/api/handler.ts)" "$both_lanes"
assert_block "legacy: tank denied in the frontend lane" "$HOOK" "$(payload_file tank src/web/page.ts)" "out of" "$both_lanes"

# Only one lane path set → ambiguous → fail closed.
one_lane="$(make_claude_md '- **Backend stack:** node
- **Frontend stack:** nextjs
- **Backend lane path(s):** src/api')"
assert_block "legacy: only one lane path configured → fail closed" \
  "$HOOK" "$(payload_file tank src/api/handler.ts)" "only one of" "$one_lane"

# --- Precedence: .claude/crew.md wins over a stale legacy block ----------------
# Migration removes the CLAUDE.md block, but a project can carry both — a partial
# migration, or a branch that restored the old file. The lanes must come from the
# file /crew:init writes, so the two fixtures below swap src/api and src/web.
both_files="$(make_crew_md 'backendStack: node
frontendStack: nextjs
backendLanePaths: src/api
frontendLanePaths: src/web')"
printf '%s\n' '- **Backend stack:** node
- **Frontend stack:** nextjs
- **Backend lane path(s):** src/web
- **Frontend lane path(s):** src/api' > "$both_files/CLAUDE.md"
assert_allow "frontmatter wins over a stale legacy block" \
  "$HOOK" "$(payload_file tank src/api/handler.ts)" "$both_files"
assert_block "the stale legacy block does not widen tank's lane" \
  "$HOOK" "$(payload_file tank src/web/page.ts)" "out of" "$both_files"

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
