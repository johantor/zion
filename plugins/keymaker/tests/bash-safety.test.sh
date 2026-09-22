#!/usr/bin/env bash
# Behavioral tests for keymaker's hooks/bash-safety.sh.
#
# Two things are under test, and they fail for different reasons. The "shared
# floor" block proves keymaker's vendored copy of hooks/lib/guard-lib.sh is
# actually wired and enforcing — a standalone keymaker install has no crew hooks
# behind it, so if the vendored library ever stopped loading, only a test run
# against *this* plugin's copy would notice. The rest is keymaker's own policy:
# twins never run git, and no agent commits on a protected branch.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="bash-safety.sh"

# --- The shared floor, enforced by keymaker's own copy -------------------------
assert_block "rm -rf /"         "$HOOK" "$(payload_bash 'rm -rf /' twin)"   "unsafe command"
assert_block "rm -fr ~"         "$HOOK" "$(payload_bash 'rm -fr ~' twin)"   "unsafe command"
assert_block "rm -r -f *"       "$HOOK" "$(payload_bash 'rm -r -f *' twin)" "unsafe command"
assert_allow "rm -rf ./build (scoped)" "$HOOK" "$(payload_bash 'rm -rf ./build' twin)"

assert_block "git push --force"  "$HOOK" "$(payload_bash 'git push --force' keymaker)" "unsafe command"
assert_block "git push -f"       "$HOOK" "$(payload_bash 'git push -f' keymaker)"      "unsafe command"
assert_allow "git push --force-with-lease" "$HOOK" "$(payload_bash 'git push --force-with-lease' keymaker)"

assert_block "redirect into .env"        "$HOOK" "$(payload_bash 'echo s > .env' twin)"   "unsafe command"
assert_block "redirect into .git/config" "$HOOK" "$(payload_bash 'echo x > .git/config' twin)" "unsafe command"

for cmd in 'dotnet watch' 'npm run dev' 'pnpm dev' 'vite' 'next dev' 'ng serve' 'nodemon' 'webpack serve'; do
  assert_block "watch: $cmd" "$HOOK" "$(payload_bash "$cmd" twin)" "never terminate"
done
assert_block "bare --watch flag" "$HOOK" "$(payload_bash 'jest --watch' twin)" "never terminate"
assert_allow "vite build (not a dev server)"     "$HOOK" "$(payload_bash 'vite build' twin)"
assert_allow "--watch=false (disable spelling)"  "$HOOK" "$(payload_bash 'jest --watch=false' twin)"
assert_allow "npm run dev in a no-agent session" "$HOOK" "$(payload_bash 'npm run dev')"

# The shared library also covers the non-web ecosystems a twin works in.
for cmd in 'uvicorn app:app' 'flask --debug run' './manage.py runserver' \
           'air' 'cargo watch -x test' './gradlew -t build' './gradlew :service:bootRun' \
           'fastapi dev app.py' 'uv run python -m uvicorn app:app' \
           'django-admin runserver' 'watch shellcheck .' '/usr/bin/watch shellcheck .' 'uv run --project x uvicorn app:app' \
           'python services/api/manage.py runserver' 'poetry -C service run uvicorn app:app' \
           '.venv/bin/uvicorn app:app' \
           'cargo +nightly watch' 'python -m http.server' \
           './mvnw spring-boot:run' 'service/mvnw spring-boot:run'; do
  assert_block "watch: $cmd" "$HOOK" "$(payload_bash "$cmd" twin)" "never terminate"
done
for cmd in 'pytest -q' 'go test ./...' 'cargo test' './gradlew test' './mvnw -B verify'; do
  assert_allow "one-shot: $cmd" "$HOOK" "$(payload_bash "$cmd" twin)"
done

assert_block "sed -i"                "$HOOK" "$(payload_bash "sed -i 's/a/b/' src/Foo.cs" twin)" "reaches no Edit|Write hook"
assert_block "redirect into a file"  "$HOOK" "$(payload_bash 'echo x > src/Foo.cs' twin)"        "reaches no Edit|Write hook"
assert_allow "redirect to /dev/null" "$HOOK" "$(payload_bash 'npm run build > /dev/null' twin)"
assert_allow "Bash write in a no-agent session" "$HOOK" "$(payload_bash 'echo x > src/Foo.cs')"
# `git mv` is the floor's one carve-out. The floor lets any agent run it -- with
# crew installed too, both guards fire on every Bash call, and this one must not
# refuse crew's morpheus -- and keymaker's own twin rule refuses a twin's.
nl=$'\n'
assert_allow "keymaker git mv"           "$HOOK" "$(payload_bash 'git mv src/a.ts src/b.ts' keymaker)"
assert_allow "keymaker git mv on a second line" "$HOOK" "$(payload_bash "cd src${nl}git mv a.ts b.ts" keymaker)"
assert_allow "another plugin's git owner may git mv" "$HOOK" "$(payload_bash 'git mv src/a.cs src/b.cs' morpheus)"
assert_block "keymaker git mv -f"        "$HOOK" "$(payload_bash 'git mv -f src/a.ts src/b.ts' keymaker)" "git mv -f/--force can overwrite"
assert_block "keymaker bare mv"          "$HOOK" "$(payload_bash 'mv src/a.ts src/b.ts' keymaker)"        "reaches no Edit|Write hook"
assert_block "bare mv on a second line"  "$HOOK" "$(payload_bash "git mv a b${nl}mv c d" keymaker)"       "reaches no Edit|Write hook"
assert_block "twin git mv names the owner" "$HOOK" "$(payload_bash 'git mv src/a.ts src/b.ts' twin)"      "keymaker owns git"
# The hand-back reads the flattened command, so a line of data is never refused.
assert_allow "twin prints a git mv in a quoted string" "$HOOK" "$(payload_bash "printf '%s\\n' 'header${nl}git mv a b'" twin)"
assert_allow "twin writes a git mv in a heredoc"       "$HOOK" "$(payload_bash "cat > /tmp/notes <<EOF${nl}git mv a b${nl}EOF" twin)"
assert_block "keymaker git mv -f after a line continuation" "$HOOK" "$(payload_bash "git mv \\${nl}-f a b" keymaker)" "git mv -f/--force can overwrite"

# Raw/streaming reads. A habit redirect, not a boundary: `grep . f` dumps the
# same file and is deliberately allowed, so these pin the habit and the escapes,
# not redirect spellings -- see AGENTS.md, "The Bash guards are floors, not sandboxes".
assert_block "cat a file"    "$HOOK" "$(payload_bash 'cat foo.txt' twin)"     "unbounded cat"
assert_block "less a file"   "$HOOK" "$(payload_bash 'less foo.txt' twin)"    "interactive raw reads"
assert_block "tail -f a log" "$HOOK" "$(payload_bash 'tail -f app.log' twin)" "streaming raw output"
assert_block "bare read with no agent_type" "$HOOK" "$(payload_bash 'cat foo.txt')" "unbounded cat"
assert_block "env wrapper"        "$HOOK" "$(payload_bash 'env cat foo.txt' twin)"     "unbounded cat"
assert_block "command wrapper"    "$HOOK" "$(payload_bash 'command cat foo.txt' twin)" "unbounded cat"
assert_block "assignment wrapper" "$HOOK" "$(payload_bash 'FOO=1 cat foo.txt' twin)"   "unbounded cat"
# `_g_pfx` is on the pager and stream patterns too, and this suite runs against
# keymaker's own vendored copy -- so those branches need exercising here, not
# only in crew's.
assert_block "env wrapper on the pager"  "$HOOK" "$(payload_bash 'env less foo.txt' twin)"    "interactive raw reads"
assert_block "env wrapper on the stream" "$HOOK" "$(payload_bash 'env tail -f app.log' twin)" "streaming raw output"
assert_allow "piped into grep"        "$HOOK" "$(payload_bash 'cat foo.txt | grep x' twin)"
assert_allow "redirected into a file" "$HOOK" "$(payload_bash 'cat foo.txt > out.txt')"
# The refusals name the tool to use and say why the shell read is refused.
assert_block "refusal names the Read tool" "$HOOK" "$(payload_bash 'cat foo.txt' twin)" "Use the Read tool"
assert_block "refusal gives the reason"    "$HOOK" "$(payload_bash 'cat foo.txt' twin)" "reaches no Read hook"
assert_block "pager refusal names the Read tool" "$HOOK" "$(payload_bash 'less foo.txt' twin)" "Use the Read tool"
assert_block "pager refusal gives the reason"    "$HOOK" "$(payload_bash 'less foo.txt' twin)" "reaches no Read hook"
# Nothing replaces a `tail -f`, so the stream refusal points at capture/filter --
# but it carries the same reason, and only asserting the category would let a
# revert to the old wording pass.
assert_block "stream refusal gives the reason"   "$HOOK" "$(payload_bash 'tail -f app.log' twin)" "reaches no Read hook"

# --- Twins never run git ------------------------------------------------------
assert_block "twin blocked from git"         "$HOOK" "$(payload_bash 'git status' twin)" "never runs git"
assert_block "smuggled env git (twin)"       "$HOOK" "$(payload_bash 'env git push' twin)" "never runs git"
assert_block "smuggled FOO=1 git (twin)"     "$HOOK" "$(payload_bash 'FOO=1 git status' twin)" "never runs git"
assert_block "smuggled command git (twin)"   "$HOOK" "$(payload_bash 'command git log' twin)" "never runs git"
# keymaker owns branching and commits, so the git block is scoped to twins only.
assert_allow "keymaker itself may run git"   "$HOOK" "$(payload_bash 'git status' keymaker)"
assert_allow "git in a no-agent session"     "$HOOK" "$(payload_bash 'git status')"

# --- Protected-branch commit backstop -----------------------------------------
main_repo="$(make_git_branch main)"
master_repo="$(make_git_branch master)"
work_repo="$(make_git_branch chore/debt-upgrade-x)"
assert_block "keymaker commit on main"   "$HOOK" "$(payload_bash 'git commit -m x' keymaker)" "protected branch" "$main_repo"
assert_block "keymaker commit on master" "$HOOK" "$(payload_bash 'git commit -m x' keymaker)" "protected branch" "$master_repo"
assert_block "git -C dir commit on main" "$HOOK" "$(payload_bash 'git -C . commit -m x' keymaker)" "protected branch" "$main_repo"
assert_allow "keymaker commit on the work branch" "$HOOK" "$(payload_bash 'git commit -m x' keymaker)" "$work_repo"
assert_allow "no-agent session may commit on main" "$HOOK" "$(payload_bash 'git commit -m x')" "$main_repo"

# --- Fail closed --------------------------------------------------------------
assert_block "non-JSON payload fails closed" "$HOOK" 'this is not json' "could not parse"

finish
