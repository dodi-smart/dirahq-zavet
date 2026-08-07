#!/bin/sh
# PreToolUse gate for Bash `git commit` — one hook, one parse, two checks:
#
#  - Guard WALL: commits touching guarded paths must reference the guarding
#    decision with a `Refs: <ID>` or `Supersedes: <ID>` trailer, where <ID>
#    carries any prefix this repo mints or has retired (see `zavet prefixes`).
#  - Spec NUDGE (once per spec per session): staged work covered by a living
#    spec should keep it current — stage the updated .zavet/specs/<slug>.md
#    or carry a `Spec: <slug>` trailer. Blocks once with instructions, then
#    passes on retry regardless. The transparent document flow rides on it.
#
# Both live in `zavet gate`, which is also what the commit-msg git hook and
# `zavet check` call. That is the point: a repo must not enforce one rule in the
# agent loop and a different one at `git commit`, and it must not depend on
# which harness the developer happens to be running.
#
# Only `git commit` commands are inspected; everything else passes. Fail-open on
# any unexpected condition.
set -u

# shellcheck disable=SC1007
ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

"$ZAVET" hook guard-commit --flavor claude 2>/dev/null || exit 0
exit 0
