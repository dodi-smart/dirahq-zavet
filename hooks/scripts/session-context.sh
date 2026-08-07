#!/bin/sh
# SessionStart: inject the repo's standing rules and decision index so the
# agent starts every session knowing what has been decided.
#
# stdout on exit 0 becomes session context. Silent no-op outside zavet repos.
#
# Claude Code is the only harness that can do this — Grok Build fires the event
# but discards the hook's stdout, and nothing else has the event at all. Those
# harnesses read the same payload from a generated file instead (see
# `zavet rules` / `zavet agents-md`), which is why the payload itself lives in
# bin/zavet rather than here: one builder, so what this injects and what those
# files contain cannot drift.
#
# The plugin resolves ${CLAUDE_PLUGIN_ROOT} FIRST, unlike everything else that
# calls zavet. Plugin and script ship together so their versions match by
# construction; a repo's vendored copy may be older or newer than the plugin
# driving this session.
set -u

command -v git >/dev/null 2>&1 || exit 0

# shellcheck disable=SC1007
ZAVET="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}/bin/zavet"
[ -x "$ZAVET" ] || exit 0

"$ZAVET" context 2>/dev/null || exit 0
exit 0
