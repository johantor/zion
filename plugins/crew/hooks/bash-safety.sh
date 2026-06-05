#!/usr/bin/env bash
# PreToolUse(Bash) guard. Blocks destructive commands and raw/streaming reads
# that bypass context discipline.
#
# Fail closed: a security guard that can't read its input must block, not let
# the command through uninspected. jq is a documented dependency (also required
# by lane-guard and validate-plugin).
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: bash-safety needs jq to inspect commands." >&2
  exit 2
fi
payload="$(cat)"
if ! printf '%s' "$payload" | jq empty >/dev/null 2>&1; then
  echo "Blocked: bash-safety could not parse the hook payload." >&2
  exit 2
fi

# Flatten newlines to spaces so a multi-line command can't slip a clause past
# the single-line regexes. POSIX [[:space:]] is used throughout instead of the
# GNU-only \s so the guard also holds on BSD/macOS grep.
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
normalized="$(printf '%s' "$cmd" | tr '\n' ' ')"
agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // empty')"

# Destructive ops, in order: rm -rf of /, ~ or *; force-push (but not the safe
# --force-with-lease / --force-if-includes); redirect (> or >>) into .env;
# redirect or rm into .git/. \b is a backspace in ERE, so `rm` is anchored on a
# separator/space rather than \brm\b.
if echo "$normalized" | grep -Eq 'rm -rf (/|~|\*)|git push .*--force([^-]|$)|>>?[[:space:]]*\.env|>>?[^|;&]*\.git/|(^|[[:space:];|&(])rm[[:space:]][^|;&]*\.git/'; then
  echo "Blocked: unsafe command." >&2
  exit 2
fi

# Crew agents must not commit onto a protected base branch — they work on feature
# branches (morpheus owns branching). Scoped to crew agents via agent_type so a
# normal main session (no agent_type) is never intercepted. Catches plain `git commit`.
if [ -n "$agent_type" ] && echo "$normalized" | grep -Eq '(^|[;&|][&|]?[[:space:]]*)git[[:space:]]+commit([[:space:]]|$)'; then
  branch="$(git branch --show-current 2>/dev/null || true)"
  case "$branch" in
    main|master|develop)
      echo "Blocked: ${agent_type} may not commit on protected branch '$branch'. Work on a feature branch (morpheus owns branching)." >&2
      exit 2 ;;
  esac
fi

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

exit 0
