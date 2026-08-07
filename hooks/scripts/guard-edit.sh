#!/bin/sh
# PreToolUse guard for Edit/Write tools: teach-before-change.
#
# The first time in a session that the agent touches a path guarded by an
# active decision, the edit is denied and the decision record is returned as
# the reason — the agent reads it and retries informed. Subsequent edits to
# paths guarded by the same decision pass silently (show-once-per-session).
#
# The logic lives in `zavet hook guard-edit`, not here. Claude Code is not the
# only harness with a blocking pre-tool hook — Grok Build and Cursor have one
# too, and each wants a different deny envelope and spells the stdin fields
# differently. Keeping the implementation in bin/zavet means the single file
# `zavet adapters` vendors into a repo is the whole guard, so a harness with no
# plugin system still gets it.
#
# Fail-open everywhere: this hook must never break an agent loop over a missing
# tool, an unreadable file, or a repo without .zavet/.
set -u

# shellcheck disable=SC1007
ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

"$ZAVET" hook guard-edit --flavor claude 2>/dev/null || exit 0
exit 0
