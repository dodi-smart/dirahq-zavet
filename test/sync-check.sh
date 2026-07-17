#!/bin/sh
# Verify the vendored dialect fixtures match their MANIFEST (git blob oids).
# The canonical copy lives in dirahq-cli (cli/core/testdata/zavet-dialect);
# CI additionally diffs this MANIFEST against the canonical one.
#
# Usage: sh test/sync-check.sh            # verify
#        sh test/sync-check.sh --write    # regenerate MANIFEST
set -u

dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures/dialect" && pwd) || exit 1
cd -- "$dir" || exit 1

manifest_body() {
    # Every fixture file except MANIFEST itself, sorted, dotfiles included.
    find . \( -name MANIFEST -o -name '.DS_Store' \) -prune -o -type f -print |
        sed 's|^\./||' | LC_ALL=C sort |
        while IFS= read -r f; do
            printf '%s  %s\n' "$(git hash-object -- "$f")" "$f"
        done
}

if [ "${1:-}" = "--write" ]; then
    manifest_body >MANIFEST
    printf 'sync-check: MANIFEST written (%s entries)\n' "$(grep -c . MANIFEST)"
    exit 0
fi

actual=$(manifest_body)
expected=$(cat MANIFEST 2>/dev/null)
if [ "$actual" = "$expected" ]; then
    printf 'sync-check: fixtures match MANIFEST\n'
    exit 0
fi
printf 'sync-check: fixtures diverge from MANIFEST:\n' >&2
printf '%s\n' "$expected" >"${TMPDIR:-/tmp}/zavet-manifest-expected.$$"
printf '%s\n' "$actual" | diff -u "${TMPDIR:-/tmp}/zavet-manifest-expected.$$" - >&2
rm -f "${TMPDIR:-/tmp}/zavet-manifest-expected.$$"
exit 1
