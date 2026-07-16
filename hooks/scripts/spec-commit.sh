#!/bin/sh
# PreToolUse nudge for Bash: commits touching paths covered by a spec should
# keep that spec current — stage the updated .zavet/specs/<slug>.md or carry a
# `Spec: <slug>` trailer acknowledging the spec was considered.
#
# Unlike the decision guard this is a NUDGE, not a wall: it blocks once per
# spec per session with instructions, then passes on retry regardless. The
# transparent document flow rides on it — the agent updates the spec and adds
# the trailer as part of the normal commit loop.
#
# Fail-open on any unexpected condition.
set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)
# The session id names a temp file — keep it to a safe charset.
session=$(printf '%s' "$session" | sed 's/[^A-Za-z0-9_-]/_/g')
[ -n "$cmd" ] || exit 0

# Same standalone-token matcher as guard-commit.sh: only a real `git commit`
# counts; `git log --grep=commit` and friends pass untouched.
printf '%s\n' "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]([^;&|]*[[:space:]])?commit([[:space:]]|$)' || exit 0

[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=.
root=$(cd -- "$cwd" 2>/dev/null && "$ZAVET" root 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0

staged=$(cd -- "$root" 2>/dev/null && git diff --cached --name-only 2>/dev/null)
[ -n "$staged" ] || exit 0

# Which specs cover the staged work?
covering=$(printf '%s\n' "$staged" | (cd -- "$root" && "$ZAVET" spec-match 2>/dev/null))
[ -n "$covering" ] || exit 0

# Satisfied when the commit already carries a Spec: trailer, or when every
# covering spec file is itself part of the commit. Only the inline command
# text is scanned — `git commit -F file` / `--amend --no-edit` with a real
# trailer still gets one nudge; acceptable for show-once.
if printf '%s' "$cmd" | grep -qE 'Spec:[[:space:]]*[a-z0-9][a-z0-9-]*'; then
    exit 0
fi
unstale=""
for slug in $covering; do
    if ! printf '%s\n' "$staged" | grep -qxF ".zavet/specs/$slug.md"; then
        unstale="$unstale $slug"
    fi
done
unstale=${unstale# }
[ -n "$unstale" ] || exit 0

# Show-once per spec per session: the nudge fires the first time only.
state="${TMPDIR:-/tmp}/zavet-spec-shown-${session}"
fresh=""
for slug in $unstale; do
    if ! grep -qx "$slug" "$state" 2>/dev/null; then
        fresh="$fresh $slug"
        printf '%s\n' "$slug" >>"$state" 2>/dev/null || true
    fi
done
fresh=${fresh# }
[ -n "$fresh" ] || exit 0

first=${fresh%% *}
reason=$(printf 'Staged changes touch paths covered by spec(s): %s (see .zavet/specs/). Keep the living spec current: update the sections your change affects (and its decisions/date), stage the spec file with this commit, and add a `Spec: %s` trailer. If the spec truly needs no update, just add the trailer. Then retry the commit — this reminder fires once per session.' \
    "$fresh" "$first")

"$ZAVET" deny "$reason"
exit 0
