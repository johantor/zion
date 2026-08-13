#!/usr/bin/env bash
# Fails a PR whose shipped changes would leave no trace in any release notes.
#
# Users receive a plugin through `claude plugin update`, which keys on `version`,
# and the release notes for a version are that version's CHANGELOG section. So a
# PR that edits shipped files without either bumping or writing an entry ships
# silently: it rides inside whichever tag comes next, described nowhere. Both
# escapes are checked here, in both directions:
#
#   1. shipped files changed  -> bump the version, or park a bullet under
#      `## [Unreleased]` for the next bump to fold in.
#   2. version bumped         -> `## [Unreleased]` must be empty, because
#      auto-release only reads the version's own section and would drop
#      whatever was still parked.
#
# Shipped = everything under plugins/<name>/ except `tests/` (repo tooling),
# `CLAUDE.md` and `VERIFICATION.md` (contributor material), and `CHANGELOG.md`
# itself. README.md counts: it is what a user reads to work the plugin.
#
# Repo tooling, not part of any plugin. Diff-based, so unlike
# validate-plugin.sh it needs a base ref — CI passes the PR's base branch:
#   scripts/check-changelog.sh [<base-ref>]     # default: origin/main
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
ok()  { echo "ok:   $*"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

base_ref="${1:-${GITHUB_BASE_REF:-main}}"
# Remote-tracking form first: on CI the local branch of the same name is either
# absent or the PR head itself, and diffing against that finds nothing.
base_sha=""
for candidate in "origin/$base_ref" "$base_ref"; do
  if base_sha="$(git rev-parse --verify --quiet "$candidate^{commit}")"; then break; fi
done
[ -n "$base_sha" ] || { echo "FAIL: cannot resolve base ref '$base_ref'" >&2; exit 1; }

# Compare against the merge base, not the base tip: unrelated commits that
# landed on the base branch since this PR forked are not this PR's changes.
merge_base="$(git merge-base "$base_sha" HEAD)"

# unreleased_bullets — reads a CHANGELOG on stdin, prints the bullet lines of its
# `## [Unreleased]` section. Bullets only, so reflowing or a blank-line change
# can't pass as a recorded note.
unreleased_bullets() {
  awk '
    /^## \[Unreleased\]/ { in_u = 1; next }
    /^## \[/             { in_u = 0 }
    in_u && /^[-*][[:space:]]/ { print }
  '
}

# at_rev <rev> <path> — file contents at a revision, empty if it did not exist.
at_rev() { git show "$1:$2" 2>/dev/null || true; }

while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"  # plugins/<name>
  changelog="$plugin_dir/CHANGELOG.md"

  # Shipped files this PR touched in this plugin. Compared against the working
  # tree rather than HEAD so the check is useful mid-branch, before committing;
  # on CI the two are the same thing. (Untracked files are invisible to `git
  # diff`, so a brand-new file only registers locally once it is staged.)
  # Pathspec exclusions mirror the "Shipped =" comment above; keep the two in step.
  changed="$(git diff --name-only "$merge_base" -- "$plugin_dir" \
    ":(exclude)${plugin_dir}/tests" \
    ":(exclude)${changelog}" \
    ":(exclude)${plugin_dir}/CLAUDE.md" \
    ":(exclude)${plugin_dir}/VERIFICATION.md")"

  base_version="$(at_rev "$merge_base" "$manifest" | jq -r '.version // empty' 2>/dev/null || true)"
  head_version="$(jq -r '.version // empty' "$manifest")"
  bumped=0
  if [ "$base_version" != "$head_version" ]; then bumped=1; fi

  parked_head="$(unreleased_bullets < "$changelog")"
  parked_base="$(at_rev "$merge_base" "$changelog" | unreleased_bullets)"

  # Direction 2 first: a bump must leave the parking slot empty, or auto-release
  # ships the version without the notes still sitting in it.
  if [ "$bumped" -eq 1 ] && [ -n "$parked_head" ]; then
    err "$plugin_dir bumps to $head_version but $changelog still has bullets under '## [Unreleased]'; fold them into the [$head_version] section (auto-release reads only that section, so they would ship undescribed)"
    continue
  fi

  if [ -z "$changed" ]; then
    continue
  fi

  if [ "$bumped" -eq 1 ]; then
    ok "$plugin_dir: shipped files changed, version bumped $base_version -> $head_version"
  elif [ -n "$parked_head" ] && [ "$parked_head" != "$parked_base" ]; then
    ok "$plugin_dir: shipped files changed, note parked under '## [Unreleased]'"
  else
    err "$plugin_dir changes shipped files with no release-notes trace: bump 'version' in $manifest with a matching '## [X.Y.Z]' entry, or add a bullet under '## [Unreleased]' in $changelog citing this PR as (#N). Changed: $(printf '%s' "$changed" | tr '\n' ' ')"
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

if [ "$fail" -ne 0 ]; then
  echo "Changelog check failed." >&2
  exit 1
fi
echo "Changelog check passed."
