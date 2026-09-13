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
# `git mv` is the floor's one carve-out, for the git owner this hook names.
assert_allow "keymaker git mv"           "$HOOK" "$(payload_bash 'git mv src/a.ts src/b.ts' keymaker)"
assert_block "keymaker git mv -f"        "$HOOK" "$(payload_bash 'git mv -f src/a.ts src/b.ts' keymaker)" "git mv -f/--force can overwrite"
assert_block "keymaker bare mv"          "$HOOK" "$(payload_bash 'mv src/a.ts src/b.ts' keymaker)"        "reaches no Edit|Write hook"
assert_block "twin git mv names the owner" "$HOOK" "$(payload_bash 'git mv src/a.ts src/b.ts' twin)"      "keymaker owns git"

assert_block "cat a file"    "$HOOK" "$(payload_bash 'cat foo.txt' twin)"     "unbounded cat"
assert_block "less a file"   "$HOOK" "$(payload_bash 'less foo.txt' twin)"    "interactive raw reads"
assert_block "tail -f a log" "$HOOK" "$(payload_bash 'tail -f app.log' twin)" "streaming raw output"
assert_allow "cat piped into grep" "$HOOK" "$(payload_bash 'cat foo.txt | grep x' twin)"
# The verdict follows stdout. A stderr redirect moves none of it, in any of its
# spellings or positions, so the file lands in the context exactly as the bare
# form does and blocks with it.
assert_block "cat with stderr discarded"  "$HOOK" "$(payload_bash 'cat foo.txt 2>/dev/null' twin)"  "unbounded cat"
assert_block "cat with stderr spaced"     "$HOOK" "$(payload_bash 'cat foo.txt 2> /dev/null' twin)" "unbounded cat"
assert_block "cat with stderr appended"   "$HOOK" "$(payload_bash 'cat foo.txt 2>> err.log' twin)"  "unbounded cat"
assert_block "cat with stderr duped"      "$HOOK" "$(payload_bash 'cat foo.txt 2>&1' twin)"         "unbounded cat"
assert_block "cat with redirect first"    "$HOOK" "$(payload_bash 'cat 2>/dev/null foo.txt' twin)"  "unbounded cat"
# A stdout redirect or a pipe does move it, so each falls through. The allow cases
# carry no agent_type: the read guard runs first and passes them, and the
# file-write guard -- which is agent-only -- would then answer the redirect, so
# the allow would go untested.
assert_allow "cat with fd dup, then piped"  "$HOOK" "$(payload_bash 'cat foo.txt 2>&1 | grep x' twin)"
assert_allow "cat with stdout to /dev/null" "$HOOK" "$(payload_bash 'cat foo.txt &>/dev/null' twin)"
assert_allow "cat redirected into a file"   "$HOOK" "$(payload_bash 'cat foo.txt > out.txt')"
# `file2>/tmp/out` is the operand `file2` plus a stdout redirect. The stderr arm
# must not reinterpret an operand's own suffix as its `2>`.
assert_allow "operand ending in 2 before a redirect" "$HOOK" "$(payload_bash 'cat file2>/tmp/out' twin)"
# An input redirect reads the file and prints it; `<<`/`<<<` replace stdin, which
# `cat` ignores once it has an operand. The noclobber stderr spelling is a
# redirect like the rest; it carries no agent_type only to keep the agent-only
# file-write guard out of the case -- the read guard runs first and is what
# blocks here.
assert_block "cat with input redirect"        "$HOOK" "$(payload_bash 'cat < foo.txt' twin)"  "unbounded cat"
assert_block "cat with glued input redirect"  "$HOOK" "$(payload_bash 'cat <foo.txt' twin)"   "unbounded cat"
assert_block "cat with noclobber stderr"      "$HOOK" "$(payload_bash 'cat foo.txt 2>|err.log')" "unbounded cat"
assert_allow "heredoc"    "$HOOK" "$(payload_bash 'cat <<EOF' twin)"
assert_allow "herestring" "$HOOK" "$(payload_bash 'cat <<<somestring' twin)"
# Duping stdout to stderr moves nothing out of reach: stderr is surfaced in the
# tool result too. A noclobber *stdout* redirect does move it.
assert_block "cat duped to stderr"         "$HOOK" "$(payload_bash 'cat foo.txt >&2' twin)"  "unbounded cat"
assert_block "cat fd 1 duped to stderr"    "$HOOK" "$(payload_bash 'cat foo.txt 1>&2' twin)" "unbounded cat"
assert_allow "cat with noclobber stdout"   "$HOOK" "$(payload_bash 'cat foo.txt >|out.txt')"
assert_allow "cat with stdout to /dev/null, stderr duped" "$HOOK" "$(payload_bash 'cat foo.txt >/dev/null 2>&1' twin)"
# The refusals are a user-facing contract: they name the tool to use and say why
# the shell read is refused. Asserted apart from the category substrings above,
# which would still pass if the guidance were dropped.
assert_block "cat refusal names the Read tool"   "$HOOK" "$(payload_bash 'cat foo.txt' twin)"  "Use the Read tool"
assert_block "cat refusal gives the reason"      "$HOOK" "$(payload_bash 'cat foo.txt' twin)"  "reaches no Read hook"
assert_block "pager refusal names the Read tool" "$HOOK" "$(payload_bash 'less foo.txt' twin)" "Use the Read tool"
assert_block "pager refusal gives the reason"    "$HOOK" "$(payload_bash 'less foo.txt' twin)" "reaches no Read hook"
# A wrapper the command-position policy already knows must not walk a read past
# the guard, on any of the three raw-read rules.
assert_block "env cat"       "$HOOK" "$(payload_bash 'env cat foo.txt' twin)"     "unbounded cat"
assert_block "command cat"   "$HOOK" "$(payload_bash 'command cat foo.txt' twin)" "unbounded cat"
assert_block "FOO=1 cat"     "$HOOK" "$(payload_bash 'FOO=1 cat foo.txt' twin)"   "unbounded cat"
assert_block "env less"      "$HOOK" "$(payload_bash 'env less foo.txt' twin)"    "interactive raw reads"
assert_block "env tail -f"   "$HOOK" "$(payload_bash 'env tail -f app.log' twin)" "streaming raw output"
# Only stdout ends the run: a redirect of any other fd leaves the bytes in the
# context. `1>`/`>` stay stdout -- asserted without an agent_type, since the
# file-write guard answers a redirect into the checkout first.
assert_block "cat with fd 3 redirected"  "$HOOK" "$(payload_bash 'cat big.txt 3>/tmp/err')"  "unbounded cat"
assert_block "cat with fd 10 redirected" "$HOOK" "$(payload_bash 'cat big.txt 10>/tmp/err')" "unbounded cat"
assert_block "cat with fd 3 input"       "$HOOK" "$(payload_bash 'cat big.txt 3<other.txt' twin)" "unbounded cat"
assert_allow "cat with fd 1 redirected"  "$HOOK" "$(payload_bash 'cat foo.txt 1>out.txt')"
# A heredoc replaces stdin, which `cat` ignores once it has an operand, so it
# never makes a read safe on its own -- but a `cat` with no operand reads no file
# and stays out of the rule entirely.
assert_block "heredoc with a file operand"    "$HOOK" "$(payload_bash 'cat foo.txt <<EOF')"    "unbounded cat"
assert_block "quoted heredoc with an operand" "$HOOK" "$(payload_bash "cat foo.txt <<'EOF'")" "unbounded cat"
assert_block "dash heredoc with an operand"   "$HOOK" "$(payload_bash 'cat foo.txt <<-EOF')"   "unbounded cat"
assert_block "herestring with a file operand" "$HOOK" "$(payload_bash 'cat foo.txt <<<somestring')" "unbounded cat"
assert_block "herestring before the operand"  "$HOOK" "$(payload_bash 'cat <<<somestring foo.txt')" "unbounded cat"
assert_allow "cat reading stdin only"         "$HOOK" "$(payload_bash 'cat 2>/dev/null' twin)"
# `>&-` closes stdout rather than duping it, so nothing is read into the context.
# `>&N-` is the move form: stderr becomes stdout, and stderr is surfaced too.
assert_allow "stdout closed"      "$HOOK" "$(payload_bash 'cat secret >&-')"
assert_allow "fd 1 closed"        "$HOOK" "$(payload_bash 'cat secret 1>&-')"
assert_block "stdout moved onto fd 2"      "$HOOK" "$(payload_bash 'cat secret >&2-')"  "unbounded cat"
assert_block "fd 1 moved onto fd 2"        "$HOOK" "$(payload_bash 'cat secret 1>&2-')" "unbounded cat"
assert_block "stderr closed"      "$HOOK" "$(payload_bash 'cat secret 2>&-')" "unbounded cat"
# A redirect whose destination the tool result surfaces anyway is not an escape;
# `/dev/null` still is.
assert_block "stdout to /dev/stderr" "$HOOK" "$(payload_bash 'cat f >/dev/stderr')" "unbounded cat"
assert_block "stdout to /dev/stdout" "$HOOK" "$(payload_bash 'cat f >/dev/stdout')" "unbounded cat"
assert_block "stdout to /dev/fd/2"   "$HOOK" "$(payload_bash 'cat f >/dev/fd/2')"   "unbounded cat"
assert_block "both streams to /dev/stderr" "$HOOK" "$(payload_bash 'cat f &>/dev/stderr')" "unbounded cat"
assert_allow "stdout to /dev/null"   "$HOOK" "$(payload_bash 'cat f >/dev/null')"
# A metacharacter inside a quoted filename is not a redirect: the scan reads the
# quote-masked copy, as the write path does.
assert_block "quoted operand with >" "$HOOK" "$(payload_bash "cat 'report>2026'")" "unbounded cat"
assert_allow "quoted operand, quoted redirect target" "$HOOK" "$(payload_bash "cat 'a' > 'out.txt'")"
# `<>` opens the file read-write and still prints it.
assert_block "read-write redirect"       "$HOOK" "$(payload_bash 'cat f <>tmp')" "unbounded cat"
assert_block "fd-qualified read-write"   "$HOOK" "$(payload_bash 'cat f 3<>tmp')" "unbounded cat"
# guard_normalize turns a newline into `;`, so a later line is its own command at
# every anchored guard -- not welded onto the previous line's operands.
assert_block "raw read on a second line" "$HOOK" "$(payload_bash 'echo ok
cat foo.txt' twin)" "unbounded cat"
assert_block "pager on a second line"    "$HOOK" "$(payload_bash 'echo ok
less foo.txt' twin)" "interactive raw reads"
assert_allow "a backslash-newline is a continuation, not a separator" "$HOOK" "$(payload_bash 'echo one \
two' twin)"

# --- Twins never run git ------------------------------------------------------
assert_block "twin blocked from git"         "$HOOK" "$(payload_bash 'git status' twin)" "never runs git"
assert_block "smuggled env git (twin)"       "$HOOK" "$(payload_bash 'env git push' twin)" "never runs git"
assert_block "smuggled FOO=1 git (twin)"     "$HOOK" "$(payload_bash 'FOO=1 git status' twin)" "never runs git"
# A newline separates commands, so a twin cannot reach git on a later line.
assert_block "twin git on a second line"     "$HOOK" "$(payload_bash 'echo ok
git status' twin)" "never runs git"
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
