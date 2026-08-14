#!/bin/sh
# Generate the portable Agent Skills under .agents/skills/ from the Claude Code
# plugin's own commands/ and skills/.
#
# WHY GENERATE RATHER THAN WRITE BOTH
#
# Agent Skills is an open standard (agentskills.io) that Codex, Cursor, Grok
# Build, Gemini CLI, OpenCode, Copilot, Amp, Factory and ~70 other harnesses
# implement, with `.agents/skills/` as the shared project path. So zavet's
# workflows are already portable in substance — what is not portable is the
# Claude-specific packaging around them: `${CLAUDE_PLUGIN_ROOT}`, which exists
# only inside Claude Code; `argument-hint`, which Claude Code rejects as a
# SKILL.md key; and `/zavet:x` command names, which only exist for a plugin.
#
# Two hand-maintained copies of eight documents would diverge inside a month,
# and the divergence would be invisible: both files look fine, they just teach
# different things. So commands/*.md stay canonical — they are the reviewed
# prose — and this script derives the portable form mechanically. CI runs it
# with --check, so a commit that edits a command without regenerating fails.
#
# WHY .agents/skills/ AND NOT .claude/skills/
#
# Distribution is `npx skills add dodi-smart/dirahq-zavet`, which already solves
# multi-agent detection, symlink-vs-copy for Windows, project-vs-global scope
# and updates. It reads `.claude-plugin/marketplace.json`'s "skills" array to
# find these at their declared depth. Claude Code itself does not read
# `.agents/skills/` — it does not need to, because the plugin already provides
# these same workflows as /zavet:* commands.
#
# Usage: sh scripts/gen-adapters.sh            # write
#        sh scripts/gen-adapters.sh --check    # report drift, write nothing

# SC2016 (expressions don't expand in single quotes) is disabled file-wide
# rather than per line: this script's entire output is markdown prose full of
# backticked commands, plus a deliberately literal `$ARGUMENTS` and
# `${CLAUDE_PLUGIN_ROOT}` in the sed patterns. Every hit is intentional, and
# there is no case here where expansion would be the right answer.
# SC2329 and SC2317 both fire because the renderers are dispatched indirectly
# through `emit` ("$_fn" "$@"), which shellcheck cannot follow: it concludes the
# functions are never called and therefore that their bodies are unreachable.
# Newer shellcheck reports SC2317 where 0.11.0 reported only SC2329, so both are
# listed — the CI runner tracks a newer release than most local installs.
# shellcheck disable=SC2016,SC2329,SC2317
set -u

# shellcheck disable=SC1007
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
cd -- "$ROOT" || exit 1

OUT=".agents/skills"
BIN_REL=".zavet/bin/zavet"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# The workflows, in the order they appear in the README's command table.
COMMANDS="init decide why wiki backfill spec audit verify"

stale=0
wrote=0

# One frontmatter line, verbatim, so whatever quoting the source chose is
# preserved rather than re-derived (descriptions contain quotes and em dashes).
fm_line() { # $1 = file, $2 = key
    awk -v k="$2" '
        NR == 1 && /^---/ { inside = 1; next }
        inside && /^---/ { exit }
        inside && index($0, k ":") == 1 { print; exit }
    ' "$1"
}

# The value half of a frontmatter line, unquoted.
fm_value() { # $1 = file, $2 = key
    fm_line "$1" "$2" | sed -e "s/^$2:[[:space:]]*//" -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# Everything after the closing frontmatter fence, minus a leading HTML comment.
#
# A source file may open with a note to whoever maintains it ("this is the
# canonical copy, regenerate after editing"). That note is addressed to a
# contributor holding the plugin repo, and publishing it into a skill installed
# in someone else's project tells them to run a script they do not have.
fm_body() { # $1 = file
    awk 'NR == 1 && /^---/ { inside = 1; next }
         inside && /^---/ { inside = 0; body = 1; next }
         body { print }' "$1" |
        awk '
            !started && NF == 0 { next }
            !started && /^<!--/ { skipping = 1; started = 1 }
            skipping { if (/-->/) { skipping = 0; blanks = 1 } next }
            blanks && NF == 0 { next }
            { blanks = 0; started = 1; print }
        '
}

# The path and command-name rewrites, applied to a body on stdin.
#
# `${CLAUDE_PLUGIN_ROOT}/templates/*` maps to the copies `zavet init` already
# places in `.zavet/` — the plugin's templates directory does not exist in a
# repo that never installed the plugin, but its scaffolded copies always do.
portable_body() {
    sed \
        -e "s|\${CLAUDE_PLUGIN_ROOT}/bin/zavet|$BIN_REL|g" \
        -e 's|\${CLAUDE_PLUGIN_ROOT}/templates/decision\.md|.zavet/.template.md|g' \
        -e 's|\${CLAUDE_PLUGIN_ROOT}/templates/spec\.md|.zavet/.spec-template.md|g' \
        -e 's|/zavet:\([a-z][a-z-]*\)|zavet-\1|g'
}

# Shared preamble. Every generated skill says where it came from (so nobody
# hand-edits it) and how to reach the CLI (so a repo that installed zavet
# globally instead of vendoring it is not stuck).
preamble() { # $1 = source path
    printf '<!-- GENERATED from %s by scripts/gen-adapters.sh — do not edit. -->\n\n' "$1"
    printf 'Commands below use this repo'\''s vendored CLI at `%s`, written by\n' "$BIN_REL"
    printf '`zavet adapters`. If zavet is on your PATH instead, use plain `zavet`.\n\n'
}

render_command_skill() { # $1 = slug
    _src="commands/$1.md"
    _hint=$(fm_value "$_src" argument-hint)
    printf -- '---\n'
    printf 'name: zavet-%s\n' "$1"
    fm_line "$_src" description
    # Pre-approving the CLI and the read tools is what keeps a workflow from
    # stopping to ask permission for `zavet next-id` mid-flow. Nothing here can
    # write: the skill body tells the agent what to change, and that edit goes
    # through the harness's normal permission path.
    printf 'allowed-tools: Bash(%s:*) Read Grep Glob\n' "$BIN_REL"
    printf 'metadata:\n'
    printf '  source: "%s"\n' "$_src"
    printf '  generated: "true"\n'
    printf -- '---\n\n'
    preamble "$_src"
    # `argument-hint` is not a legal SKILL.md key (Claude Code rejects unknown
    # frontmatter outright, and the open spec does not define it), but the shape
    # it documents is real information the body assumes. Keep it as prose.
    if [ -n "$_hint" ]; then
        printf 'Arguments: `%s` — available as $ARGUMENTS.\n\n' "$_hint"
    fi
    fm_body "$_src" | portable_body
}

render_ambient_skill() {
    _src="skills/zavet/SKILL.md"
    printf -- '---\n'
    printf 'name: zavet\n'
    fm_line "$_src" description
    printf 'allowed-tools: Bash(%s:*) Read Grep Glob\n' "$BIN_REL"
    printf 'metadata:\n'
    printf '  source: "%s"\n' "$_src"
    printf '  generated: "true"\n'
    printf -- '---\n\n'
    preamble "$_src"
    fm_body "$_src" | portable_body
    # The one real behavioral difference off Claude Code and Grok Build: nothing
    # denies the edit, so the agent has to check for itself. Saying this in the
    # ambient skill rather than only in AGENTS.md matters because the skill is
    # what a globally-installed copy carries into a repo that has no AGENTS.md.
    printf '\n## Guards may not be enforced by your harness\n\n'
    printf 'Claude Code and Grok Build deny a guarded edit and show you the record. Every\n'
    printf 'other harness does not, so the check is yours to make: run `%s match\n' "$BIN_REL"
    printf '<path>` before you edit, and read every record it names. A commit still gets\n'
    printf 'caught by the `commit-msg` hook and by `zavet check` in CI — but by then you\n'
    printf 'have already written code against a decision you never read.\n'
}

emit() { # $1 = skill dir name, $2 = renderer, $3... = renderer args
    _name=$1
    _fn=$2
    shift 2
    _dst="$OUT/$_name/SKILL.md"
    _tmp="${TMPDIR:-/tmp}/zavet-gen-$_name.$$"
    "$_fn" "$@" >"$_tmp" || {
        printf 'gen-adapters: failed to render %s\n' "$_dst" >&2
        rm -f "$_tmp"
        exit 1
    }
    if [ "$CHECK" -eq 1 ]; then
        if ! diff -u "$_dst" "$_tmp" >/dev/null 2>&1; then
            printf 'gen-adapters: %s is missing or stale\n' "$_dst" >&2
            diff -u "$_dst" "$_tmp" 2>/dev/null | head -20 >&2
            stale=1
        fi
        rm -f "$_tmp"
        return 0
    fi
    mkdir -p "$OUT/$_name" || exit 1
    if [ -f "$_dst" ] && cmp -s "$_dst" "$_tmp"; then
        rm -f "$_tmp"
        return 0
    fi
    mv "$_tmp" "$_dst" || exit 1
    printf 'gen-adapters: wrote %s\n' "$_dst"
    wrote=1
}

# Fail loudly before any generation starts, rather than trusting emit() to
# catch it: render_command_skill's/render_ambient_skill's last step is a
# pipeline like `fm_body "$_src" | portable_body`, and a pipeline's exit
# status is the LAST command's (portable_body/sed), not fm_body's — so if
# `$_src` is missing or unreadable, awk's "can't open file" on stderr is
# swallowed, sed still exits 0 on empty input, and emit() would happily write
# an empty, spec-invalid SKILL.md and report success. Checking readability of
# every source up front turns that into one clear, early failure instead.
for slug in $COMMANDS; do
    src="commands/$slug.md"
    [ -r "$src" ] || {
        printf 'gen-adapters: missing or unreadable source: %s\n' "$src" >&2
        exit 1
    }
done
[ -r "skills/zavet/SKILL.md" ] || {
    printf 'gen-adapters: missing or unreadable source: skills/zavet/SKILL.md\n' >&2
    exit 1
}

emit zavet render_ambient_skill
for slug in $COMMANDS; do
    emit "zavet-$slug" render_command_skill "$slug"
done

# A skill left behind by a command that was renamed or removed would keep being
# published by `npx skills` forever, so anything generated that no source still
# claims is reported (and removed on a write run).
for d in "$OUT"/*/; do
    [ -d "$d" ] || continue
    name=$(basename -- "$d")
    keep=0
    [ "$name" = "zavet" ] && keep=1
    for slug in $COMMANDS; do
        [ "$name" = "zavet-$slug" ] && keep=1
    done
    [ "$keep" -eq 1 ] && continue
    if [ "$CHECK" -eq 1 ]; then
        printf 'gen-adapters: %s is orphaned — no command or skill generates it\n' "$d" >&2
        stale=1
    else
        rm -rf "$d"
        printf 'gen-adapters: removed orphaned %s\n' "$d"
        wrote=1
    fi
done

if [ "$CHECK" -eq 1 ]; then
    [ "$stale" -eq 0 ] || {
        printf 'gen-adapters: run "sh scripts/gen-adapters.sh" and commit the result\n' >&2
        exit 1
    }
    printf 'gen-adapters: %s up to date\n' "$OUT"
    exit 0
fi
[ "$wrote" -eq 1 ] || printf 'gen-adapters: %s already up to date\n' "$OUT"
exit 0
