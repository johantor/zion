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
