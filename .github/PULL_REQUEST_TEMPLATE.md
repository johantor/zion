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

<!-- Per AGENTS.md "Releasing": a PR that changes plugin behavior bumps `version` in the
affected plugin's `.claude-plugin/plugin.json` and adds a matching `CHANGELOG.md` entry. A
change too small for its own release still gets recorded — park a bullet under
`## [Unreleased]` for the next bump to fold in. CI (`scripts/check-changelog.sh`) blocks a
shipped change with neither, and a bump that leaves bullets parked. Only changes that reach no
user through `claude plugin update` are N/A. -->

- [ ] Bumped `plugins/<name>/.claude-plugin/plugin.json` version + matching `CHANGELOG.md` entry
- [ ] Parked a bullet under `## [Unreleased]` instead (too small for its own release)
- [ ] Folded any previously parked `## [Unreleased]` bullets into this bump
- [ ] N/A — nothing shipped changed (CI, root docs, tests)

## Test plan

<!-- What you ran, as results not transcripts: "ran X, all green", or one line
per case. Never paste output. Per AGENTS.md "Validating changes". -->

- [ ] `shellcheck plugins/*/hooks/*.sh scripts/*.sh`
- [ ] `bash scripts/validate-plugin.sh`
- [ ] Manually exercised the affected agent/command/skill flow

## Related issues

<!-- Use a closing keyword (Closes/Fixes/Resolves #N) so the issue auto-closes on merge.
Plain references (Implements #N) only cross-link, they don't close it. -->
