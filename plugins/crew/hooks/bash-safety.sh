#!/usr/bin/env bash
# PreToolUse(Bash) guard. Blocks destructive commands and raw/streaming reads
# that bypass context discipline.
#
# The "shared guard" regions marked below are byte-synced with keymaker's copy
# (validate-plugin.sh §5); this copy is canonical — edit here and mirror there.
#
# Fail closed: a security guard that can't read its input must block, not let
# the command through uninspected. jq is a documented dependency (also required
# by lane-guard and validate-plugin).
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: bash-safety needs jq to inspect commands." >&2
  exit 2
fi
payload="$(cat)"
# One jq call for both fields. jq's own exit status is the payload-validity
# check (checked directly by `if !` below, not by inspecting $fields — a
# failed jq still assigns $fields, typically to an empty string). Fields are
# joined with a record-separator byte via -j (raw, unescaped) rather than
# @tsv, so cmd's own newlines/tabs survive intact for the flatten step below —
# @tsv would have escaped them to literal "\n"/"\t" text.
rs=$'\x1e'
if ! fields="$(printf '%s' "$payload" | jq -j --arg rs "$rs" '(.tool_input.command // "") + $rs + (.agent_type // "")' 2>/dev/null)"; then
  echo "Blocked: bash-safety could not parse the hook payload." >&2
  exit 2
fi
# Split on the LAST separator, not the first: cmd is arbitrary command text
# and could in principle contain the separator byte itself, whereas
# agent_type (the trailing field) is a small, harness-controlled value that
# never does. Splitting on the first occurrence would let an embedded
# separator inside cmd truncate what gets inspected below — silently hiding
# whatever follows it from the safety regexes.
cmd="${fields%"$rs"*}"
agent_type="${fields##*"$rs"}"

# Flatten newlines to spaces so a multi-line command can't slip a clause past
# the single-line regexes. POSIX [[:space:]] is used throughout instead of the
# GNU-only \s so the guard also holds on BSD/macOS grep.
normalized="$(printf '%s' "$cmd" | tr '\n' ' ')"

# --- BEGIN shared guard: destructive-ops ---
# Destructive ops, in order: recursive+force rm of /, ~ or * — flags combined in
# either order (-rf, -fr, -rfv) or separate/long (-r -f, --recursive --force),
# with arbitrary other flag tokens between them and arbitrary arguments (incl.
# the `--` separator) before the dangerous target; force-push via --force or
# short -f (but not the safe --force-with-lease / --force-if-includes —
# `-[A-Za-z]*f` can't cross their second dash); redirect (> or >>) into .env;
# redirect or rm into .git/. \b is a backspace in ERE, so `rm` is anchored on a
# separator/space rather than \brm\b.
flag='-[^[:space:]]*'                          # any single flag token
word='[^[:space:];|&<>]+'                      # any token within this command
rec='(-[A-Za-z]*[rR][A-Za-z]*|--recursive)'    # token containing recursive
frc='(-[A-Za-z]*f[A-Za-z]*|--force)'           # token containing force
comb='-[A-Za-z]*([rR][A-Za-z]*f|f[A-Za-z]*[rR])[A-Za-z]*'  # both in one token
rm_rf="rm[[:space:]]+(${flag}[[:space:]]+)*(${comb}|${rec}[[:space:]]+(${flag}[[:space:]]+)*${frc}|${frc}[[:space:]]+(${flag}[[:space:]]+)*${rec})([[:space:]]+${word})*[[:space:]]+(/|~|\\*)"
if echo "$normalized" | grep -Eq "${rm_rf}|git[[:space:]]+push[^;&|]*[[:space:]](--force([^-]|\$)|-[A-Za-z]*f)|>>?[[:space:]]*\\.env|>>?[^|;&]*\\.git/|(^|[[:space:];|&(])rm[[:space:]][^|;&]*\\.git/"; then
  echo "Blocked: unsafe command." >&2
  exit 2
fi
# --- END shared guard: destructive-ops ---

# Workers never touch git — morpheus is the sole git owner (branching and
# per-step commits; see AGENTS.md "How the crew works"). Any git invocation at
# a command position is blocked for the Bash-capable workers (seraph carries no
# Bash tool, so it needs no entry); the prefix consumes env assignments and
# env/command wrappers so they can't smuggle git past the anchor.
git_at_cmd='(^|[;&|][&|]?[[:space:]]*)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|command[[:space:]]+)*git([[:space:]]|$)'
case "$agent_type" in
  tank|trinity|oracle|dozer|neo)
    if echo "$normalized" | grep -Eq "$git_at_cmd"; then
      echo "Blocked: ${agent_type} never runs git — morpheus owns branching and commits. Return your result; morpheus commits verified steps." >&2
      exit 2
    fi ;;
esac

# Any other agent (morpheus, other plugins' agents) must not commit onto a
# protected base branch — crew work happens on feature branches (morpheus owns
# branching). Scoped via agent_type so a normal main session (no agent_type) is
# never intercepted. Catches plain `git commit` and git global flags before the
# subcommand (`git -c k=v commit`, `git -C dir commit`).
if [ -n "$agent_type" ] && echo "$normalized" | grep -Eq '(^|[;&|][&|]?[[:space:]]*)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|command[[:space:]]+)*git[[:space:]]+(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*commit([[:space:]]|$)'; then
  branch="$(git branch --show-current 2>/dev/null || true)"
  case "$branch" in
    main|master|develop)
      echo "Blocked: ${agent_type} may not commit on protected branch '$branch'. Work on a feature branch (morpheus owns branching)." >&2
      exit 2 ;;
  esac
fi

# Watch/dev/serve commands never terminate, so an agent turn that launches one
# hangs until its maxTurns/timeout — agents use one-shot build/test commands
# instead (morpheus's "One-shot build, bounded" rule). Scoped to agent
# sessions: the user's own session may legitimately run a dev server. `--watch`
# matches the bare flag only, not `--watch=false` (the disable spelling).
# `vite build` stays allowed.
# --- BEGIN shared guard: watch-commands ---
if [ -n "$agent_type" ]; then
  cmdpos='(^|[;&|][&|]?[[:space:]]*)'
  pfx='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|command[[:space:]]+)*((npx|bunx)[[:space:]]+)?'
  watch='dotnet[[:space:]]+watch([[:space:]]|$)|(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(dev|start|serve|watch)([[:space:]]|$)|vite([[:space:]]+(dev|serve|preview)([[:space:]]|$)|[[:space:]]+-|[[:space:]]*($|[;&|]))|(next|nuxt)[[:space:]]+dev([[:space:]]|$)|ng[[:space:]]+serve([[:space:]]|$)|nodemon([[:space:]]|$)|webpack[[:space:]]+serve([[:space:]]|$)|webpack-dev-server([[:space:]]|$)'
  if echo "$normalized" | grep -Eq "${cmdpos}${pfx}(${watch})|--watch([[:space:]]|$)"; then
    echo "Blocked: watch/dev/serve commands never terminate. Use the project's one-shot build/test command instead." >&2
    exit 2
  fi
fi
# --- END shared guard: watch-commands ---

# --- BEGIN shared guard: raw-reads ---
if echo "$normalized" | grep -Eq '(^|[;&|][&|]?[[:space:]]*)(less|more)[[:space:]]+'; then
  echo "Blocked: interactive raw reads are disallowed. Use targeted grep/rg/jq/scripted summaries instead." >&2
  exit 2
fi

if echo "$normalized" | grep -Eq '(^|[;&|][&|]?[[:space:]]*)tail[[:space:]]+-f([[:space:]]|$)'; then
  echo "Blocked: streaming raw output is disallowed. Capture/filter and surface only the needed result." >&2
  exit 2
fi

if echo "$normalized" | grep -Eq '(^|[;&|][&|]?[[:space:]]*)cat[[:space:]]+[^|><;&]+([[:space:]]*($|[;&]|&&|\|\|))'; then
  echo "Blocked: unbounded cat reads are disallowed. Pipe/filter with grep/rg/jq or script the analysis." >&2
  exit 2
fi
# --- END shared guard: raw-reads ---

exit 0
