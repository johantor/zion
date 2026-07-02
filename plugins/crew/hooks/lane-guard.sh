#!/usr/bin/env bash
# Per-agent file-write lane enforcement for PreToolUse(Edit|Write). Routes on the
# `agent_type` the harness adds to the payload; plugin agents can't carry their
# own hooks, so the lanes are centralized here.
#
# Directory-based lanes (CLAUDE.md path config) apply when set; otherwise falls
# back to extension-based globs. A same-language pair (node backend + node/JS
# frontend) with no lane paths fails closed — extensions alone can't tell tank's
# and trinity's files apart there. That case is recognized whether the stacks are
# pinned in CLAUDE.md or left unset (morpheus resolves them via memory/detection):
# when unset, the guard probes the repo's markers (server framework in
# package.json, .NET project files) to decide. Backend-only Node repos (no frontend
# lane) skip enforcement since there's no same-language conflict to resolve.

# Fail closed: a guard that can't read its input must block, not allow.
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: lane-guard needs jq to enforce write lanes." >&2
  exit 2
fi
payload="$(cat)"
if ! printf '%s' "$payload" | jq empty >/dev/null 2>&1; then
  echo "Blocked: lane-guard could not parse the hook payload." >&2
  exit 2
fi
agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // empty')"
path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
[ -z "$path" ] && exit 0

# Read a Crew-configuration slot's value from CLAUDE.md (plain text after the bold
# label, up to the em-dash). Missing file, missing slot, or the *unset*/none
# placeholders all mean "not configured" -> empty string.
config_slot() {
  [ -f CLAUDE.md ] || return 0
  v="$(sed -n "s/^- \*\*$1:\*\* *\([^—]*\).*/\1/p" CLAUDE.md | head -1 | sed 's/[[:space:]]*$//')"
  case "$v" in
    # Treat *unset*, empty, and any value starting with "none" (e.g.
    # "none (no e2e suite detected)") as not configured.
    '*unset*'|none|none[!A-Za-z0-9]*|'') return 0 ;;
    *) printf '%s' "$v" ;;
  esac
}

# Comma-separated path config -> space-separated "<path>/**" globs. Split on
# commas via IFS (not command substitution, which would word-split and, worse,
# glob-expand a value containing * ? [ against the filesystem), with glob
# expansion disabled and surrounding whitespace trimmed off each entry.
lane_globs() {
  local IFS=','
  set -f
  for p in $1; do
    p="${p#"${p%%[![:space:]]*}"}"   # trim leading whitespace
    p="${p%"${p##*[![:space:]]}"}"   # trim trailing whitespace
    [ -z "$p" ] && continue
    case "$p" in */) printf '%s** ' "$p" ;; *) printf '%s/** ' "$p" ;; esac
  done
  set +f
}

# Marker detection — used only when the stack slots are *unset* (morpheus can
# resolve stacks from memory/detection without pinning them in CLAUDE.md) and no
# lane paths are configured. The extension regime is only safe for disjoint
# languages (a .NET backend's `.cs` vs a web frontend's `.ts`); a Node backend
# makes extensions ambiguous because tank's own source is `.ts`/`.js` too. These
# probes let the guard recognize that case from the repo instead of silently
# applying the wrong regime. All are cheap and short-circuit; node_modules is
# pruned so a large tree doesn't slow the hook.
has_dotnet_backend() {
  find . -type d -name node_modules -prune -o \
         \( -name '*.csproj' -o -name '*.sln' \) -print 2>/dev/null | grep -q .
}
has_node_backend() {
  # Scan every package.json (not just the repo root) so a workspace/monorepo
  # backend under e.g. apps/api/package.json is still detected.
  while IFS= read -r pj; do
    grep -Eq '"(@nestjs/core|@nestjs/common|express|fastify|koa|@hapi/hapi|hapi|@feathersjs/feathers|restify|@adonisjs/core)"[[:space:]]*:' "$pj" && return 0
  done < <(find . -type d -name node_modules -prune -o -name package.json -print 2>/dev/null)
  return 1
}
has_frontend() {
  # Same workspace-aware scan for a frontend dep in any package.json...
  while IFS= read -r pj; do
    grep -Eq '"(react|react-dom|next|vue|svelte|@sveltejs/kit|@angular/core|solid-js|preact|astro)"[[:space:]]*:' "$pj" && return 0
  done < <(find . -type d -name node_modules -prune -o -name package.json -print 2>/dev/null)
  # ...or any JSX/TSX file anywhere in the tree.
  find . -type d -name node_modules -prune -o \
         \( -name '*.tsx' -o -name '*.jsx' \) -print 2>/dev/null | grep -q .
}

# agent_type -> mode + space-separated glob patterns (+ optional exempt patterns
# that bypass a deny before it's evaluated, confine patterns an --allow path must
# also be inside, and exclude patterns that deny an --allow path even if it matches).
exempt=""
confine=""
exclude=""
case "$agent_type" in
  # Backend patterns (.NET style) first, then shared/frontend test file patterns.
  # `.spec.*` is kept (Vitest/Jest/Angular unit tests use it), but oracle is
  # excluded from the e2e-tool directories, which are dozer's — otherwise a
  # Playwright `e2e/foo.spec.ts` would fall in oracle's lane too.
  oracle) mode="--allow"
          patterns='**/*Tests/** **/*.Tests.* tests/** **/__tests__/** **/*.test.* **/*.spec.*'
          exclude='e2e/** cypress/** playwright/** tests/e2e/**' ;;
  dozer)
    # Scope to the resolved e2e tool's conventional locations rather than a blanket
    # tests/** that would grant write access to backend/unit tests. Cypress keeps to
    # cypress/ + *.cy.* files. Playwright's default testDir is tests/ or e2e/, but a
    # bare tests/** also matches nested backend test dirs and overlaps oracle — so it
    # is only widened to tests/** when a Frontend lane path is configured (the confine
    # below then keeps it in-lane); otherwise it is restricted to structured e2e
    # locations. The broad fallback applies only when the tool is unset/unknown.
    mode="--allow"
    frontend_lane="$(config_slot 'Frontend lane path(s)')"
    case "$(config_slot 'Frontend e2e tool')" in
      cypress)    patterns='cypress/** **/*.cy.*' ;;
      playwright)
        if [ -n "$frontend_lane" ]; then
          patterns='e2e/** playwright/** tests/**'
        else
          patterns='e2e/** playwright/** tests/e2e/**'
        fi
        ;;
      *)          patterns='cypress/** e2e/** tests/** playwright/** **/*.cy.*' ;;
    esac
    # In a same-language monorepo a bare tests/** can match backend tests
    # (e.g. apps/api/tests/**). When a Frontend lane path is configured,
    # additionally confine dozer to it, so an e2e-shaped path that lives
    # outside the frontend lane is still denied.
    [ -n "$frontend_lane" ] && confine="$(lane_globs "$frontend_lane")"
    ;;
  # neo is the express-lane generalist — small changes across any lane — so it has
  # no lane restriction by design. Explicit here (rather than falling through to the
  # default) to document that all-lane access is intentional, not an oversight.
  neo)     exit 0 ;;
  tank|trinity)
    backend_lane="$(config_slot 'Backend lane path(s)')"
    frontend_lane="$(config_slot 'Frontend lane path(s)')"
    backend_stack="$(config_slot 'Backend stack')"
    frontend_stack="$(config_slot 'Frontend stack')"
    if [ -n "$backend_lane" ] && [ -n "$frontend_lane" ]; then
      # Route handlers live in the frontend tree but are tank's by concern
      # (single-owner, unlike Razor's markup/logic split) — exempt tank, deny trinity.
      route_handlers='app/**/route.ts app/**/route.js pages/api/**'
      mode="--deny"
      if [ "$agent_type" = "tank" ]; then
        patterns="$(lane_globs "$frontend_lane")"
        exempt="$route_handlers"
      else
        patterns="$(lane_globs "$backend_lane") $route_handlers"
      fi
    elif [ -n "$backend_lane" ] || [ -n "$frontend_lane" ]; then
      # Partial config: one lane path is set but not both. Fail closed rather
      # than silently falling back to the extension regime, which can't reliably
      # separate tank from trinity in same-language stacks.
      echo "Blocked: only one of Backend lane path(s) / Frontend lane path(s) is configured. Set both in CLAUDE.md (see /crew:init) before delegating." >&2
      exit 2
    elif [ "$backend_stack" = "node" ] && [ -n "$frontend_stack" ]; then
      echo "Blocked: backend stack is node — tank and trinity can both touch .ts/.js files, so extension-based lanes can't tell them apart. Set Backend lane path(s) / Frontend lane path(s) in CLAUDE.md (see /crew:init) before delegating." >&2
      exit 2
    elif [ "$backend_stack" = "node" ]; then
      # Backend-only Node repo (no Frontend stack configured). tank owns the whole
      # Node codebase, so it writes freely; trinity is the frontend implementer with
      # no frontend lane to scope to here, so it fails closed rather than getting
      # unrestricted access.
      [ "$agent_type" = "tank" ] && exit 0
      echo "Blocked: backend stack is node with no frontend configured — trinity has no frontend lane here. Set a Frontend stack / Frontend lane path(s) in CLAUDE.md (see /crew:init) before delegating frontend work." >&2
      exit 2
    elif [ -z "$backend_stack" ] && has_node_backend && ! has_dotnet_backend; then
      # Stacks unset (resolved via morpheus's memory/detection, not pinned) but the
      # repo's markers show a Node backend and no .NET project. The extension regime
      # can't separate tank's `.ts`/`.js` from trinity's, so mirror the pinned
      # `Backend stack: node` behavior.
      if has_frontend; then
        # Node backend + a frontend, no lane paths: genuinely ambiguous — fail closed.
        echo "Blocked: detected a Node backend (server framework in package.json) alongside a frontend, with no lane paths configured — extension-based lanes can't tell tank's and trinity's .ts/.js apart. Set Backend lane path(s) / Frontend lane path(s) in CLAUDE.md (see /crew:init), or pin Backend stack / Frontend stack, before delegating." >&2
        exit 2
      fi
      # Backend-only Node repo: tank owns it, trinity has no frontend lane here.
      [ "$agent_type" = "tank" ] && exit 0
      echo "Blocked: detected a backend-only Node repo — trinity has no frontend lane here. Set a Frontend stack / Frontend lane path(s) in CLAUDE.md (see /crew:init) before delegating frontend work." >&2
      exit 2
    else
      # Extension-based regime (default) — unchanged from before same-language
      # stacks existed. Note: .cshtml is intentionally NOT denied to either tank
      # or trinity. Razor is shared by concern (trinity = markup/DOM in
      # server-rendered mode, tank = C#/server logic), and the mode/concern split
      # is enforced by the agent prompts, not here — file globs can't see inside
      # a file.
      mode="--deny"
      if [ "$agent_type" = "tank" ]; then
        patterns='*.ts *.tsx *.jsx *.js *.mjs *.scss *.css *.html'
      else
        patterns='*.cs *.csproj'
      fi
    fi
    ;;
  # seraph is a read-only reviewer with no edit/write tools, so it never reaches
  # this Edit|Write hook — no lane entry needed.
  *) exit 0 ;;  # main session or any agent without a lane: no restriction
esac

# True if $path matches any glob in $1 (space-separated). set -f keeps patterns
# literal for [[ ]] instead of expanding them against the filesystem. The */
# prefix lets repo-relative patterns (tests/**) match an absolute file_path; the
# ./ prefix lets **/-anchored patterns (**/*Tests/**) match a repo-relative
# file_path (** needs a leading component to consume); in [[ ]] a single *
# already spans '/'.
matches() {
  set -f
  for g in $1; do
    # shellcheck disable=SC2053
    if [[ "$path" == $g || "$path" == */$g || "./$path" == $g ]]; then
      set +f
      return 0
    fi
  done
  set +f
  return 1
}

if [ -n "$exempt" ] && matches "$exempt"; then
  exit 0
fi

if matches "$patterns"; then match=1; else match=0; fi

# An --allow agent with an exclude set is denied a path that matches it even when
# it also matches the allow patterns — used to keep oracle's test globs out of the
# e2e-tool directories, which are dozer's lane.
if [ "$mode" = "--allow" ] && [ -n "$exclude" ] && matches "$exclude"; then
  echo "Blocked: $path is in an e2e lane (dozer's), not ${agent_type}'s." >&2
  exit 2
fi

# An --allow agent with a confine set must ALSO be inside the confine globs —
# used to keep dozer's e2e patterns within the configured frontend lane so a
# tests/** match in a backend lane (same-language monorepo) is still denied.
if [ "$mode" = "--allow" ] && [ -n "$confine" ] && ! matches "$confine"; then
  echo "Blocked: $path is outside ${agent_type}'s frontend lane." >&2
  exit 2
fi

if [ "$mode" = "--deny" ] && [ "$match" = 1 ]; then
  echo "Blocked: $path is out of ${agent_type}'s lane." >&2
  exit 2
fi
if [ "$mode" = "--allow" ] && [ "$match" = 0 ]; then
  echo "Blocked: $path is outside ${agent_type}'s allowed paths." >&2
  exit 2
fi
exit 0
