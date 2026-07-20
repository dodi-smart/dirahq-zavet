#!/bin/sh
# Bump the "version" key in .claude-plugin/plugin.json in place.
#
# This is a targeted single-line replace, not a JSON parse/stringify
# round-trip — a round-trip would reflow the entire manifest (key order,
# whitespace) on every release. It must survive both BSD sed (macOS CI leg)
# and GNU sed (Linux CI leg): rather than relying on `sed -i`, whose
# in-place/backup-suffix syntax differs between the two, this writes to a
# temp file and moves it into place.
#
# Idempotent: running with the current version is a no-op (exit 0).
# Fails if the "version" key is absent, or if the edit would touch more
# than one line of the file.
set -eu

usage() {
  echo "usage: $0 <version>" >&2
  exit 1
}

[ "$#" -eq 1 ] || usage
version="$1"

manifest=".claude-plugin/plugin.json"

if [ ! -f "$manifest" ]; then
  echo "set-version: $manifest not found" >&2
  exit 1
fi

if ! grep -q '"version"[[:space:]]*:' "$manifest"; then
  echo "set-version: no \"version\" key found in $manifest" >&2
  exit 1
fi

tmp="${manifest}.tmp.$$"
trap 'rm -f "$tmp"' EXIT INT TERM

sed -E 's/^([[:space:]]*"version"[[:space:]]*:[[:space:]]*")[^"]*(",?)[[:space:]]*$/\1'"$version"'\2/' \
  "$manifest" >"$tmp"

set +e
diff_out=$(diff "$manifest" "$tmp")
diff_status=$?
set -e

if [ "$diff_status" -eq 0 ]; then
  # Already at the requested version — nothing to do.
  exit 0
elif [ "$diff_status" -ne 1 ]; then
  echo "set-version: diff failed comparing $manifest to the rewritten copy" >&2
  exit 1
fi

removed=$(printf '%s\n' "$diff_out" | grep -c '^<')
added=$(printf '%s\n' "$diff_out" | grep -c '^>')

if [ "$removed" -ne 1 ] || [ "$added" -ne 1 ]; then
  echo "set-version: expected exactly one changed line, got $removed removed / $added added" >&2
  exit 1
fi

mv "$tmp" "$manifest"
