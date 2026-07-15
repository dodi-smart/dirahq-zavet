#!/bin/sh
# SessionStart: inject the repo's standing rules and decision index so the
# agent starts every session knowing what has been decided.
#
# stdout on exit 0 becomes session context. Silent no-op outside zavet repos.
set -u

command -v git >/dev/null 2>&1 || exit 0

ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$root/.zavet" ] || exit 0

printf '## Zavet knowledge layer (this repo records decisions in .zavet/)\n\n'

if [ -f "$root/.zavet/RULES.md" ]; then
    printf '### Standing rules\n\n'
    cat -- "$root/.zavet/RULES.md"
    printf '\n'
fi

decisions=$(cd -- "$root" && "$ZAVET" list 2>/dev/null)
if [ -n "$decisions" ]; then
    printf '### Recorded decisions (read the file before changing guarded code; ask /zavet:why)\n\n'
    printf '%s\n' "$decisions" | sort | awk -F '\t' '{
        line = "- " $1
        if ($3 != "") line = line " — " $3
        line = line " (" $2 ")"
        print line
    }'
fi

printf '\nCapture bar: record non-obvious choices a future reader could not reconstruct — micro-decisions as commit trailers (Why:/Rejected:/Constraint:/Refs:), structural ones via /zavet:decide.\n'
exit 0
