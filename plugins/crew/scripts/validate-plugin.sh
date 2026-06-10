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
#     exists, has a manifest, and its manifest name matches the entry name.
marketplace=".claude-plugin/marketplace.json"
if [ -f "$marketplace" ] && jq empty "$marketplace" >/dev/null 2>&1; then
  while IFS=$'\t' read -r mname msource; do
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
    if [ "$pname" = "$mname" ]; then
      ok "$marketplace entry '$mname' matches $pmanifest"
    else
      err "$marketplace entry '$mname' != plugin.json name '$pname' ($pmanifest)"
    fi
  done < <(jq -r '.plugins[] | select((.source | type) == "string") | [.name, .source] | @tsv' "$marketplace")
else
  err "$marketplace missing or invalid"
fi

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

if [ "$fail" -ne 0 ]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "Plugin validation passed."
