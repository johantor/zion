#!/usr/bin/env bash
# Fails a PR that changes a plugin's shipped files without bumping its version.
#
# Users receive a plugin through `claude plugin update`, which keys on `version`,
# and a version's release notes are its CHANGELOG section (validate-plugin.sh
# §2h pairs the two). So a PR that edits shipped files without a bump rides
# inside whichever tag comes next, described nowhere. One rule, no exceptions:
# a shipped change bumps (AGENTS.md, "Releasing").
#
# Shipped = everything under plugins/<name>/ except `tests/` (repo tooling),
# `CLAUDE.md` and `VERIFICATION.md` (contributor material), and `CHANGELOG.md`
# itself. README.md counts: it is what a user reads to work the plugin.
#
# Repo tooling, not part of any plugin. Diff-based, so unlike validate-plugin.sh
# it needs a base ref — CI passes the PR's base branch:
#   scripts/check-changelog.sh [<branch>]     # default: main
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

while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"  # plugins/<name>

  # Shipped files this PR touched. Compared against the working tree rather than
  # HEAD so the check is useful mid-branch; on CI the two are the same thing.
  # (Untracked files are invisible to `git diff`, so a new file only registers
  # locally once it is staged.)
  changed="$(git diff --name-only "$merge_base" -- "$plugin_dir" \
    ":(exclude)${plugin_dir}/tests" \
    ":(exclude)${plugin_dir}/CHANGELOG.md" \
    ":(exclude)${plugin_dir}/CLAUDE.md" \
    ":(exclude)${plugin_dir}/VERIFICATION.md")"
  [ -n "$changed" ] || continue

  base_version="$(git show "$merge_base:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  head_version="$(jq -r '.version // empty' "$manifest")"
  if [ "$base_version" != "$head_version" ]; then
    ok "$plugin_dir: shipped files changed, version bumped ${base_version:-none} -> $head_version"
  else
    err "$plugin_dir changes shipped files without a version bump: bump 'version' in $manifest and add a matching '## [X.Y.Z]' entry to $plugin_dir/CHANGELOG.md. Changed: $(printf '%s' "$changed" | tr '\n' ' ')"
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

if [ "$fail" -ne 0 ]; then
  echo "Changelog check failed." >&2
  exit 1
fi
echo "Changelog check passed."
