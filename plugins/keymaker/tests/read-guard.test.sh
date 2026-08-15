#!/usr/bin/env bash
# Behavioral tests for keymaker's hooks/read-guard.sh (context-hygiene guard;
# fails OPEN). The hook is byte-identical to crew's copy, so this suite is not
# re-testing the logic — it proves keymaker's *shipped* copy, with its own
# vendored hooks/lib/guard-lib.sh behind it, enforces the same limits when the
# plugin is installed on its own.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="read-guard.sh"

work="$(new_tmpdir)"
big="$work/big.txt"
small="$work/small.txt"
# The guard only inspects byte size, so the content is irrelevant.
printf '%*s' 70000 '' > "$big"      # > 64 KiB
printf '%*s' 1000  '' > "$small"    # <= 64 KiB

assert_block "raw read of a >64 KiB file" "$HOOK" "$(payload_read "$big")" "Don't read it raw"
assert_allow "raw read of a small file"   "$HOOK" "$(payload_read "$small")"

# A bounded read (explicit limit <= 2000 lines) passes regardless of size; a
# limit above the cap falls through to the size check and is blocked.
assert_allow "big file with a bounded limit (<= 2000)" "$HOOK" "$(payload_read "$big" 500)"
assert_block "big file with an over-cap limit"         "$HOOK" "$(payload_read "$big" 5000)" "Don't read it raw"

# Fail open on missing inputs.
assert_allow "nonexistent path"        "$HOOK" "$(payload_read "$work/does-not-exist.txt")"
assert_allow "missing file_path field" "$HOOK" '{"tool_input": {}}'
assert_allow "non-JSON payload fails open" "$HOOK" 'this is not json'

finish
