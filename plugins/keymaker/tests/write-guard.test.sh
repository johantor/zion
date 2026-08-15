#!/usr/bin/env bash
# Behavioral tests for keymaker's hooks/write-guard.sh — the PreToolUse(Edit|Write)
# allowlist that keeps the keymaker orchestrator out of source files. keymaker
# delegates every code change to a twin, so its own writes are confined to the
# batch ledger, outlines and notes under .claude/, plus scratch/temp.
#
# This is a fail-CLOSED guard: anything it cannot verify must block. The
# can't-parse and no-path cases below are the ones that matter most — a guard
# that quietly allowed them would let the allowlist be bypassed by a malformed
# payload rather than by an argument about the file.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="write-guard.sh"

# --- keymaker's own writes: the .claude/ allowlist ----------------------------
for p in \
  '.claude/ledger.md' \
  '.claude/outlines/tier-2.md' \
  '/repo/.claude/notes.md' \
  '/tmp/scratch.txt' \
  '/private/tmp/scratch.txt' \
  '/var/folders/ab/cd/T/scratch.txt' \
  '/private/var/folders/ab/cd/T/scratch.txt'
do
  assert_allow "keymaker may write $p" "$HOOK" "$(payload_file keymaker "$p")"
done

# --- Source edits belong to a twin --------------------------------------------
for p in \
  'src/app.ts' \
  'Program.cs' \
  '/repo/src/index.js' \
  'package.json' \
  'README.md' \
  '.github/workflows/ci.yml' \
  'claude/not-dot-claude.md'
do
  assert_block "keymaker may not write $p" "$HOOK" "$(payload_file keymaker "$p")" "never edits source files"
done

# A path merely *containing* the string is not the .claude/ lane: the allowlist
# matches a real path component, so a lookalike filename stays blocked.
assert_block "a .claude lookalike filename is not the lane" \
  "$HOOK" "$(payload_file keymaker 'src/my.claude/thing.ts')" "never edits source files"
assert_block "a file literally named .claude is not the directory" \
  "$HOOK" "$(payload_file keymaker '.claude')" "never edits source files"

# --- Everyone else is unrestricted here ---------------------------------------
# Twin confinement is prose-enforced by its delegation contract, not by this
# hook, and the user's own session is never intercepted.
assert_allow "a twin may write source"        "$HOOK" "$(payload_file twin 'src/app.ts')"
assert_allow "the main session may write source" "$HOOK" "$(jq -nc '{tool_input: {file_path: "src/app.ts"}}')"
assert_allow "another plugin's agent is untouched" "$HOOK" "$(payload_file tank 'src/app.ts')"

# --- Fail closed --------------------------------------------------------------
assert_block "non-JSON payload fails closed" "$HOOK" 'this is not json' "could not parse"
assert_block "keymaker with no file path fails closed" \
  "$HOOK" "$(jq -nc '{agent_type: "keymaker"}')" "no file path"
# `path` is read from either spelling the harness may send.
assert_allow "the .path spelling is honoured too" \
  "$HOOK" "$(jq -nc '{agent_type: "keymaker", tool_input: {path: ".claude/ledger.md"}}')"
assert_block "the .path spelling is enforced too" \
  "$HOOK" "$(jq -nc '{agent_type: "keymaker", tool_input: {path: "src/app.ts"}}')" "never edits source files"

finish
