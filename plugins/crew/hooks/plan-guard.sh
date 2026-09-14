#!/usr/bin/env bash
# Plan-mode dispatch guard: while the session is in plan mode, refuse to launch
# a crew worker that edits files.
#
# Plan mode refuses every Edit/Write until the plan is approved, so an
# implementer dispatched during planning spends its turns on refused edits and
# hands back nothing. The worker's own frontmatter decides, not a roster (the
# rosters validator §9 pins live in bash-safety/lane-guard; a third one here
# would drift unwatched): `owns-git: true` marks the orchestrator, which plans
# in plan mode and passes; any other crew agent whose `tools:` carry
# Edit/Write/NotebookEdit is refused until the plan is approved; a worker with
# none of those passes.
#
# A fast-fail, not a boundary: plan mode itself is what blocks the edits. So it
# FAILS OPEN — no jq, an unparseable payload, a dispatch that isn't a crew
# worker's, an agent file it can't find — all allow. Inert under this repo's own
# dev wiring, where nothing dispatches namespaced agents (as dispatch-denied).
# See plugins/crew/CLAUDE.md and the README's "Plan mode".
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# Fast path, no subprocess: only an Agent/Task dispatch carries subagent_type,
# and only a plan-mode payload carries the mode this guard acts on.
case "$guard_payload" in
  *'"subagent_type"'*) ;;
  *) exit 0 ;;
esac
case "$guard_payload" in
  *'"plan"'*) ;;
  *) exit 0 ;;
esac

# Both fields are harness-controlled; the mode is a fixed enum, so it anchors
# the split (see guard_jq2).
guard_jq2 '.tool_input.subagent_type // ""' '.permission_mode // ""' || exit 0
# shellcheck disable=SC2154  # set by guard_jq2 in the library sourced above
[ "$guard_trusted" = "plan" ] || exit 0
# shellcheck disable=SC2154
case "$guard_untrusted" in
  crew:?*) worker="${guard_untrusted#crew:}" ;;
  *) exit 0 ;;
esac
# An agent name is a file name below; anything else is not a crew worker's file.
case "$worker" in
  *[!A-Za-z0-9_-]*) exit 0 ;;
esac

# The worker's definition ships beside this hook. CREW_AGENTS_DIR is the test
# override, so the parser can be exercised on fixture agents.
agent_file="${CREW_AGENTS_DIR:-${BASH_SOURCE[0]%/*}/../agents}/$worker.md"
[ -f "$agent_file" ] || exit 0

# Frontmatter only: a `tools:` in the prose body is documentation, not a grant.
# Both YAML shapes of `tools:` are read — the inline comma list the agents here
# use and a `  - name` block list — as validator §13 does.
tools='' owns_git='' in_fm=0 in_list=0
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ---*)
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi ;;
  esac
  [ "$in_fm" -eq 1 ] || continue
  if [ "$in_list" -eq 1 ]; then
    case "$line" in
      [[:space:]]*-[[:space:]]*) tools="$tools,${line#*-}"; continue ;;
      *) in_list=0 ;;
    esac
  fi
  case "$line" in
    tools:*)
      tools="${line#tools:}"
      [ -z "${tools//[[:space:]]/}" ] && in_list=1 ;;
    owns-git:*)
      owns_git="${line#owns-git:}"; owns_git="${owns_git//[[:space:]]/}" ;;
  esac
done < "$agent_file"

# The orchestrator plans in plan mode; it is the one agent this guard lets
# through with an editing tool set.
[ "$owns_git" = "true" ] && exit 0

tools=",${tools//[[:space:]]/},"
case "$tools" in
  *,Edit,*|*,Write,*|*,NotebookEdit,*|*,MultiEdit,*) ;;
  *) exit 0 ;;
esac

echo "Blocked: this session is in plan mode, and crew:${worker} edits files — plan mode refuses every edit until the plan is approved, so the dispatch would spend the worker's turns on refused edits and return nothing. Finish the plan and get it approved (ExitPlanMode as the main thread; return the plan when you run as a subagent), then dispatch crew:${worker}. Workers whose tools carry no Edit/Write still run in plan mode." >&2
exit 2
