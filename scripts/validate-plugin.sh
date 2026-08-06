#!/usr/bin/env bash
# Validates every plugin's structure so manifest/file drift fails fast.
# Repo tooling, not part of any plugin: it needs this monorepo's layout and
# never runs in an installed plugin. Runnable locally (`scripts/validate-plugin.sh`)
# and in CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
ok()  { echo "ok:   $*"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# Associative arrays (declare -A in §2g/§4/§5/§6/§8) need Bash 4+; macOS's
# stock /bin/bash is 3.2. Fail with a pointer instead of the cryptic
# `declare: -A: invalid option` those sections would otherwise die with.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "FAIL: this validator needs Bash >= 4 (associative arrays); on macOS run it with a newer bash (e.g. brew install bash)" >&2
  exit 1
fi

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
#     notes from that section) and notes can't land without a bump. Every plugin
#     keeps its changelog next to its manifest: plugins/<name>/CHANGELOG.md.
while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"  # plugins/<name>
  # Malformed JSON is already reported by §1; skip so a bad manifest doesn't abort
  # the whole run under `set -e` (mirrors the §2 loop).
  jq empty "$manifest" >/dev/null 2>&1 || continue
  plugin_version="$(jq -r '.version // empty' "$manifest")"
  [ -z "$plugin_version" ] && continue  # missing version already reported by 2a
  changelog="$plugin_dir/CHANGELOG.md"
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
#    Structurally invalid markers — a stray END, a nested BEGIN, a label that
#    doesn't pair up, an unclosed block, or a marker missing its trailing
#    " ---" — are a failure: a sync check that can't parse its regions can't
#    verify its claim, and would otherwise silently compare the wrong content.
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
    /^# --- END shared guard: .* ---/ { inblock = 0; next }
    inblock { print }
  ' "$1"
}

# Structural marker validation for one file: BEGIN/END must strictly alternate
# (no nesting, no stray END), the END label must match the open BEGIN's, every
# block must close by EOF, and a marker-prefixed line must carry the full
# "... ---" shape. Prints one line per problem; silence means the markers are
# sound and shared_regions can be trusted.
marker_errors() {
  awk '
    /^# --- (BEGIN|END) shared guard: / {
      is_begin = ($0 ~ /^# --- BEGIN /)
      if ($0 !~ / ---[[:space:]]*$/) {
        print "marker at line " NR " is missing its trailing \" ---\""
        next
      }
      label = $0
      sub(/^# --- (BEGIN|END) shared guard: /, "", label)
      sub(/ ---[[:space:]]*$/, "", label)
      if (is_begin) {
        if (open != "") print "BEGIN \"" label "\" at line " NR " nests inside open block \"" open "\""
        open = label
      } else {
        if (open == "") print "END \"" label "\" at line " NR " has no matching BEGIN"
        else if (label != open) print "END \"" label "\" at line " NR " does not match open BEGIN \"" open "\""
        open = ""
      }
      next
    }
    END { if (open != "") print "BEGIN \"" open "\" is never closed" }
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
  markers_ok=1
  for h in "${copies[@]}"; do
    problems="$(marker_errors "$h")"
    [ -z "$problems" ] && continue
    while IFS= read -r problem; do
      err "$h shared-guard $problem; fix the markers so the sync check can verify its regions"
    done <<<"$problems"
    markers_ok=0
  done
  [ "$markers_ok" = 1 ] || continue
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
  # Fail loudly on a structurally wrong file (valid JSON, wrong shape): the
  # extraction below would otherwise spray a raw jq error and report every
  # script as "not wired", which misdiagnoses the actual problem.
  if ! jq -e '(.hooks | type == "object")
              and ([.hooks[] | type == "array"] | all)
              and ([.hooks[][] | .hooks | type == "array"] | all)' "$hooks_json" >/dev/null 2>&1; then
    err "$hooks_json does not have the expected shape ({hooks: {<event>: [{hooks: [{command}]}]}}); cannot cross-check its hook wiring"
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

# 8. Turn-budget table <-> agent frontmatter lockstep: a plugin that ships
#    hooks/turn-budget.sh keeps a per-agent budget table (`<name>) budget=<n> ;;`
#    lines — the hook documents that shape as load-bearing) that must equal each
#    of that plugin's agents' frontmatter `maxTurns`, both ways: every agent
#    with a maxTurns needs exactly one matching entry, and every entry must map
#    back to such an agent (no stale rows after a rename/removal). Without this,
#    a maxTurns edit silently miscalibrates the wind-down warnings.
while IFS= read -r tb_hook; do
  plugin_dir="${tb_hook%/hooks/turn-budget.sh}"
  # Extract "name n" pairs from the table. A hook whose table yields nothing is
  # a loud failure: a lockstep check that can't parse its subject can't verify
  # its claim (see AGENTS.md).
  table="$(sed -n 's/^[[:space:]]*\([A-Za-z0-9_-]\{1,\}\))[[:space:]]*budget=\([0-9]\{1,\}\)[[:space:]]*;;.*$/\1 \2/p' "$tb_hook")"
  if [ -z "$table" ]; then
    err "$tb_hook has no parseable budget table (expected '<agent>) budget=<n> ;;' lines); cannot verify it matches agent maxTurns"
    continue
  fi
  declare -A tb_budget=() tb_seen=()
  dup=0
  while read -r tname tval; do
    [ -z "$tname" ] && continue
    if [ -n "${tb_budget[$tname]:-}" ]; then
      err "$tb_hook has duplicate budget entries for '$tname'"
      dup=1
    fi
    tb_budget["$tname"]="$tval"
  done <<<"$table"
  [ "$dup" -ne 0 ] && continue
  while IFS= read -r agent; do
    aname="$(basename "$agent" .md)"
    aturns="$(awk '
      /^---[[:space:]]*$/ { if (in_fm == 0) { in_fm = 1; next } else exit }
      in_fm && /^maxTurns:[[:space:]]*[0-9]+[[:space:]]*$/ { sub(/^maxTurns:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }
    ' "$agent")"
    if [ -z "$aturns" ]; then
      # No maxTurns -> unbounded agent, no budget to enforce; a table entry for
      # it is stale and caught by the reverse pass below.
      ok "$agent has no maxTurns (no turn-budget entry required)"
      continue
    fi
    tb_seen["$aname"]=1
    if [ -z "${tb_budget[$aname]:-}" ]; then
      err "$tb_hook has no budget entry for agent '$aname' (maxTurns: $aturns); add '$aname) budget=$aturns ;;'"
    elif [ "${tb_budget[$aname]}" = "$aturns" ]; then
      ok "$tb_hook budget for '$aname' matches maxTurns ($aturns)"
    else
      err "$tb_hook budget for '$aname' (${tb_budget[$aname]}) != $agent maxTurns ($aturns); keep the table in lockstep"
    fi
  done < <(git ls-files "$plugin_dir/agents/*.md")
  for tname in "${!tb_budget[@]}"; do
    if [ -z "${tb_seen[$tname]:-}" ]; then
      err "$tb_hook budget entry '$tname' does not match any $plugin_dir/agents/*.md with a maxTurns; remove the stale row"
    fi
  done
done < <(git ls-files 'plugins/*/hooks/turn-budget.sh')

# 9. Hook rosters <-> agent frontmatter lockstep (same shape as §8, for the two
#    facts that guard write access rather than turn count). A hook that gates on
#    a hardcoded list of agent names fails OPEN for any name missing from it: add
#    an eighth agent and it silently gets unrestricted git and no write lane. The
#    agents declare the fact (`owns-git:`, `lane-guarded:`), the hooks carry the
#    roster, and this keeps them equal both ways.
#
#    Opt-in per plugin: a plugin whose agents declare `owns-git` must carry the
#    `# crew-roster: no-git` marker, and likewise `lane-guarded` <-> the
#    `# crew-roster: lane-guarded` marker. A plugin that declares neither is
#    skipped, so this doesn't force the shape onto plugins that gate differently
#    (keymaker's twin check is a plain `[ "$agent_type" = ... ]`).
#
#    Note: lane-guard.sh's per-agent dispatch arms further down are NOT checked
#    against the roster — they sit inside a nested `case` on the e2e tool, and a
#    parser that can't reliably tell the two apart would report false lockstep.
#    The hook's own comment is the only thing holding those in sync today.

# Read one `key: value` from a Markdown file's YAML frontmatter.
fm_field() {
  awk -v key="$2" '
    /^---[[:space:]]*$/ { if (in_fm == 0) { in_fm = 1; next } else exit }
    in_fm && index($0, key ":") == 1 {
      sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit
    }
  ' "$1"
}

# Read the `a|b|c)` case arm on the line following a `# crew-roster: <name>`
# marker, as space-separated names.
roster_arm() {
  awk -v marker="# crew-roster: $2" '
    found && /^[[:space:]]*[A-Za-z0-9_|-]+\)/ {
      sub(/^[[:space:]]*/, ""); sub(/\).*$/, ""); gsub(/\|/, " "); print; exit
    }
    index($0, marker) == 1 { found = 1 }
  ' "$1"
}

while IFS= read -r plugin_manifest; do
  plugin_dir="${plugin_manifest%/.claude-plugin/plugin.json}"
  agents=()
  while IFS= read -r a; do [ -n "$a" ] && agents+=("$a"); done \
    < <(git ls-files "$plugin_dir/agents/*.md")
  [ "${#agents[@]}" -eq 0 ] && continue

  # Does this plugin opt in? (any agent declaring the field)
  declares_git=0 declares_lane=0
  for agent in "${agents[@]}"; do
    [ -n "$(fm_field "$agent" owns-git)" ] && declares_git=1
    [ -n "$(fm_field "$agent" lane-guarded)" ] && declares_lane=1
  done

  if [ "$declares_git" -eq 1 ]; then
    hook="$plugin_dir/hooks/bash-safety.sh"
    # Not `arm="$([ -f ... ] && ...)"`: a missing hook makes the substitution
    # exit non-zero, which under `set -e` aborts the whole validator.
    arm=""
    if [ -f "$hook" ]; then arm="$(roster_arm "$hook" no-git)"; fi
    read -ra arm_names <<<"$arm"
    if [ -z "$arm" ]; then
      err "$plugin_dir agents declare 'owns-git' but $hook has no parseable '# crew-roster: no-git' marker + case arm; cannot verify the no-git roster"
    else
      declare -A no_git=() git_seen=()
      for n in "${arm_names[@]}"; do no_git["$n"]=1; done
      owners=()
      for agent in "${agents[@]}"; do
        aname="$(basename "$agent" .md)"
        owns="$(fm_field "$agent" owns-git)"
        case "$owns" in
          true|false) ;;
          "") err "$agent has no 'owns-git' (sibling agents declare it); add 'owns-git: true|false'"; continue ;;
          *) err "$agent has 'owns-git: $owns'; expected true or false"; continue ;;
        esac
        [ "$owns" = true ] && owners+=("$aname")
        git_seen["$aname"]=1
        # Bash-less agents can't run git at all, so they need no roster entry.
        has_bash=0
        case ",$(fm_field "$agent" tools | tr -d ' ')," in *,Bash,*) has_bash=1 ;; esac
        if [ "$owns" = true ]; then
          if [ -n "${no_git[$aname]:-}" ]; then
            err "$hook lists the git owner '$aname' in its no-git roster; remove it or flip 'owns-git' in $agent"
          else
            ok "$aname owns git and is absent from $hook's no-git roster"
          fi
        elif [ "$has_bash" -eq 1 ]; then
          if [ -n "${no_git[$aname]:-}" ]; then
            ok "$hook no-git roster covers Bash-capable '$aname'"
          else
            err "$hook has no no-git roster entry for '$aname' (owns-git: false, has Bash); it would run git unguarded -- add it to the arm"
          fi
        elif [ -n "${no_git[$aname]:-}" ]; then
          err "$hook lists '$aname' in its no-git roster, but $agent has no Bash tool; remove the dead entry"
        else
          ok "$aname has no Bash tool (no no-git roster entry required)"
        fi
      done
      if [ "${#owners[@]}" -ne 1 ]; then
        err "$plugin_dir/agents must declare exactly one agent with 'owns-git: true' (found ${#owners[@]}: ${owners[*]:-none})"
      fi
      for n in "${arm_names[@]}"; do
        if [ -z "${git_seen[$n]:-}" ]; then
          err "$hook no-git roster entry '$n' does not match any $plugin_dir/agents/*.md; remove the stale name"
        fi
      done
    fi
  fi

  if [ "$declares_lane" -eq 1 ]; then
    hook="$plugin_dir/hooks/lane-guard.sh"
    arm=""
    if [ -f "$hook" ]; then arm="$(roster_arm "$hook" lane-guarded)"; fi
    read -ra arm_names <<<"$arm"
    if [ -z "$arm" ]; then
      err "$plugin_dir agents declare 'lane-guarded' but $hook has no parseable '# crew-roster: lane-guarded' marker + case arm; cannot verify the lane roster"
    else
      declare -A laned=() lane_seen=()
      for n in "${arm_names[@]}"; do laned["$n"]=1; done
      for agent in "${agents[@]}"; do
        aname="$(basename "$agent" .md)"
        lg="$(fm_field "$agent" lane-guarded)"
        case "$lg" in
          true|false) ;;
          "") err "$agent has no 'lane-guarded' (sibling agents declare it); add 'lane-guarded: true|false'"; continue ;;
          *) err "$agent has 'lane-guarded: $lg'; expected true or false"; continue ;;
        esac
        lane_seen["$aname"]=1
        if [ "$lg" = true ] && [ -z "${laned[$aname]:-}" ]; then
          err "$agent declares 'lane-guarded: true' but $hook's roster omits '$aname'; it would write outside any lane -- add it to the arm"
        elif [ "$lg" = false ] && [ -n "${laned[$aname]:-}" ]; then
          err "$hook's roster lists '$aname' but $agent declares 'lane-guarded: false'; drop one side"
        else
          ok "$aname lane-guarded: $lg matches $hook's roster"
        fi
      done
      for n in "${arm_names[@]}"; do
        if [ -z "${lane_seen[$n]:-}" ]; then
          err "$hook lane roster entry '$n' does not match any $plugin_dir/agents/*.md; remove the stale name"
        fi
      done
    fi
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

if [ "$fail" -ne 0 ]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "Plugin validation passed."
