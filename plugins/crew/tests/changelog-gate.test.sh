#!/usr/bin/env bash
# Self-tests for the two release-notes scripts:
#
#   scripts/check-changelog.sh — the PR gate: a change to shipped files must be
#     described somewhere (a version bump, or a bullet parked under
#     `## [Unreleased]`), and a bump must not leave parked bullets behind.
#   scripts/release-notes.sh   — the notes builder: a version's CHANGELOG
#     section plus the commits that shipped in the same tag without an entry.
#
# Both are diff/history-driven, so each case builds a throwaway repo with real
# commits (and tags) rather than a static tree — that history *is* the input.
# Assert on the message, not the exit code, so it is clear which guard fired.
#
# shellcheck source=plugins/crew/tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
for s in check-changelog.sh release-notes.sh; do
  [ -f "$REPO_ROOT/scripts/$s" ] || { echo "FATAL: scripts/$s not found" >&2; exit 1; }
done

# new_gate_repo -> echoes a repo on `main` carrying both scripts and one plugin
# (foo v1.0.0) already committed, with a `work` branch checked out. The base
# branch is local: the scripts try `origin/<ref>` first and fall back to a plain
# ref, which is what makes a fixture without a remote work.
new_gate_repo() {
  local d
  d="$(new_tmpdir)"
  git init -q -b main "$d" 2>/dev/null \
    || { git init -q "$d"; git -C "$d" symbolic-ref HEAD refs/heads/main; }
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "Test"
  git -C "$d" config commit.gpgsign false
  mkdir -p "$d/scripts"
  cp "$REPO_ROOT/scripts/check-changelog.sh" "$REPO_ROOT/scripts/release-notes.sh" "$d/scripts/" \
    || die "cp scripts failed into $d"
  mk_plugin "$d" foo 1.0.0
  gate_commit "$d" "initial"
  git -C "$d" checkout -q -b work
  printf '%s' "$d"
}

# mk_plugin <repo> <name> <version> — manifest + changelog (with the Unreleased
# slot) + a README standing in for any shipped file.
mk_plugin() {
  local p="$1/plugins/$2"
  mkdir -p "$p/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$2" "$3" > "$p/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## [Unreleased]\n\n## [%s] - 2026-01-01\n\n### Added\n- initial\n' \
    "$3" > "$p/CHANGELOG.md"
  printf 'readme v1\n' > "$p/README.md"
}

gate_commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -q -m "$2" || die "commit failed in $1"; }

# park <repo> <bullet> — add a bullet under `## [Unreleased]`.
park() {
  local cl="$1/plugins/foo/CHANGELOG.md" tmp
  tmp="$(mktemp "$FIXTURE_ROOT/cl.XXXXXX")" || die "mktemp failed"
  awk -v b="- $2" '{ print } /^## \[Unreleased\]/ { print ""; print b }' "$cl" > "$tmp"
  mv "$tmp" "$cl"
}

# bump <repo> <version> [extra-bullet] — bump the manifest and open that
# version's section. The heading goes immediately above the previous newest
# version, i.e. *below* the Unreleased section — the real shape, and the one that
# leaves anything already parked still parked.
bump() {
  local p="$1/plugins/foo" tmp
  printf '{"name":"foo","version":"%s"}\n' "$2" > "$p/.claude-plugin/plugin.json"
  tmp="$(mktemp "$FIXTURE_ROOT/cl.XXXXXX")" || die "mktemp failed"
  awk -v h="## [$2] - 2026-02-02" -v extra="${3:-}" '
    !inserted && /^## \[[0-9]/ {
      print h; print ""; print "### Changed"; print "- bumped"
      if (extra != "") print "- " extra
      print ""
      inserted = 1
    }
    { print }
  ' "$p/CHANGELOG.md" > "$tmp"
  mv "$tmp" "$p/CHANGELOG.md"
}

# clear_parked <repo> — drop the Unreleased bullets, as folding them into a
# version section does.
clear_parked() {
  local cl="$1/plugins/foo/CHANGELOG.md" tmp
  tmp="$(mktemp "$FIXTURE_ROOT/cl.XXXXXX")" || die "mktemp failed"
  awk '
    /^## \[Unreleased\]/ { print; in_u = 1; next }
    /^## \[/             { in_u = 0 }
    in_u && /^[-*][[:space:]]/ { next }
    { print }
  ' "$cl" > "$tmp"
  mv "$tmp" "$cl"
}

run_gate()  { _out="$(cd "$1" && bash scripts/check-changelog.sh main 2>&1)" || true; }
run_notes() { _out="$(cd "$1" && bash scripts/release-notes.sh "plugins/$2" "$3" 2>&1)" || true; }

assert_out() {    # <label> <substr>
  if [[ "$_out" == *"$2"* ]]; then _pass; else _fail "$1: expected '$2' — output: $_out"; fi
}
assert_no_out() { # <label> <substr>
  if [[ "$_out" != *"$2"* ]]; then _pass; else _fail "$1: unexpectedly emitted '$2'"; fi
}

TRACE="no release-notes trace"
PARKED="still has bullets"

# --- The gate: a shipped change needs a bump or a parked bullet ----------------
d="$(new_gate_repo)"; printf 'readme v2\n' > "$d/plugins/foo/README.md"; gate_commit "$d" "docs: reword"
run_gate "$d"; assert_out "bites on a shipped change with neither" "$TRACE"

d="$(new_gate_repo)"; printf 'readme v2\n' > "$d/plugins/foo/README.md"; park "$d" "reworded the README (#7)"
gate_commit "$d" "docs: reword"
run_gate "$d"; assert_no_out "silent when the change is parked" "$TRACE"

d="$(new_gate_repo)"; printf 'readme v2\n' > "$d/plugins/foo/README.md"; bump "$d" 1.1.0
gate_commit "$d" "feat: reword (v1.1.0)"
run_gate "$d"; assert_no_out "silent when the version is bumped" "$TRACE"

# A pre-existing parked bullet is not this PR's note: an unchanged Unreleased
# section must not launder the next shipped change through it.
d="$(new_gate_repo)"; park "$d" "someone else's note (#1)"; gate_commit "$d" "chore: park"
git -C "$d" checkout -q main; git -C "$d" merge -q --ff-only work; git -C "$d" checkout -q work
printf 'readme v2\n' > "$d/plugins/foo/README.md"; gate_commit "$d" "docs: reword"
run_gate "$d"; assert_out "bites when the parked bullet predates the branch" "$TRACE"

# --- The gate, other direction: a bump must not leave bullets parked -----------
d="$(new_gate_repo)"; park "$d" "small thing (#7)"; bump "$d" 1.1.0
gate_commit "$d" "feat: thing (v1.1.0)"
run_gate "$d"; assert_out "bites on a bump with bullets still parked" "$PARKED"

d="$(new_gate_repo)"; park "$d" "small thing (#7)"; bump "$d" 1.1.0; clear_parked "$d"
gate_commit "$d" "feat: thing (v1.1.0)"
run_gate "$d"; assert_no_out "silent once the parked bullets are folded in" "$PARKED"

# --- The gate ignores what users never receive --------------------------------
d="$(new_gate_repo)"; mkdir -p "$d/plugins/foo/tests"; printf 'x\n' > "$d/plugins/foo/tests/t.sh"
gate_commit "$d" "test: add a case"
run_gate "$d"; assert_no_out "silent on a tests/-only change" "$TRACE"

d="$(new_gate_repo)"; printf 'notes\n' > "$d/plugins/foo/CLAUDE.md"; gate_commit "$d" "docs: contributor notes"
run_gate "$d"; assert_no_out "silent on a CLAUDE.md-only change" "$TRACE"

# --- The notes builder --------------------------------------------------------
ALSO="Also in this release"

# The leak this exists for: a shipped change with no entry, riding inside the
# next plugin tag, has to appear in that release's notes.
d="$(new_gate_repo)"; git -C "$d" tag "foo/v1.0.0"
printf 'readme v2\n' > "$d/plugins/foo/README.md"; park "$d" "reworded"
gate_commit "$d" "docs: reword the README (#7)"
bump "$d" 1.1.0; clear_parked "$d"; gate_commit "$d" "feat: thing (v1.1.0)"
run_notes "$d" foo 1.1.0
assert_out "notes carry the version's own section" "- bumped"
assert_out "notes list an unbumped commit from the range" "docs: reword the README (#7)"
assert_out "the extra commits get their own heading" "$ALSO"
assert_no_out "the bump commit itself is not re-listed" "feat: thing (v1.1.0)"

# A commit whose PR is cited in the section is already described.
d="$(new_gate_repo)"; git -C "$d" tag "foo/v1.0.0"
printf 'readme v2\n' > "$d/plugins/foo/README.md"; gate_commit "$d" "docs: reword the README (#7)"
bump "$d" 1.1.0 "covers the README too (#7)"
gate_commit "$d" "feat: thing (v1.1.0)"
run_notes "$d" foo 1.1.0
assert_no_out "a commit cited by (#N) in the section is not repeated" "$ALSO"

# First release: no previous tag, so there is no range to describe.
d="$(new_gate_repo)"; bump "$d" 1.1.0; gate_commit "$d" "feat: thing (v1.1.0)"
run_notes "$d" foo 1.1.0
assert_no_out "no range section without a previous tag" "$ALSO"
assert_out "still prints the version's section" "- bumped"

# A tag that HEAD does not descend from must not be picked as the range start:
# the range would describe history this release never travelled.
d="$(new_gate_repo)"; git -C "$d" tag "foo/v1.0.0"
printf 'readme v2\n' > "$d/plugins/foo/README.md"; gate_commit "$d" "docs: reword the README (#7)"
git -C "$d" checkout -q -b side; bump "$d" 9.9.9; gate_commit "$d" "feat: side (v9.9.9)"
git -C "$d" tag "foo/v9.9.9"; git -C "$d" checkout -q work
bump "$d" 1.1.0; gate_commit "$d" "feat: thing (v1.1.0)"
run_notes "$d" foo 1.1.0
assert_out "falls back to the newest ancestor tag" "since foo/v1.0.0"

finish
