#!/bin/sh
# PreToolUse gate for Bash `git commit` — one hook, one parse, two checks:
#
#  - Guard WALL: commits touching guarded paths must reference the guarding
#    decision with a `Refs: D-NNNN` or `Supersedes: D-NNNN` trailer.
#  - Spec NUDGE (once per spec per session): staged work covered by a living
#    spec should keep it current — stage the updated .zavet/specs/<slug>.md
#    or carry a `Spec: <slug>` trailer. Blocks once with instructions, then
#    passes on retry regardless. The transparent document flow rides on it.
#
# Both checks share the stdin parse, the commit matcher, and the staged-file
# listing, and a commit failing both gets ONE combined deny (one retry, not
# two). Only `git commit` commands are inspected; everything else passes with
# a single jq + grep. Fail-open on any unexpected condition.
set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# shellcheck disable=SC1007
ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# The cheap gate first — the overwhelming majority of Bash calls exit here.
# Only a real `git commit` invocation counts: "commit" must appear as a
# standalone whitespace-delimited token in a `git …` command segment, which
# admits global flags (`git -C . commit`) while `git log --grep=commit`
# and `git log commits.txt` pass untouched.
printf '%s\n' "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]([^;&|]*[[:space:]])?commit([[:space:]]|$)' || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=.
# zavet root already fails unless the toplevel carries .zavet/.
root=$(cd -- "$cwd" 2>/dev/null && "$ZAVET" root 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0

# One staged listing (newline-safe, spaces included) feeds both checks.
staged=$(cd -- "$root" 2>/dev/null && git diff --cached --name-only 2>/dev/null)
[ -n "$staged" ] || exit 0

nl='
'
reasons=""

# --- Guard wall -------------------------------------------------------------
guarded=$(printf '%s\n' "$staged" | (cd -- "$root" && "$ZAVET" match-batch 2>/dev/null) | tr '\n' ' ')
guarded=${guarded% }
if [ -n "$guarded" ]; then
    # The agent commits with -m/heredoc, so the trailer is visible in the
    # command string. Amends/editor commits without an inline message are
    # conservatively treated as unreferenced.
    if printf '%s' "$cmd" | grep -qE '(Refs|Supersedes):[[:space:]]*D-[0-9]+'; then
        for id in $guarded; do
            (cd -- "$root" && "$ZAVET" emit guard_complied "$id" "") 2>/dev/null || true
        done
        if printf '%s' "$cmd" | grep -qE 'Supersedes:[[:space:]]*D-[0-9]+'; then
            sup=$(printf '%s' "$cmd" | grep -oE 'Supersedes:[[:space:]]*D-[0-9]+' | head -1 | grep -oE 'D-[0-9]+')
            [ -n "$sup" ] && (cd -- "$root" && "$ZAVET" emit decision_superseded "$sup" "") 2>/dev/null || true
        fi
    else
        for id in $guarded; do
            (cd -- "$root" && "$ZAVET" emit guard_blocked "$id" "") 2>/dev/null || true
        done
        first=${guarded%% *}
        # shellcheck disable=SC2016
        reasons=$(printf 'Staged changes touch paths guarded by: %s. Reference the decision in the commit message with a trailer — `Refs: %s` if the change complies with it, or `Supersedes: %s` (after recording the replacement decision via /zavet:decide) if it intentionally replaces it.' \
            "$guarded" "$first" "$first")
    fi
fi

# --- Spec nudge -------------------------------------------------------------
# Satisfied when the commit carries a Spec: trailer, when every covering spec
# file is itself staged, or when the spec was already nudged this session.
# Only the inline command text is scanned — `git commit -F file` with a real
# trailer still gets one nudge; acceptable for show-once.
covering=$(printf '%s\n' "$staged" | (cd -- "$root" && "$ZAVET" spec-match 2>/dev/null))
if [ -n "$covering" ] && ! printf '%s' "$cmd" | grep -qE 'Spec:[[:space:]]*[a-z0-9][a-z0-9-]*'; then
    session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)
    # The session id names a temp file — keep it to a safe charset.
    session=$(printf '%s' "$session" | sed 's/[^A-Za-z0-9_-]/_/g')
    state="${TMPDIR:-/tmp}/zavet-spec-shown-${session}"
    fresh=""
    for slug in $covering; do
        printf '%s\n' "$staged" | grep -qxF ".zavet/specs/$slug.md" && continue
        grep -qx "$slug" "$state" 2>/dev/null && continue
        fresh="$fresh $slug"
        printf '%s\n' "$slug" >>"$state" 2>/dev/null || true
    done
    fresh=${fresh# }
    if [ -n "$fresh" ]; then
        firstspec=${fresh%% *}
        # shellcheck disable=SC2016
        nudge=$(printf 'Staged changes touch paths covered by spec(s): %s (see .zavet/specs/). Keep the living spec current: update the sections your change affects (and its decisions/date), stage the spec file with this commit, and add a `Spec: %s` trailer. If the spec truly needs no update, just add the trailer. This reminder fires once per session.' \
            "$fresh" "$firstspec")
        if [ -n "$reasons" ]; then
            reasons="${reasons}${nl}${nl}${nudge}"
        else
            reasons=$nudge
        fi
    fi
fi

[ -n "$reasons" ] || exit 0
reasons="${reasons}${nl}${nl}Then retry the commit."
"$ZAVET" deny "$reasons"
exit 0
