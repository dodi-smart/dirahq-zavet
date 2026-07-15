#!/bin/sh
# PreToolUse guard for Bash: commits touching guarded paths must reference
# the guarding decision with a `Refs: D-NNNN` or `Supersedes: D-NNNN` trailer.
#
# Only `git commit` commands are inspected; everything else passes untouched.
# Fail-open on any unexpected condition.
set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# Only a real `git commit` invocation counts: "commit" must appear as a
# standalone whitespace-delimited token in a `git …` command segment, which
# admits global flags (`git -C . commit`) while `git log --grep=commit`
# and `git log commits.txt` pass untouched.
printf '%s\n' "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]([^;&|]*[[:space:]])?commit([[:space:]]|$)' || exit 0

[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=.
root=$(cd -- "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0
[ -d "$root/.zavet" ] || exit 0

staged=$(cd -- "$root" && git diff --cached --name-only 2>/dev/null)
[ -n "$staged" ] || exit 0

# Newline-safe over staged paths (ids themselves never contain spaces).
guarded=$(printf '%s\n' "$staged" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    (cd -- "$root" && "$ZAVET" match "$f") 2>/dev/null
done | sort -u | tr '\n' ' ')
guarded=$(printf '%s' "$guarded" | sed 's/[[:space:]]*$//')
[ -n "$guarded" ] || exit 0

# The agent commits with -m/heredoc, so the trailer is visible in the command
# string. Amends/editor commits without an inline message are conservatively
# treated as unreferenced.
if printf '%s' "$cmd" | grep -qE '(Refs|Supersedes):[[:space:]]*D-[0-9]+'; then
    for id in $guarded; do
        (cd -- "$root" && "$ZAVET" emit guard_complied "$id" "") 2>/dev/null || true
    done
    if printf '%s' "$cmd" | grep -qE 'Supersedes:[[:space:]]*D-[0-9]+'; then
        sup=$(printf '%s' "$cmd" | grep -oE 'Supersedes:[[:space:]]*D-[0-9]+' | head -1 | grep -oE 'D-[0-9]+')
        [ -n "$sup" ] && (cd -- "$root" && "$ZAVET" emit decision_superseded "$sup" "") 2>/dev/null || true
    fi
    exit 0
fi

for id in $guarded; do
    (cd -- "$root" && "$ZAVET" emit guard_blocked "$id" "") 2>/dev/null || true
done

reason=$(printf 'Staged changes touch paths guarded by: %s. Reference the decision in the commit message with a trailer — `Refs: %s` if the change complies with it, or `Supersedes: %s` (after recording the replacement decision via /zavet:decide) if it intentionally replaces it. Then retry the commit.' \
    "$guarded" "$(printf '%s' "$guarded" | awk '{print $1}')" "$(printf '%s' "$guarded" | awk '{print $1}')")

jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
    }
}'
exit 0
