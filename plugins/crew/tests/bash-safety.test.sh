#!/usr/bin/env bash
# Behavioral tests for hooks/bash-safety.sh.
# shellcheck source=plugins/crew/tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HOOK="bash-safety.sh"

# --- Workers never run git -----------------------------------------------------
for agent in tank trinity oracle dozer neo; do
  assert_block "worker $agent blocked from git" "$HOOK" "$(payload_bash 'git status' "$agent")" "never runs git"
done
assert_allow "git in a no-agent session" "$HOOK" "$(payload_bash 'git status')"
assert_block "smuggled env git push (tank)" "$HOOK" "$(payload_bash 'env git push' tank)" "never runs git"
assert_block "smuggled FOO=1 git (tank)" "$HOOK" "$(payload_bash 'FOO=1 git status' tank)" "never runs git"

# --- Protected-branch commit backstop -----------------------------------------
main_repo="$(make_git_branch main)"
feat_repo="$(make_git_branch feature/x)"
assert_block "morpheus git commit on main" "$HOOK" "$(payload_bash 'git commit -m x' morpheus)" "protected branch" "$main_repo"
assert_allow "morpheus git commit on feature branch" "$HOOK" "$(payload_bash 'git commit -m x' morpheus)" "$feat_repo"
assert_allow "no-agent session may commit on main" "$HOOK" "$(payload_bash 'git commit -m x')" "$main_repo"

# --- Destructive commands ------------------------------------------------------
assert_block "rm -rf /"        "$HOOK" "$(payload_bash 'rm -rf /' tank)"        "unsafe command"
assert_block "rm -fr ~"        "$HOOK" "$(payload_bash 'rm -fr ~' tank)"        "unsafe command"
assert_block "rm -rf *"        "$HOOK" "$(payload_bash 'rm -rf *' tank)"        "unsafe command"
assert_block "rm -r -f /"      "$HOOK" "$(payload_bash 'rm -r -f /' tank)"      "unsafe command"
assert_allow "rm -rf ./build (scoped)" "$HOOK" "$(payload_bash 'rm -rf ./build' tank)"

# --- Force-push ----------------------------------------------------------------
# Force-push detection is agentless here (uses a non-worker agent so the generic
# worker-git block doesn't mask it); the destructive regex fires regardless.
assert_block "git push --force"   "$HOOK" "$(payload_bash 'git push --force' morpheus)"   "unsafe command"
assert_block "git push -f"        "$HOOK" "$(payload_bash 'git push -f' morpheus)"         "unsafe command"
assert_allow "git push --force-with-lease" "$HOOK" "$(payload_bash 'git push --force-with-lease' morpheus)"

# --- Redirects / .git writes ---------------------------------------------------
assert_block "redirect into .env"        "$HOOK" "$(payload_bash 'echo secret > .env' tank)"       "unsafe command"
assert_block "redirect into .git/config" "$HOOK" "$(payload_bash 'echo x > .git/config' tank)"     "unsafe command"
assert_block "rm inside .git/"           "$HOOK" "$(payload_bash 'rm .git/index' tank)"             "unsafe command"

# --- Watch/dev/serve commands (agent sessions only) ---------------------------
for cmd in 'dotnet watch' 'npm run dev' 'pnpm dev' 'vite' 'next dev' 'ng serve' 'nodemon' 'webpack serve'; do
  assert_block "watch: $cmd" "$HOOK" "$(payload_bash "$cmd" tank)" "never terminate"
done
assert_block "bare --watch flag" "$HOOK" "$(payload_bash 'jest --watch' tank)" "never terminate"
assert_allow "vite build (not a dev server)"  "$HOOK" "$(payload_bash 'vite build' tank)"
assert_allow "--watch=false (disable spelling)" "$HOOK" "$(payload_bash 'jest --watch=false' tank)"
assert_allow "npm run build"                  "$HOOK" "$(payload_bash 'npm run build' tank)"
assert_allow "npm run dev in a no-agent session" "$HOOK" "$(payload_bash 'npm run dev')"

# --- Raw / streaming reads -----------------------------------------------------
assert_block "cat a file"     "$HOOK" "$(payload_bash 'cat foo.txt' tank)"      "unbounded cat"
assert_block "less a file"    "$HOOK" "$(payload_bash 'less foo.txt' tank)"     "interactive raw reads"
assert_block "tail -f a log"  "$HOOK" "$(payload_bash 'tail -f app.log' tank)"  "streaming raw output"
assert_allow "cat piped into grep" "$HOOK" "$(payload_bash 'cat foo.txt | grep x' tank)"

# --- Fail closed on unparseable input -----------------------------------------
assert_block "non-JSON payload fails closed" "$HOOK" 'this is not json' "could not parse"

finish
