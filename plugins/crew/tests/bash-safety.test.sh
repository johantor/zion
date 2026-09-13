#!/usr/bin/env bash
# Behavioral tests for hooks/bash-safety.sh.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
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

# --- The commit's own directory decides, not the hook's ------------------------
# A crew session working in a git worktree commits onto the worktree's branch
# while the hook sits in the main checkout, which may be on a protected branch.
# The guard resolves `git -C <dir>` and a preceding `cd`, so it judges the branch
# the commit actually lands on.
wt_repo="$(make_git_worktree develop feature/y)"
assert_allow "git -C <worktree> commit"        "$HOOK" "$(payload_bash 'git -C wt commit -m x' morpheus)"        "$wt_repo"
assert_allow "cd <worktree> && commit"         "$HOOK" "$(payload_bash 'cd wt && git commit -m x' morpheus)"     "$wt_repo"
assert_allow "cd <worktree>; commit"           "$HOOK" "$(payload_bash 'cd wt; git commit -m x' morpheus)"       "$wt_repo"
assert_allow "subshell cd <worktree>"          "$HOOK" "$(payload_bash '(cd wt && git commit -m x)' morpheus)"   "$wt_repo"
assert_allow "quoted worktree path"            "$HOOK" "$(payload_bash 'git -C "wt" commit -m x' morpheus)"      "$wt_repo"
assert_allow "git -C with a global flag after" "$HOOK" "$(payload_bash 'git -C wt -c user.name=a commit -m x' morpheus)" "$wt_repo"
assert_allow "separator inside the message"    "$HOOK" "$(payload_bash 'cd wt && git commit -m "fix: a; b"' morpheus)"   "$wt_repo"
assert_allow "staging then committing"         "$HOOK" "$(payload_bash 'cd wt && git add -A && git commit -m x' morpheus)" "$wt_repo"

# The same resolution must not become a way around the backstop: every shape the
# guard cannot read falls back to its own directory, which is the protected one.
assert_block "commit back in the main checkout" "$HOOK" "$(payload_bash 'cd wt && git commit -m x && cd .. && git commit -m y' morpheus)" "protected branch" "$wt_repo"
assert_block "git -C back to the main checkout" "$HOOK" "$(payload_bash 'cd wt && git -C .. commit -m x' morpheus)" "protected branch" "$wt_repo"
# shellcheck disable=SC2016  # `$WT` must reach the guard unexpanded: an
# expansion is exactly the target shape the guard cannot resolve.
assert_block "unresolvable cd target"           "$HOOK" "$(payload_bash 'cd $WT && git commit -m x' morpheus)"      "protected branch" "$wt_repo"
assert_block "cd in its own pipe segment"       "$HOOK" "$(payload_bash 'cd wt | git commit -m x' morpheus)"        "protected branch" "$wt_repo"
assert_block "subshell cd does not leak out"    "$HOOK" "$(payload_bash '(cd wt && git commit -m a) && git commit -m b' morpheus)" "protected branch" "$wt_repo"
assert_block "a cd inside the message is text"  "$HOOK" "$(payload_bash 'git commit -m "cd wt"' morpheus)"          "protected branch" "$wt_repo"
assert_block "a cd another command prints"      "$HOOK" "$(payload_bash 'echo cd wt && git commit -m x' morpheus)"  "protected branch" "$wt_repo"
assert_block "a cd that would fail"             "$HOOK" "$(payload_bash 'cd nope; git commit -m x' morpheus)"       "protected branch" "$wt_repo"
assert_allow "no-agent session in a worktree checkout" "$HOOK" "$(payload_bash 'cd wt && git commit -m x')" "$wt_repo"

# Resolving the directory must never weaken the backstop: where the walk cannot
# model a construct, the hook's own directory stays a candidate and the commit is
# judged against it too. Each of these reaches a commit in the protected checkout.
assert_block "quoted path with a suffix"        "$HOOK" "$(payload_bash 'git -C "wt"/.. commit -m x' morpheus)"        "protected branch" "$wt_repo"
assert_block "cd back out of the worktree"      "$HOOK" "$(payload_bash 'cd wt && cd .. && git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "pushd after a cd"                 "$HOOK" "$(payload_bash 'cd wt && pushd .. > /dev/null && git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "cd on a pipe's right-hand side"   "$HOOK" "$(payload_bash 'true | cd wt && git commit -m x' morpheus)"   "protected branch" "$wt_repo"
assert_block "cd the shell may skip"            "$HOOK" "$(payload_bash 'false && cd wt; git commit -m x' morpheus)"   "protected branch" "$wt_repo"
assert_block "cd run in the background"         "$HOOK" "$(payload_bash 'cd wt & git commit -m x' morpheus)"           "protected branch" "$wt_repo"
assert_block "commit inside a nested shell"     "$HOOK" "$(payload_bash 'cd wt && bash -c "cd .. && git commit -m x"' morpheus)" "protected branch" "$wt_repo"
assert_block "cd through eval"                  "$HOOK" "$(payload_bash 'cd wt && eval "cd .." && git commit -m x' morpheus)"    "protected branch" "$wt_repo"
assert_block "another repo via --git-dir"       "$HOOK" "$(payload_bash 'cd wt && git --git-dir=../.git --work-tree=.. commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "-C inside a quoted option value"  "$HOOK" "$(payload_bash "git -c 'user.name=x -C nowhere' commit -m y" morpheus)" "protected branch" "$wt_repo"
assert_block "cd with a second operand"         "$HOOK" "$(payload_bash 'cd wt nope; git commit -m x' morpheus)"       "protected branch" "$wt_repo"
assert_block "an escaped separator in a path"   "$HOOK" "$(payload_bash 'git -C wt\;x commit -m x' morpheus)"          "protected branch" "$wt_repo"
assert_block "commit in a subshell"             "$HOOK" "$(payload_bash '(git commit -m x)' morpheus)"                 "protected branch" "$wt_repo"
assert_block "subshell cd stays in the subshell" "$HOOK" "$(payload_bash '(cd wt && git commit -m a); git commit -m b' morpheus)" "protected branch" "$wt_repo"
# shellcheck disable=SC2016  # `$HOME` must reach the guard unexpanded — a target
# the guard cannot read is exactly what these two assert.
assert_block "cd to an unreadable target"       "$HOOK" "$(payload_bash 'cd wt && cd "$HOME"; cd ..; git commit -m x' morpheus)" "protected branch" "$wt_repo"

# Shapes the walk does model stay allowed: a quoted `)` or an expansion inside a
# commit message decides nothing about where the commit runs.
assert_allow "a closing paren in the message"   "$HOOK" "$(payload_bash 'cd wt && git commit -m "fix )" && git commit -m x' morpheus)" "$wt_repo"
# shellcheck disable=SC2016  # the substitution is the point: it is in the message,
# not in anything that decides the directory.
assert_allow "a substitution in the message"    "$HOOK" "$(payload_bash 'cd wt && git commit -m "done $(date)"' morpheus)" "$wt_repo"
assert_allow "a guarded cd in an && chain"      "$HOOK" "$(payload_bash 'git fetch origin && cd wt && git commit -m x' morpheus)" "$wt_repo"
assert_allow "git -C with -c before commit"     "$HOOK" "$(payload_bash 'git -C wt -c user.name=a commit -m x' morpheus)" "$wt_repo"
assert_allow "quoted path carrying spaces"      "$HOOK" "$(payload_bash 'git -C "wt two words" commit -m x' morpheus)" "$wt_repo"
assert_allow "cd into a path carrying spaces"   "$HOOK" "$(payload_bash 'cd "wt two words" && git commit -m x' morpheus)" "$wt_repo"
assert_allow "a separator in the message"       "$HOOK" "$(payload_bash 'cd wt && git commit -m "a; b" && git commit -m c' morpheus)" "$wt_repo"

# A quoted span ends where the shell ends it, and a substitution runs commands of
# its own: neither may be read as inert text that leaves the carry trusted.
assert_block "escaped quote inside a message"   "$HOOK" "$(payload_bash 'cd wt && git commit -m "x\"; noop" && cd .. && git commit -m y' morpheus)" "protected branch" "$wt_repo"
# shellcheck disable=SC2016  # the substitution must reach the guard unexpanded —
# it is the commit hidden inside it that this asserts on.
assert_block "commit inside a substitution"     "$HOOK" "$(payload_bash 'cd wt && git commit -m "$(git -C .. commit -m x)"' morpheus)" "protected branch" "$wt_repo"
# shellcheck disable=SC2016  # the substitution must reach the guard unexpanded.
assert_block "commit inside a backquoted one"   "$HOOK" "$(payload_bash 'cd wt && git commit -m `git -C .. commit -m x`' morpheus)" "protected branch" "$wt_repo"
assert_block "a glob as the target"             "$HOOK" "$(payload_bash 'git -C ./[Ww]t commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "cd back through a wrapper"        "$HOOK" "$(payload_bash 'cd wt; command cd .. && git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "a trailing separator"             "$HOOK" "$(payload_bash 'git commit -m x;' morpheus)" "protected branch" "$wt_repo"

# The walk is the detector, so it must find a commit the patterns cannot see —
# and must not invent one where there is none.
assert_allow "the word commit in an echo"       "$HOOK" "$(payload_bash 'echo commit' morpheus)" "$wt_repo"
assert_allow "commit as a log filter"           "$HOOK" "$(payload_bash 'git log --grep=commit -1' morpheus)" "$wt_repo"
# shellcheck disable=SC1003  # the trailing backslash is the payload: a command
# ending in one used to spin the word tokenizer forever.
assert_block "a trailing backslash"             "$HOOK" "$(payload_bash 'git commit\' morpheus)" "protected branch" "$wt_repo"
assert_block "nested subshell parens"           "$HOOK" "$(payload_bash '( (git -C . commit -m x) )' morpheus)" "protected branch" "$wt_repo"
assert_block "a redirection before the command" "$HOOK" "$(payload_bash '> /tmp/guard-test-out git -C . commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "GIT_DIR in the environment"       "$HOOK" "$(payload_bash 'GIT_DIR=.git GIT_WORK_TREE=. git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "a wrapper carrying options"       "$HOOK" "$(payload_bash 'env -i git -C . commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "a commit inside an if"            "$HOOK" "$(payload_bash 'if true; then git -C . commit -m x; fi' morpheus)" "protected branch" "$wt_repo"
assert_block "bare cd leaves the worktree"      "$HOOK" "$(payload_bash 'cd wt && cd; git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "a redirection on the cd"          "$HOOK" "$(payload_bash 'cd wt < /nonexistent; git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "--git-dir read from git -C"       "$HOOK" "$(payload_bash 'cd wt && git -C .. --git-dir=.git --work-tree=. commit -m x' morpheus)" "protected branch" "$wt_repo"
# shellcheck disable=SC2016  # the substitution must reach the guard unexpanded.
assert_block "a substitution under echo"        "$HOOK" "$(payload_bash 'echo "$(git -C . commit -m x)"' morpheus)" "protected branch" "$wt_repo"
assert_block "a backgrounded && list"           "$HOOK" "$(payload_bash 'cd wt && git commit -m a & git commit -m b' morpheus)" "protected branch" "$wt_repo"
assert_block "a cd the || may skip"             "$HOOK" "$(payload_bash 'true || cd wt && git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "coproc before git commit"         "$HOOK" "$(payload_bash 'coproc git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "case statement with git commit"   "$HOOK" "$(payload_bash 'case x in x) git commit -m x;; esac' morpheus)" "protected branch" "$wt_repo"
assert_block "function body with git commit"    "$HOOK" "$(payload_bash 'f() { git commit -m x; }; f' morpheus)" "protected branch" "$wt_repo"
assert_block "brace group piped to git commit"  "$HOOK" "$(payload_bash '{ cd wt; true; } | git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "path-qualified git commit"        "$HOOK" "$(payload_bash '/usr/bin/git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "newline after && keeps short-circuit" "$HOOK" "$(payload_bash $'false &&\ncd wt\ngit commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "quoted commit subcommand spelling" "$HOOK" "$(payload_bash "git com'mit' -m x" morpheus)" "protected branch" "$wt_repo"
assert_block "the outer subshell's directory"   "$HOOK" "$(payload_bash '(cd . && (cd wt && git commit -m a) && git commit -m b)' morpheus)" "protected branch" "$wt_repo"
assert_block "cd -P resolves symlinks itself"   "$HOOK" "$(payload_bash 'cd -P wt && cd .. && git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "an external wrapper cannot cd"    "$HOOK" "$(payload_bash 'nohup cd wt; git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "env cannot run the cd builtin"    "$HOOK" "$(payload_bash 'env cd wt; git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "an option cd does not take"       "$HOOK" "$(payload_bash 'cd -Z wt; git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "a cd skipped by an ||"            "$HOOK" "$(payload_bash 'false && cd wt || git commit -m x' morpheus)" "protected branch" "$wt_repo"
assert_block "a cd inside an if body"           "$HOOK" "$(payload_bash 'cd wt; if true; then cd ..; git commit -m x; fi' morpheus)" "protected branch" "$wt_repo"
assert_allow "command runs the cd builtin"      "$HOOK" "$(payload_bash 'command cd wt && git commit -m x' morpheus)" "$wt_repo"
assert_allow "cd -L is the default mode"        "$HOOK" "$(payload_bash 'cd -L wt && git commit -m x' morpheus)" "$wt_repo"
assert_allow "cd -P without a symlink"          "$HOOK" "$(payload_bash 'cd -P wt && git commit -m x' morpheus)" "$wt_repo"

# A newline is a command separator. The patterns see a one-line command, so the
# walk reads the payload as it arrived.
assert_allow "a newline before a worktree commit" "$HOOK" "$(payload_bash $'cd wt\ngit commit -m x' morpheus)" "$wt_repo"
assert_block "a newline back to the checkout"     "$HOOK" "$(payload_bash $'cd wt\ncd ..\ngit commit -m x' morpheus)" "protected branch" "$wt_repo"

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
assert_block "noclobber redirect into .env" "$HOOK" "$(payload_bash 'echo secret >| .env' tank)"   "unsafe command"
assert_block "rm inside .git/"           "$HOOK" "$(payload_bash 'rm .git/index' tank)"             "unsafe command"

# --- Watch/dev/serve commands (agent sessions only) ---------------------------
for cmd in 'dotnet watch' 'npm run dev' 'pnpm dev' 'vite' 'next dev' 'ng serve' 'nodemon' 'webpack serve'; do
  assert_block "watch: $cmd" "$HOOK" "$(payload_bash "$cmd" tank)" "never terminate"
done
assert_block "bare --watch flag" "$HOOK" "$(payload_bash 'jest --watch' tank)" "never terminate"
assert_allow "vite build (not a dev server)"  "$HOOK" "$(payload_bash 'vite build' tank)"
assert_allow "--watch=false (disable spelling)" "$HOOK" "$(payload_bash 'jest --watch=false' tank)"

# The same rule in the non-web stacks.
for cmd in 'uvicorn app:app --reload' 'uvicorn app:app' 'hypercorn app:app' 'gunicorn wsgi:app' \
           'python manage.py runserver' 'flask run' 'flask --app app run' 'ptw' 'watchmedo auto-restart' \
           'poetry run uvicorn app:app' 'uv run flask run' 'pipenv run uvicorn app:app' \
           'fastapi dev app.py' 'fastapi run' \
           'django-admin runserver' 'python -m django runserver' \
           'python services/api/manage.py runserver' \
           'uv run python -m uvicorn app:app' 'poetry run python -m flask run' \
           '.venv/bin/python -m uvicorn app:app' 'python3.12 -m uvicorn app:app' \
           '.venv/bin/uvicorn app:app' \
           'uv run --project service uvicorn app:app' 'pdm run --site-packages flask run' \
           'poetry -C service run uvicorn app:app' 'uv --directory service run uvicorn app:app' \
           'watch shellcheck .' '/usr/bin/watch shellcheck .' 'watchexec -- shellcheck .' 'entr make' \
           'air' 'reflex' 'cargo watch' 'cargo watch -x test' 'cargo +nightly watch -x test' \
           'trunk serve' 'python -m http.server' 'python3 -m http.server 8000' \
           './mvnw spring-boot:run' 'mvn quarkus:dev' './gradlew bootRun' './gradlew build --continuous' \
           'service/mvnw spring-boot:run' './service/gradlew bootRun'; do
  assert_block "watch: $cmd" "$HOOK" "$(payload_bash "$cmd" tank)" "never terminate"
done
# One-shot commands in the same ecosystems stay allowed: refusing one of these
# would break the gate it belongs to.
for cmd in 'pytest -q' 'mypy .' 'ruff check .' 'python -m pytest tests/' \
           'uv run pytest' 'poetry run python -m pytest tests/' 'python -m build' 'pipenv run pytest' \
           'django-admin startproject x' 'python -m django --version' \
           'python services/api/manage.py migrate' \
           '.venv/bin/python -m pytest' 'python3.12 -m build' \
           'uv run --project service pytest' 'pdm run --site-packages pytest' 'shellcheck hooks/a.sh' \
           'poetry -C service run pytest' 'uv --directory service run pytest' \
           'go build ./...' 'go test ./...' 'go run ./cmd/tool' \
           'cargo test' 'cargo build --all-targets' 'cargo clippy -- -D warnings' 'cargo +nightly test' \
           './mvnw -B verify' './gradlew test' './gradlew check -x test' \
           'service/mvnw -B verify' './service/gradlew test'; do
  assert_allow "one-shot: $cmd" "$HOOK" "$(payload_bash "$cmd" tank)"
done
assert_allow "npm run build"                  "$HOOK" "$(payload_bash 'npm run build' tank)"
assert_allow "npm run dev in a no-agent session" "$HOOK" "$(payload_bash 'npm run dev')"

# --- Raw / streaming reads -----------------------------------------------------
assert_block "cat a file"     "$HOOK" "$(payload_bash 'cat foo.txt' tank)"      "unbounded cat"
assert_block "less a file"    "$HOOK" "$(payload_bash 'less foo.txt' tank)"     "interactive raw reads"
assert_block "tail -f a log"  "$HOOK" "$(payload_bash 'tail -f app.log' tank)"  "streaming raw output"
assert_allow "cat piped into grep" "$HOOK" "$(payload_bash 'cat foo.txt | grep x' tank)"

# --- File writes through Bash (agent sessions only) ---------------------------
# lane-guard and format.sh are wired to Edit|Write, so a Bash write would land
# outside both. Blocking it here keeps one enforcement point instead of
# reimplementing lane resolution on the Bash path (#192).
gap="reaches no Edit|Write hook"
assert_block "sed -i"             "$HOOK" "$(payload_bash "sed -i 's/a/b/' src/Foo.cs" tank)"   "$gap"
assert_block "sed -i.bak"         "$HOOK" "$(payload_bash 'sed -i.bak s/a/b/ src/Foo.cs' tank)" "$gap"
assert_block "perl -pi -e"        "$HOOK" "$(payload_bash "perl -pi -e 's/a/b/' src/Foo.cs" tank)" "$gap"
assert_block "sed -i under -exec" "$HOOK" "$(payload_bash "find . -name '*.cs' -exec sed -i s/a/b/ {} +" tank)" "$gap"
assert_block "redirect into a file"   "$HOOK" "$(payload_bash 'echo x > src/Foo.cs' tank)"  "$gap"
assert_block "glued redirect"         "$HOOK" "$(payload_bash 'echo x>src/Foo.cs' tank)"    "$gap"
assert_block "append redirect"        "$HOOK" "$(payload_bash 'printf x >> README.md' tank)" "$gap"
assert_block "quoted redirect target" "$HOOK" "$(payload_bash 'echo x > "src/Foo.cs"' tank)" "quoted path"
# `>|` is the noclobber override, a redirect like any other. Without the `\|?` in
# the pattern its target hides behind the `|` and the redirect reads as
# targetless, i.e. as an exempt sink.
assert_block "noclobber override"     "$HOOK" "$(payload_bash 'echo x >| src/Foo.cs' tank)" "$gap"
assert_block "glued >| redirect"      "$HOOK" "$(payload_bash 'echo x >|src/Foo.cs' tank)"  "$gap"
# `-` means stdout to some commands, but `> -` writes a file named `-`.
assert_block "redirect into a file named -" "$HOOK" "$(payload_bash 'echo x > -' tank)"     "$gap"
# A glob metacharacter in an earlier, exempt target must not derail the scan of
# the later ones. The trim that advances past a match interpolates it *quoted*,
# which keeps it literal inside `${var#pattern}`; unquoted it would match
# nothing, leave `rest` unchanged and loop forever.
assert_block "redirect after a bracketed exempt target" "$HOOK" "$(payload_bash 'cmd > /tmp/out[1] > src/Foo.cs' tank)" "$gap"
assert_block "redirect after a starred exempt target"   "$HOOK" "$(payload_bash 'cmd > /tmp/a*b > src/Foo.cs' tank)"    "$gap"
assert_allow "bracketed exempt target alone"            "$HOOK" "$(payload_bash 'cmd > /tmp/out[1] > /dev/null' tank)"
assert_block "tee into a file"        "$HOOK" "$(payload_bash 'cat t | tee src/Foo.cs' tank)" "$gap"
assert_block "cp into the tree"       "$HOOK" "$(payload_bash 'cp /tmp/x src/Foo.cs' tank)"  "$gap"
assert_block "mv inside the tree"     "$HOOK" "$(payload_bash 'mv src/a.cs src/b.cs' tank)"  "$gap"
assert_block "patch"                  "$HOOK" "$(payload_bash 'patch -p1 < fix.diff' tank)"  "$gap"
# `git mv` is a rename recorded in the index, not a write: no bytes change, so no
# lane guard or formatter has anything to inspect. The git owner alone may run it
# -- the rename lands in its commit, where it is reviewed. Bare `mv`/`cp` stay
# refused for everyone, and so does a forced `git mv`, which can clobber.
force="git mv -f/--force can overwrite"
assert_allow "morpheus git mv"                 "$HOOK" "$(payload_bash 'git mv BishopsArms.Members src/BishopsArms.Members' morpheus)"
assert_allow "morpheus git -C dir mv"          "$HOOK" "$(payload_bash 'git -C . mv src/a.cs src/b.cs' morpheus)"
assert_allow "morpheus git mv after &&"        "$HOOK" "$(payload_bash 'cd src && git mv a.cs b.cs' morpheus)"
assert_allow "morpheus two git mvs"            "$HOOK" "$(payload_bash 'git mv a b; git mv c d' morpheus)"
assert_allow "morpheus git mv -k (skip errors)" "$HOOK" "$(payload_bash 'git mv -k a b' morpheus)"
assert_allow "morpheus git mv of an mv-prefixed path" "$HOOK" "$(payload_bash 'git mv mvc/a.cs mvc/b.cs' morpheus)"
assert_block "morpheus git mv -f"              "$HOOK" "$(payload_bash 'git mv -f a b' morpheus)"       "$force"
assert_block "morpheus git mv --force"         "$HOOK" "$(payload_bash 'git mv --force a b' morpheus)"  "$force"
assert_block "morpheus git mv -kf (bundled)"   "$HOOK" "$(payload_bash 'git mv -kf a b' morpheus)"      "$force"
assert_block "morpheus git mv with a quoted -f" "$HOOK" "$(payload_bash "git mv '-f' a b" morpheus)"    "$force"
assert_block "forced git mv behind an allowed one" "$HOOK" "$(payload_bash 'git mv a b; git mv -f c d' morpheus)" "$force"
# The allowance covers the `git mv` token only: what follows is checked as before.
assert_block "bare mv behind an allowed git mv" "$HOOK" "$(payload_bash 'git mv a b && mv c d' morpheus)" "$gap"
assert_block "cp behind an allowed git mv"      "$HOOK" "$(payload_bash 'git mv a b && cp c d' morpheus)" "$gap"
assert_block "redirect behind an allowed git mv" "$HOOK" "$(payload_bash 'git mv a b > src/log' morpheus)" "$gap"
assert_block "morpheus bare mv"                 "$HOOK" "$(payload_bash 'mv src/a.cs src/b.cs' morpheus)" "$gap"
# The matched `git mv` text is interpolated quoted when it is masked and when the
# operands are cut out, so a glob metacharacter in it stays literal: the mask
# lands on that one token and a bare `mv` behind it is still seen.
assert_allow "git mv with a glob in a flag value" "$HOOK" "$(payload_bash 'git -C "*" mv a b' morpheus)"
assert_allow "git mv with globs in its operands"  "$HOOK" "$(payload_bash 'git mv "a*" "b[1]"' morpheus)"
assert_block "bare mv behind a glob-carrying git mv" "$HOOK" "$(payload_bash 'git -C "[" mv a b && mv c d' morpheus)" "$gap"
assert_block "forced glob-carrying git mv"          "$HOOK" "$(payload_bash 'git -C "*" mv -f a b' morpheus)"       "$force"
# Only a `git mv` at a command position is recognised; `-exec git mv` is not.
assert_block "git mv under find -exec"          "$HOOK" "$(payload_bash 'find . -name "*.cs" -exec git mv {} old/ \;' morpheus)" "$gap"
# A worker is told whose the rename is and what to hand back, rather than the
# generic write message that sends it looking for a synonym.
assert_block "tank git mv names the owner"      "$HOOK" "$(payload_bash 'git mv a b' tank)" "morpheus owns git"
assert_block "tank git mv says hand it back"    "$HOOK" "$(payload_bash 'git mv a b' tank)" "Hand the rename back"
# Exempt sinks and read-only uses of the same tools stay allowed: a guard that
# blocked `> /dev/null` would just be routed around.
assert_allow "redirect to /dev/null"  "$HOOK" "$(payload_bash 'dotnet build > /dev/null' tank)"
assert_allow "redirect to /dev/stderr" "$HOOK" "$(payload_bash 'echo x > /dev/stderr' tank)"
assert_allow "redirect to /dev/fd/2"   "$HOOK" "$(payload_bash 'echo x > /dev/fd/2' tank)"
# The /dev exemption is a list, not a glob: `/dev/*` would wave through a socket
# write and every device node.
assert_block "redirect to /dev/tcp"   "$HOOK" "$(payload_bash 'echo x > /dev/tcp/example.com/443' tank)" "$gap"
assert_block "redirect to a device node" "$HOOK" "$(payload_bash 'echo x > /dev/sda' tank)" "$gap"
assert_allow "fd dup (2>&1)"          "$HOOK" "$(payload_bash 'dotnet build 2>&1 | grep -c warning' tank)"
assert_allow "redirect under /tmp"    "$HOOK" "$(payload_bash 'dotnet build > /tmp/build.log 2>&1' tank)"
assert_allow "sed without -i"         "$HOOK" "$(payload_bash "sed 's/a/b/' src/Foo.cs | head -5" tank)"
assert_allow "sed -n (bounded read)"  "$HOOK" "$(payload_bash "sed -n '1,20p' src/Foo.cs" tank)"
assert_allow "quoted > in a pattern"  "$HOOK" "$(payload_bash 'grep -rn "a>b" src' tank)"
assert_allow "awk expression with >"  "$HOOK" "$(payload_bash "awk '\$3 > 5 {print}' report.txt" tank)"
assert_allow "Bash write in a no-agent session" "$HOOK" "$(payload_bash 'echo x > src/Foo.cs')"

# --- Fail closed on unparseable input -----------------------------------------
assert_block "non-JSON payload fails closed" "$HOOK" 'this is not json' "could not parse"

finish
