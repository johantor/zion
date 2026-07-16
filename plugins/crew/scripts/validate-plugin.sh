#!/usr/bin/env bash
# Validates every plugin's structure so manifest/file drift fails fast.
# Runnable locally (`plugins/crew/scripts/validate-plugin.sh`) and in CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
ok()  { echo "ok:   $*"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# 1. Every JSON file parses.
while IFS= read -r f; do
  if jq empty "$f" >/dev/null 2>&1; then
    ok "valid JSON: $f"
  else
    err "invalid JSON: $f"
  fi
done < <(git ls-files '*.json')

# 2. Validate each plugin under plugins/<name>/. Component paths in a plugin
#    manifest are resolved relative to that plugin's root.
while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"  # plugins/<name>
  if ! jq empty "$manifest" >/dev/null 2>&1; then
    # Malformed JSON is already reported above; skip content checks.
    err "$manifest is not valid JSON; skipping content checks"
    continue
  fi

  # 2a. Required identity fields.
  for key in name version; do
    if [ "$(jq -r --arg k "$key" 'has($k)' "$manifest")" != "true" ]; then
      err "$manifest missing required key: $key"
    else
      ok "$plugin_dir has key: $key"
    fi
  done

  # 2b. Component paths the manifest points at actually exist. A field may be a
  #     single path string or an array of paths; validate every path.
  #     Note: `hooks` is intentionally NOT validated here — the standard
  #     hooks/hooks.json is auto-loaded, so it must NOT be declared in the
  #     manifest (doing so triggers a "Duplicate hooks file" load error).
  for key in commands skills; do
    while IFS= read -r path; do
      path="${path%$'\r'}"  # tolerate CRLF checkouts on Windows
      [ -z "$path" ] && continue
      if [ -e "$plugin_dir/$path" ]; then
        ok "$plugin_dir $key -> $path exists"
      else
        err "$plugin_dir $key -> $path declared in $manifest but not found"
      fi
    done < <(jq -r --arg k "$key" '(.[$k] // empty) | if type == "array" then .[] else . end' "$manifest")
  done

  # 2c. The manifest may declare *additional* hook files, but must NOT declare the
  #     standard hooks/hooks.json — it is auto-loaded, so declaring it triggers a
  #     "Duplicate hooks file" load error. Validate that additional files exist.
  while IFS= read -r path; do
    path="${path%$'\r'}"  # tolerate CRLF checkouts on Windows
    [ -z "$path" ] && continue
    if [ "${path#./}" = "hooks/hooks.json" ]; then
      err "$plugin_dir declares the auto-loaded hooks/hooks.json in its manifest; remove it (only additional hook files belong in manifest.hooks)"
    elif [ -e "$plugin_dir/$path" ]; then
      ok "$plugin_dir hooks -> $path exists (additional hook file)"
    else
      err "$plugin_dir hooks -> $path declared in $manifest but not found"
    fi
  done < <(jq -r '(.hooks // empty) | if type == "array" then .[] else . end' "$manifest")

  # 2d. Agents are auto-discovered from the plugin's `agents/` directory, not the
  #     manifest (declaring them there passes validation but they never load).
  #     The directory itself is optional — a commands/skills-only plugin is fine —
  #     but if it exists it must contain agent files (an empty dir means drift).
  if [ -d "$plugin_dir/agents" ]; then
    if ls "$plugin_dir"/agents/*.md >/dev/null 2>&1; then
      ok "$plugin_dir agents/ exists with agent files"
    else
      err "$plugin_dir agents/ exists but has no .md agent files (agents are auto-discovered from there)"
    fi
  else
    ok "$plugin_dir has no agents/ (optional)"
  fi

  # 2e. Hooks are optional, but a hooks/ directory without the auto-loaded
  #     hooks/hooks.json means the hook scripts in it never run.
  if [ -d "$plugin_dir/hooks" ]; then
    if [ -f "$plugin_dir/hooks/hooks.json" ]; then
      ok "$plugin_dir hooks/hooks.json exists (auto-loaded)"
    else
      err "$plugin_dir hooks/ exists but hooks/hooks.json missing (nothing wires the hooks)"
    fi
  else
    ok "$plugin_dir has no hooks/ (optional)"
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

# 2f. Marketplace entries agree with the plugins on disk: every listed source
#     exists, has a manifest, its manifest name matches the entry name, and its
#     description matches the manifest's (plugin.json is canonical — the two
#     read the same to users, so wording drift is a doc bug).
marketplace=".claude-plugin/marketplace.json"
if [ -f "$marketplace" ] && jq empty "$marketplace" >/dev/null 2>&1; then
  while IFS=$'\t' read -r mname msource; do
    msource="${msource%$'\r'}"  # tolerate CRLF checkouts on Windows
    src="${msource#./}"
    if [ ! -d "$src" ]; then
      err "$marketplace entry '$mname': source $msource does not exist"
      continue
    fi
    pmanifest="$src/.claude-plugin/plugin.json"
    if [ ! -f "$pmanifest" ]; then
      err "$marketplace entry '$mname': $pmanifest missing"
      continue
    fi
    pname="$(jq -r '.name // empty' "$pmanifest")"
    pname="${pname%$'\r'}"  # tolerate CRLF checkouts on Windows
    if [ "$pname" = "$mname" ]; then
      ok "$marketplace entry '$mname' matches $pmanifest"
    else
      err "$marketplace entry '$mname' != plugin.json name '$pname' ($pmanifest)"
    fi
    # Descriptions are compared via jq (not the @tsv fields above) so tabs or
    # escapes in either value can't skew the comparison.
    mdesc="$(jq -r --arg n "$mname" '.plugins[] | select(.name == $n) | .description // ""' "$marketplace")"
    pdesc="$(jq -r '.description // ""' "$pmanifest")"
    if [ "$mdesc" = "$pdesc" ]; then
      ok "$marketplace entry '$mname' description matches $pmanifest"
    else
      err "$marketplace entry '$mname' description differs from $pmanifest (plugin.json is canonical; copy it into the marketplace entry)"
    fi
  done < <(jq -r '.plugins[] | select((.source | type) == "string") | [.name, .source] | @tsv' "$marketplace")
else
  err "$marketplace missing or invalid"
fi

# 2g. Every skill referenced in an agent's YAML frontmatter `skills:` list must
#     resolve to some plugins/*/skills/<name>/SKILL.md in the repo. Skills are
#     referenced unqualified (per the existing convention), so resolution is
#     "exists anywhere under any plugin's skills/ directory". A typo here would
#     otherwise fail silently at runtime — the skill just doesn't load.
declare -A skill_index=()
while IFS= read -r skill_md; do
  skill_name="$(basename "$(dirname "$skill_md")")"
  skill_index["$skill_name"]=1
done < <(git ls-files 'plugins/*/skills/*/SKILL.md')

while IFS= read -r agent; do
  while IFS= read -r skill_ref; do
    [ -z "$skill_ref" ] && continue
    if [ -n "${skill_index[$skill_ref]:-}" ]; then
      ok "$agent skills -> $skill_ref resolves"
    else
      err "$agent skills -> $skill_ref does not resolve to any plugins/*/skills/$skill_ref/SKILL.md"
    fi
  done < <(awk '
    BEGIN { in_fm = 0; in_skills = 0 }
    /^---[[:space:]]*$/ {
      if (in_fm == 0) { in_fm = 1; next }
      else { exit }
    }
    in_fm && in_skills {
      if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, "")
        sub(/[[:space:]]+#.*$/, "")
        sub(/[[:space:]]+$/, "")
        gsub(/^["\047]|["\047]$/, "")
        if (length($0)) print
        next
      } else if ($0 !~ /^[[:space:]]*$/) {
        in_skills = 0
      }
    }
    in_fm && /^skills:[[:space:]]*$/ { in_skills = 1 }
  ' "$agent")
done < <(git ls-files 'plugins/*/agents/*.md')

# 2h. Each plugin's manifest version must match the newest entry in its CHANGELOG,
#     so a version bump can't ship without release notes (auto-release.yml pulls
#     notes from that section) and notes can't land without a bump. crew's
#     changelog is the repo-root CHANGELOG.md; every other plugin keeps its own.
while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"  # plugins/<name>
  # Malformed JSON is already reported by §1; skip so a bad manifest doesn't abort
  # the whole run under `set -e` (mirrors the §2 loop).
  jq empty "$manifest" >/dev/null 2>&1 || continue
  plugin_version="$(jq -r '.version // empty' "$manifest")"
  [ -z "$plugin_version" ] && continue  # missing version already reported by 2a
  if [ "$(basename "$plugin_dir")" = "crew" ]; then
    changelog="CHANGELOG.md"
  else
    changelog="$plugin_dir/CHANGELOG.md"
  fi
  if [ ! -f "$changelog" ]; then
    err "$plugin_dir declares version $plugin_version but has no changelog at $changelog"
    continue
  fi
  # grep -m1 reads the file directly and stops at the first hit (no `| head`,
  # which could SIGPIPE the producer under `set -o pipefail`); strip with
  # parameter expansion. `|| true` swallows grep's exit 1 when there's no match.
  newest_line="$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$changelog" || true)"
  newest_entry="${newest_line#*\[}"
  newest_entry="${newest_entry%%\]*}"
  if [ "$newest_entry" = "$plugin_version" ]; then
    ok "$plugin_dir version $plugin_version matches newest $changelog entry"
  else
    err "$plugin_dir version $plugin_version != newest $changelog entry (${newest_entry:-none}); bump the manifest and add its CHANGELOG entry together"
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

# 3. Hook scripts are syntactically valid and executable.
while IFS= read -r h; do
  if bash -n "$h" 2>/dev/null; then
    ok "syntax: $h"
  else
    err "bash syntax error: $h"
  fi
  if [ -x "$h" ]; then
    ok "executable: $h"
  else
    err "not executable (chmod +x): $h"
  fi
done < <(git ls-files 'plugins/*/hooks/*.sh')

# 4. Skill drift: any skill name shipped by more than one plugin must stay
#    byte-for-byte identical across every copy. Generic by skill *name*, not
#    hardcoded to any specific pair of plugins — grouping every SKILL.md by its
#    directory basename catches drift between any two plugins that happen to
#    ship the same skill, today or in the future, not just ones crew is party
#    to. When crew ships the skill, its copy is the reference (crew is the
#    documented canonical source for shared skills — see AGENTS.md); otherwise
#    the first copy found is the reference, and every other copy is compared
#    against it. Compares whole skill directories (diff -rq) so missing/extra
#    reference files count as drift too, not just SKILL.md changes.
declare -A skill_dirs=()
while IFS= read -r skill_md; do
  dir="$(dirname "$skill_md")"
  name="$(basename "$dir")"
  skill_dirs["$name"]="${skill_dirs["$name"]:-}${skill_dirs["$name"]:+ }$dir"
done < <(git ls-files 'plugins/*/skills/*/SKILL.md')

for name in "${!skill_dirs[@]}"; do
  # shellcheck disable=SC2206  # intentional word-splitting: dirs never contain spaces
  dirs=(${skill_dirs["$name"]})
  [ "${#dirs[@]}" -lt 2 ] && continue
  reference=""
  for d in "${dirs[@]}"; do
    case "$d" in plugins/crew/skills/*) reference="$d" ;; esac
  done
  [ -z "$reference" ] && reference="${dirs[0]}"
  for d in "${dirs[@]}"; do
    [ "$d" = "$reference" ] && continue
    if diff -rq "$reference" "$d" >/dev/null 2>&1; then
      ok "skill in sync: $d == $reference"
    else
      err "skill drift: $d differs from $reference (skill '$name' shipped by multiple plugins)"
    fi
  done
done

# 5. Hook-script drift: a hook script filename shipped by more than one plugin
#    must stay in sync across every copy — same policy as §4 for skills, and
#    crew's copy is likewise the reference when crew ships the file (else the
#    first copy found). Two regimes:
#      - no shared-guard markers in the reference -> the whole file must be
#        byte-identical (today: read-guard.sh);
#      - regions delimited by "# --- BEGIN shared guard: <label> ---" ...
#        "# --- END shared guard: <label> ---" -> only the marked regions must
#        match (labels, contents, and order), since the rest is per-plugin
#        policy (today: bash-safety.sh).
#    Unbalanced markers are a failure: a sync check that can't parse its
#    regions can't verify its claim.
declare -A hook_groups=()
while IFS= read -r h; do
  b="$(basename "$h")"
  hook_groups["$b"]="${hook_groups["$b"]:-}${hook_groups["$b"]:+ }$h"
done < <(git ls-files 'plugins/*/hooks/*.sh')

# Print each marked region as "=== <label> ===" followed by its lines, so two
# files' shared regions can be compared as plain strings.
shared_regions() {
  awk '
    /^# --- BEGIN shared guard: .* ---/ {
      label = $0
      sub(/^# --- BEGIN shared guard: /, "", label)
      sub(/ ---.*$/, "", label)
      print "=== " label " ==="
      inblock = 1
      next
    }
    /^# --- END shared guard: / { inblock = 0; next }
    inblock { print }
  ' "$1"
}

for b in "${!hook_groups[@]}"; do
  # shellcheck disable=SC2206  # intentional word-splitting: paths never contain spaces
  copies=(${hook_groups["$b"]})
  [ "${#copies[@]}" -lt 2 ] && continue
  reference=""
  for h in "${copies[@]}"; do
    case "$h" in plugins/crew/hooks/*) reference="$h" ;; esac
  done
  [ -z "$reference" ] && reference="${copies[0]}"
  marker_balance_ok=1
  for h in "${copies[@]}"; do
    begins="$(grep -c '^# --- BEGIN shared guard: ' "$h" || true)"
    ends="$(grep -c '^# --- END shared guard: ' "$h" || true)"
    if [ "$begins" != "$ends" ]; then
      err "$h has $begins BEGIN but $ends END shared-guard markers; fix the markers so the sync check can run"
      marker_balance_ok=0
    fi
  done
  [ "$marker_balance_ok" = 1 ] || continue
  ref_regions="$(shared_regions "$reference")"
  for h in "${copies[@]}"; do
    [ "$h" = "$reference" ] && continue
    if [ -z "$ref_regions" ]; then
      if diff -q "$reference" "$h" >/dev/null 2>&1; then
        ok "hook in sync: $h == $reference"
      else
        err "hook drift: $h differs from $reference (hook '$b' shipped by multiple plugins with no shared-guard markers, so copies must be byte-identical)"
      fi
    elif [ "$(shared_regions "$h")" = "$ref_regions" ]; then
      ok "hook shared-guard regions in sync: $h == $reference"
    else
      err "hook drift: shared-guard regions in $h differ from $reference (labels, contents, and order must match; crew's copy is canonical)"
    fi
  done
done

# 6. Hook wiring cross-check: every command in a plugin's hooks/hooks.json must
#    resolve (via its "${CLAUDE_PLUGIN_ROOT}"/ prefix) to a file in that plugin,
#    and every hooks/*.sh on disk must be wired by some command — an unwired
#    guard script silently never runs (the same failure class §2g catches for
#    agent skills: references).
# Single-quoted: the literal, unexpanded prefix as it appears in the JSON.
# shellcheck disable=SC2016
wiring_pfx='"${CLAUDE_PLUGIN_ROOT}"/'
while IFS= read -r hooks_json; do
  plugin_dir="${hooks_json%/hooks/hooks.json}"
  # Malformed JSON is already reported by §1; skip the cross-check.
  if ! jq empty "$hooks_json" >/dev/null 2>&1; then
    err "$hooks_json is not valid JSON; cannot cross-check its hook wiring"
    continue
  fi
  declare -A wired=()
  while IFS= read -r hcmd; do
    hcmd="${hcmd%$'\r'}"  # tolerate CRLF checkouts on Windows
    [ -z "$hcmd" ] && continue
    rel="${hcmd#"$wiring_pfx"}"
    if [ "$rel" = "$hcmd" ]; then
      err "$hooks_json command '$hcmd' does not start with $wiring_pfx — a plugin's own hooks must resolve through CLAUDE_PLUGIN_ROOT"
      continue
    fi
    rel="${rel%% *}"  # a command may carry arguments; the script path is the first token
    if [ -f "$plugin_dir/$rel" ]; then
      ok "$hooks_json -> $rel exists"
    else
      err "$hooks_json wires $rel but $plugin_dir/$rel does not exist"
    fi
    wired["$rel"]=1
  done < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command // empty' "$hooks_json")
  while IFS= read -r sh_file; do
    rel="${sh_file#"$plugin_dir/"}"
    if [ -n "${wired[$rel]:-}" ]; then
      ok "$plugin_dir wires $rel"
    else
      err "$sh_file exists but is not wired in $hooks_json — it never runs"
    fi
  done < <(git ls-files "$plugin_dir/hooks/*.sh")
done < <(git ls-files 'plugins/*/hooks/hooks.json')

# 7. This repo's dev-time hook wiring (.claude/settings.json) must mirror the
#    installed-plugin wiring (plugins/crew/hooks/hooks.json), modulo the root
#    variable each resolves through (CLAUDE_PROJECT_DIR vs CLAUDE_PLUGIN_ROOT)
#    -- see AGENTS.md for why both exist.
dev_hooks=".claude/settings.json"
plugin_hooks="plugins/crew/hooks/hooks.json"
if [ ! -f "$dev_hooks" ]; then
  err "$dev_hooks is missing -- expected to mirror $plugin_hooks (see AGENTS.md)"
elif [ ! -f "$plugin_hooks" ]; then
  err "$plugin_hooks is missing -- required for the crew plugin's hooks to load"
elif ! jq empty "$dev_hooks" >/dev/null 2>&1; then
  err "$dev_hooks is not valid JSON; cannot verify it mirrors $plugin_hooks"
elif ! jq empty "$plugin_hooks" >/dev/null 2>&1; then
  err "$plugin_hooks is not valid JSON; cannot verify $dev_hooks mirrors it"
else
  hook_sig() {
    jq -r --arg strip "$2" '
      .hooks | to_entries[] | .key as $event | .value[] |
      .matcher as $matcher | .hooks[] |
      [$event, $matcher, (.command | ltrimstr($strip)), (.timeout // "none")] | @tsv
    ' "$1" | sort
  }
  # Single-quoted: literal, unexpanded "${VAR}" text as it appears in the JSON.
  # shellcheck disable=SC2016
  dev_sig="$(hook_sig "$dev_hooks" '"${CLAUDE_PROJECT_DIR}"/plugins/crew/hooks/')"
  # shellcheck disable=SC2016
  plugin_sig="$(hook_sig "$plugin_hooks" '"${CLAUDE_PLUGIN_ROOT}"/hooks/')"
  if [ "$dev_sig" = "$plugin_sig" ]; then
    ok "hook wiring in sync: $dev_hooks == $plugin_hooks (modulo root variable)"
  else
    err "hook wiring drift: $dev_hooks no longer mirrors $plugin_hooks -- compare PreToolUse/PostToolUse matchers, script paths, and timeouts"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "Plugin validation passed."
