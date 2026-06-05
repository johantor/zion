#!/usr/bin/env bash
cmd="$(jq -r '.tool_input.command // empty')"
normalized="$(printf '%s' "$cmd" | tr '\n' ' ')"

if echo "$normalized" | grep -Eq 'rm -rf (/|~|\*)|git push .*--force([^-]|$)|>\s*\.env|>>?[^|;&]*\.git/|(^|[ \t;|&(])rm[ \t][^|;&]*\.git/'; then
  echo "Blocked: unsafe command." >&2
  exit 2
fi

if echo "$normalized" | grep -Eq '(^|[;&|][&|]?\s*)(less|more)\s+'; then
  echo "Blocked: interactive raw reads are disallowed. Use targeted grep/rg/jq/scripted summaries instead." >&2
  exit 2
fi

if echo "$normalized" | grep -Eq '(^|[;&|][&|]?\s*)tail\s+-f(\s|$)'; then
  echo "Blocked: streaming raw output is disallowed. Capture/filter and surface only the needed result." >&2
  exit 2
fi

if echo "$normalized" | grep -Eq '(^|[;&|][&|]?\s*)cat\s+[^|><;&]+(\s*($|[;&]|&&|\|\|))'; then
  echo "Blocked: unbounded cat reads are disallowed. Pipe/filter with grep/rg/jq or script the analysis." >&2
  exit 2
fi

exit 0
