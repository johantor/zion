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
guard_normalize() { guard_cmd="${1//$'\n'/ }"; }

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
# Python: ASGI/WSGI servers block whether or not --reload is passed, so they are
# matched bare; `manage.py runserver` needs its script prefix, since `runserver`
# alone is too generic to match at a command position.
_g_watch_py='(uvicorn|hypercorn|gunicorn|daphne|watchmedo|ptw|pytest-watch)([[:space:]]|$)|manage\.py[[:space:]]+runserver([[:space:]]|$)|flask[[:space:]]+(--app[[:space:]]+[^[:space:]]+[[:space:]]+)?run([[:space:]]|$)'
# Go/Rust: live-reload runners, plus `cargo watch`, a subcommand spelling the
# bare `--watch` alternative below does not reach.
_g_watch_gors='(air|reflex|gow)([[:space:]]|$)|cargo([[:space:]]+-[^[:space:]]+)*[[:space:]]+watch([[:space:]]|$)|trunk[[:space:]]+serve([[:space:]]|$)'
# JVM: the framework run goals, and Gradle's continuous build. `-t` is NOT
# matched -- it is Maven's --toolchains and far too generic at this position.
_g_watch_jvm='(mvn|mvnw|\./mvnw)[[:space:]]+([^[:space:]]+[[:space:]]+)*(spring-boot:run|quarkus:dev|jetty:run|tomcat7:run)([[:space:]]|$)|(gradle|gradlew|\./gradlew)[[:space:]]+([^[:space:]]+[[:space:]]+)*(bootRun|quarkusDev|--continuous)([[:space:]]|$)'
_g_watch="${_g_watch_web}|${_g_watch_py}|${_g_watch_gors}|${_g_watch_jvm}"
GUARD_RE_WATCH="${_g_cmdpos}${_g_pfx}"'((npx|bunx|uv[[:space:]]+run|poetry[[:space:]]+run|pdm[[:space:]]+run|python3?[[:space:]]+-m|python3?)[[:space:]]+)?'"(${_g_watch})"'|--watch([[:space:]]|$)'

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

# guard_block_protected_branch_commit <agent_type> <advice>
#   Backstop for any agent that reaches a `git commit`: refuse it on a protected
#   branch. Scoped by the caller to agent sessions, so a normal user session is
#   never intercepted. The branch lookup is the one fork here, and only for a
#   command that already looks like a commit.
guard_block_protected_branch_commit() {
  local agent_type="$1" advice="$2" branch
  [ -n "$agent_type" ] || return 0
  [[ $guard_cmd =~ $GUARD_RE_GIT_COMMIT ]] || return 0
  branch="$(git branch --show-current 2>/dev/null || true)"
  if [[ $branch =~ ^($GUARD_PROTECTED_BRANCHES)$ ]]; then
    echo "Blocked: ${agent_type} may not commit on protected branch '$branch'. ${advice}" >&2
    exit 2
  fi
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
