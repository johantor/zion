#!/usr/bin/env bash
# Self-tests for the two release scripts:
#
#   scripts/check-changelog.sh — the PR gate: a change to a plugin's shipped
#     files must bump its version. Diff-driven, so each case builds a throwaway
#     repo with real commits rather than a static tree — that history *is* the
#     input.
#   scripts/release-notes.sh   — the notes extractor: one version's CHANGELOG
#     section, which auto-release.yml turns into the GitHub Release.
#
# Assert on the message, not the exit code, so it is clear which guard fired.
#
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
for s in check-changelog.sh release-notes.sh; do
  [ -f "$REPO_ROOT/scripts/$s" ] || { echo "FATAL: scripts/$s not found" >&2; exit 1; }
done

# new_gate_repo -> echoes a repo on `main` carrying the script and one plugin
# (foo v1.0.0) already committed, with a `work` branch checked out. The base
# branch is local: the script tries `origin/<ref>` first and falls back to a
# plain ref, which is what makes a fixture without a remote work.
new_gate_repo() {
  local d
  d="$(new_tmpdir)"
  git init -q -b main "$d" 2>/dev/null \
    || { git init -q "$d"; git -C "$d" symbolic-ref HEAD refs/heads/main; }
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "Test"
  git -C "$d" config commit.gpgsign false
  mkdir -p "$d/scripts"
  cp "$REPO_ROOT/scripts/check-changelog.sh" "$d/scripts/" || die "cp script failed into $d"
  mk_plugin "$d" foo 1.0.0
  gate_commit "$d" "initial"
  git -C "$d" checkout -q -b work
  printf '%s' "$d"
}

# mk_plugin <repo> <name> <version> — manifest + changelog + a README standing in
# for any shipped file.
mk_plugin() {
  local p="$1/plugins/$2"
  mkdir -p "$p/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$2" "$3" > "$p/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## [%s] - 2026-01-01\n\n### Added\n- initial\n' "$3" > "$p/CHANGELOG.md"
  printf 'readme v1\n' > "$p/README.md"
}

gate_commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -q -m "$2" || die "commit failed in $1"; }

# bump <repo> <version> — bump the manifest and open that version's section.
bump() {
  local p="$1/plugins/foo" tmp
  printf '{"name":"foo","version":"%s"}\n' "$2" > "$p/.claude-plugin/plugin.json"
  tmp="$(mktemp "$FIXTURE_ROOT/cl.XXXXXX")" || die "mktemp failed"
  awk -v h="## [$2] - 2026-02-02" '
    !inserted && /^## \[/ { print h; print ""; print "### Changed"; print "- bumped"; print ""; inserted = 1 }
    { print }
  ' "$p/CHANGELOG.md" > "$tmp"
  mv "$tmp" "$p/CHANGELOG.md"
}

run_gate() { _out="$(cd "$1" && bash scripts/check-changelog.sh main 2>&1)" || true; }

assert_out() {    # <label> <substr>
  if [[ "$_out" == *"$2"* ]]; then _pass; else _fail "$1: expected '$2' — output: $_out"; fi
}
assert_no_out() { # <label> <substr>
  if [[ "$_out" != *"$2"* ]]; then _pass; else _fail "$1: unexpectedly emitted '$2'"; fi
}

NOBUMP="without a version bump"

# --- A shipped change needs a bump --------------------------------------------
d="$(new_gate_repo)"; printf 'readme v2\n' > "$d/plugins/foo/README.md"; gate_commit "$d" "docs: reword"
run_gate "$d"; assert_out "bites on a shipped change with no bump" "$NOBUMP"

d="$(new_gate_repo)"; printf 'readme v2\n' > "$d/plugins/foo/README.md"; bump "$d" 1.1.0
gate_commit "$d" "feat: reword (v1.1.0)"
run_gate "$d"; assert_no_out "silent when the version is bumped" "$NOBUMP"

# Mid-branch: an uncommitted edit counts, so the check is useful before the commit.
d="$(new_gate_repo)"; printf 'readme v2\n' > "$d/plugins/foo/README.md"
run_gate "$d"; assert_out "bites on an uncommitted shipped change" "$NOBUMP"

# --- The gate ignores what users never receive --------------------------------
d="$(new_gate_repo)"; mkdir -p "$d/plugins/foo/tests"; printf 'x\n' > "$d/plugins/foo/tests/t.sh"
gate_commit "$d" "test: add a case"
run_gate "$d"; assert_no_out "silent on a tests/-only change" "$NOBUMP"

d="$(new_gate_repo)"; printf 'notes\n' > "$d/plugins/foo/CLAUDE.md"; gate_commit "$d" "docs: contributor notes"
run_gate "$d"; assert_no_out "silent on a CLAUDE.md-only change" "$NOBUMP"

# Unrelated commits on main since the branch forked are not this PR's changes.
d="$(new_gate_repo)"; git -C "$d" checkout -q main
printf 'readme v2\n' > "$d/plugins/foo/README.md"; gate_commit "$d" "docs: on main"
git -C "$d" checkout -q work; mkdir -p "$d/plugins/foo/tests"; printf 'x\n' > "$d/plugins/foo/tests/t.sh"
gate_commit "$d" "test: add a case"
run_gate "$d"; assert_no_out "silent when only main moved" "$NOBUMP"

# --- The notes extractor: one version's section, nothing else -----------------
run_notes() { _out="$(bash "$REPO_ROOT/scripts/release-notes.sh" "$1" "$2" 2>&1)" || true; }

d="$(new_tmpdir)"; mkdir -p "$d/p"
printf '# Changelog\n\n## [1.0.10] - 2026-03-03\n- ten\n\n## [1.0.1] - 2026-02-02\n\n### Fixed\n- one\n\n## [1.0.0] - 2026-01-01\n- initial\n' \
  > "$d/p/CHANGELOG.md"
run_notes "$d/p" 1.0.1
assert_out "notes carry the version's heading" "## [1.0.1]"
assert_out "notes carry the version's bullets" "- one"
assert_no_out "notes stop at the next heading" "- initial"
assert_no_out "1.0.1 does not match the 1.0.10 section above it" "- ten"
run_notes "$d/p" 9.9.9
assert_out "a missing section is an error, not empty notes" "no '## [9.9.9]' section"

finish
