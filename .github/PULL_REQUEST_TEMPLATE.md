## Summary

<!-- Why this change, plus anything a reviewer needs to approve safely.
BUDGET: 150 words max here, 5 bullets max, whole body under 400 words. Count
before posting; if over, cut rather than reword.
NOT here: self-review write-ups, bugs-found-and-fixed logs, how-the-work-went
narrative, design-alternatives reasoning, pasted tool output. Those belong in the
commit message (not budgeted), the issue, or a review comment on the line.
See AGENTS.md, "Conventions". -->

-

## Scope

<!-- Which plugin(s) does this touch? plugins/crew, plugins/keymaker, plugins/engineering-principles, or repo-wide (docs/CI/hooks). -->

## Version / changelog

<!-- Per AGENTS.md: a PR that changes plugin behavior must bump `version` in the affected
plugin's `.claude-plugin/plugin.json` and add a matching `CHANGELOG.md` entry. Docs-only /
no-behavior-change PRs can skip this — say so below. -->

- [ ] Bumped `plugins/<name>/.claude-plugin/plugin.json` version
- [ ] Added a `CHANGELOG.md` entry for the affected plugin(s)
- [ ] N/A — no plugin behavior changed

## Test plan

<!-- What you ran, as results not transcripts: "ran X, all green", or one line
per case. Never paste output. Per AGENTS.md "Validating changes". -->

- [ ] `shellcheck plugins/*/hooks/*.sh scripts/*.sh`
- [ ] `bash scripts/validate-plugin.sh`
- [ ] Manually exercised the affected agent/command/skill flow

## Related issues

<!-- Use a closing keyword (Closes/Fixes/Resolves #N) so the issue auto-closes on merge.
Plain references (Implements #N) only cross-link, they don't close it. -->
