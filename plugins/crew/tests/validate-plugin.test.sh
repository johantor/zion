#!/usr/bin/env bash
# Self-tests for scripts/validate-plugin.sh: prove every section's guards bite.
# Each case builds a throwaway git repo with a copy of the validator and a
# minimal plugin layout, then asserts the specific guard's FAIL message appears
# (bite). Every section additionally carries at least one silent control — a
# valid tree the guard must stay quiet on — which is what proves the guard
# discriminates rather than firing unconditionally. Controls are per section, not
# per bite: several bites in a section share one control, since the guards differ
# only in which way the same fixture is broken.
#
# We assert on the guard's own message, not the overall exit, so unrelated
# scaffolding gaps a minimal fixture can't satisfy (e.g. §7's
# .claude/settings.json mirror) don't mask which guard fired.
#
# Choosing that substring is the subtle part: it must not also appear in the
# validator's `ok:` lines, or the silent control can never pass. §5 asserts on
# the shared "hook drift" prefix rather than either message's tail for exactly
# this reason — "shared-guard regions in" also occurs in "ok: hook shared-guard
# regions in sync". Prefer the FAIL-only prefix over a distinctive-looking tail.
#
# Every validator section carries at least one negative fixture here — a check
# that silently stopped checking is the worst failure mode for an enforcement
# tool. A new section (or a new guard within one) lands with its fixture; see
# AGENTS.md ("Validating changes").
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

# Raw-JSON writers for the shapes the two above can't express: a manifest missing
# a key, declaring component paths, or carrying a description; a marketplace.
mk_manifest_json() { mkdir -p "$1/.claude-plugin"; printf '%s\n' "$2" > "$1/.claude-plugin/plugin.json"; }
mk_marketplace()   { mkdir -p "$1/.claude-plugin"; printf '%s\n' "$2" > "$1/.claude-plugin/marketplace.json"; }

# mk_hook <plugin_dir> <filename> <body> — a valid, executable hook, so §3's two
# guards stay silent and the fixture isolates whichever section is under test.
mk_hook() {
  mkdir -p "$1/hooks"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/hooks/$2"
  chmod +x "$1/hooks/$2"
}
# mk_hooks_json <plugin_dir> <command-string> — wiring in §6's expected shape.
mk_hooks_json() {
  mkdir -p "$1/hooks"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s"}]}]}}\n' "$2" > "$1/hooks/hooks.json"
}
# mk_dev_settings <repo> <command-string> <matcher> — §7's dev-side mirror.
mk_dev_settings() {
  mkdir -p "$1/.claude"
  printf '{"hooks":{"PreToolUse":[{"matcher":"%s","hooks":[{"type":"command","command":"%s"}]}]}}\n' "$3" "$2" > "$1/.claude/settings.json"
}

# Wiring commands, shared by §2e/§6/§7. Single-quoted so the "${VAR}" text stays
# literal — it is JSON content here, not a shell expansion — and the \" pairs
# become real quotes when printf writes them.
# shellcheck disable=SC2016
wired_x='\"${CLAUDE_PLUGIN_ROOT}\"/hooks/x.sh'
# shellcheck disable=SC2016
wired_missing='\"${CLAUDE_PLUGIN_ROOT}\"/hooks/missing.sh'
# shellcheck disable=SC2016
dev_x='\"${CLAUDE_PROJECT_DIR}\"/plugins/crew/hooks/x.sh'

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

# A reformatted arm must fail loudly, not silently resolve to another case
# statement further down the hook (bash-safety has a `main|master|develop)` arm).
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mkdir -p "$d/plugins/foo/hooks"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\n# crew-roster: no-git -- fixture\ncase "$agent_type" in\n  a | b)\n  ;;\nesac\ncase "$branch" in\n  main|master|develop) ;;\nesac\n' \
  > "$d/plugins/foo/hooks/bash-safety.sh"
assert_emits "§9 bites on a reformatted arm instead of scanning on" "$d" \
  "has no parseable '# crew-roster: no-git'"
assert_silent "§9 does not adopt a later case statement's arm" "$d" "'main'"

# A duplicated roster name is a copy-paste error, not a silent dedupe.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" hand "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'hand|hand'
assert_emits "§9 bites on a duplicated roster name" "$d" "names 'hand' more than once"

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
mk_roster_agent "$d/plugins/foo" laned "Read, Bash" false true
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'laned'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'laned|laned'
assert_emits "§9 bites on a duplicated lane roster name" "$d" \
  "lane roster names 'laned' more than once"

# A Bash-less agent in the no-git roster is a dead entry: it can never run git.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" looker "Read, Grep" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'looker'
assert_emits "§9 bites on a Bash-less agent in the no-git roster" "$d" \
  "has no Bash tool; remove the dead entry"

# An inline YAML comment on a declaration is valid YAML, not a broken value.
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/agents"
printf -- '---\nname: boss\ndescription: d\ntools: Read, Bash\nowns-git: true  # sole git owner\nlane-guarded: false\n---\nbody\n' \
  > "$d/plugins/foo/agents/boss.md"
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'none'
assert_silent "§9 accepts an inline comment after a declaration" "$d" "expected true or false"

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

# --- §1: every tracked .json must parse ----------------------------------------
d="$(new_repo)"; mkdir -p "$d/plugins/foo"; printf '{\n' > "$d/plugins/foo/broken.json"
assert_emits "§1 bites on unparseable JSON" "$d" "invalid JSON: plugins/foo/broken.json"
d="$(new_repo)"; mkdir -p "$d/plugins/foo"; printf '{"a":1}\n' > "$d/plugins/foo/broken.json"
assert_silent "§1 silent on well-formed JSON" "$d" "invalid JSON: plugins/foo/broken.json"

# --- §2a: manifest identity fields ---------------------------------------------
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo"}'; mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2a bites on a manifest missing version" "$d" "missing required key: version"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
assert_silent "§2a silent when identity keys are present" "$d" "missing required key"

# --- §2b: declared component paths must exist ----------------------------------
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","skills":"skills/nope"}'
mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2b bites on a declared path that is missing" "$d" "skills -> skills/nope declared in"
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","skills":"skills/real"}'
mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/skills/real"; printf -- '---\nname: real\ndescription: d\n---\n' > "$d/plugins/foo/skills/real/SKILL.md"
assert_silent "§2b silent when the declared path exists" "$d" "declared in"

# --- §2c: the auto-loaded hooks/hooks.json must not be declared ----------------
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","hooks":"hooks/hooks.json"}'
mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2c bites when the manifest declares hooks/hooks.json" "$d" "declares the auto-loaded hooks/hooks.json"
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","hooks":"hooks/extra.sh"}'
mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2c bites on an additional hook file that is missing" "$d" "hooks -> hooks/extra.sh declared in"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
assert_silent "§2c silent when the manifest omits it" "$d" "declares the auto-loaded hooks/hooks.json"

# --- §2d: an agents/ directory must hold agent files ---------------------------
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/agents"; printf 'notes\n' > "$d/plugins/foo/agents/notes.txt"
assert_emits "§2d bites on an agents/ dir with no .md files" "$d" "agents/ exists but has no .md agent files"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/agents"; printf -- '---\nname: bar\ndescription: d\n---\nbody\n' > "$d/plugins/foo/agents/bar.md"
assert_silent "§2d silent when agents/ holds an agent" "$d" "agents/ exists but has no .md agent files"

# --- §2e: a hooks/ directory must carry the auto-loaded hooks.json -------------
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_hook "$d/plugins/foo" x.sh 'exit 0'
assert_emits "§2e bites on a hooks/ dir with no hooks.json" "$d" "hooks/ exists but hooks/hooks.json missing"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" "$wired_x"
assert_silent "§2e silent when hooks.json is present" "$d" "hooks/ exists but hooks/hooks.json missing"

# --- §2f: marketplace entries agree with the plugins on disk -------------------
d="$(new_repo)"
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/nope"}]}'
assert_emits "§2f bites on a source that does not exist" "$d" "source ./plugins/nope does not exist"

# A source directory that exists but ships no manifest. git tracks files, not
# dirs, so the fixture needs a file inside for the source to survive `git add`.
d="$(new_repo)"; mkdir -p "$d/plugins/foo"; printf 'placeholder\n' > "$d/plugins/foo/README.md"
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/foo"}]}'
assert_emits "§2f bites on a source with no manifest" "$d" "plugins/foo/.claude-plugin/plugin.json missing"

d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"bar","source":"./plugins/foo"}]}'
assert_emits "§2f bites on an entry name != manifest name" "$d" "!= plugin.json name"

d="$(new_repo)"
mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","description":"canonical"}'
mk_changelog "$d/plugins/foo" 1.0.0
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/foo","description":"stale"}]}'
assert_emits "§2f bites on a description that drifted" "$d" "description differs from"

d="$(new_repo)"
mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","description":"canonical"}'
mk_changelog "$d/plugins/foo" 1.0.0
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/foo","description":"canonical"}]}'
assert_silent "§2f silent when the entry matches its manifest" "$d" "description differs from"

# --- §3: hook scripts are valid bash and executable ----------------------------
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/hooks"; printf '#!/usr/bin/env bash\nif [ 1\n' > "$d/plugins/foo/hooks/x.sh"
chmod +x "$d/plugins/foo/hooks/x.sh"   # chmod so only the syntax guard can fire
assert_emits "§3 bites on a bash syntax error" "$d" "bash syntax error: plugins/foo/hooks/x.sh"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/hooks"; printf '#!/usr/bin/env bash\nexit 0\n' > "$d/plugins/foo/hooks/x.sh"
assert_emits "§3 bites on a non-executable hook" "$d" "not executable (chmod +x): plugins/foo/hooks/x.sh"
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
mk_hook "$d/plugins/foo" x.sh 'exit 0'
# Two asserts, each on its own FAIL text: the bare path also appears in this
# section's `ok:` lines, so matching on it alone would never go silent.
assert_silent "§3 silent on valid syntax" "$d" "bash syntax error"
assert_silent "§3 silent on an executable hook" "$d" "not executable"

# --- §5: a hook shipped by >1 plugin must stay in sync -------------------------
# Two regimes: unmarked copies must be byte-identical; marked copies need only
# their shared-guard regions to match. Plugin names are arbitrary (neither is
# crew), so the reference is whichever sorts first — the asserts key on the
# message body, not on which copy was chosen.
mk_marked_hook() {  # <plugin_dir> <region-body> <per-plugin-tail>
  mkdir -p "$1/hooks"
  printf '#!/usr/bin/env bash\n# --- BEGIN shared guard: g ---\n%s\n# --- END shared guard: g ---\n%s\n' "$2" "$3" > "$1/hooks/shared.sh"
  chmod +x "$1/hooks/shared.sh"
}

d="$(new_repo)"; mk_hook "$d/plugins/aaa" shared.sh 'echo ALPHA'; mk_hook "$d/plugins/bbb" shared.sh 'echo BETA'
assert_emits "§5 bites on unmarked copies that differ" "$d" "must be byte-identical"
d="$(new_repo)"; mk_hook "$d/plugins/aaa" shared.sh 'echo SAME'; mk_hook "$d/plugins/bbb" shared.sh 'echo SAME'
assert_silent "§5 silent when unmarked copies match" "$d" "hook drift"

d="$(new_repo)"; mk_marked_hook "$d/plugins/aaa" 'echo ALPHA' 'echo tail-a'
mk_marked_hook "$d/plugins/bbb" 'echo BETA' 'echo tail-b'
assert_emits "§5 bites on diverged shared-guard regions" "$d" "shared-guard regions in"
d="$(new_repo)"; mk_marked_hook "$d/plugins/aaa" 'echo SHARED' 'echo tail-a'
mk_marked_hook "$d/plugins/bbb" 'echo SHARED' 'echo tail-b'
assert_silent "§5 silent when regions match despite per-plugin tails" "$d" "hook drift"

d="$(new_repo)"; mk_marked_hook "$d/plugins/aaa" 'echo SHARED' 'echo tail-a'
mkdir -p "$d/plugins/bbb/hooks"
printf '#!/usr/bin/env bash\n# --- BEGIN shared guard: g ---\necho SHARED\n' > "$d/plugins/bbb/hooks/shared.sh"
chmod +x "$d/plugins/bbb/hooks/shared.sh"
assert_emits "§5 bites on a shared-guard block that never closes" "$d" "is never closed"

# --- §6: hooks.json wiring resolves, and every hook script is wired ------------
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" './hooks/x.sh'
assert_emits "§6 bites on a command that skips CLAUDE_PLUGIN_ROOT" "$d" "does not start with"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" "$wired_missing"
assert_emits "§6 bites on wiring a script that does not exist" "$d" "wires hooks/missing.sh but"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hook "$d/plugins/foo" y.sh 'exit 0'
mk_hooks_json "$d/plugins/foo" "$wired_x"
assert_emits "§6 bites on a hook script nothing wires" "$d" "plugins/foo/hooks/y.sh exists but is not wired"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'
mkdir -p "$d/plugins/foo/hooks"; printf '{"hooks":[]}\n' > "$d/plugins/foo/hooks/hooks.json"
assert_emits "§6 bites on valid JSON of the wrong shape" "$d" "does not have the expected shape"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'
mkdir -p "$d/plugins/foo/hooks"; printf '{\n' > "$d/plugins/foo/hooks/hooks.json"
assert_emits "§6 bites on unparseable wiring" "$d" "cannot cross-check its hook wiring"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" "$wired_x"
assert_silent "§6 silent when wiring and scripts agree" "$d" "is not wired"

# --- §7: .claude/settings.json mirrors plugins/crew/hooks/hooks.json ----------
d="$(new_repo)"; mk_hook "$d/plugins/crew" x.sh 'exit 0'; mk_hooks_json "$d/plugins/crew" "$wired_x"
assert_emits "§7 bites when the dev mirror is absent" "$d" ".claude/settings.json is missing"
d="$(new_repo)"; mk_dev_settings "$d" "$dev_x" Bash
assert_emits "§7 bites when the plugin wiring is absent" "$d" "plugins/crew/hooks/hooks.json is missing"
d="$(new_repo)"; mk_hook "$d/plugins/crew" x.sh 'exit 0'; mk_hooks_json "$d/plugins/crew" "$wired_x"
mk_dev_settings "$d" "$dev_x" Write
assert_emits "§7 bites when the mirrored matcher drifts" "$d" "hook wiring drift"
d="$(new_repo)"; mk_hook "$d/plugins/crew" x.sh 'exit 0'; mk_hooks_json "$d/plugins/crew" "$wired_x"
mk_dev_settings "$d" "$dev_x" Bash
assert_silent "§7 silent when the mirror matches modulo root variable" "$d" "hook wiring drift"

finish
