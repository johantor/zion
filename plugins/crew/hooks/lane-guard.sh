#!/usr/bin/env bash
# Per-agent file-write lane enforcement for PreToolUse(Edit|Write). Routes on the
# `agent_type` the harness adds to the payload; plugin agents can't carry their
# own hooks, so the lanes are centralized here.
#
# Directory-based lanes (CLAUDE.md path config) apply when set; otherwise falls
# back to extension-based globs. node backend + no lane paths fails closed —
# extensions alone can't tell tank's and trinity's files apart there.

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
    '*unset*'|none|'') return 0 ;;
    *) printf '%s' "$v" ;;
  esac
}

# Comma-separated path config -> space-separated "<path>/**" globs.
lane_globs() {
  for p in $(printf '%s' "$1" | tr ',' ' '); do
    case "$p" in */) printf '%s** ' "$p" ;; *) printf '%s/** ' "$p" ;; esac
  done
}

# agent_type -> mode + space-separated glob patterns (+ optional exempt patterns
# that bypass a deny before it's evaluated).
exempt=""
case "$agent_type" in
  oracle) mode="--allow"; patterns='**/*Tests/** **/*.Tests.* tests/**' ;;
  dozer)  mode="--allow"; patterns='cypress/** e2e/** **/*.cy.* **/*.spec.*' ;;
  tank|trinity)
    backend_lane="$(config_slot 'Backend lane path(s)')"
    frontend_lane="$(config_slot 'Frontend lane path(s)')"
    backend_stack="$(config_slot 'Backend stack')"
    if [ -n "$backend_lane" ] && [ -n "$frontend_lane" ]; then
      # Route handlers live in the frontend tree but are tank's by concern
      # (single-owner, unlike Razor's markup/logic split) — exempt tank, deny trinity.
      route_handlers='**/api/** **/route.ts **/route.js **/route.tsx'
      mode="--deny"
      if [ "$agent_type" = "tank" ]; then
        patterns="$(lane_globs "$frontend_lane")"
        exempt="$route_handlers"
      else
        patterns="$(lane_globs "$backend_lane") $route_handlers"
      fi
    elif [ "$backend_stack" = "node" ]; then
      echo "Blocked: backend stack is node — tank and trinity can both touch .ts/.js files, so extension-based lanes can't tell them apart. Set Backend lane path(s) / Frontend lane path(s) in CLAUDE.md (see /crew:init) before delegating." >&2
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

if [ "$mode" = "--deny" ] && [ "$match" = 1 ]; then
  echo "Blocked: $path is out of ${agent_type}'s lane." >&2
  exit 2
fi
if [ "$mode" = "--allow" ] && [ "$match" = 0 ]; then
  echo "Blocked: $path is outside ${agent_type}'s allowed paths." >&2
  exit 2
fi
exit 0
