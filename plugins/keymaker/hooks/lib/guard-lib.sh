#!/usr/bin/env bash
# Shared runtime for the plugin hook guards: payload plumbing, the command-shape
# patterns every plugin's Bash guard enforces, and per-session state files.
#
# Sourced, never executed, and wired in no hooks.json -- validator §6 wires only
# the top-level hooks/*.sh entry points, and §5 pins every plugin's copy of this
# file byte-identical (crew's copy is canonical: edit crew's, then mirror), so a
# standalone keymaker install enforces the same floor as crew.
#
# Two rules shape everything below.
#
# 1. No forks on the hot path -- PreToolUse(Bash) runs before *every* Bash tool
#    call. Matching uses bash's own =~ and parameter expansion, and the single
#    `jq` that parses the payload is the only child a guard spawns. Patterns stay
#    POSIX (`[[:space:]]`, never the GNU-only `\s`) for BSD/macOS regcomp.
# 2. The caller owns the failure posture: security guards source this file
#    fail-closed, context/advisory hooks fail-open. The guard_block_* helpers are
#    the exception -- they exist to block.

# shellcheck disable=SC2034
# ^ GUARD_* and guard_* are this library's public surface. shellcheck cannot
#   follow a `source` whose path is built at runtime, so it sees them as unused.

# Idempotent: two hooks in one process (or a re-source) must not redefine state.
# A full `if` rather than `[ ... ] && return`, whose non-zero status on the first
# load would trap a caller running under `set -e`.
if [ -n "${GUARD_LIB_VERSION:-}" ]; then return 0; fi
GUARD_LIB_VERSION=1

# ------------------------------------------------------------------ constants

# Branches no agent may commit onto. One list, so the two guards cannot disagree.
GUARD_PROTECTED_BRANCHES='main|master|develop'

# read-guard's context-hygiene limits: raw reads above this size are refused
# unless the call carries an explicit line bound no larger than the cap.
GUARD_READ_MAX_BYTES=65536
GUARD_READ_MAX_BOUNDED_LINES=2000

# How long a per-session state file stays interesting. Swept opportunistically in
# guard_state_path, so the files do not accumulate forever.
GUARD_STATE_TTL_MINUTES=1440

# Record separator used to join fields out of a single jq pass.
GUARD_RS=$'\x1e'

# ------------------------------------------------------------------- payload

# guard_read_payload -- read all of stdin into $guard_payload without forking.
# `read -d ''` stops only at a NUL, which JSON never contains, so this consumes
# the whole payload; its non-zero return at EOF is the normal case.
guard_read_payload() {
  guard_payload=''
  IFS= read -r -d '' guard_payload || :
}

# guard_jq2 <untrusted-expr> <trusted-expr>
#   Pulls two fields out of $guard_payload in ONE jq pass and splits them at the
#   LAST separator, setting $guard_untrusted and $guard_trusted. Non-zero when
#   the payload is not valid JSON -- the caller decides what that means (block
#   for a security guard, exit 0 for an advisor).
#
#   Argument order is load-bearing: the untrusted field goes FIRST because it may
#   itself contain the separator byte, and the trusted one (a small
#   harness-controlled value like `agent_type`) anchors the split from the right.
#   See AGENTS.md, "Recurring review findings". Joined with `-j` rather than
#   @tsv, which would escape newlines and tabs and corrupt the command text.
guard_jq2() {
  local _fields
  _fields="$(jq -j --arg rs "$GUARD_RS" "($1) + \$rs + ($2)" <<<"$guard_payload" 2>/dev/null)" || return 1
  guard_untrusted="${_fields%"$GUARD_RS"*}"
  guard_trusted="${_fields##*"$GUARD_RS"}"
}

# guard_normalize <cmd> -- sets $guard_cmd with newlines flattened to spaces, so
# a multi-line command cannot slip a clause past the single-line patterns below.
guard_normalize() {
  # The patterns all expect one line, so newlines become spaces. The original is
  # kept beside it: a newline is a command separator, and the shell walk that
  # resolves a commit's directory has to see it as one.
  guard_cmd_raw="$1"
  guard_cmd="${1//$'\n'/ }"
}

# ------------------------------------------------- command-shape patterns

# Assembled once at source time. Every pattern expects the normalized command in
# $guard_cmd.

_g_flag='-[^[:space:]]*'                                     # any single flag token
_g_word='[^[:space:];|&<>]+'                                 # any token within one command
_g_rec='(-[A-Za-z]*[rR][A-Za-z]*|--recursive)'               # token containing recursive
_g_frc='(-[A-Za-z]*f[A-Za-z]*|--force)'                      # token containing force
_g_comb='-[A-Za-z]*([rR][A-Za-z]*f|f[A-Za-z]*[rR])[A-Za-z]*'  # both in one token

# Recursive+force rm of /, ~ or * -- flags combined in either order (-rf, -fr) or
# separate/long (-r -f, --recursive --force), with other flag tokens and
# arguments (including `--`) before the dangerous target. `\b` is a backspace in
# ERE, so `rm` is anchored on a separator rather than a word boundary.
_g_rm_rf="rm[[:space:]]+(${_g_flag}[[:space:]]+)*(${_g_comb}|${_g_rec}[[:space:]]+(${_g_flag}[[:space:]]+)*${_g_frc}|${_g_frc}[[:space:]]+(${_g_flag}[[:space:]]+)*${_g_rec})([[:space:]]+${_g_word})*"'[[:space:]]+(/|~|\*)'

# The rest of the destructive set: force-push via --force or short -f (but not
# the safe --force-with-lease / --force-if-includes -- `-[A-Za-z]*f` cannot cross
# their second dash); a redirect into `.env`; a redirect or removal aimed inside
# the repository's own `.git/`. `\|?` after every redirect operator covers `>|`,
# the noclobber override, without which its target hides behind the `|` and the
# redirect reads as targetless.
_g_dotgit='\.git/'
GUARD_RE_DESTRUCTIVE="${_g_rm_rf}"'|git[[:space:]]+push[^;&|]*[[:space:]](--force([^-]|$)|-[A-Za-z]*f)|>>?\|?[[:space:]]*\.env|>>?\|?[^|;&]*'"${_g_dotgit}"'|(^|[[:space:];|&(])rm[[:space:]][^|;&]*'"${_g_dotgit}"

# A command position: start of line, or just after a separator.
_g_cmdpos='(^|[;&|][&|]?[[:space:]]*)'
# Prefixes that must not smuggle a command past that anchor: leading env
# assignments, `env`, `command`.
_g_pfx='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|command[[:space:]]+)*'

# Any git invocation at a command position (for the workers that never run git).
GUARD_RE_GIT_AT_CMD="${_g_cmdpos}${_g_pfx}"'git([[:space:]]|$)'
# git global flags before a subcommand (`git -c k=v commit`, `git -C dir mv`): a
# flag token, optionally followed by its value token.
_g_gitopt='(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*'
GUARD_RE_GIT_COMMIT="${_g_cmdpos}${_g_pfx}"'git[[:space:]]+'"${_g_gitopt}"'commit([[:space:]]|$)'
# `git mv` at a command position, with at least one operand after it. Matched
# ONLY here, never at an arbitrary word boundary: `find -exec git mv` and a
# subshell `(git mv ...)` fall through to the generic write check and are
# refused, which is the failure direction a guard wants.
GUARD_RE_GIT_MV="${_g_cmdpos}${_g_pfx}"'git[[:space:]]+'"${_g_gitopt}"'mv[[:space:]]'
# A force flag among `git mv`'s operands: `-f`, bundled (`-kf`, `-fk`) or long.
GUARD_RE_GIT_MV_FORCE="(^|[[:space:]])${_g_frc}"'([[:space:]]|$)'

# Watch/dev/serve commands never terminate, so an agent turn that launches one
# hangs until its maxTurns/timeout. `--watch` matches the bare flag only, not
# `--watch=false` (the disable spelling); `vite build` stays allowed.
# Grouped per ecosystem; every stack the crew resolves has its own.
_g_watch_web='dotnet[[:space:]]+watch([[:space:]]|$)|(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(dev|start|serve|watch)([[:space:]]|$)|vite([[:space:]]+(dev|serve|preview)([[:space:]]|$)|[[:space:]]+-|[[:space:]]*($|[;&|]))|(next|nuxt)[[:space:]]+dev([[:space:]]|$)|ng[[:space:]]+serve([[:space:]]|$)|nodemon([[:space:]]|$)|webpack[[:space:]]+serve([[:space:]]|$)|webpack-dev-server([[:space:]]|$)'
# Python: the servers block with or without --reload, so they match bare;
# `runserver` needs its script prefix, being too generic on its own.
_g_watch_py='(uvicorn|hypercorn|gunicorn|daphne|watchmedo|ptw|pytest-watch|http\.server)([[:space:]]|$)|fastapi[[:space:]]+(dev|run)([[:space:]]|$)|(([^[:space:]]*/)?manage\.py|django-admin|django)[[:space:]]+runserver([[:space:]]|$)|flask([[:space:]]+--[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+run([[:space:]]|$)'
# Go/Rust: live-reload runners, plus `cargo watch`, a subcommand spelling the
# bare `--watch` alternative below does not reach.
_g_watch_gors='(air|reflex|gow)([[:space:]]|$)|cargo([[:space:]]+[-+][^[:space:]]+)*[[:space:]]+watch([[:space:]]|$)|trunk[[:space:]]+serve([[:space:]]|$)'
# JVM: the run goals and Gradle's continuous build. Tasks may be module-qualified
# (`:service:bootRun`). `-t` is matched only in the Gradle arm -- under Maven it
# is --toolchains.
_g_watch_jvm='(mvn|([^[:space:]]*/)?mvnw)[[:space:]]+([^[:space:]]+[[:space:]]+)*(spring-boot:run|quarkus:dev|jetty:run|tomcat7:run)([[:space:]]|$)|(gradle|([^[:space:]]*/)?gradlew)[[:space:]]+([^[:space:]]+[[:space:]]+)*((:[A-Za-z0-9_.:-]*)?(bootRun|quarkusDev)|--continuous|-t)([[:space:]]|$)'
# Tool-agnostic re-runners: these wrap ANY command and never terminate, so they
# belong to no single stack. `watch` is coreutils'; the rest are file watchers.
_g_watch_any='(watch|watchexec|entr|fswatch|nodemon)([[:space:]]|$)'
_g_watch="${_g_watch_web}|${_g_watch_py}|${_g_watch_gors}|${_g_watch_jvm}|${_g_watch_any}"
GUARD_RE_WATCH="${_g_cmdpos}${_g_pfx}"'((npx|bunx|(uv|poetry|pdm|pipenv)([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+run([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*|([^[:space:]]*/)?python[0-9.]*[[:space:]]+-m|([^[:space:]]*/)?python[0-9.]*)[[:space:]]+)*(([^[:space:]]*/)?('"${_g_watch}"'))|--watch([[:space:]]|$)'

# Raw/streaming reads that dump a whole file or an endless stream into context.
GUARD_RE_PAGER="${_g_cmdpos}"'(less|more)[[:space:]]+'
GUARD_RE_STREAM="${_g_cmdpos}"'tail[[:space:]]+-f([[:space:]]|$)'
GUARD_RE_CAT="${_g_cmdpos}"'cat[[:space:]]+[^|><;&]+([[:space:]]*($|[;&]|&&|\|\|))'

# Bash can mutate a file without any Edit|Write hook seeing it: a redirect, a
# `tee`, an in-place stream edit, a copy into the tree. Such a write skips every
# PreToolUse(Edit|Write) guard (write lanes, write allowlists) and every
# PostToolUse(Edit|Write) one (formatting), so for an agent session it is a way
# around a guard rather than a matter of style.
#
# Two patterns, enforced by guard_block_file_writes. A file-mutating command is
# matched at any word boundary rather than only at a command position, so a
# `find ... -exec` form is caught too. The stream editors need their in-place
# flag: short spellings bundle it (`-pi`, `-i.bak`), the long one spells it out,
# and `--expression` cannot match the short form because [A-Za-z] does not cross
# the second dash. Destinations are deliberately not analysed: `cp`/`mv` are
# refused outright, one rule instead of an operand table per command. The one
# carve-out is `git mv` for the plugin's git owner -- a rename, not a write; see
# guard_block_file_writes.
_g_anypos='(^|[[:space:];|&(])'
GUARD_RE_WRITE_CMD="${_g_anypos}"'(tee|patch|cp|mv)([[:space:]]|$)'"|${_g_anypos}"'(sed|perl|ruby|awk|gawk)[[:space:]]+([^;|&]*[[:space:]])?(-[A-Za-z]*i([[:space:]]|[.=]|$)|--in-place)'
# A redirect and its target, glued or spaced (`>file`, `>> file`, `2>`, `&>`, and
# the noclobber `>|`). The target excludes `&`, so an fd dup (`2>&1`) captures
# nothing and reads as the exempt sink it is. `<` is absent by design: an input
# redirect writes nothing.
GUARD_RE_REDIRECT='([0-9]*|&)>>?\|?[[:space:]]*([^[:space:];|&<>]*)'

# --------------------------------------------------------- blocking helpers
#
# The shared floor, as functions rather than copy-pasted regions: each inspects
# $guard_cmd and exits 2 with the message the agent sees. Order and wording are
# part of the contract both plugins keep.

guard_block_destructive() {
  if [[ $guard_cmd =~ $GUARD_RE_DESTRUCTIVE ]]; then
    echo "Blocked: unsafe command." >&2
    exit 2
  fi
}

guard_block_watch_commands() {
  if [[ $guard_cmd =~ $GUARD_RE_WATCH ]]; then
    echo "Blocked: watch/dev/serve commands never terminate. Use the project's one-shot build/test command instead." >&2
    exit 2
  fi
}

guard_block_raw_reads() {
  if [[ $guard_cmd =~ $GUARD_RE_PAGER ]]; then
    echo "Blocked: interactive raw reads are disallowed. Use targeted grep/rg/jq/scripted summaries instead." >&2
    exit 2
  fi
  if [[ $guard_cmd =~ $GUARD_RE_STREAM ]]; then
    echo "Blocked: streaming raw output is disallowed. Capture/filter and surface only the needed result." >&2
    exit 2
  fi
  if [[ $guard_cmd =~ $GUARD_RE_CAT ]]; then
    echo "Blocked: unbounded cat reads are disallowed. Pipe/filter with grep/rg/jq or script the analysis." >&2
    exit 2
  fi
}

# ------------------------------------------------- file writes through Bash
#
# The two patterns above, enforced. A floor, not a sandbox: an interpreter a
# build runs can still write files, and a write hidden inside a quoted `bash -c`
# string is not read as one. What this closes is the routine path -- editing
# through Bash instead of Edit/Write.

# Placeholder that replaces a quoted span. Deliberately not an exempt sink: a
# quoted target (`> "src/x.cs"`) must still read as a write.
GUARD_QUOTED='@quoted@'

# guard_write_sink_exempt <target> -- true for a target a write may reach without
# escaping the Edit|Write guards: the null/std streams, an fd dup (which captures
# as the empty string), and the temp locations agents use for scratch output.
# Anything else counts as a path in the checkout, relative paths included:
# resolving one costs a fork, and a guard that guesses permissively is the hole
# it exists to close. `-` is NOT exempt -- `> -` writes a file named `-`.
#
# The /dev list is enumerated rather than globbed: `/dev/*` would also exempt
# every device node, and `/dev/tcp/<host>/<port>`, which bash turns into a socket
# write.
guard_write_sink_exempt() {
  case "$1" in
    '') return 0 ;;
    /dev/null|/dev/stdout|/dev/stderr|/dev/tty) return 0 ;;
    /dev/fd/*|/proc/self/fd/*) return 0 ;;
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;;
    "${TMPDIR:-/tmp}"/*) return 0 ;;
  esac
  return 1
}

# guard_mask_quotes <cmd> -- sets $guard_masked to <cmd> with every single- or
# double-quoted span replaced by GUARD_QUOTED. One substitution, two jobs: a `>`
# inside a string (`grep "a>b" f`, `awk '$3 > 5'`) stops looking like a redirect,
# and a quoted path still leaves a non-exempt target behind, so quoting cannot
# hide a write. Quote types are tracked properly: an apostrophe inside `"..."`
# opens nothing.
#
# An unterminated quote drops the remainder, and a `\"` inside a double-quoted
# span ends it here where bash would keep going. Both mis-parses close a span
# EARLY, so the scan masks less than it should and over-detects: the failure
# direction is a refused command, never a write that slips through.
guard_mask_quotes() {
  local s="$1" out='' pre rest q sq dq
  while :; do
    case "$s" in
      *\'*|*\"*) ;;
      *) guard_masked="$out$s"; return 0 ;;
    esac
    # The shorter prefix marks the quote that comes first; a quote type that is
    # absent yields the whole string, so it always loses the comparison.
    sq="${s%%\'*}"; dq="${s%%\"*}"
    if [ "${#sq}" -lt "${#dq}" ]; then q=\'; pre="$sq"; else q='"'; pre="$dq"; fi
    out+="$pre$GUARD_QUOTED"
    rest="${s#"$pre$q"}"
    case "$rest" in
      *"$q"*) s="${rest#*"$q"}" ;;
      *) s='' ;;
    esac
  done
}

# guard_write_refuse <what> -- the one message both halves below report with.
guard_write_refuse() {
  echo "Blocked: $1 writes a file from Bash, which reaches no Edit|Write hook — write lanes and formatting are wired to Edit/Write, so the write would land unguarded. Use Edit/Write for files in the checkout; send scratch output under /tmp." >&2
  exit 2
}

# Placeholder for a permitted `git mv` subcommand token. `mv` followed by `@`
# matches neither GUARD_RE_GIT_MV (which wants whitespace after it) nor the
# generic write pattern, so the loop below terminates and the masked command
# keeps every other token where it was.
GUARD_GIT_MV_MASK='@gitmv@'

# guard_block_file_writes <agent_type> <git_owner> -- refuse a Bash command that
# edits a file in the checkout. Callers scope it to agent sessions: the operator's
# own session is not lane-guarded, so it has no guard to route around.
#
# `git mv` is the one carve-out, for <git_owner> alone. It renames a tracked path
# and records the rename in the index; no bytes change, so there is nothing for a
# lane guard or a formatter to inspect, and the rename lands in the git owner's
# own commit, where it is reviewed. Every other agent is told to hand the rename
# back rather than reach for a synonym. `-f`/`--force` stays refused for everyone:
# it can clobber an existing destination, which IS a write.
#
# Each permitted `git mv` is masked out and the generic check then runs on the
# masked copy, so an allowed `git mv a b` cannot carry a bare `mv c d` behind it.
# `${cmd/"$m"/...}` replaces the FIRST literal occurrence of the match, which is
# the match itself: a regex match is leftmost, and an identical earlier
# occurrence would itself have matched (the pattern reads no context beyond the
# separator it consumes), so at worst two identical `git mv`s swap places.
#
# The command check reads the raw command, so a quoted argument cannot hide a
# `sed -i`; the redirect scan reads the quote-masked copy, where a quoted `>` is
# no longer an operator.
guard_block_file_writes() {
  local agent_type="${1:-}" git_owner="${2:-}" cmd rest target what m ops
  cmd="$guard_cmd"
  while [[ $cmd =~ $GUARD_RE_GIT_MV ]]; do
    m="${BASH_REMATCH[0]}"
    if [ -z "$git_owner" ]; then
      break   # no owner named: `git mv` is an `mv` like any other, refused below
    fi
    if [ "$agent_type" != "$git_owner" ]; then
      echo "Blocked: git mv is a git operation — ${git_owner} owns git, and a rename is recorded in its commit. Hand the rename back: name the exact \`git mv <from> <to>\` in your result and stop; do not recreate the file under the new path." >&2
      exit 2
    fi
    # Operands up to the next separator, quotes stripped so `'-f'` still reads as
    # the flag git would see. A filename that merely looks like a force flag is
    # refused too: the failure direction is a refused rename, never a clobber.
    # `$m` stays QUOTED inside every expansion below, as in the redirect scan:
    # unquoted it would be a glob, and a `*` or `[` in a flag value (`git -C
    # "*" mv`) or an operand would widen the match and mask what follows.
    ops="${cmd#*"$m"}"; ops="${ops%%[;|&]*}"; ops="${ops//[\'\"]/}"
    if [[ $ops =~ $GUARD_RE_GIT_MV_FORCE ]]; then
      echo "Blocked: git mv -f/--force can overwrite an existing path, which is a write. Rename without it; if the destination exists, move or remove it as its own step first." >&2
      exit 2
    fi
    cmd="${cmd/"$m"/"${m%mv*}${GUARD_GIT_MV_MASK}${m##*mv}"}"
  done
  if [[ $cmd =~ $GUARD_RE_WRITE_CMD ]]; then
    what="${BASH_REMATCH[0]#[[:space:];|\&(]}"   # drop the separator it matched
    guard_write_refuse "${what%%[[:space:]]*}"
  fi
  case "$guard_cmd" in *'>'*) ;; *) return 0 ;; esac
  guard_mask_quotes "$guard_cmd"
  rest="$guard_masked"
  while [[ $rest =~ $GUARD_RE_REDIRECT ]]; do
    target="${BASH_REMATCH[2]}"
    if ! guard_write_sink_exempt "$target"; then
      # Never report the mask back as if it were the path itself -- a target can
      # also merely contain it (`b"` in `echo "a \" > b" > f`).
      case "$target" in *"$GUARD_QUOTED"*) target='a quoted path' ;; esac
      guard_write_refuse "a redirect into $target"
    fi
    # Advance past this match. The interpolation stays QUOTED so a glob
    # metacharacter in the matched text (`> /tmp/out[1]`) stays literal and the
    # trim lands where the match ended; unquoted it would match nothing and loop
    # forever. Every match is at least one character, so this terminates.
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
}

# ------------------------------------------ where a `git commit` would land
#
# A commit lands on the branch of the working tree the command runs in, which is
# not always the hook's own working directory: an agent working in a git worktree
# writes `cd ../wt && git commit` or `git -C ../wt commit`, and the branch checked
# out where the hook sits says nothing about that commit. Refusing it because the
# main checkout is on `develop` blocks work that never touches `develop`, so the
# directory is read out of the command itself.
#
# One rule keeps that from becoming a way around the backstop: a candidate
# directory is ADDED, never substituted. The hook's own directory -- all this
# guard used to look at -- stays in the set unless the walk models every
# construct between the start of the command and the commit, and a commit is
# refused when ANY candidate sits on a protected branch. So the check is at least
# as strict as reading the hook's directory alone, on every command, while a
# worktree still commits on its own branch.
#
# Confidence is lost -- and the hook's directory therefore stays in the set -- on
# a word this cannot read literally where it decides *where* a command runs (an
# expansion, a substitution, a backslash escape, a glob), a nested shell or
# `eval`, `pushd`/`popd`, a `cd` whose target cannot be entered or which carries
# extra operands, `--git-dir`/`--work-tree`, and a `cd` the shell may skip or run
# in a subshell. The one modelled gap left is physical vs logical `..` above the
# hook's own directory: `cd ../wt` is read as git reads it, which differs only if
# the hook's own path runs through a symlink.

# The run of ordinary characters at the front of a shell word, and of a segment:
# everything up to the next quote, escape, separator or (for a word) blank. Both
# are matched with `=~` rather than a pattern in `${..%%}`, so the class stays one
# literal and needs no quoting dance.
GUARD_RE_WORD_RUN=$'^([^[:space:];&|<>()\'"\\]+)'

# guard_dq_span <text after an opening `"`>
#   Sets $guard_span to the rest of that double-quoted span, its closing quote
#   included, and $guard_rest_after to what follows it. A `\"` inside the span
#   does not close it -- read naively, an escaped quote ends the span early and
#   every separator after it splits where the shell would not. An unterminated
#   span takes the remainder, which hides no separator.
guard_dq_span() {
  local s="$1" out='' piece t n
  while :; do
    case "$s" in
      *\"*) piece="${s%%\"*}" ;;
      *) guard_span="$out$s"; guard_rest_after=''; return 0 ;;
    esac
    s="${s#"$piece"}"
    t="$piece"; n=0
    while [ "${t%\\}" != "$t" ]; do t="${t%\\}"; n=$((n + 1)); done
    if [ $((n % 2)) -eq 1 ]; then
      out+="$piece\""; s="${s#\"}"          # the quote was escaped: span continues
    else
      guard_span="$out$piece\""; guard_rest_after="${s#\"}"; return 0
    fi
  done
}

# guard_next_word -- takes the next shell word off the front of $guard_wrest into
# $guard_word, quotes removed, and sets $guard_word_ok to '' when the word cannot
# be taken literally. Returns non-zero when the stream is at a separator or empty,
# leaving $guard_wrest on that separator for the caller to read.
#
# A word this cannot read is never guessed at: an expansion, a command
# substitution, a glob, a `~`, a backslash escape and an unterminated quote all
# clear $guard_word_ok, and every caller turns that into a lost-confidence
# candidate rather than a path.
guard_next_word() {
  local rest="$guard_wrest" out='' ok=1 piece
  while :; do
    case "$rest" in [[:space:]]*) rest="${rest#?}" ;; *) break ;; esac
  done
  guard_wrest="$rest"
  case "$rest" in ''|[';&|<>()']*) guard_word=''; guard_word_ok=''; return 1 ;; esac
  while [ -n "$rest" ]; do
    case "$rest" in
      [[:space:]]*|[';&|<>()']*) break ;;
      \'*)
        rest="${rest#?}"
        case "$rest" in
          *\'*) out+="${rest%%\'*}"; rest="${rest#*\'}" ;;
          *)    out+="$rest"; rest=''; ok='' ;;
        esac ;;
      \"*)
        guard_dq_span "${rest#?}"
        piece="${guard_span%\"}"; rest="$guard_rest_after"
        [ "$guard_span" != "$piece" ] || ok=''       # unterminated
        case "$piece" in *'$'*|*'`'*|*\\*) ok='' ;; esac
        out+="$piece" ;;
      \\*)
        # An escape this cannot read. Consume the backslash AND what it escapes,
        # but a lone trailing one escapes nothing: `${rest#??}` would not match
        # it and the walk would never advance.
        ok=''
        if [ "${#rest}" -ge 2 ]; then rest="${rest:2}"; else rest=''; fi ;;
      *)
        [[ $rest =~ $GUARD_RE_WORD_RUN ]] || { ok=''; break; }
        piece="${BASH_REMATCH[1]}"
        case "$piece" in *'$'*|*'`'*|*'*'*|*'?'*|*'['*) ok='' ;; esac
        out+="$piece"; rest="${rest#"$piece"}" ;;
    esac
  done
  case "$out" in '~'*) ok='' ;; esac
  guard_word="$out"; guard_word_ok="$ok"; guard_wrest="$rest"
  return 0
}

GUARD_RE_SEG_RUN=$'^([^\'";&|\\\n]+)'

# guard_next_segment -- pulls one segment off the front of $guard_rest into
# $guard_seg, and the separator run that ended it into $guard_sep (empty at the
# end of the command). Quoted spans and backslash escapes are copied through
# whole, so neither a separator inside a commit message nor an escaped one ends
# a segment where the shell would not.
guard_next_segment() {
  local piece
  guard_seg=''; guard_sep=''
  while [ -n "$guard_rest" ]; do
    case "$guard_rest" in
      [$'\n'';&|']*)
        while :; do
          case "$guard_rest" in
            [$'\n'';&|']*) guard_sep+="${guard_rest:0:1}"; guard_rest="${guard_rest:1}" ;;
            *) return 0 ;;
          esac
        done ;;
      \\*) guard_seg+="${guard_rest:0:2}"; guard_rest="${guard_rest:2}" ;;
      \"*)
        guard_seg+='"'; guard_dq_span "${guard_rest#?}"
        guard_seg+="$guard_span"; guard_rest="$guard_rest_after" ;;
      \'*)
        guard_seg+="'"; guard_rest="${guard_rest#?}"
        case "$guard_rest" in
          *\'*) guard_seg+="${guard_rest%%\'*}'"; guard_rest="${guard_rest#*\'}" ;;
          *)     guard_seg+="$guard_rest"; guard_rest='' ;;
        esac ;;
      *)
        [[ $guard_rest =~ $GUARD_RE_SEG_RUN ]] || { guard_seg+="$guard_rest"; guard_rest=''; return 0; }
        piece="${BASH_REMATCH[1]}"
        guard_seg+="$piece"; guard_rest="${guard_rest#"$piece"}"
        [ -n "$guard_rest" ] || return 0 ;;
    esac
  done
}

# guard_join_dir <base> <target> [logical]
#   Sets $guard_dir to <target> resolved against <base>: an absolute target
#   replaces it, a relative one extends it, an empty one leaves it alone. The
#   empty string means the hook's own directory, so a relative target stays
#   relative and needs no `pwd`.
#
#   With <logical> set, `<name>/..` pairs cancel the way a shell's `cd` does:
#   `cd link && cd ..` comes back where it started, while git, handed `link/..`,
#   resolves the symlink first and lands somewhere else. Git's own `-C` is
#   resolved by git, so that caller passes <logical> empty and leaves the `..`
#   in place. A leading `..` has nothing to cancel and stays either way.
guard_join_dir() {
  local p out rest comp t
  case "$2" in
    '') guard_dir="$1"; return 0 ;;
    /*) p="$2" ;;
    *)  p="${1:+$1/}$2" ;;
  esac
  if [ -n "${3:-}" ]; then
    out=''; rest="$p"
    case "$p" in /*) out='/'; rest="${p#/}" ;; esac
    while [ -n "$rest" ]; do
      comp="${rest%%/*}"
      case "$rest" in */*) rest="${rest#*/}" ;; *) rest='' ;; esac
      case "$comp" in
        ''|.) ;;
        ..)
          case "$out" in
            /) ;;                      # the root's parent is the root
            ''|*'../') out+='../' ;;   # nothing to cancel yet
            *) t="${out%/}"
               case "$t" in */*) out="${t%/*}/" ;; *) out='' ;; esac ;;
          esac ;;
        *) out+="$comp/" ;;
      esac
    done
    case "$out" in
      '')  p='.' ;;
      /)   p='/' ;;
      *)   p="${out%/}" ;;
    esac
  fi
  guard_dir="$p"
}

# guard_dir_usable <dir> -- true when a `cd` there would succeed as far as this
# can tell: an existing, searchable directory, and no CDPATH to send a relative
# target somewhere else entirely. All builtins, so no fork. The empty string is
# the hook's own directory, which it is already in.
guard_dir_usable() {
  [ -n "$1" ] || return 0
  [ -z "${CDPATH:-}" ] || case "$1" in /*) ;; *) return 1 ;; esac
  [ -d "$1" ] && [ -x "$1" ]
}

# guard_add_dir <dir> -- appends to the $guard_dirs candidate list, skipping a
# directory already in it. Each entry costs one branch lookup, and the list is
# short, so a scan beats any encoding that has to survive a path's own bytes.
guard_add_dir() {
  local d
  for d in ${guard_dirs[@]+"${guard_dirs[@]}"}; do
    [ "$d" = "$1" ] && return 0
  done
  guard_dirs+=("$1")
}

# Words that move the shell, or run a command this walk cannot see into. Either
# way the directory a later commit runs in stops being knowable from here.
GUARD_RE_OPAQUE_CMD='^(pushd|popd|eval|exec|source|\.|bash|sh|zsh|dash|ksh|xargs|coproc|case|esac|function|\{|\})$'
# Prefixes that may stand before the real command word: an assignment, a wrapper,
# and the shell keywords that put a command after them (`then git commit …`).
GUARD_RE_CMD_PREFIX='^([A-Za-z_][A-Za-z0-9_]*=.*|env|command|builtin|nohup|time|if|then|else|elif|while|until|do|!)$'
# Of those, the ones that exec a program: they cannot run `cd`, which is a
# builtin, so `nohup cd wt` moves nothing and the carry must not follow it.
GUARD_RE_EXTERNAL_WRAPPER='^(env|nohup)$'
# The options bash's own `cd` accepts. Anything else makes it fail before it
# moves, so the shell stays where it was.
GUARD_RE_CD_OPTION='^-[LPe@]+$'
# The two assignments that send git at another repository entirely.
GUARD_RE_GIT_ENV='^(GIT_DIR|GIT_WORK_TREE)=(.*)$'

# guard_collect_commit_dirs -- fills the $guard_dirs array with every directory a
# `git commit` in the command might run in, '' meaning the hook's own and a
# `gitdir:` entry meaning a repository named outright. An empty array means the
# walk found nothing that commits.
#
# The command is walked segment by segment, carrying a `cd` onto what follows the
# way the shell carries it. Every construct that could move the shell somewhere
# this cannot follow costs confidence, and lost confidence adds '' to the
# candidates rather than replacing them.
guard_collect_commit_dirs() {
  local cur='' sure=1 cond='' in_pipe='' next_cond='' list_cur='' opaque commit
  local dir dirsure target extra masked opens closes did_cd pre_cur w i n sep_norm
  local cd_phys
  local -a stack=()
  guard_rest="${guard_cmd_raw:-$guard_cmd}"
  guard_dirs=()
  while [ -n "$guard_rest" ]; do
    guard_next_segment
    masked=''
    if [ -n "$guard_seg" ]; then guard_mask_quotes "$guard_seg"; masked="$guard_masked"; fi
    # Subshell bookkeeping, one entry per nesting level: a `cd` inside `( … )`
    # never reaches what follows the closing paren.
    opens="${masked//[!(]/}"; closes="${masked//[!)]/}"
    n=${#opens}; i=0
    while [ "$i" -lt "$n" ]; do stack+=("$cur"); i=$((i + 1)); done
    # Strip every leading `(`/`{`: `( (git commit) )` opens two at once, and the
    # command word is what follows them.
    while :; do
      guard_seg="${guard_seg#"${guard_seg%%[![:space:]]*}"}"
      case "$guard_seg" in
        \(*|\{*) guard_seg="${guard_seg#?}" ;;
        *) break ;;
      esac
    done
    guard_wrest="$guard_seg"
    pre_cur="$cur"; did_cd=''; commit=''; opaque=''; dir="$cur"; dirsure="$sure"; ext=''

    # The command word, past any prefix word. An assignment that points git at
    # another repository is a candidate of its own, not a harmless prefix.
    while guard_next_word; do
      if [ -z "$guard_word_ok" ]; then opaque=1; break; fi
      if [[ $guard_word =~ $GUARD_RE_GIT_ENV ]]; then
        target="${BASH_REMATCH[2]}"
        case "${BASH_REMATCH[1]}" in
          GIT_DIR)       guard_join_dir "$cur" "$target"; guard_add_dir "gitdir:$guard_dir" ;;
          GIT_WORK_TREE) guard_join_dir "$cur" "$target"; guard_add_dir "$guard_dir" ;;
        esac
        dirsure=''
        continue
      fi
      [[ $guard_word =~ $GUARD_RE_CMD_PREFIX ]] || break
      if [[ $guard_word =~ $GUARD_RE_EXTERNAL_WRAPPER ]]; then ext=1; fi
    done
    case "$guard_word" in
      # A command word cannot begin with `-`, so a wrapper's own option (`env -i
      # git …`) ends the walk here, and an empty word means the segment opened
      # with a redirection or a construct this does not parse.
      ''|-*) [ -n "$guard_seg" ] && opaque=1 ;;
    esac
    # `name() { ...; }`: a function definition. This walk cannot model its body or
    # a later call site, so it is an opaque construct.
    target="${guard_wrest#"${guard_wrest%%[![:space:]]*}"}"
    case "$target" in '()'*) [ -n "$guard_word" ] && opaque=1 ;; esac
    if [ -z "$opaque" ]; then
      case "$guard_word" in
        cd)
          target=''; extra=''; cd_phys=''
          while guard_next_word; do
            if [ -z "$guard_word_ok" ]; then extra=1; break; fi
            case "$guard_word" in
              --) continue ;;
              -?*) if [ -n "$target" ]; then extra=1; break; fi
                   # An option bash's `cd` does not take makes it fail before it
                   # moves anywhere.
                   [[ $guard_word =~ $GUARD_RE_CD_OPTION ]] || { extra=1; break; }
                   # `-P` resolves symlinks as it goes and leaves the shell on
                   # the physical path, so from here on `..` means what it means
                   # to git, and the joins stop collapsing it.
                   case "$guard_word" in -*P*) cd_phys=1 ;; *) cd_phys='' ;; esac
                   continue ;;
            esac
            if [ -n "$target" ]; then extra=1; break; fi   # `cd a b` fails outright
            target="$guard_word"
          done
          # A redirection on the `cd` can fail and take the `cd` with it, and an
          # external wrapper cannot run a builtin at all.
          case "$guard_wrest" in [\<\>]*) extra=1 ;; esac
          if [ -n "$ext" ]; then extra=1; fi
          if [ -n "$extra" ]; then
            sure=''
          elif [ -z "$target" ]; then
            # Bare `cd` goes to $HOME. The hook holds the same environment, so
            # the destination is knowable even though the word is not there.
            sure=''
            if [ -n "${HOME:-}" ] && guard_dir_usable "$HOME"; then did_cd=1; cur="$HOME"; fi
          else
            if [ -n "$cd_phys" ]; then
              guard_join_dir "$cur" "$target"
            else
              guard_join_dir "$cur" "$target" logical
            fi
            if guard_dir_usable "$guard_dir"; then
              did_cd=1; cur="$guard_dir"
              # A `cd` the shell may skip: after `||` it runs only when the left
              # side failed, and the commands after it run either way.
              if [ "$next_cond" = 'or' ]; then sure=''; elif [ -n "$next_cond" ]; then cond=1; fi
            else
              sure=''
            fi
          fi ;;
        git|*/git)
          while guard_next_word; do
            if [ -z "$guard_word_ok" ]; then
              # The subcommand itself can be the unreadable word: a trailing
              # backslash makes `git commit\` one, and it still commits.
              dirsure=''
              case "$guard_word" in commit*) commit=1; break ;; esac
              continue
            fi
            case "$guard_word" in
              commit) commit=1; break ;;
              -C) if guard_next_word && [ -n "$guard_word_ok" ]; then
                    # Git resolves its own `-C`, `..` physically included, so
                    # this join stays textual.
                    guard_join_dir "$dir" "$guard_word"; dir="$guard_dir"
                  else
                    dirsure=''
                  fi ;;
              --git-dir=*|--work-tree=*|--git-dir|--work-tree)
                # Another repository entirely. Git resolves these against its own
                # `-C`, so they join onto $dir, not the shell's directory.
                case "$guard_word" in
                  *=*) target="${guard_word#*=}"; w="${guard_word%%=*}" ;;
                  *)   w="$guard_word"
                       if guard_next_word && [ -n "$guard_word_ok" ]; then
                         target="$guard_word"
                       else
                         target=''
                       fi ;;
                esac
                if [ -n "$target" ]; then
                  guard_join_dir "$dir" "$target"
                  case "$w" in
                    --git-dir) guard_add_dir "gitdir:$guard_dir" ;;
                    *)         guard_add_dir "$guard_dir" ;;
                  esac
                fi
                dirsure='' ;;
              -c|--namespace|--exec-path|--config-env|--super-prefix)
                guard_next_word || : ;;
              -*) ;;
              *) break ;;
            esac
          done ;;
        *) if [[ $guard_word =~ $GUARD_RE_OPAQUE_CMD ]]; then opaque=1; fi ;;
      esac
    fi
    if [ -n "$opaque" ]; then
      # A nested shell, an `eval`, a redirection ahead of the command, a word
      # this cannot read: it may cd, and it may carry the commit itself. Nothing
      # in such a segment can be parsed, so any `commit` in it counts.
      sure=''; dir="$cur"; dirsure=''
      case "$guard_seg" in *commit*) commit=1 ;; esac
    fi
    # A substitution runs commands of its own inside a word this walk reads as
    # one token. Tested against the command-position pattern from the
    # substitution's own start, so `-m "done $(date)"` and `--grep=commit` keep
    # the directory the segment resolved.
    # shellcheck disable=SC2016  # the patterns are a literal `$(` and a backtick
    case "$guard_seg" in
      *'$('*) target="${guard_seg#*'$('}" ;;
      *'`'*)  target="${guard_seg#*\`}" ;;
      *)      target='' ;;
    esac
    if [ -n "$target" ] && [[ $target =~ $GUARD_RE_GIT_COMMIT ]]; then
      commit=1; dirsure=''
    fi
    if [ -n "$commit" ]; then
      guard_add_dir "$dir"
      if [ -z "$dirsure" ] || [ -z "$sure" ]; then guard_add_dir ''; fi
    fi

    # Either side of a pipe runs in a subshell, and `&` backgrounds the whole
    # list before it: neither moves the shell that runs what follows. The `&`
    # case restores the directory from the start of that list, not just this
    # segment's, so a `cd` earlier in the backgrounded list is undone too.
    case "$guard_sep" in
      '|'|'|&') if [ -n "$did_cd" ]; then cur="$pre_cur"; fi ;;
      '&')      cur="$list_cur" ;;
    esac
    if [ -n "$in_pipe" ] && [ -n "$did_cd" ]; then cur="$pre_cur"; fi
    sep_norm="${guard_sep//$'\n'/}"
    # A `cd` reached through `&&` is safe to carry while that chain continues; a
    # `;` or `&` ends the chain, and with it the certainty.
    case "$sep_norm" in
      ';'|'&'|'||'|'') if [ -n "$cond" ]; then sure=''; cond=''; fi ;;
    esac
    case "$sep_norm" in
      '&&') next_cond='and' ;;
      '||') next_cond='or' ;;
      *)    next_cond='' ;;
    esac
    case "$guard_sep" in
      '|'|'|&') in_pipe=1 ;;
      '')       ;;
      *)        in_pipe='' ;;
    esac
    case "$guard_sep" in
      ';'|'&'|$'\n') list_cur="$cur" ;;
    esac
    n=${#closes}; i=0
    while [ "$i" -lt "$n" ] && [ "${#stack[@]}" -gt 0 ]; do
      cur="${stack[${#stack[@]} - 1]}"
      unset "stack[${#stack[@]} - 1]"
      i=$((i + 1))
    done
  done
}

# guard_branch_at <dir> -- sets $guard_branch to the branch checked out in <dir>,
# or in the hook's own directory when <dir> is empty. Empty for a detached HEAD
# and for a path that is no work tree at all; neither is a protected branch, and
# a commit there lands nowhere this guard protects.
guard_branch_at() {
  case "$1" in
    # A `--git-dir`/`GIT_DIR` candidate: its work tree may be anywhere, or be a
    # plain directory with no `.git` of its own, so the repository is asked
    # directly rather than through a directory that may know nothing about it.
    gitdir:*) guard_branch="$(git --git-dir="${1#gitdir:}" branch --show-current 2>/dev/null || true)" ;;
    '')       guard_branch="$(git branch --show-current 2>/dev/null || true)" ;;
    *)        guard_branch="$(git -C "$1" branch --show-current 2>/dev/null || true)" ;;
  esac
}

# guard_block_protected_branch_commit <agent_type> <advice>
#   Backstop for any agent that reaches a `git commit`: refuse it when any
#   directory the commit might run in is on a protected branch. Scoped by the
#   caller to agent sessions, so a normal user session is never intercepted.
#
#   The walk is the detector, not just the resolver: a `commit` anywhere in the
#   command starts it, which also reaches a subshell spelling (`(git commit)`)
#   that the command-position pattern alone does not. The branch lookups are the
#   only forks, one per candidate directory.
guard_block_protected_branch_commit() {
  local agent_type="$1" advice="$2" dir where
  [ -n "$agent_type" ] || return 0
  guard_collect_commit_dirs
  if [ "${#guard_dirs[@]}" -eq 0 ]; then
    # The walk found nothing that commits. `echo commit` and `git log
    # --grep=commit` end here rather than being judged as commits. Only the
    # command-position pattern can still see one the walk misread, and then the
    # hook's own directory is all that is known about it.
    [[ $guard_cmd =~ $GUARD_RE_GIT_COMMIT ]] || return 0
    guard_dirs=('')
  fi
  for dir in "${guard_dirs[@]}"; do
    guard_branch_at "$dir"
    if [[ $guard_branch =~ ^($GUARD_PROTECTED_BRANCHES)$ ]]; then
      where=''
      case "$dir" in
        '') ;;
        gitdir:*) where=" in the repository at '${dir#gitdir:}'" ;;
        *) where=" in '$dir'" ;;
      esac
      echo "Blocked: ${agent_type} may not commit on protected branch '$guard_branch'${where}. ${advice}" >&2
      exit 2
    fi
  done
}

# ---------------------------------------------------------------- state files
#
# Advisory hooks (turn-budget, dispatch-denied) keep a tiny per-session counter.
# A non-zero return means "cannot count", never a reason to block.

# guard_state_path <dir> <name-prefix> <key-source> <tag>
#   Sets $guard_state_path to "<dir>/<prefix>.<hash>.<tag>", or returns non-zero
#   when <dir> is unusable or <key-source> is empty. <tag> is dropped unless it
#   is plainly filename-safe. cksum is POSIX (and present on BSD/macOS) and keeps
#   the name short however long a transcript path is.
#
#   A path that does not exist yet also triggers the TTL sweep below: at most one
#   `find` per agent instance per session, rather than one per tool call.
guard_state_path() {
  local dir="$1" prefix="$2" key_src="$3" tag="$4" key
  [ -n "$key_src" ] || return 1
  [ -d "$dir" ] && [ -w "$dir" ] || return 1
  case "$tag" in
    ''|*[!A-Za-z0-9_-]*) tag="state" ;;
  esac
  key="$(printf '%s' "$key_src" | cksum | tr -s ' \t' '--')"
  guard_state_path="$dir/$prefix.$key.$tag"
  # `-mmin` and `-delete` are extensions rather than POSIX `find`, but both GNU
  # and BSD/macOS find carry them. The sweep is best-effort anyway: errors are
  # swallowed and `|| :` keeps a failure off the caller's exit status, so a find
  # without them degrades to the files accumulating, never to a guard that stops
  # guarding.
  if [ ! -e "$guard_state_path" ]; then
    find "$dir" -maxdepth 1 -name "$prefix.*" -type f \
      -mmin "+$GUARD_STATE_TTL_MINUTES" -delete 2>/dev/null || :
  fi
  return 0
}

# guard_read_counter <file> -- sets $guard_count and $guard_stage from the file's
# first two whitespace-separated fields, normalising a missing file, a short line
# or anything non-numeric to zero. Assigns rather than echoing: turn-budget calls
# it after every tool call, and `$(...)` would cost a fork for two integers.
guard_read_counter() {
  guard_count=0 guard_stage=0
  if [ -f "$1" ]; then
    read -r guard_count guard_stage < "$1" 2>/dev/null || :
    case "$guard_count" in ''|*[!0-9]*) guard_count=0 ;; esac
    case "$guard_stage" in ''|*[!0-9]*) guard_stage=0 ;; esac
  fi
}
