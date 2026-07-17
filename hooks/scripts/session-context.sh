#!/bin/sh
# SessionStart: inject the repo's standing rules and decision index so the
# agent starts every session knowing what has been decided.
#
# stdout on exit 0 becomes session context. Silent no-op outside zavet repos.
set -u

command -v git >/dev/null 2>&1 || exit 0

# shellcheck disable=SC1007
ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

# zavet root already fails unless the toplevel carries .zavet/.
root=$("$ZAVET" root 2>/dev/null) || exit 0

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

specs=$(cd -- "$root" && "$ZAVET" specs 2>/dev/null)
if [ -n "$specs" ]; then
    printf '\n### Living specs (.zavet/specs/ — keep current while you work)\n\n'
    printf '%s\n' "$specs" | sort | awk -F '\t' '{
        line = "- " $1
        if ($5 != "") line = line " — " $5
        print line " (" $2 ", " $3 ")"
    }'
fi

printf '\nCapture bar: record non-obvious choices a future reader could not reconstruct — micro-decisions as commit trailers (Why:/Rejected:/Constraint:/Refs:), structural ones via /zavet:decide.\n'
# shellcheck disable=SC2016
printf 'Spec maintenance (do this as part of normal work, no command needed): when implementing or changing a feature, update its covering spec in .zavet/specs/ — or create one from .zavet/.spec-template.md (origin: session) for substantial new features — reference the decisions involved, and add a `Spec: <slug>` trailer to the commit.\n'
exit 0
