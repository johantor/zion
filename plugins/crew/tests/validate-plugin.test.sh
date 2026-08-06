#!/usr/bin/env bash
# Self-tests for scripts/validate-plugin.sh: prove the drift/version guards bite.
# Each case builds a throwaway git repo with a copy of the validator and a
# minimal plugin layout, then asserts the specific guard's FAIL message appears
# (bite) and is absent from an otherwise-identical control (silent). We assert on
# the guard's own message, not the overall exit, so unrelated scaffolding gaps a
# minimal fixture can't satisfy (e.g. §7's .claude/settings.json mirror) don't
# mask which guard fired.
# shellcheck source=plugins/crew/tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VALIDATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/validate-plugin.sh"
[ -f "$VALIDATOR" ] || { echo "FATAL: $VALIDATOR not found" >&2; exit 1; }

# new_repo -> echoes a throwaway git repo carrying a copy of the validator.
new_repo() {
  local d
  d="$(new_tmpdir)"
  git init -q "$d" || die "git init failed in $d"
  mkdir -p "$d/scripts" || die "mkdir failed in $d"
  cp "$VALIDATOR" "$d/scripts/validate-plugin.sh" || die "cp validator failed into $d"
  printf '%s' "$d"
}

# run_validator <dir> — stages the tree and runs the validator inside it,
# capturing merged stdout+stderr in _vout. The validator exits non-zero on a
# minimal fixture (unrelated scaffolding gaps), which is fine: the asserts key on
# the specific guard message, not the exit code.
run_validator() {
  git -C "$1" add -A >/dev/null 2>&1
  _vout="$(cd "$1" && bash scripts/validate-plugin.sh 2>&1)" || true
}

assert_emits() {  # <label> <dir> <substr>
  run_validator "$2"
  if [[ "$_vout" == *"$3"* ]]; then _pass; else _fail "$1: validator did not emit '$3' — output: $_vout"; fi
}
assert_silent() { # <label> <dir> <substr>
  run_validator "$2"
  if [[ "$_vout" != *"$3"* ]]; then _pass; else _fail "$1: validator unexpectedly emitted '$3'"; fi
}

mk_manifest() { mkdir -p "$1/.claude-plugin"; printf '{"name":"%s","version":"%s"}\n' "$2" "$3" > "$1/.claude-plugin/plugin.json"; }
mk_changelog() { printf '## [%s]\n- note\n' "$2" > "$1/CHANGELOG.md"; }

# --- §2h: manifest version must match the newest CHANGELOG entry ---------------
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 9.9.9; mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2h bites on version/changelog mismatch" "$d" "!= newest"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
assert_silent "§2h silent when they match" "$d" "!= newest"

# --- §2g: an agent's skills: ref must resolve to a real skill -----------------
mk_agent() {  # <plugin_dir> <skill_ref>
  mkdir -p "$1/agents"
  printf -- '---\nname: bar\ndescription: d\nskills:\n  - %s\n---\nbody\n' "$2" > "$1/agents/bar.md"
}
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_agent "$d/plugins/foo" nonexistent-skill
assert_emits "§2g bites on an unresolved skill ref" "$d" "does not resolve"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/skills/real"; printf -- '---\nname: real\ndescription: d\n---\n' > "$d/plugins/foo/skills/real/SKILL.md"
mk_agent "$d/plugins/foo" real
assert_silent "§2g silent when the skill exists" "$d" "does not resolve"

# --- §8: turn-budget table must be in lockstep with agent maxTurns -------------
mk_turns_agent() {  # <plugin_dir> <name> <maxTurns>
  mkdir -p "$1/agents"
  printf -- '---\nname: %s\ndescription: d\nmaxTurns: %s\n---\nbody\n' "$2" "$3" > "$1/agents/$2.md"
}
mk_turn_budget() {  # <plugin_dir> <case-table-body>
  mkdir -p "$1/hooks"
  # Both formats intentionally emit their `$`-expressions as literal text into
  # the generated fixture — that's the shape §8 and §6 parse — so they must not
  # expand here.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\ncase "$agent_type" in\n%s\n  *) exit 0 ;;\nesac\n' "$2" > "$1/hooks/turn-budget.sh"
  # shellcheck disable=SC2016
  printf '{"hooks":{"PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"\\"${CLAUDE_PLUGIN_ROOT}\\"/hooks/turn-budget.sh"}]}]}}\n' > "$1/hooks/hooks.json"
}
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_turns_agent "$d/plugins/foo" bar 40; mk_turn_budget "$d/plugins/foo" '  bar) budget=30 ;;'
assert_emits "§8 bites on a budget != maxTurns" "$d" "!= plugins/foo/agents/bar.md maxTurns"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_turns_agent "$d/plugins/foo" bar 40; mk_turn_budget "$d/plugins/foo" '  baz) budget=40 ;;'
assert_emits "§8 bites on a missing agent entry" "$d" "no budget entry for agent 'bar'"
assert_emits "§8 bites on a stale table row" "$d" "budget entry 'baz' does not match any"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_turns_agent "$d/plugins/foo" bar 40; mk_turn_budget "$d/plugins/foo" '  # no table lines'
assert_emits "§8 bites on an unparseable table" "$d" "no parseable budget table"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_turns_agent "$d/plugins/foo" bar 40; mk_turn_budget "$d/plugins/foo" '  bar) budget=40 ;;'
assert_silent "§8 silent when table matches maxTurns" "$d" "keep the table in lockstep"

# --- §9: hook rosters must be in lockstep with agent owns-git/lane-guarded -----
mk_roster_agent() {  # <plugin_dir> <name> <tools> <owns-git> <lane-guarded>
  mkdir -p "$1/agents"
  printf -- '---\nname: %s\ndescription: d\ntools: %s\nowns-git: %s\nlane-guarded: %s\n---\nbody\n' \
    "$2" "$3" "$4" "$5" > "$1/agents/$2.md"
}
mk_roster_hook() {  # <plugin_dir> <hook-basename> <roster-name> <arm-alternation>
  mkdir -p "$1/hooks"
  # The `$agent_type` below is fixture text in the shape §9 parses, not a value
  # to expand here.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\n# crew-roster: %s -- fixture\ncase "$agent_type" in\n  %s) ;;\n  *) exit 0 ;;\nesac\n' \
    "$3" "$4" > "$1/hooks/$2"
}
# A Bash-capable non-owner missing from the no-git roster would run git unguarded.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" hand "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'other'
assert_emits "§9 bites on a Bash agent missing from the no-git roster" "$d" \
  "no no-git roster entry for 'hand'"
assert_emits "§9 bites on a stale no-git roster name" "$d" \
  "roster entry 'other' does not match any"

# Listing the git owner in the no-git roster would block the one agent that must commit.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'boss'
assert_emits "§9 bites when the git owner is in the no-git roster" "$d" \
  "lists the git owner 'boss'"

# Exactly one owner: neither zero nor two.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" a "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'a'
assert_emits "§9 bites when no agent owns git" "$d" "exactly one agent with 'owns-git: true'"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" a "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" b "Read, Bash" true false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'none'
assert_emits "§9 bites on two git owners" "$d" "found 2"

# A new agent that declares neither fact is the drift this section exists to catch.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'none'
printf -- '---\nname: newbie\ndescription: d\ntools: Read, Bash\n---\nbody\n' > "$d/plugins/foo/agents/newbie.md"
assert_emits "§9 bites on an agent declaring no owns-git" "$d" \
  "plugins/foo/agents/newbie.md has no 'owns-git'"

# Dropping the marker must fail loudly, not silently disable the check.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mkdir -p "$d/plugins/foo/hooks"; printf '#!/usr/bin/env bash\nexit 0\n' > "$d/plugins/foo/hooks/bash-safety.sh"
assert_emits "§9 bites on a missing no-git marker" "$d" "has no parseable '# crew-roster: no-git'"

# No hook file at all must report, not abort the validator under `set -e`.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
assert_emits "§9 bites when the hook file is absent entirely" "$d" \
  "has no parseable '# crew-roster: no-git'"
assert_emits "§9 keeps running after an absent hook" "$d" "Plugin validation failed."

# lane-guarded, both directions.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" laned "Read, Bash" false true
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'laned'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'other'
assert_emits "§9 bites when a lane-guarded agent is missing from the roster" "$d" \
  "roster omits 'laned'"
assert_emits "§9 bites on a stale lane roster name" "$d" \
  "lane roster entry 'other' does not match any"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" free "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'free'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'free'
assert_emits "§9 bites when the roster lists a lane-guarded: false agent" "$d" \
  "declares 'lane-guarded: false'"

# A Bash-less agent needs no no-git entry, and the control must stay silent.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" laned "Read, Bash" false true
mk_roster_agent "$d/plugins/foo" looker "Read, Grep" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'laned'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'laned'
# Assert on FAIL-only phrasing: the `ok:` lines also contain the word "roster".
assert_silent "§9 silent when both rosters are in lockstep" "$d" "add it to the arm"
assert_silent "§9 silent: no stale-name complaint in lockstep" "$d" "remove the stale name"
assert_silent "§9 silent: no owner complaint in lockstep" "$d" "exactly one agent"

# A plugin whose agents declare neither field is skipped entirely (keymaker).
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_turns_agent "$d/plugins/foo" plain 40
assert_silent "§9 silent for a plugin that hasn't opted in" "$d" "crew-roster"

# --- §4: a skill shipped by >1 plugin must stay byte-identical -----------------
mk_shared_skill() {  # <dir> <body>
  mkdir -p "$1/skills/shared"
  printf -- '---\nname: shared\ndescription: d\n---\n%s\n' "$2" > "$1/skills/shared/SKILL.md"
}
d="$(new_repo)"
mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0; mk_shared_skill "$d/plugins/foo" ALPHA
mk_manifest "$d/plugins/bar" bar 1.0.0; mk_changelog "$d/plugins/bar" 1.0.0; mk_shared_skill "$d/plugins/bar" BETA
assert_emits "§4 bites on diverged shared skill" "$d" "skill drift"
d="$(new_repo)"
mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0; mk_shared_skill "$d/plugins/foo" SAME
mk_manifest "$d/plugins/bar" bar 1.0.0; mk_changelog "$d/plugins/bar" 1.0.0; mk_shared_skill "$d/plugins/bar" SAME
assert_silent "§4 silent when shared skills match" "$d" "skill drift"

finish
