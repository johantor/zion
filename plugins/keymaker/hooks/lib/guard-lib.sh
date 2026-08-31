#!/usr/bin/env bash
# Shared runtime for the plugin hook guards: payload plumbing, the command-shape
# patterns every plugin's Bash guard enforces, and per-session state files.
#
# This file is SOURCED, never executed, and is deliberately not wired in any
# hooks.json -- validator §6 wires only the top-level hooks/*.sh entry points,
# and §5 requires every plugin's copy of this file to be byte-identical (crew's
# copy is canonical: edit here, then mirror). Keeping the shared floor in one
# vendored file is what lets a standalone keymaker install enforce exactly the
# same rules as crew without the two drifting apart.
#
# Two rules shape everything below.
#
# 1. No forks on the hot path. PreToolUse(Bash) runs before *every* Bash tool
#    call, so each `echo ... | grep -E` is latency the agent pays every time.
#    Matching goes through bash's own =~ and parameter expansion instead; the
#    single `jq` that parses the payload is the only child process a guard
#    spawns. Patterns stay POSIX (`[[:space:]]`, never the GNU-only `\s`) so
#    they behave the same under BSD/macOS regcomp.
#
# 2. The caller owns the failure posture. Nothing here decides whether a
#    can't-inspect path blocks or passes: security guards source this file
#    fail-closed and context/advisory hooks source it fail-open. The one
#    exception is the guard_block_* helpers, which exist precisely to block.

# shellcheck disable=SC2034
# ^ Everything below is this library's public surface: the entry points that
#   source it consume GUARD_* and guard_* by name. shellcheck analyses one file
#   at a time and cannot follow a `source` whose path is built at runtime, so it
#   sees every export as unused. Disabled once here rather than line by line.

# Idempotent: two hooks in one process (or a re-source) must not redefine state.
# Spelled as a full `if` rather than `[ ... ] && return`, whose non-zero status
# on the first load would be a trap for a caller running under `set -e`.
if [ -n "${GUARD_LIB_VERSION:-}" ]; then return 0; fi
GUARD_LIB_VERSION=1

# ------------------------------------------------------------------ constants

# Branches no agent may commit onto -- crew and keymaker both work on branches
# their orchestrator creates. One list, so the two guards cannot disagree.
GUARD_PROTECTED_BRANCHES='main|master|develop'

# read-guard's context-hygiene limits: raw reads above this size are refused
# unless the call carries an explicit line bound no larger than the cap.
GUARD_READ_MAX_BYTES=65536
GUARD_READ_MAX_BOUNDED_LINES=2000

# How long a per-session state file stays interesting. Swept opportunistically
# (see guard_state_path), so a long-lived machine does not accumulate one tiny
# file per agent instance forever.
GUARD_STATE_TTL_MINUTES=1440

# Record separator used to join fields out of a single jq pass.
GUARD_RS=$'\x1e'

# ------------------------------------------------------------------- payload

# guard_read_payload -- read all of stdin into $guard_payload without forking.
# `read -d ''` stops only at a NUL, which well-formed JSON never contains, so
# this consumes the whole payload; it returns non-zero at EOF, which is the
# normal case and not an error.
guard_read_payload() {
  guard_payload=''
  IFS= read -r -d '' guard_payload || :
}

# guard_jq2 <untrusted-expr> <trusted-expr>
#   Pulls two fields out of $guard_payload in ONE jq pass and splits them at the
#   LAST separator, setting $guard_untrusted and $guard_trusted. Returns
#   non-zero when the payload is not valid JSON -- the caller decides what that
#   means (block for a security guard, exit 0 for an advisor).
#
#   Argument order is load-bearing, not stylistic. The untrusted field goes
#   FIRST because it is attacker-influenced text (a command line, a file path)
#   that may itself contain the separator byte; splitting at the last one keeps
#   an embedded separator from truncating the value a guard is about to
#   inspect. The trusted field -- always a small harness-controlled value like
#   `agent_type`, which never contains the byte -- anchors the split from the
#   right. Joined with `-j` rather than @tsv, which would escape newlines and
#   tabs to literal "\n"/"\t" and corrupt the command text.
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

# Assembled once at source time so the per-call cost is a bash regex match and
# nothing else. Every pattern expects the normalized command in $guard_cmd.

_g_flag='-[^[:space:]]*'                                     # any single flag token
_g_word='[^[:space:];|&<>]+'                                 # any token within one command
_g_rec='(-[A-Za-z]*[rR][A-Za-z]*|--recursive)'               # token containing recursive
_g_frc='(-[A-Za-z]*f[A-Za-z]*|--force)'                      # token containing force
_g_comb='-[A-Za-z]*([rR][A-Za-z]*f|f[A-Za-z]*[rR])[A-Za-z]*'  # both in one token

# Recursive+force rm of /, ~ or * -- flags combined in either order (-rf, -fr,
# -rfv) or separate/long (-r -f, --recursive --force), with arbitrary other flag
# tokens between them and arbitrary arguments (including `--`) before the
# dangerous target. `\b` is a backspace in ERE, so `rm` is anchored on a
# separator rather than a word boundary.
_g_rm_rf="rm[[:space:]]+(${_g_flag}[[:space:]]+)*(${_g_comb}|${_g_rec}[[:space:]]+(${_g_flag}[[:space:]]+)*${_g_frc}|${_g_frc}[[:space:]]+(${_g_flag}[[:space:]]+)*${_g_rec})([[:space:]]+${_g_word})*"'[[:space:]]+(/|~|\*)'

# The rest of the destructive set: force-push via --force or short -f (but not
# the safe --force-with-lease / --force-if-includes -- `-[A-Za-z]*f` cannot
# cross their second dash); a redirect into .env; a redirect or removal aimed
# inside the repository's own git directory.
#
# `\|?` after every redirect operator covers `>|`, the noclobber override: it is
# a redirect like any other, and without it `echo s >| .env` reads as a `>` with
# the target hidden behind the `|`.
_g_dotgit='\.git/'
GUARD_RE_DESTRUCTIVE="${_g_rm_rf}"'|git[[:space:]]+push[^;&|]*[[:space:]](--force([^-]|$)|-[A-Za-z]*f)|>>?\|?[[:space:]]*\.env|>>?\|?[^|;&]*'"${_g_dotgit}"'|(^|[[:space:];|&(])rm[[:space:]][^|;&]*'"${_g_dotgit}"

# A command position: start of line, or just after a separator.
_g_cmdpos='(^|[;&|][&|]?[[:space:]]*)'
# Prefixes that must not let a command smuggle itself past the anchor above:
# leading env assignments, `env`, `command`.
_g_pfx='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|command[[:space:]]+)*'

# Any git invocation at a command position (for the workers that never run git).
GUARD_RE_GIT_AT_CMD="${_g_cmdpos}${_g_pfx}"'git([[:space:]]|$)'
# `git commit`, including git global flags before the subcommand (`git -c k=v
# commit`, `git -C dir commit`).
GUARD_RE_GIT_COMMIT="${_g_cmdpos}${_g_pfx}"'git[[:space:]]+(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*commit([[:space:]]|$)'

# Watch/dev/serve commands never terminate, so an agent turn that launches one
# hangs until its maxTurns/timeout. `--watch` matches the bare flag only, not
# `--watch=false` (the disable spelling); `vite build` stays allowed.
_g_watch='dotnet[[:space:]]+watch([[:space:]]|$)|(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(dev|start|serve|watch)([[:space:]]|$)|vite([[:space:]]+(dev|serve|preview)([[:space:]]|$)|[[:space:]]+-|[[:space:]]*($|[;&|]))|(next|nuxt)[[:space:]]+dev([[:space:]]|$)|ng[[:space:]]+serve([[:space:]]|$)|nodemon([[:space:]]|$)|webpack[[:space:]]+serve([[:space:]]|$)|webpack-dev-server([[:space:]]|$)'
GUARD_RE_WATCH="${_g_cmdpos}${_g_pfx}"'((npx|bunx)[[:space:]]+)?'"(${_g_watch})"'|--watch([[:space:]]|$)'

# Raw/streaming reads that dump a whole file or an endless stream into context.
GUARD_RE_PAGER="${_g_cmdpos}"'(less|more)[[:space:]]+'
GUARD_RE_STREAM="${_g_cmdpos}"'tail[[:space:]]+-f([[:space:]]|$)'
GUARD_RE_CAT="${_g_cmdpos}"'cat[[:space:]]+[^|><;&]+([[:space:]]*($|[;&]|&&|\|\|))'

# Bash can mutate a file without any Edit|Write hook seeing it: a redirect,
# `tee`, an in-place `sed`, a `cp` into the tree. Such a write skips every
# PreToolUse(Edit|Write) guard (write lanes, write allowlists) and every
# PostToolUse(Edit|Write) one (formatting), so for an agent session it is a way
# around a guard rather than a matter of style -- the same reasoning that makes
# GUARD_RE_CAT block raw reads on the Bash path instead of leaving read-guard to
# cover only the Read tool.
#
# Two patterns, enforced by guard_block_file_writes. A file-mutating command is
# matched at any word boundary rather than only at a command position, so
# `find ... -exec sed -i` is caught too. The stream editors need their in-place
# flag: short spellings bundle it (`perl -pi`, `sed -i.bak`), the long one spells
# it out, and `--expression` cannot match the short form because [A-Za-z] does
# not match the second dash. Destinations are deliberately not analysed --
# `cp`/`mv` are refused outright, which is one rule instead of an operand table
# per command.
_g_anypos='(^|[[:space:];|&(])'
GUARD_RE_WRITE_CMD="${_g_anypos}"'(tee|patch|cp|mv)([[:space:]]|$)'"|${_g_anypos}"'(sed|perl|ruby|awk|gawk)[[:space:]]+([^;|&]*[[:space:]])?(-[A-Za-z]*i([[:space:]]|[.=]|$)|--in-place)'
# A redirect and its target, glued or spaced (`>file`, `>> file`, `2>`, `&>`,
# and `>|`, the noclobber override -- without that `\|?` the target hides behind
# the `|` and the redirect reads as targetless). The target excludes `&`, so an
# fd dup (`2>&1`) captures nothing and reads as the exempt sink it is. `<` is
# absent by design: an input redirect writes nothing.
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
# The two patterns above, enforced. A floor, not a sandbox: any interpreter or
# code generator a build runs can still write files, and a write hidden inside a
# quoted `bash -c` string is not read as one. What this closes is the routine
# path -- editing through Bash instead of Edit/Write -- which is exactly the one
# the harness's own auto-mode notice pushes every agent toward.

# Placeholder that replaces a quoted span. Deliberately not an exempt sink: a
# quoted target (`> "src/x.cs"`) must still read as a write.
GUARD_QUOTED='@quoted@'

# guard_write_sink_exempt <target> -- true for a target a write may reach without
# escaping the Edit|Write guards: the null/std streams, an fd dup (which captures
# as the empty string), and the temp locations agents use for scratch output.
# Anything else counts as a path in the checkout, relative paths included:
# resolving one costs a fork, and a guard that guesses in the permissive
# direction is the hole it exists to close. `-` is NOT exempt -- it means stdout
# to some commands, but `> -` writes a file literally named `-`.
guard_write_sink_exempt() {
  case "$1" in
    '') return 0 ;;
    /dev/*|/proc/self/fd/*) return 0 ;;
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;;
    "${TMPDIR:-/tmp}"/*) return 0 ;;
  esac
  return 1
}

# guard_mask_quotes <cmd> -- sets $guard_masked to <cmd> with every single- or
# double-quoted span replaced by GUARD_QUOTED. One substitution, two jobs: a `>`
# inside a string (`grep "a>b" f`, `awk '$3 > 5'`) stops looking like a redirect,
# and a quoted path still leaves a non-exempt target behind, so quoting cannot
# hide a write. Quote types are tracked properly -- an apostrophe inside "..."
# opens nothing -- and an unterminated quote drops the remainder, which can only
# make the scan see less. That is fine: the shell would reject that command too.
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

# guard_block_file_writes -- refuse a Bash command that edits a file in the
# checkout. Callers scope it to agent sessions: the operator's own session is not
# lane-guarded in the first place, so it has no guard to route around, and its
# Bash editing is the harness's own suggestion.
#
# The command check reads the raw command, so a quoted argument cannot hide a
# `sed -i`; the redirect scan reads the masked copy, where a quoted `>` is no
# longer an operator. Each half gets the input it needs.
guard_block_file_writes() {
  local rest target what
  if [[ $guard_cmd =~ $GUARD_RE_WRITE_CMD ]]; then
    what="${BASH_REMATCH[0]#[[:space:];|\&(]}"   # drop the separator it matched
    guard_write_refuse "${what%%[[:space:]]*}"
  fi
  case "$guard_cmd" in *'>'*) ;; *) return 0 ;; esac
  guard_mask_quotes "$guard_cmd"
  rest="$guard_masked"
  while [[ $rest =~ $GUARD_RE_REDIRECT ]]; do
    target="${BASH_REMATCH[2]}"
    if ! guard_write_sink_exempt "$target"; then
      # Never report the mask back as if it were the path itself.
      [ "$target" = "$GUARD_QUOTED" ] && target='a quoted path'
      guard_write_refuse "a redirect into $target"
    fi
    rest="${rest#*"${BASH_REMATCH[0]}"}"          # every match is >= 1 char, so this terminates
  done
}

# guard_block_protected_branch_commit <agent_type> <advice>
#   Backstop for any agent that reaches a `git commit`: refuse it on a protected
#   branch. Scoped by the caller to agent sessions, so a normal user session is
#   never intercepted. The branch lookup is the one fork here, and it only
#   happens for a command that already looks like a commit.
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
# Callers treat a non-zero return as "cannot count" and degrade accordingly --
# never as a reason to block.

# guard_state_path <dir> <name-prefix> <key-source> <tag>
#   Sets $guard_state_path to "<dir>/<prefix>.<hash>.<tag>", or returns non-zero
#   when <dir> is unusable or <key-source> is empty. <tag> is dropped unless it
#   is plainly filename-safe. cksum is POSIX (and present on BSD/macOS), and
#   keeps the name short regardless of how long a transcript path is.
#
#   Reaching a path that does not exist yet also sweeps the directory of entries
#   older than GUARD_STATE_TTL_MINUTES. That is at most one `find` per agent
#   instance per session rather than one per tool call, which is why the sweep
#   lives here and not at the top of every hook.
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
  # and BSD/macOS find carry them, which covers everywhere these hooks run. The
  # sweep is deliberately best-effort anyway: errors are swallowed and the `|| :`
  # keeps a failure off the caller's exit status, so a find without them degrades
  # to exactly the old behavior (state files simply accumulate) and never to a
  # guard that stops guarding. That is why it is not worth a feature-detection
  # probe -- the probe would cost a fork on a path whose whole point is to be
  # cheap, to defend against a failure that is already harmless.
  if [ ! -e "$guard_state_path" ]; then
    find "$dir" -maxdepth 1 -name "$prefix.*" -type f \
      -mmin "+$GUARD_STATE_TTL_MINUTES" -delete 2>/dev/null || :
  fi
  return 0
}

# guard_read_counter <file> -- sets $guard_count and $guard_stage from the file's
# first two whitespace-separated fields, normalising a missing file, a short line
# or anything non-numeric to zero. Deliberately assigns rather than echoing:
# turn-budget calls this after every tool call of an agent session, and a caller
# forced to write `$(guard_read_counter ...)` would pay a fork each time for two
# integers this can just hand back.
guard_read_counter() {
  guard_count=0 guard_stage=0
  if [ -f "$1" ]; then
    read -r guard_count guard_stage < "$1" 2>/dev/null || :
    case "$guard_count" in ''|*[!0-9]*) guard_count=0 ;; esac
    case "$guard_stage" in ''|*[!0-9]*) guard_stage=0 ;; esac
  fi
}
