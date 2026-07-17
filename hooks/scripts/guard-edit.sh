#!/bin/sh
# PreToolUse guard for Edit/Write tools: teach-before-change.
#
# The first time in a session that the agent touches a path guarded by an
# active decision, the edit is denied and the decision record is returned as
# the reason — the agent reads it and retries informed. Subsequent edits to
# paths guarded by the same decision pass silently (show-once-per-session).
#
# Fail-open everywhere: this hook must never break an agent loop over a
# missing tool, an unreadable file, or a repo without .zavet/.
set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# shellcheck disable=SC1007
ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

input=$(cat) || exit 0
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)
# The session id names a temp file — keep it to a safe charset.
session=$(printf '%s' "$session" | sed 's/[^A-Za-z0-9_-]/_/g')
[ -n "$file" ] || exit 0

# Resolve the file to a physical path (macOS /tmp -> /private/tmp etc.) by
# walking up to its nearest existing ancestor; git reports physical toplevels.
p=$file
suffix=""
while [ ! -d "$p" ]; do
    parent=$(dirname -- "$p")
    [ "$parent" = "$p" ] && exit 0
    suffix="/$(basename -- "$p")$suffix"
    p=$parent
done
phys=$(cd -- "$p" 2>/dev/null && pwd -P) || exit 0
file="$phys$suffix"

root=$(cd -- "$phys" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0
[ -d "$root/.zavet" ] || exit 0

case "$file" in
    "$root"/*) rel=${file#"$root"/} ;;
    *) exit 0 ;;
esac

matches=$(cd -- "$root" && "$ZAVET" match "$rel" 2>/dev/null)
[ -n "$matches" ] || exit 0

state="${TMPDIR:-/tmp}/zavet-shown-${session}"
fresh=""
for id in $matches; do
    if ! grep -qx "$id" "$state" 2>/dev/null; then
        fresh="$fresh $id"
    fi
done
# Everything relevant was already shown this session: allow silently.
[ -n "${fresh# }" ] || exit 0

reason=""
for id in $fresh; do
    printf '%s\n' "$id" >>"$state" 2>/dev/null || true
    (cd -- "$root" && "$ZAVET" emit guard_shown "$id" "$rel") 2>/dev/null || true
    path=$(cd -- "$root" && "$ZAVET" decision-path "$id" 2>/dev/null) || continue
    body=$(cat -- "$root/$path" 2>/dev/null) || continue
    reason=$(printf '%s\n\n=== %s guards %s (%s) ===\n%s' "$reason" "$id" "$rel" "$path" "$body")
done

reason=$(printf 'This path is guarded by recorded decision(s) you have not seen this session. Read them, honor their constraints (or supersede them via /zavet:decide), then retry the edit — it will be allowed.\n%s' "$reason")

"$ZAVET" deny "$reason"
exit 0
