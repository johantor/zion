## Summary

<!-- What changed and why. Focus on the "why" — the diff shows the "what". -->

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

<!-- What you ran to verify this, per AGENTS.md "Validating changes". -->

- [ ] `shellcheck plugins/*/hooks/*.sh scripts/*.sh`
- [ ] `bash scripts/validate-plugin.sh`
- [ ] Manually exercised the affected agent/command/skill flow

## Related issues

<!-- Use a closing keyword (Closes/Fixes/Resolves #N) so the issue auto-closes on merge.
Plain references (Implements #N) only cross-link, they don't close it. -->
