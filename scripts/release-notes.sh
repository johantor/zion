#!/usr/bin/env bash
# Builds one plugin release's notes: its CHANGELOG section, plus every commit
# that shipped inside the same tag without an entry of its own.
#
# The second half is the point. A tag carries everything merged since the previous
# tag, so a PR that touched shipped files without bumping (a README rewrite, a
# hook comment pass) used to go out inside a release that never mentioned it.
# Listing the range keeps the record complete when the per-PR discipline slips.
#
# Repo tooling, not part of any plugin: it needs this monorepo's layout and the
# `<plugin>/vX.Y.Z` tag scheme. Used by .github/workflows/auto-release.yml, and
# runnable locally to preview notes:
#   scripts/release-notes.sh plugins/crew 3.17.0
set -euo pipefail

plugin_dir="${1:-}"
version="${2:-}"
if [ -z "$plugin_dir" ] || [ -z "$version" ]; then
  echo "usage: $0 <plugin-dir> <version>   e.g. $0 plugins/crew 3.17.0" >&2
  exit 2
fi

plugin="$(basename "$plugin_dir")"
changelog="$plugin_dir/CHANGELOG.md"
[ -f "$changelog" ] || { echo "no changelog at $changelog" >&2; exit 1; }

# The version's own section: start at its heading, stop at the next `## [`. Only
# numeric headings are matched by the caller's existence check, so an
# `## [Unreleased]` block sitting above this section is never picked up here.
notes="$(awk -v ver="## [${version}]" '
  /^## \[/ { if (found) exit; if (index($0, ver) == 1) { found = 1; print; next } }
  found { print }
' "$changelog")"
[ -n "$notes" ] || { echo "no '## [${version}]' section in $changelog" >&2; exit 1; }

printf '%s\n' "$notes"

# Previous release of *this* plugin: the newest of its tags that HEAD actually
# descends from. `-v:refname` compares the embedded version numerically, so
# crew/v3.17.0 sorts above crew/v3.9.0. The ancestry test matters because a tag
# can exist outside this history (a release cut from another branch), and naming
# it as the range's start would describe a range HEAD never travelled.
prev_tag=""
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  [ "$tag" = "${plugin}/v${version}" ] && continue
  if git merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then prev_tag="$tag"; break; fi
done < <(git tag --list "${plugin}/v*" --sort=-v:refname)
# First release: there is no range to walk, so the section is just the changelog.
[ -n "$prev_tag" ] || exit 0

# Commits since that tag that touched this plugin. The exclusions are the same
# "shipped" definition check-changelog.sh gates on, so a change the gate does not
# ask anyone to describe cannot turn up in user-facing notes either; keep the two
# lists in step. Merges are skipped: PRs land squashed here, so a merge would only
# duplicate its own commits.
extra=""
while IFS=$'\t' read -r sha subject; do
  [ -n "$sha" ] || continue

  # A commit that touched the manifest is the bump itself; the section above is
  # its release notes, so listing it again would just echo the headline.
  if [ -n "$(git show --name-only --format='' "$sha" -- "$plugin_dir/.claude-plugin/plugin.json")" ]; then
    continue
  fi

  # Already cited: changelog entries reference their PR/issue as `(#N)`, so if
  # any number in the subject appears in the notes the change is described.
  cited=0
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$notes" in *"$ref"*) cited=1; break ;; esac
  done < <(printf '%s\n' "$subject" | grep -oE '#[0-9]+' || true)
  [ "$cited" -eq 1 ] && continue

  extra="${extra}- ${subject}"$'\n'
done < <(git log --no-merges --format='%H%x09%s' "${prev_tag}..HEAD" -- \
  "$plugin_dir" ":(exclude)${plugin_dir}/tests" ":(exclude)${changelog}" \
  ":(exclude)${plugin_dir}/CLAUDE.md" ":(exclude)${plugin_dir}/VERIFICATION.md")

[ -n "$extra" ] || exit 0

printf '\n### Also in this release\n\n'
# The backticks are Markdown code quoting in the released notes, not a command
# substitution — shellcheck can't tell the two apart inside a format string.
# shellcheck disable=SC2016
printf 'Changes to `%s` that landed since %s without a changelog entry of their own:\n\n' \
  "$plugin_dir" "$prev_tag"
printf '%s' "$extra"
