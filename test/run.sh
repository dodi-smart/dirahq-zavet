#!/bin/sh
# zavet test runner — POSIX sh + BSD awk + git, nothing else.
#
#   sh test/run.sh
#
# Twelve suites, all through the public `bin/zavet` interface:
#   dialect  — fixture corpus vs the golden TSVs (the cross-parser contract
#              shared with dira-core; see fixtures/dialect/README.md)
#   matcher  — run_match glob semantics (** collapse, trailing /, dedup)
#   check    — the CI trailer floor over real commit ranges
#   audit    — staleness + guard-pressure sweeps over real history
#   version  — `zavet version`'s manifest lookup, independent of git or .zavet/
#   verify   — running recorded checks (the one command that executes repo
#              content), plus section extraction and the guard-injection budget
#   ids      — decision-id collisions: next-id across refs and history,
#              duplicate detection, and the refusal to resolve an ambiguous id
#   prefix   — `zavet prefix`/`init --prefix`: minting, retirement, sibling
#              collisions, and the renumber repair path duplicates print
#   hooks    — the guard-commit git hook, which fails open by design
#   adapters — the cross-harness layer: generated files vs their source,
#              per-harness deny envelopes, and the agent-loop-vs-commit wall
#   harness envelopes — per-harness deny envelope shapes: claude/grok/cursor
#              detection and formats
#   sdlc     — spec sources: the four framework adapters over fixtures/sdlc,
#              `specs --json`, accretion and the per-slug `Spec:` grammar,
#              config round-trip, and the read-only invariants
set -u

# shellcheck disable=SC1007
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
Z="$ROOT/bin/zavet"
FIX="$ROOT/test/fixtures/dialect"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zavet-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

fails=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1"
    fails=$((fails + 1))
}

assert_file() { # $1 label, $2 expected file, $3 actual file
    if diff -u -- "$2" "$3" >"$TMP/diff.out" 2>&1; then
        pass "$1"
    else
        fail "$1"
        cat "$TMP/diff.out"
    fi
}

assert_eq() { # $1 label, $2 expected, $3 actual
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1"
        printf '  expected: [%s]\n  actual:   [%s]\n' "$2" "$3"
    fi
}

new_repo() { # $1 dir
    rm -rf "$1"
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.email zavet-test@example.invalid
    git -C "$1" config user.name "zavet test"
    git -C "$1" config commit.gpgsign false
    mkdir -p "$1/.zavet/decisions" "$1/.zavet/specs"
}

# git in the CURRENT suite repo ($R) — one definition, every suite uses it.
gc() { git -C "$R" "$@"; }

# ---------------------------------------------------------------- dialect --
printf -- '-- dialect\n'
R="$TMP/dialect"
new_repo "$R"
# The corpus carries its own config — `prefix: ZAVET`, `prefix-aliases: D`.
# Both parsers read it, which is what lets ZAVET-0018 and the older D-*
# records resolve side by side.
cp "$FIX/config" "$R/.zavet/config"
cp "$FIX"/decisions/*.md "$R/.zavet/decisions/"
cp "$FIX"/specs/*.md "$R/.zavet/specs/"
cp "$FIX/specs/.hidden-template.md" "$R/.zavet/specs/"
(cd "$R" && sh "$Z" list) >"$TMP/a.dm" && assert_file "decisions-meta" "$FIX/expected/decisions-meta.tsv" "$TMP/a.dm"
(cd "$R" && sh "$Z" guards) >"$TMP/a.dg" && assert_file "decisions-guards" "$FIX/expected/decisions-guards.tsv" "$TMP/a.dg"
(cd "$R" && sh "$Z" specs) >"$TMP/a.sm" && assert_file "specs-meta" "$FIX/expected/specs-meta.tsv" "$TMP/a.sm"
(cd "$R" && sh "$Z" spec-paths) >"$TMP/a.sp" && assert_file "spec-paths" "$FIX/expected/spec-paths.tsv" "$TMP/a.sp"
(cd "$R" && sh "$Z" checks) >"$TMP/a.dc" && assert_file "decision-checks" "$FIX/expected/decision-checks.tsv" "$TMP/a.dc"
(cd "$R" && sh "$Z" spec-checks) >"$TMP/a.sc" && assert_file "spec-checks" "$FIX/expected/spec-checks.tsv" "$TMP/a.sc"
(cd "$R" && sh "$Z" spec-sources --list) >"$TMP/a.ss" && assert_file "spec-sources" "$FIX/expected/spec-sources.tsv" "$TMP/a.ss"
# No golden for errata: id canonicalization is a documented Rust-only extra,
# so the two sides deliberately disagree here (D-0015 carries `D-7`).
(cd "$R" && sh "$Z" errata) >"$TMP/a.er"
assert_eq "errata reports the pointer verbatim" "D-0015	D-7
D-0017	D-9999" "$(cat "$TMP/a.er")"

# ---------------------------------------------------------------- matcher --
printf -- '-- matcher\n'
R="$TMP/matcher"
new_repo "$R"
cat >"$R/.zavet/decisions/D-0001-globs.md" <<'EOF'
---
id: D-0001
title: Matcher fixture
status: active
guards:
  - src/**
  - docs/
  - "**/*.sql"
---
body
EOF
cat >"$R/.zavet/decisions/D-0002-second.md" <<'EOF'
---
id: D-0002
title: Second matcher fixture
status: active
guards: [src/deep/**]
---
body
EOF
cat >"$R/.zavet/specs/cover.md" <<'EOF'
---
title: Coverage fixture
origin: session
confidence: high
date: 2026-01-01
paths: [lib/**]
---
body
EOF
m() { (cd "$R" && sh "$Z" match-batch); }
assert_eq "star crosses directories" "D-0001" "$(printf 'src/a/b/c.rs\n' | m)"
assert_eq "trailing slash prefix-matches" "D-0001" "$(printf 'docs/x/y.md\n' | m)"
assert_eq "**/*.sql needs a slash" "D-0001" "$(printf 'migrations/0001_init.sql\n' | m)"
assert_eq "top-level .sql misses */*.sql" "" "$(printf 'top.sql\n' | m)"
assert_eq "no match stays silent" "" "$(printf 'other.txt\n' | m)"
assert_eq "ids print once, table order" "D-0001
D-0002" "$(printf 'src/deep/x.rs\nsrc/a.rs\ndocs/r.md\n' | m)"
assert_eq "single-path match form" "D-0001" "$(cd "$R" && sh "$Z" match src/one.rs)"
assert_eq "spec-match covers" "cover" "$(printf 'lib/l.rs\n' | (cd "$R" && sh "$Z" spec-match))"

# ------------------------------------------------------------------ check --
printf -- '-- check\n'
R="$TMP/check"
new_repo "$R"
cat >"$R/.zavet/decisions/D-0001-guard.md" <<'EOF'
---
id: D-0001
title: Guarded area
status: active
guards: [src/**]
---
body
EOF
cat >"$R/.zavet/specs/cap.md" <<'EOF'
---
title: Cap
origin: session
confidence: high
date: 2026-07-01
paths: [lib/**]
---
body
EOF
mkdir -p "$R/src/a" "$R/lib"
gc add -A
gc commit -qm "chore: scaffold"
base=$(gc rev-parse HEAD)
echo one >"$R/src/a/f.rs" && gc add -A && gc commit -qm "feat: guarded no trailer"
echo two >"$R/src/a/f.rs" && gc add -A && gc commit -qm "feat: guarded refs" -m "Refs: D-0001"
echo three >"$R/src/a/f.rs" && gc add -A && gc commit -qm "feat: guarded supersedes" -m "Supersedes: D-0001"
echo four >"$R/lib/l.rs" && gc add -A && gc commit -qm "feat: spec covered no trailer"
echo five >"$R/lib/l.rs" && gc add -A && gc commit -qm "feat: spec covered spec trailer" -m "Spec: cap"
echo six >"$R/lib/l.rs"
printf -- '---\ntitle: Cap\norigin: session\nconfidence: high\ndate: 2026-07-02\npaths: [lib/**]\n---\nbody2\n' >"$R/.zavet/specs/cap.md"
gc add -A && gc commit -qm "feat: spec covered, spec staged"
gc checkout -qb side "$base"
mkdir -p "$R/src/a"
echo m >"$R/src/a/g.rs" && gc add -A && gc commit -qm "feat: side guarded no trailer"
gc checkout -q -
gc merge -q --no-ff -m "merge side" side

out=$( (cd "$R" && sh "$Z" check "$base..HEAD" 2>"$TMP/check.err") )
rc=$?
assert_eq "check exit 1 on violations" "1" "$rc"
assert_eq "check rows (type+keys, sorted)" "violation	D-0001
violation	D-0001
warn-spec	cap" "$(printf '%s\n' "$out" | cut -f1,3 | sort)"
if grep -q "2 commit(s) touch guarded paths" "$TMP/check.err"; then
    pass "check summary on stderr"
else
    fail "check summary on stderr"
fi

out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) )
assert_eq "check empty range passes" "0:" "$?:$out"

R2="$TMP/nozavet"
rm -rf "$R2" && mkdir -p "$R2" && git -C "$R2" init -q
out=$( (cd "$R2" && sh "$Z" check HEAD~1..HEAD 2>/dev/null) )
assert_eq "check without .zavet passes" "0:" "$?:$out"

# ------------------------------------------------------------------ audit --
printf -- '-- audit\n'
R="$TMP/audit"
new_repo "$R"
cat >"$R/.zavet/decisions/D-0001-guard.md" <<'EOF'
---
id: D-0001
title: Guarded area
status: active
guards: [src/**]
---
body
EOF
cat >"$R/.zavet/specs/cap.md" <<'EOF'
---
title: Cap
origin: session
confidence: high
date: 2026-07-01
paths: [lib/**]
---
body
EOF
mkdir -p "$R/src/b" "$R/lib"
echo a >"$R/src/a.rs"
echo c >"$R/src/b/c.rs"
echo l >"$R/lib/l.rs"
gc add -A
gc commit -qm "chore: scaffold"
echo a2 >"$R/src/a.rs" && gc add -A && gc commit -qm "feat: decision drift"
echo l2 >"$R/lib/l.rs" && gc add -A && gc commit -qm "feat: spec drift"
out=$( (cd "$R" && sh "$Z" audit) )
# This fixture is scaffolded by hand and never runs `zavet adapters`, so the
# cross-harness rows are expected here — a repo with no AGENTS.md and no
# AGENTS.md genuinely has no decision index for anything but Claude Code,
# which is exactly what audit exists to say out loud. They are filtered out of
# the staleness assertion below and asserted separately.
# The Grok rules file is opt-in, so a repo with no .grok/ is not "missing" it.
assert_eq "audit reports a repo with no cross-harness layer" "adapter-missing	AGENTS.md" \
    "$(printf '%s\n' "$out" | grep '^adapter-' | cut -f1-2)"
mkdir -p "$R/.grok"
assert_eq "audit reports the Grok rules as missing once .grok/ exists" "adapter-missing	.grok/rules/zavet.md
adapter-missing	AGENTS.md" "$( (cd "$R" && sh "$Z" audit) | grep '^adapter-' | cut -f1-2)"
rmdir "$R/.grok"
assert_eq "audit rows (minus shas)" "stale-spec	cap	1
stale-decision	D-0001	1
guard-pressure	D-0001	src/**" "$(printf '%s\n' "$out" | grep -v '^adapter-' | grep -v '^githook-' | cut -f1-3)"
assert_eq "guard-pressure counts files" "guard-pressure	D-0001	src/**	2	5" "$(printf '%s\n' "$out" | grep '^guard-pressure')"

# --- uncovered-invariant / long-record: the two audit rows keyed by decision
# id. REGRESSION: both used to derive the id as `${name%%-*}`, which is the
# PREFIX, not the id — every row read `D`, and the checks-table lookup
# (`$1 == i`) could never match, so a record WITH checks was still reported
# uncovered. Nothing asserted on these rows, so it went unnoticed.
R="$TMP/audit-invariants"
new_repo "$R"
mk_directive_record() { # $1 = id, $2 = slug, $3 = checks block (may be empty)
    {
        printf -- '---\nid: %s\ntitle: T\nstatus: active\n' "$1"
        [ -n "$3" ] && printf '%s\n' "$3"
        printf -- '---\n\n## Agent directives\n\n- do the thing\n'
    } >"$R/.zavet/decisions/$1-$2.md"
}
mk_directive_record D-0001 unchecked ''
mk_directive_record D-0002 checked 'checks:
  - it holds :: true'
out=$( (cd "$R" && sh "$Z" audit) )
assert_eq "uncovered-invariant names the FULL id, not the prefix" \
    "uncovered-invariant	D-0001	D-0001-unchecked.md" \
    "$(printf '%s\n' "$out" | grep '^uncovered-invariant')"

# A long record, and a prefixed one, so both rows are pinned under a prefix.
(cd "$R" && sh "$Z" prefix CLOUD) >/dev/null 2>&1
mk_directive_record CLOUD-0003 prefixed ''
{
    printf -- '---\nid: CLOUD-0004\ntitle: T\nstatus: active\n---\n'
    i=0
    while [ "$i" -lt 65 ]; do
        printf 'filler line %s\n' "$i"
        i=$((i + 1))
    done
} >"$R/.zavet/decisions/CLOUD-0004-long.md"
out=$( (cd "$R" && sh "$Z" audit) )
# Row order is filename-sort order, so adopting a prefix reorders the report
# (CLOUD-* sorts before D-*). Pinned deliberately: the audit rows are diffed
# by eye between runs, and a silent reordering would read as churn.
assert_eq "uncovered-invariant works under a prefix too" \
    "uncovered-invariant	CLOUD-0003	CLOUD-0003-prefixed.md
uncovered-invariant	D-0001	D-0001-unchecked.md" \
    "$(printf '%s\n' "$out" | grep '^uncovered-invariant')"
assert_eq "long-record names the full id and the line count" \
    "long-record	CLOUD-0004	70" \
    "$(printf '%s\n' "$out" | grep '^long-record')"

# -------------------------------------------------------------- version --
# `zavet version` needs no .zavet/ and no git repo — it only depends on
# script_dir() finding ../.claude-plugin/plugin.json relative to $0. That
# helper (line ~57) was, until now, exercised only incidentally by
# cmd_init's `../templates` lookup and never asserted on directly. Build a
# throwaway plugin skeleton so the manifest version is a known literal,
# independent of whatever the real repo's plugin.json currently says.
printf -- '-- version\n'
R="$TMP/version"
mkdir -p "$R/plugin/bin" "$R/plugin/.claude-plugin"
cp "$Z" "$R/plugin/bin/zavet"
cat >"$R/plugin/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "zavet",
  "version": "9.9.9-test",
  "description": "fixture manifest for the version-contract tests"
}
EOF
json_expected='{"v":1,"plugin":"zavet","version":"9.9.9-test","emit_schema":1,"min_dira":"0.1.0","specs_json":1,"spec_sources_json":1}'

assert_eq "version: bare, direct invocation" "9.9.9-test" "$(sh "$R/plugin/bin/zavet" version)"
assert_eq "version: --json, direct invocation" "$json_expected" "$(sh "$R/plugin/bin/zavet" version --json)"
line_count=$(sh "$R/plugin/bin/zavet" version --json | wc -l)
line_count=$((line_count + 0))
assert_eq "version --json is a single line" "1" "$line_count"

# Ancestor-directory symlink — the realistic shape of a plugin reached
# through a stable alias (Claude's plugin cache is versioned;
# ~/.claude/plugins/cache/<marketplace>/zavet/<version>/ is exactly the
# kind of path a convenience symlink would point at). $0's dirname then
# runs THROUGH the symlink rather than resolving it, and "../.claude-plugin"
# still lands on the right manifest because intermediate path components
# are followed transparently by the OS — script_dir() never chases the
# link itself, so this is the property that actually needs proving.
ln -s "$R/plugin" "$R/plugin-current"
assert_eq "version: bare, via symlinked plugin dir" "9.9.9-test" "$(sh "$R/plugin-current/bin/zavet" version)"
assert_eq "version: --json, via symlinked plugin dir" "$json_expected" "$(sh "$R/plugin-current/bin/zavet" version --json)"

# Arbitrary cwd — script_dir() resolves off $0, never off the caller's
# working directory (a `cd /` proves no accidental reliance on PWD).
assert_eq "version: bare, arbitrary cwd, absolute path" "9.9.9-test" "$(cd / && sh "$R/plugin/bin/zavet" version)"
assert_eq "version: --json, arbitrary cwd, via symlink" "$json_expected" "$(cd / && sh "$R/plugin-current/bin/zavet" version --json)"

# A missing or unreadable manifest must never fail the command.
R2="$TMP/version-missing"
mkdir -p "$R2/plugin/bin"
cp "$Z" "$R2/plugin/bin/zavet"
out=$(sh "$R2/plugin/bin/zavet" version)
rc=$?
assert_eq "version: missing manifest exits 0" "0" "$rc"
assert_eq "version: missing manifest prints unknown" "unknown" "$out"
out=$(sh "$R2/plugin/bin/zavet" version --json)
rc=$?
assert_eq "version --json: missing manifest exits 0" "0" "$rc"
assert_eq "version --json: missing manifest embeds unknown" \
    '{"v":1,"plugin":"zavet","version":"unknown","emit_schema":1,"min_dira":"0.1.0","specs_json":1,"spec_sources_json":1}' "$out"

# Byte-for-byte against the REAL shipped manifest, through the real $Z —
# the actual contract dira-side installers will read.
real_version=$(sed -n 's/^[[:space:]]*"version": *"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json" | head -n1)
assert_eq "version: matches real plugin.json byte-for-byte" "$real_version" "$(sh "$Z" version)"

# ----------------------------------------------------------------- verify --
printf -- '-- verify\n'
R="$TMP/verify"
new_repo "$R"
mkdir -p "$R/src"
cat >"$R/.zavet/decisions/D-0001-passing.md" <<'EOF'
---
id: D-0001
title: Checks that pass
status: active
guards:
  - src/**
checks:
  - tree has src :: test -d src
  - "quoted keeps a hash :: test -n 'a # b'"
---

## Decision
x

## Agent directives
- Never do the thing.
- Nor the other thing.
EOF
cat >"$R/.zavet/decisions/D-0002-failing.md" <<'EOF'
---
id: D-0002
title: A check that fails
status: superseded
checks:
  - absent file :: test -f definitely-not-here
---
body
EOF
cat >"$R/.zavet/specs/flows.md" <<'EOF'
---
title: Flows
origin: session
confidence: high
date: 2026-01-01
paths: [src/**]
checks:
  - flow still runs :: true
---
body
EOF

# Checks emit for EVERY status — D-0002 is superseded and still listed.
assert_eq "checks list every status" "D-0001	tree has src	test -d src
D-0001	quoted keeps a hash	test -n 'a # b'
D-0002	absent file	test -f definitely-not-here" "$( (cd "$R" && sh "$Z" checks) )"

out=$( (cd "$R" && sh "$Z" verify 2>/dev/null) ); rc=$?
assert_eq "verify exit 1 when a check fails" "1" "$rc"
assert_eq "verify reports PASS and FAIL rows" "FAIL	D-0002	absent file
PASS	D-0001	quoted keeps a hash
PASS	D-0001	tree has src
PASS	flows	flow still runs" "$(printf '%s\n' "$out" | sort)"

out=$( (cd "$R" && sh "$Z" verify --id D-0001 2>/dev/null) ); rc=$?
assert_eq "verify --id selects one decision" "0" "$rc"
assert_eq "verify --id runs only its checks" "2" "$(printf '%s\n' "$out" | grep -c .)"

out=$( (cd "$R" && sh "$Z" verify --spec flows 2>/dev/null) ); rc=$?
assert_eq "verify --spec selects one spec" "PASS	flows	flow still runs" "$out"

# --paths resolves through the SAME tables the hooks use.
out=$( (cd "$R" && sh "$Z" verify --paths src/a.ts 2>/dev/null) )
assert_eq "verify --paths covers guard and spec matches" "3" "$(printf '%s\n' "$out" | grep -c .)"

out=$( (cd "$R" && sh "$Z" verify --grep quoted 2>/dev/null) )
assert_eq "verify --grep filters by label" "PASS	D-0001	quoted keeps a hash" "$out"

out=$( (cd "$R" && sh "$Z" verify --id D-9999 2>/dev/null) ); rc=$?
assert_eq "verify with no match exits 0" "0" "$rc"
assert_eq "verify with no match prints nothing" "" "$out"

assert_eq "section extracts one body section" "- Never do the thing.
- Nor the other thing." "$( (cd "$R" && sh "$Z" section D-0001 'Agent directives') )"
assert_eq "section of an absent heading is empty" "" "$( (cd "$R" && sh "$Z" section D-0001 'Nope') )"

# A dangling corrected-by fails the CI floor.
cat >"$R/.zavet/decisions/D-0003-dangling.md" <<'EOF'
---
id: D-0003
title: Points at nothing
status: active
corrected-by: D-4242
---
body
EOF
# An EMPTY range, so the only thing check can complain about is the pointer.
gc add -A >/dev/null 2>&1
gc commit -qm "records" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) ); rc=$?
assert_eq "check fails on a dangling corrected-by" "1" "$rc"
assert_eq "check names the bad pointer" "violation-errata	D-0003	D-4242" "$(printf '%s\n' "$out" | cut -f1,2,3)"

# -------------------------------------------------------------------- ids --
printf -- '-- ids\n'
R="$TMP/ids"
new_repo "$R"

assert_eq "next-id on an empty repo" "D-0001" "$( (cd "$R" && sh "$Z" next-id) )"

cat >"$R/.zavet/decisions/D-0001-first.md" <<'EOF'
---
id: D-0001
title: First
status: active
---
body
EOF
assert_eq "next-id counts the working tree" "D-0002" "$( (cd "$R" && sh "$Z" next-id) )"

# The real collision: a decision that exists only on ANOTHER branch. The old
# next-id looked at the checked-out tree alone, so this returned D-0002 and two
# branches picked the same number.
gc add -A >/dev/null 2>&1
gc commit -qm "first" >/dev/null 2>&1
gc checkout -q -b other 2>/dev/null
cat >"$R/.zavet/decisions/D-0002-on-a-branch.md" <<'EOF'
---
id: D-0002
title: Written on another branch
status: active
---
body
EOF
gc add -A >/dev/null 2>&1
gc commit -qm "second, elsewhere" >/dev/null 2>&1
gc checkout -q - 2>/dev/null
if [ -e "$R/.zavet/decisions/D-0002-on-a-branch.md" ]; then
    fail "fixture: D-0002 must not be in this tree"
else
    pass "fixture: D-0002 lives only on the other branch"
fi
assert_eq "next-id sees ids taken on other refs" "D-0003" "$( (cd "$R" && sh "$Z" next-id) )"

# Append-only: a deleted record still burns its number, or every Refs: trailer
# already in the log would point at a different decision.
gc checkout -q other 2>/dev/null
gc rm -q ".zavet/decisions/D-0002-on-a-branch.md" >/dev/null 2>&1 || rm -f "$R/.zavet/decisions/D-0002-on-a-branch.md"
gc commit -qm "delete it" >/dev/null 2>&1
assert_eq "a deleted id is never reissued" "D-0003" "$( (cd "$R" && sh "$Z" next-id) )"
gc checkout -q - 2>/dev/null

# History is UNFILTERED — any file ever committed under decisions/ on any
# fetched ref lands in the same scan, unlike the tree half which
# is_decision_file already keeps clean. A stray non-decision filename must
# not be mistaken for a record and inflate the counter.
gc checkout -q -b junk 2>/dev/null
printf 'not a decision record\n' >"$R/.zavet/decisions/notes-99999.md"
printf 'also not a decision record\n' >"$R/.zavet/decisions/readme-2024-old.md"
gc add -A >/dev/null 2>&1
gc commit -qm "junk landed under decisions/ by mistake" >/dev/null 2>&1
gc rm -q ".zavet/decisions/notes-99999.md" ".zavet/decisions/readme-2024-old.md" >/dev/null 2>&1
gc commit -qm "remove the junk" >/dev/null 2>&1
gc checkout -q - 2>/dev/null
assert_eq "junk filenames in history never inflate next-id" "D-0003" \
    "$( (cd "$R" && sh "$Z" next-id) )"

# --- what a bad merge leaves behind: two records, one id.
R="$TMP/ids-dup"
new_repo "$R"
# The shape a clean auto-merge actually produces: both branches ran next-id,
# both got D-0016, each wrote its own slug.
cat >"$R/.zavet/decisions/D-0016-ours.md" <<'EOF'
---
id: D-0016
title: Ours
status: active
guards:
  - src/**
---
body
EOF
cat >"$R/.zavet/decisions/D-0016-theirs.md" <<'EOF'
---
id: D-0016
title: Theirs
status: active
---
body
EOF
gc add -A >/dev/null 2>&1
gc commit -qm "records" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) ); rc=$?
assert_eq "check fails on a duplicate id" "1" "$rc"
assert_eq "check names both files" "violation-duplicate-id	D-0016	D-0016-ours.md D-0016-theirs.md" "$out"

# Resolution must refuse rather than silently pick one — the silent pick is
# what loses a record and its guards.
if ( cd "$R" && sh "$Z" decision-path D-0016 ) >/dev/null 2>&1; then
    fail "decision-path resolves an ambiguous id"
else
    pass "decision-path refuses an ambiguous id"
fi

# `D-7` and `D-0016` style shorthand: ONE id to dira, two filenames here. The
# glob-based resolver sees them as separate files (sh does not canonicalize —
# a documented divergence), so `check` is the only thing that can catch it.
R="$TMP/ids-shorthand"
new_repo "$R"
printf -- '---\nid: D-0007\nstatus: active\n---\nbody\n' >"$R/.zavet/decisions/D-0007-padded.md"
printf -- '---\nid: D-0007\nstatus: active\n---\nbody\n' >"$R/.zavet/decisions/D-7-shorthand.md"
gc add -A >/dev/null 2>&1
gc commit -qm "records" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) ); rc=$?
assert_eq "check fails on a canonical duplicate" "1" "$rc"
assert_eq "check canonicalizes before comparing" "violation-duplicate-id	D-0007	D-0007-padded.md D-7-shorthand.md" "$out"

# ----------------------------------------------------------------- prefix --
printf -- '-- prefix\n'

# The guarantee that makes this migration-free: a repo with no .zavet/config
# behaves EXACTLY as it did before prefixes existed.
R="$TMP/prefix-default"
new_repo "$R"
assert_eq "no config mints the historical D-NNNN" "D-0001" "$( (cd "$R" && sh "$Z" next-id) )"
assert_eq "no config reports prefix D" "D" "$( (cd "$R" && sh "$Z" prefix) )"
assert_eq "no config keeps width 4" "D-0042" \
    "$(printf -- '---\nid: D-0041\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/D-0041-x.md" &&
        (cd "$R" && sh "$Z" next-id))"

# --- derivation: product stem + role code.
#
# A prefix must carry the PRODUCT, not just the role — `cloud`, `cli` and `api`
# are exactly the segments that repeat across sibling repos, so a last-segment
# rule hands them all the same prefix.
derive_in() { # $1 = org dir (may be empty), $2 = repo name, $3 = remote owner
    _d="$TMP/derive/${1:-_}/$2"
    rm -rf "$_d"
    mkdir -p "$_d"
    git -C "$_d" init -q
    git -C "$_d" config user.email zavet-test@example.invalid
    git -C "$_d" config user.name "zavet test"
    git -C "$_d" config commit.gpgsign false
    [ -n "$3" ] && git -C "$_d" remote add origin "git@github.com:$3/$2.git"
    (cd "$_d" && sh "$Z" init) >/dev/null 2>&1
    (cd "$_d" && sh "$Z" prefix)
}
# A freshly written config carries no trailing whitespace. With no aliases the
# `prefix-aliases:` line used to end in a space, which every whitespace linter
# in the adopting repo then flagged in a file zavet owns.
derive_in dodi-smart dirahq-cloud dodi-smart >/dev/null
assert_eq "init writes a config with no trailing whitespace" "0" \
    "$(grep -c '[[:space:]]$' "$TMP/derive/dodi-smart/dirahq-cloud/.zavet/config")"
assert_eq "an empty prefix-aliases still reads as empty" "" \
    "$(awk -F: '/^prefix-aliases:/ { print $2 }' "$TMP/derive/dodi-smart/dirahq-cloud/.zavet/config")"
assert_eq "cloud means backend, behind the product" "DIRABE" \
    "$(derive_in dodi-smart dirahq-cloud dodi-smart)"
assert_eq "cli means shell, behind the product" "DIRASH" \
    "$(derive_in dodi-smart dirahq-cli dodi-smart)"
assert_eq "no role segment: the name IS the identity" "ZAVET" \
    "$(derive_in dodi-smart dirahq-zavet dodi-smart)"
assert_eq "a stack token is not identity" "INFRPF" \
    "$(derive_in "" infrasensing-supabase-platform "")"
# The org token adds no disambiguation inside a workspace, so it is dropped —
# `time` is what actually distinguishes this repo from its siblings.
assert_eq "an org echo is dropped (org from the remote)" "TIMEAP" \
    "$(derive_in teamschedule time-schedule-application teamschedule)"
assert_eq "an org echo is dropped (org from the parent dir)" "TIMEAP" \
    "$(derive_in teamschedule time-schedule-application "")"
# ...but only when something distinguishing survives: a repo named after its
# own org keeps its name rather than deriving from the role alone.
assert_eq "an org-named repo keeps its name" "INFRPF" \
    "$(derive_in infrasensing infrasensing-supabase-platform infrasensing)"
# The collision this whole rule exists to prevent.
assert_eq "sibling products no longer collide (1/2)" "ACMEBE" \
    "$(derive_in acme acme-cloud acme)"
assert_eq "sibling products no longer collide (2/2)" "WIDGBE" \
    "$(derive_in acme widgets-cloud widgets)"

# A corporate suffix is stripped LONGEST first, deterministically. `xyzmonorepo`
# ends with both MONOREPO and REPO, and `for (k in arr)` has unspecified order
# in awk — so which token won would depend on the awk build, and an id once
# minted is permanent. XYZ (longest) rather than XYZMON (shortest).
assert_eq "the longest corporate suffix wins, not whichever awk sees first" "XYZ" \
    "$(derive_in "" xyzmonorepo "")"

R="$TMP/derive/dodi-smart/dirahq-cloud"
assert_eq "init scaffolds width 5" "DIRABE-00001" "$( (cd "$R" && sh "$Z" next-id) )"

# `suggest` ranks candidates and explains each.
assert_eq "suggest ranks candidates with rationale" \
    "candidate	DIRABE	product + role
candidate	DIRA	product only
candidate	CLOUD	role only" \
    "$( (cd "$R" && sh "$Z" suggest) | grep '^candidate')"

R="$TMP/prefix-init-explicit/my-awesome-service"
rm -rf "$TMP/prefix-init-explicit"
mkdir -p "$R"
git -C "$R" init -q
(cd "$R" && sh "$Z" init --prefix ACME) >/dev/null 2>&1
assert_eq "--prefix overrides derivation" "ACME" "$( (cd "$R" && sh "$Z" prefix) )"

# --- sibling scan: a naming rule can only lower the ODDS of a collision;
# reading the repos next door detects one. Offline, one level up, config only.
SIB="$TMP/siblings/org"
rm -rf "$TMP/siblings"
for r in first-cloud second-web third-cloud; do
    mkdir -p "$SIB/$r"
    git -C "$SIB/$r" init -q
done
(cd "$SIB/first-cloud" && sh "$Z" init --prefix SHARED) >/dev/null 2>&1
(cd "$SIB/second-web" && sh "$Z" init --prefix OTHER) >/dev/null 2>&1
assert_eq "suggest reports prefixes the siblings hold" \
    "taken	OTHER	second-web
taken	SHARED	first-cloud" \
    "$( (cd "$SIB/third-cloud" && sh "$Z" suggest) | grep '^taken' | sort)"
# An uninitialized sibling contributes nothing, and neither does this repo.
assert_eq "an uninitialized sibling is not reported" "2" \
    "$( (cd "$SIB/third-cloud" && sh "$Z" suggest) | grep -c '^taken')"
# Choosing a prefix a sibling already holds warns on stderr — loudly, while
# changing it is still free.
warn=$( (cd "$SIB/third-cloud" && sh "$Z" init --prefix SHARED) 2>&1 >/dev/null )
case "$warn" in
    *WARNING*SHARED*first-cloud*) pass "init warns when a sibling holds the prefix" ;;
    *) fail "init warns when a sibling holds the prefix (got: $warn)" ;;
esac
# ...but it is a warning, not a wall: the user may have a reason.
assert_eq "and still scaffolds" "SHARED" "$( (cd "$SIB/third-cloud" && sh "$Z" prefix) )"
if (cd "$R" && rm -rf .zavet && sh "$Z" init --prefix "lower") >/dev/null 2>&1; then
    fail "init accepts a lowercase prefix"
else
    pass "init refuses a lowercase prefix"
fi

# REGRESSION: the same check under a UTF-8 locale. `case $x in *[!A-Z0-9]*)`
# uses a COLLATION-ordered range, which interleaves case (`a A b B …`), so
# `[A-Z]` matched lowercase and `lower` was accepted as a prefix — a repo
# would then mint ids dira-core refuses to capture at all. It reproduced only
# where LANG is set: green on a bare C-locale shell, red on macOS CI.
utf8_locale=""
for cand in en_US.UTF-8 C.UTF-8 en_GB.UTF-8; do
    if (LC_ALL="$cand" locale charmap) >/dev/null 2>&1; then
        utf8_locale=$cand
        break
    fi
done
if [ -z "$utf8_locale" ]; then
    printf 'skip lowercase-prefix locale check (no UTF-8 locale)\n'
else
    if (cd "$R" && rm -rf .zavet && LC_ALL="$utf8_locale" sh "$Z" init --prefix "lower") >/dev/null 2>&1; then
        fail "init refuses a lowercase prefix under $utf8_locale"
    else
        pass "init refuses a lowercase prefix under $utf8_locale"
    fi
    # ...and a legitimate uppercase prefix still gets through there.
    (cd "$R" && rm -rf .zavet && LC_ALL="$utf8_locale" sh "$Z" init --prefix ACME) >/dev/null 2>&1
    assert_eq "and still accepts an uppercase one under $utf8_locale" "ACME" \
        "$( (cd "$R" && sh "$Z" prefix) )"
fi

# --- retiring a prefix: records keep their ids, the counter continues.
R="$TMP/prefix-migrate"
new_repo "$R"
printf -- '---\nid: D-0041\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/D-0041-legacy.md"
(cd "$R" && sh "$Z" prefix ZAVET) >/dev/null 2>&1
assert_eq "prefix change retires the old one" "ZAVET D" "$( (cd "$R" && sh "$Z" prefixes) )"
assert_eq "the counter continues across a prefix change" "ZAVET-0042" \
    "$( (cd "$R" && sh "$Z" next-id) )"
assert_eq "a retired-prefix id still resolves" ".zavet/decisions/D-0041-legacy.md" \
    "$( (cd "$R" && sh "$Z" decision-path D-0041) )"
if [ -f "$R/.zavet/decisions/D-0041-legacy.md" ]; then
    pass "prefix change never renames a record"
else
    fail "prefix change renamed a record"
fi
assert_eq "width is untouched by a prefix change" "4" \
    "$(awk -F': *' '/^id-width:/ { print $2 }' "$R/.zavet/config")"

# --- a prefix is a NAMESPACE: same number, different prefix, no collision.
R="$TMP/prefix-namespace"
new_repo "$R"
printf -- '---\nid: ZAVET-0016\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/ZAVET-0016-ours.md"
printf -- '---\nid: CLI-0016\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/CLI-0016-theirs.md"
gc add -A >/dev/null 2>&1
gc commit -qm "records" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) ); rc=$?
assert_eq "different prefixes, same number, no collision" "0" "$rc"
assert_eq "and nothing is reported" "" "$out"

# ...but the same prefix at two widths IS one id.
printf -- '---\nid: ZAVET-16\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/ZAVET-16-shorthand.md"
gc add -A >/dev/null 2>&1
gc commit -qm "shorthand" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) ); rc=$?
assert_eq "same prefix, canonically equal, collides" "1" "$rc"
assert_eq "and names both files" \
    "violation-duplicate-id	ZAVET-0016	ZAVET-0016-ours.md ZAVET-16-shorthand.md" "$out"

# --- renumber: the repair path CI prints.
R="$TMP/prefix-renumber"
new_repo "$R"
(cd "$R" && sh "$Z" prefix ACME) >/dev/null 2>&1
printf -- '---\nid: ACME-0001\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/ACME-0001-first.md"
printf -- '---\nid: ACME-0002\nstatus: active\ncorrected-by: ACME-0001\n---\nb\n' \
    >"$R/.zavet/decisions/ACME-0002-second.md"
cat >"$R/.zavet/specs/sync.md" <<'EOF'
---
title: Sync
version: 1
origin: designed
verified: true
confidence: high
date: 2026-08-07
paths:
  - src/**
decisions: [ACME-0001]
---

## Overview
Per ACME-0001; CMD-0001 is not a decision ref.
EOF
gc add -A >/dev/null 2>&1
gc commit -qm "records" >/dev/null 2>&1
(cd "$R" && sh "$Z" renumber ACME-0001 ACME-0003) >/dev/null 2>&1
if [ -f "$R/.zavet/decisions/ACME-0003-first.md" ] && [ ! -e "$R/.zavet/decisions/ACME-0001-first.md" ]; then
    pass "renumber moves the record and keeps the slug"
else
    fail "renumber moves the record and keeps the slug"
fi
assert_eq "renumber rewrites the record's own id" "id: ACME-0003" \
    "$(grep '^id:' "$R/.zavet/decisions/ACME-0003-first.md")"
assert_eq "renumber rewrites an errata pointer" "corrected-by: ACME-0003" \
    "$(grep '^corrected-by:' "$R/.zavet/decisions/ACME-0002-second.md")"
assert_eq "renumber rewrites a spec decisions list" "decisions: [ACME-0003]" \
    "$(grep '^decisions:' "$R/.zavet/specs/sync.md")"
assert_eq "renumber leaves a lookalike prefix alone" \
    "Per ACME-0003; CMD-0001 is not a decision ref." \
    "$(grep '^Per ' "$R/.zavet/specs/sync.md")"
if (cd "$R" && sh "$Z" renumber ACME-0002 ACME-0003) >/dev/null 2>&1; then
    fail "renumber onto a claimed id"
else
    pass "renumber refuses a claimed id"
fi

# --- renumber refuses a record already on the base branch: its id is
# load-bearing in merged commit trailers, which renumber cannot rewrite.
gc add -A >/dev/null 2>&1
gc commit -qm "renumbered" >/dev/null 2>&1
gc branch -q base 2>/dev/null
if (cd "$R" && sh "$Z" renumber --base base ACME-0003 ACME-0009) >/dev/null 2>&1; then
    fail "renumber rewrites a merged record"
else
    pass "renumber refuses a merged record"
fi
if (cd "$R" && sh "$Z" renumber --base base --force ACME-0003 ACME-0009) >/dev/null 2>&1; then
    pass "--force overrides the merged-record refusal"
else
    fail "--force overrides the merged-record refusal"
fi

# --- REGRESSION: renumber must not report failure for work it completed.
# cmd_index dies on a missing INDEX.md, and renumber called it unconditionally
# AFTER the rename — so in a repo with no index the file moved, the refs were
# rewritten, and the command still exited 1.
R="$TMP/prefix-renumber-noindex"
new_repo "$R"
rm -f "$R/.zavet/INDEX.md"
printf -- '---\nid: D-0001\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/D-0001-x.md"
if (cd "$R" && sh "$Z" renumber D-0001 D-0002) >/dev/null 2>&1; then
    pass "renumber succeeds without an INDEX.md"
else
    fail "renumber succeeds without an INDEX.md"
fi
if [ -f "$R/.zavet/decisions/D-0002-x.md" ]; then
    pass "and the record really moved"
else
    fail "and the record really moved"
fi

# --- the motivating scenario end to end: a clean auto-merge lands two records
# claiming one id. `check` must fail, name a DISTINCT free id per row, and the
# suggested command must actually resolve — by path, since the id itself is
# ambiguous and renumber refuses to guess which record to move.
R="$TMP/prefix-collision"
new_repo "$R"
(cd "$R" && sh "$Z" prefix ACME) >/dev/null 2>&1
printf -- '---\nid: ACME-0001\nstatus: active\nguards:\n  - src/**\n---\nb\n' \
    >"$R/.zavet/decisions/ACME-0001-ours.md"
printf -- '---\nid: ACME-0001\nstatus: active\n---\nb\n' \
    >"$R/.zavet/decisions/ACME-0001-theirs.md"
printf -- '---\nid: ACME-0002\nstatus: active\n---\nb\n' \
    >"$R/.zavet/decisions/ACME-0002-ours.md"
printf -- '---\nid: ACME-0002\nstatus: active\n---\nb\n' \
    >"$R/.zavet/decisions/ACME-0002-theirs.md"
gc add -A >/dev/null 2>&1
gc commit -qm "merge landed two pairs" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
err=$( (cd "$R" && sh "$Z" check "$base..$base" 2>&1 >/dev/null) )
assert_eq "each duplicate row gets its OWN free id, by path" \
    "  → sh bin/zavet renumber .zavet/decisions/ACME-0001-theirs.md ACME-0003
  → sh bin/zavet renumber .zavet/decisions/ACME-0002-theirs.md ACME-0004" \
    "$(printf '%s\n' "$err" | grep 'renumber')"
# An ambiguous id is refused rather than silently picking a record...
if (cd "$R" && sh "$Z" renumber ACME-0001 ACME-0003) >/dev/null 2>&1; then
    fail "renumber refuses an ambiguous id"
else
    pass "renumber refuses an ambiguous id"
fi
# ...and names the candidates so the caller can disambiguate by path.
out=$( (cd "$R" && sh "$Z" renumber ACME-0001 ACME-0003 2>&1 >/dev/null) )
assert_eq "and lists the candidate paths" \
    "  .zavet/decisions/ACME-0001-ours.md
  .zavet/decisions/ACME-0001-theirs.md" \
    "$(printf '%s\n' "$out" | grep '^  \.zavet')"
(cd "$R" && sh "$Z" renumber .zavet/decisions/ACME-0001-theirs.md ACME-0003) >/dev/null 2>&1
(cd "$R" && sh "$Z" renumber .zavet/decisions/ACME-0002-theirs.md ACME-0004) >/dev/null 2>&1
gc add -A >/dev/null 2>&1
gc commit -qm "repaired" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) ); rc=$?
assert_eq "the suggested repair clears the violation" "0" "$rc"
assert_eq "and leaves nothing reported" "" "$out"

# --- a wider repo detects the same canonical collision at ITS width.
R="$TMP/prefix-width5"
new_repo "$R"
printf 'prefix: ACME\nid-width: 5\n' >"$R/.zavet/config"
assert_eq "a width-5 repo mints 5 wide" "ACME-00001" "$( (cd "$R" && sh "$Z" next-id) )"
printf -- '---\nid: ACME-00016\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/ACME-00016-a.md"
printf -- '---\nid: ACME-16\nstatus: active\n---\nb\n' >"$R/.zavet/decisions/ACME-16-b.md"
gc add -A >/dev/null 2>&1
gc commit -qm "records" >/dev/null 2>&1
base=$(gc rev-parse HEAD)
out=$( (cd "$R" && sh "$Z" check "$base..$base" 2>/dev/null) ); rc=$?
assert_eq "shorthand collides at width 5 too" "1" "$rc"
assert_eq "and canonicalizes to the repo's width" \
    "violation-duplicate-id	ACME-00016	ACME-00016-a.md ACME-16-b.md" "$out"

# --- the trailer floor accepts a retired prefix, so older commits stay
# compliant after a rename.
R="$TMP/prefix-trailer"
new_repo "$R"
printf -- '---\nid: D-0001\nstatus: active\nguards:\n  - src/**\n---\nb\n' \
    >"$R/.zavet/decisions/D-0001-legacy.md"
gc add -A >/dev/null 2>&1
gc commit -qm "records" >/dev/null 2>&1
(cd "$R" && sh "$Z" prefix ZAVET) >/dev/null 2>&1
mkdir -p "$R/src"
printf 'x\n' >"$R/src/a.rs"
gc add -A >/dev/null 2>&1
gc commit -qm "feat: touch guarded path

Refs: D-0001" >/dev/null 2>&1
out=$( (cd "$R" && sh "$Z" check "HEAD~1..HEAD" 2>/dev/null) ); rc=$?
assert_eq "a retired-prefix trailer still satisfies the guard floor" "0" "$rc"
assert_eq "and reports no violation" "" "$out"

# ------------------------------------------------------------------ hooks --
# The guard-commit hook builds its trailer regex from `zavet prefixes`, so a
# repo that retired a prefix must still accept trailers naming the old one.
# The hook had no coverage at all before this; it fails open by design, which
# makes a silently-broken regex invisible in normal use.
printf -- '-- hooks\n'
if ! command -v jq >/dev/null 2>&1; then
    printf 'skip hooks (no jq)\n'
else
    HOOK="$ROOT/hooks/scripts/guard-commit.sh"
    R="$TMP/hooks"
    new_repo "$R"
    printf -- '---\nid: D-0001\ntitle: Guarded\nstatus: active\nguards:\n  - src/**\n---\nb\n' \
        >"$R/.zavet/decisions/D-0001-guarded.md"
    mkdir -p "$R/src"
    echo x >"$R/src/a.rs"
    gc add -A >/dev/null 2>&1
    gc commit -qm "chore: scaffold" >/dev/null 2>&1
    echo y >"$R/src/a.rs"
    gc add -A >/dev/null 2>&1

    hook_out() { # $1 = commit command, $2 = session id
        jq -nc --arg c "$1" --arg d "$R" --arg s "$2" \
            '{tool_input: {command: $c}, cwd: $d, session_id: $s}' | sh "$HOOK"
    }

    out=$(hook_out 'git commit -m "feat: touch guarded path"' s1)
    if printf '%s' "$out" | grep -q 'permissionDecision'; then
        pass "hook blocks a guarded commit with no trailer"
    else
        fail "hook blocks a guarded commit with no trailer"
    fi

    out=$(hook_out 'git commit -m "feat: x

Refs: D-0001"' s2)
    assert_eq "hook passes a current-prefix trailer" "" "$out"

    # A non-commit Bash call never reaches the guard logic.
    assert_eq "hook ignores a non-commit command" "" "$(hook_out 'git log --grep=commit' s3)"

    # REGRESSION: retire the prefix. Commits already in the log name `D-0001`,
    # and the hook must keep honoring them — otherwise adopting a prefix would
    # block every future change to paths guarded by a pre-rename record.
    (cd "$R" && sh "$Z" prefix ACME) >/dev/null 2>&1
    assert_eq "hook still passes a RETIRED-prefix trailer" "" \
        "$(hook_out 'git commit -m "feat: x

Refs: D-0001"' s4)"
    # The assertion that actually pins the alternation to config: a trailer
    # naming the CURRENT prefix. A hook hardcoded to `D-[0-9]+` passes the
    # retired case above by accident, and blocks this one.
    assert_eq "hook passes a NEW-prefix trailer" "" \
        "$(hook_out 'git commit -m "feat: x

Refs: ACME-0002"' s6)"
    out=$(hook_out 'git commit -m "feat: touch guarded path"' s5)
    if printf '%s' "$out" | grep -q 'permissionDecision'; then
        pass "hook still blocks an untrailered commit after a prefix change"
    else
        fail "hook still blocks an untrailered commit after a prefix change"
    fi

    # REGRESSION: the cheap detection regex used to require whitespace (or
    # start/end of string) around `git … commit`, so a separator glued
    # directly onto "commit" — or a command substitution/subshell opener
    # right before "git" — walked straight past the gate. That is a SILENT
    # ALLOW of an untrailered commit touching a guarded path, not a fail-open
    # miss: worse than blocking too much. Each of these is untrailered and
    # touches src/**, so every one must still DENY.
    i=0
    # shellcheck disable=SC2016 # these are literal command TEXT under test, not meant to expand
    for cmd in \
        'git commit;echo done' \
        'x=$(git commit -m "x")' \
        'git "commit" -m "x"' \
        'X=`git commit -m "x"`'
    do
        i=$((i + 1))
        out=$(hook_out "$cmd" "sre-bypass-$i")
        if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
            pass "hook still denies a compact/quoted bypass form: $cmd"
        else
            fail "hook still denies a compact/quoted bypass form: $cmd"
            printf '  actual: %s\n' "$out"
        fi
    done

    # PINNED: a prose mention of `git commit` inside an unrelated command (a
    # heredoc body, here) sits backtick-adjacent to the tokens, which is
    # textually identical to a live command substitution — see the "ACCEPTED
    # over-trigger" note above hook_guard_commit's regex in bin/zavet. This
    # DENY is deliberate, not a bug: a future "fix" that narrows the regex to
    # dodge this prose case will fail this assertion and must confront that
    # ruling first.
    # shellcheck disable=SC2016 # literal command TEXT under test, not meant to expand
    out=$(hook_out 'cat >> notes.md <<'"'"'EOF'"'"'
Use `git commit` after editing.
EOF' sre-prose)
    if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
        pass "hook pins the deliberate prose-mention over-trigger as a DENY"
    else
        fail "hook pins the deliberate prose-mention over-trigger as a DENY"
        printf '  actual: %s\n' "$out"
    fi

    # The standalone-token property must survive the widened boundary classes:
    # "commit" appearing inside another word, or as a --grep value, is still
    # not a `git commit` invocation and must stay silent.
    assert_eq "hook still ignores --grep=commit" "" "$(hook_out 'git log --grep=commit' sre-grep)"
    assert_eq "hook still ignores a bare echo of the word commit" "" "$(hook_out 'echo commit' sre-echo)"
fi

# ------------------------------------------------------------- adapters ----
#
# The cross-harness layer. Three things can go wrong here and all three are
# SILENT, which is why they are all covered:
#
#   1. A generated file drifts from its source. Both copies still look fine;
#      they just teach different things.
#   2. A deny envelope goes to the wrong harness. Grok parses
#      `hookSpecificOutput` only for Stop hooks, so the Claude envelope reads to
#      it as no decision at all — the guard ALLOWS the edit while appearing
#      installed.
#   3. The wall enforces one rule in the agent loop and another at `git commit`,
#      so a local pass teaches a rule CI then rejects.
printf -- '-- adapters\n'

R="$TMP/adapters"
new_repo "$R"
printf -- '---\nid: D-0001\ntitle: Guarded\nstatus: active\nguards:\n  - src/**\n---\n\n## Agent directives\n- Never watch src/.\n' \
    >"$R/.zavet/decisions/D-0001-guarded.md"
cp "$ROOT/templates/INDEX.md" "$R/.zavet/INDEX.md"
cp "$ROOT/templates/RULES.md" "$R/.zavet/RULES.md"
mkdir -p "$R/src"

# --- --grok opt-in ---------------------------------------------------------
# Grok Build support is opt-in like Cursor: a repo nobody uses Grok in should
# not carry files it must commit to keep `adapters --check` green. `--grok`, or
# an existing `.grok/`, is the way in; every repo that predates the opt-in has
# `.grok/`, so none of them changes.
RG="$TMP/adapters-nogrok"
new_repo "$RG"
cp "$ROOT/templates/RULES.md" "$RG/.zavet/RULES.md"
(cd "$RG" && sh "$Z" adapters) >/dev/null 2>&1
if [ -e "$RG/.grok" ]; then
    fail "plain adapters in a fresh repo writes no .grok/"
else
    pass "plain adapters in a fresh repo writes no .grok/"
fi
for f in AGENTS.md .zavet/githooks/commit-msg .zavet/bin/zavet; do
    if [ -f "$RG/$f" ]; then
        pass "plain adapters still writes $f"
    else
        fail "plain adapters still writes $f"
    fi
done
(cd "$RG" && sh "$Z" adapters --check) >/dev/null 2>&1
assert_eq "adapters --check passes without .grok/" "0" "$?"
assert_eq "audit reports no grok adapter-missing without .grok/" "" \
    "$( (cd "$RG" && sh "$Z" audit) | grep '^adapter-' | grep -F .grok)"
(cd "$RG" && sh "$Z" index) >/dev/null 2>&1
if [ -e "$RG/.grok" ]; then
    fail "zavet index does not conjure .grok/"
else
    pass "zavet index does not conjure .grok/"
fi

(cd "$RG" && sh "$Z" adapters --grok) >/dev/null 2>&1
for f in .grok/rules/zavet.md .grok/hooks/zavet.json; do
    if [ -f "$RG/$f" ]; then
        pass "adapters --grok writes $f"
    else
        fail "adapters --grok writes $f"
    fi
done
# Real generated content, not just files that exist.
for marker in '### Standing rules' '# Zavet knowledge layer'; do
    if grep -qF "$marker" "$RG/.grok/rules/zavet.md" 2>/dev/null; then
        pass "generated .grok/rules/zavet.md carries $marker"
    else
        fail "generated .grok/rules/zavet.md carries $marker"
    fi
done
for marker in '"PreToolUse"' 'hook guard-edit --flavor grok' 'hook guard-commit --flavor grok'; do
    if grep -qF "$marker" "$RG/.grok/hooks/zavet.json" 2>/dev/null; then
        pass "generated .grok/hooks/zavet.json carries $marker"
    else
        fail "generated .grok/hooks/zavet.json carries $marker"
    fi
done
(cd "$RG" && sh "$Z" adapters --check) >/dev/null 2>&1
assert_eq "adapters --check passes with .grok/" "0" "$?"
# The flag is only needed once: .grok/ now exists, so plain adapters refreshes it.
printf 'stale\n' >"$RG/.grok/rules/zavet.md"
(cd "$RG" && sh "$Z" adapters) >/dev/null 2>&1
if grep -qF '### Standing rules' "$RG/.grok/rules/zavet.md" 2>/dev/null; then
    pass "a repo that already has .grok/ keeps getting it refreshed"
else
    fail "a repo that already has .grok/ keeps getting it refreshed"
fi
rm -f "$RG/.grok/rules/zavet.md"
assert_eq "and a deleted rules file is drift there" "1" "$( (cd "$RG" && sh "$Z" adapters --check) >/dev/null 2>&1; echo $?)"
assert_eq "audit names it adapter-missing there" "adapter-missing	.grok/rules/zavet.md" \
    "$( (cd "$RG" && sh "$Z" audit) | grep '^adapter-missing' | cut -f1-2)"

# `zavet rules` is an explicit request, so it writes the file even with no
# .grok/ — and from then on the repo has opted in.
RR="$TMP/adapters-rules-explicit"
new_repo "$RR"
cp "$ROOT/templates/RULES.md" "$RR/.zavet/RULES.md"
(cd "$RR" && sh "$Z" rules) >/dev/null 2>&1
if [ -f "$RR/.grok/rules/zavet.md" ]; then
    pass "zavet rules writes .grok/rules/zavet.md even without .grok/"
else
    fail "zavet rules writes .grok/rules/zavet.md even without .grok/"
fi

# zavet init: Grok stays out unless asked for, and --grok asks.
RI="$TMP/adapters-init"
new_repo "$RI"
rm -rf "$RI/.zavet"
(cd "$RI" && sh "$Z" init --prefix INIT) >/dev/null 2>&1
if [ -e "$RI/.grok" ]; then
    fail "zavet init in a fresh repo writes no .grok/"
else
    pass "zavet init in a fresh repo writes no .grok/"
fi
RI="$TMP/adapters-init-grok"
new_repo "$RI"
rm -rf "$RI/.zavet"
out=$(cd "$RI" && sh "$Z" init --prefix INIT --grok 2>&1)
if [ -f "$RI/.grok/rules/zavet.md" ] && [ -f "$RI/.grok/hooks/zavet.json" ]; then
    pass "zavet init --grok writes .grok/"
else
    fail "zavet init --grok writes .grok/"
fi
case $out in
    *'adapters written (AGENTS.md, .grok/rules/zavet.md'*) pass "init summary names the Grok rules only when written" ;;
    *) fail "init summary names the Grok rules only when written"; printf '  actual: %s\n' "$out" ;;
esac

(cd "$R" && sh "$Z" adapters --grok) >/dev/null 2>&1

for f in AGENTS.md .grok/rules/zavet.md .grok/hooks/zavet.json \
    .zavet/githooks/commit-msg .zavet/githooks/pre-commit .zavet/bin/zavet; do
    if [ -f "$R/$f" ]; then
        pass "adapters writes $f"
    else
        fail "adapters writes $f"
    fi
done

# --- --cursor opt-in --------------------------------------------------------
# `zavet adapters --cursor` had zero test coverage. Cursor support is opt-in
# (see cmd_adapters/adapters_table), so the flag must be the only way in: a
# fresh repo that never asked for it must not get a Cursor hook file it cannot
# audit for, and a repo that asks for it must get the real generated content,
# not just a file that happens to exist.
if [ -f "$R/.cursor/hooks.json" ]; then
    fail "plain adapters (no --cursor) does NOT create .cursor/hooks.json"
else
    pass "plain adapters (no --cursor) does NOT create .cursor/hooks.json"
fi

RC="$TMP/adapters-cursor"
new_repo "$RC"
cp "$ROOT/templates/RULES.md" "$RC/.zavet/RULES.md"
(cd "$RC" && sh "$Z" adapters --cursor) >/dev/null 2>&1
if [ -f "$RC/.cursor/hooks.json" ]; then
    pass "adapters --cursor writes .cursor/hooks.json"
else
    fail "adapters --cursor writes .cursor/hooks.json"
fi
# Assert on what ctx_render_cursor_hooks actually emits — its two hook event
# names and the `--flavor cursor` command string — not just "a file exists".
for marker in '"beforeShellExecution"' '"preToolUse"' \
    'hook guard-commit --flavor cursor' 'hook guard-edit --flavor cursor'; do
    if grep -qF "$marker" "$RC/.cursor/hooks.json" 2>/dev/null; then
        pass "generated .cursor/hooks.json carries $marker"
    else
        fail "generated .cursor/hooks.json carries $marker"
    fi
done

# REGRESSION: the git hooks must be EXECUTABLE and the rest readable, whatever
# umask the caller has. `zavet adapters` chmods each generated file from a mode
# column in its table — and the loop variable holding that mode was once named
# `_mode`, the same name `ctx_payload` assigns for its own use. POSIX sh has no
# locals and the call chain has no subshell, so `chmod` ran with the literal
# string "file" as its mode. Under the usual umask 022 the files happened to
# come out right anyway, which is precisely why this needs an explicit umask to
# surface: a hook that is not executable does not run, and git says nothing.
R="$TMP/adapters-perm"
new_repo "$R"
cp "$ROOT/templates/RULES.md" "$R/.zavet/RULES.md"
(umask 077 && cd "$R" && sh "$Z" adapters --grok) >/dev/null 2>&1
for f in .zavet/githooks/commit-msg .zavet/githooks/pre-commit .zavet/bin/zavet; do
    if [ -x "$R/$f" ]; then
        pass "adapters makes $f executable under a strict umask"
    else
        fail "adapters makes $f executable under a strict umask"
    fi
done
# Asserted as the actual mode string, not with `[ -r ]`: under umask 077 a
# failed chmod leaves the file at 600, which is still readable BY THE OWNER, so
# a `-r` test passes while every teammate and CI job gets permission denied.
# `ls -l` rather than `stat`, whose flags differ between BSD and GNU.
# shellcheck disable=SC2012 # fixed, test-authored paths; `find -printf` is GNU-only
mode_of() { ls -l "$1" | cut -c1-10; }
for f in AGENTS.md .grok/rules/zavet.md .grok/hooks/zavet.json; do
    assert_eq "adapters chmods $f to 644 under a strict umask" "-rw-r--r--" "$(mode_of "$R/$f")"
done

R="$TMP/adapters"

# Generated means regenerable: a second run must produce the same bytes, or
# `--check` in CI would fail on a clean tree.
cp "$R/AGENTS.md" "$TMP/agents.1"
cp "$R/.grok/rules/zavet.md" "$TMP/rules.1"
(cd "$R" && sh "$Z" adapters) >/dev/null 2>&1
assert_file "adapters is idempotent (AGENTS.md)" "$TMP/agents.1" "$R/AGENTS.md"
assert_file "adapters is idempotent (grok rules)" "$TMP/rules.1" "$R/.grok/rules/zavet.md"

(cd "$R" && sh "$Z" adapters --check) >/dev/null 2>&1
assert_eq "adapters --check passes on a clean tree" "0" "$?"

# The generated context files must carry the SAME decision index the
# SessionStart hook injects. This is the test that makes "Grok Build is
# first-class" a fact rather than a claim: its whole knowledge layer is this
# file, so if it disagrees with what Claude Code is told, the two harnesses are
# working from different repos.
ctx=$(cd "$R" && sh "$Z" context)
for surface in AGENTS.md .grok/rules/zavet.md; do
    missing=""
    printf '%s\n' "$ctx" | grep '^- D-0001' >"$TMP/ctx.ids" 2>/dev/null || true
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # `--` matters: index lines start with "- ", which grep reads as a flag.
        grep -qF -- "$line" "$R/$surface" || missing="$line"
    done <"$TMP/ctx.ids"
    assert_eq "$surface carries the same decision index as \`zavet context\`" "" "$missing"
done

# User prose outside the markers is not ours to touch. A generator that ate a
# hand-written AGENTS.md once would never be trusted with one again.
{
    printf '# My project\n\nHAND_WRITTEN_TOP\n\n'
    cat "$R/AGENTS.md"
    printf '\n## Notes\n\nHAND_WRITTEN_BOTTOM\n'
} >"$TMP/agents.mixed"
cp "$TMP/agents.mixed" "$R/AGENTS.md"
(cd "$R" && sh "$Z" agents-md) >/dev/null 2>&1
for marker in HAND_WRITTEN_TOP HAND_WRITTEN_BOTTOM; do
    if grep -qF "$marker" "$R/AGENTS.md"; then
        pass "agents-md preserves prose ($marker)"
    else
        fail "agents-md preserves prose ($marker)"
    fi
done
# And the block itself must still be substituted exactly once, not duplicated
# on every run.
assert_eq "agents-md keeps exactly one block" "1" \
    "$(grep -cF '<!-- zavet:agents:start -->' "$R/AGENTS.md")"

# Drift is what --check exists to catch.
printf 'tampered\n' >>"$R/.grok/rules/zavet.md"
(cd "$R" && sh "$Z" rules --check) >/dev/null 2>&1
assert_eq "rules --check reports drift" "1" "$?"
(cd "$R" && sh "$Z" adapters --check) >/dev/null 2>&1
assert_eq "adapters --check reports drift" "1" "$?"
(cd "$R" && sh "$Z" adapters) >/dev/null 2>&1

# --- hook refresh scoping --------------------------------------------------
# `zavet hook refresh` backs BOTH SessionStart and PostToolUse(matcher
# search_replace) on Grok, and Grok's matchers are tool-name only — no path
# filter — so this command is the only place able to restrict the refresh to
# .zavet/ edits. Neither generated file's content can change from an edit
# outside .zavet/, so anything else must no-op silently, and any payload the
# command cannot read a path from (empty stdin, SessionStart) must still
# refresh unconditionally, or the mid-session freshness guarantee breaks.
#
# mtime comparisons are flaky at second granularity, so these assert on a
# SENTINEL string surviving (no rewrite happened) or being replaced (a real
# render-and-mv happened) instead.
if ! command -v jq >/dev/null 2>&1; then
    printf 'skip hook refresh scoping (no jq)\n'
else
    sentinel() { printf 'SENTINEL\n' >"$R/.grok/rules/zavet.md"; } # $R = the adapters repo above
    is_sentinel() { grep -qF 'SENTINEL' "$R/.grok/rules/zavet.md" 2>/dev/null; }

    sentinel
    (cd "$R" && jq -nc '{tool_input:{file_path:"src/foo.ts"}}' | sh "$Z" hook refresh) >/dev/null 2>&1
    if is_sentinel; then
        pass "hook refresh no-ops for a payload naming a path outside .zavet/"
    else
        fail "hook refresh no-ops for a payload naming a path outside .zavet/"
    fi

    sentinel
    (cd "$R" && jq -nc '{tool_input:{file_path:".zavet/decisions/D-0001-guarded.md"}}' | sh "$Z" hook refresh) >/dev/null 2>&1
    if is_sentinel; then
        fail "hook refresh regenerates for a payload naming a .zavet/ path"
    else
        pass "hook refresh regenerates for a payload naming a .zavet/ path"
    fi

    # SessionStart's shape: no tool call, so no path to extract — the refresh
    # must run exactly as it did before this scoping existed.
    sentinel
    (cd "$R" && printf '' | sh "$Z" hook refresh) >/dev/null 2>&1
    if is_sentinel; then
        fail "hook refresh regenerates on empty stdin (SessionStart)"
    else
        pass "hook refresh regenerates on empty stdin (SessionStart)"
    fi

    # Refreshing twice in a row exercises the cmp -s no-op path in ctx_write —
    # the second call renders byte-identical content and must skip the mv
    # without that skip reading as failure.
    (cd "$R" && printf '' | sh "$Z" hook refresh) >/dev/null 2>&1
    rc1=$?
    (cd "$R" && printf '' | sh "$Z" hook refresh) >/dev/null 2>&1
    rc2=$?
    assert_eq "hook refresh exits 0 on a fresh render" "0" "$rc1"
    assert_eq "hook refresh exits 0 when the render is already current (cmp no-op)" "0" "$rc2"

    # Restore real content — later assertions in this suite read this file.
    (cd "$R" && sh "$Z" adapters) >/dev/null 2>&1
fi

# --- health reporting -----------------------------------------------------
# The three cross-harness failures nobody notices on their own: a stale index
# (reads as authoritative), a missing one (reads as "no decisions here"), and an
# inactive hook floor (looks exactly like a compliant repo until someone commits
# over a guard).
R="$TMP/health"
new_repo "$R"
printf -- '---\nid: D-0001\ntitle: Guarded\nstatus: active\nguards:\n  - src/**\n---\nb\n' \
    >"$R/.zavet/decisions/D-0001-guarded.md"
cp "$ROOT/templates/RULES.md" "$R/.zavet/RULES.md"
mkdir -p "$R/src"
echo x >"$R/src/a.rs"
gc add -A >/dev/null 2>&1
gc commit -qm "chore: scaffold" >/dev/null 2>&1

(cd "$R" && sh "$Z" adapters --grok) >/dev/null 2>&1
out=$( (cd "$R" && sh "$Z" audit) )
assert_eq "audit reports an inactive git-hook floor" \
    "githook-floor	inactive" "$(printf '%s\n' "$out" | grep '^githook-floor' | cut -f1-2)"
assert_eq "audit reports no adapter drift when fresh" "" \
    "$(printf '%s\n' "$out" | grep '^adapter-')"

(cd "$R" && sh "$Z" hooks install) >/dev/null 2>&1
out=$( (cd "$R" && sh "$Z" audit) )
assert_eq "audit stops reporting the floor once installed" "" \
    "$(printf '%s\n' "$out" | grep '^githook-floor')"

# Prose appended OUTSIDE the markers is the user's and is not drift — this is
# the distinction that makes the AGENTS.md block safe to share a file.
printf '\n## Mine\n\nnot drift\n' >>"$R/AGENTS.md"
assert_eq "prose outside the markers is not drift" "" \
    "$( (cd "$R" && sh "$Z" audit) | grep '^adapter-stale')"

# Editing INSIDE the block is drift, and `zavet check` says so without failing:
# the file is derived, so failing a PR over it would train people to ignore the
# check — but a stale decision index has to be said out loud.
sed 's/^### Standing rules$/### Tampered/' "$R/.grok/rules/zavet.md" >"$TMP/tampered"
cp "$TMP/tampered" "$R/.grok/rules/zavet.md"
assert_eq "audit reports drift inside the block" "adapter-stale	.grok/rules/zavet.md" \
    "$( (cd "$R" && sh "$Z" audit) | grep '^adapter-stale' | cut -f1-2)"
# An EMPTY range on purpose: staleness is a property of the tree, not of the
# commits under review, so it must be reported on every exit path cmd_check has
# — including the one that returns before looking at any diff.
out=$( (cd "$R" && sh "$Z" check HEAD..HEAD 2>&1) )
if printf '%s' "$out" | grep -q 'warn-generated'; then
    pass "check warns on a stale generated context file"
else
    fail "check warns on a stale generated context file"
    printf '  actual: %s\n' "$out"
fi
(cd "$R" && sh "$Z" check HEAD..HEAD) >/dev/null 2>&1
assert_eq "and does NOT fail the build over it" "0" "$?"

# A gitignored rules file is invisible to Grok, silently, on every machine.
printf '.grok/\n' >"$R/.gitignore"
assert_eq "audit reports a gitignored rules file" "adapter-ignored	.grok/rules/zavet.md" \
    "$( (cd "$R" && sh "$Z" audit) | grep '^adapter-ignored' | cut -f1-2)"
rm -f "$R/.gitignore"

# --- deny envelopes -------------------------------------------------------
# The bare form is frozen: README's integration contract §3 says the hook
# envelope is stable, and dira reads it.
bare=$(sh "$Z" deny 'r')
assert_eq "deny bare == the historical Claude envelope" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"r"}}' \
    "$bare"
assert_eq "deny --format claude is byte-identical to bare" "$bare" "$(sh "$Z" deny --format claude 'r')"
assert_eq "deny --format grok is Grok's flat decision" \
    '{"decision":"deny","reason":"r"}' "$(sh "$Z" deny --format grok 'r')"
# Cursor splits the message in two; the AGENT-facing half is the one that has
# to carry the record, or the guard teaches the human and not the model.
if printf '%s' "$(sh "$Z" deny --format cursor 'r')" | grep -q '"agent_message":"r"'; then
    pass "deny --format cursor carries the reason to the agent"
else
    fail "deny --format cursor carries the reason to the agent"
fi
# Multi-line records embed newlines and quotes; every flavor must escape them.
multi=$(printf 'a\nb"c')
for flavor in claude grok cursor; do
    out=$(sh "$Z" deny --format "$flavor" "$multi")
    if printf '%s' "$out" | grep -qF '\nb\"c' && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "1" ]; then
        pass "deny --format $flavor escapes newlines and quotes"
    else
        fail "deny --format $flavor escapes newlines and quotes"
        printf '  actual: %s\n' "$out"
    fi
done
sh "$Z" deny --format bogus x >/dev/null 2>&1
assert_eq "deny rejects an unknown format" "1" "$?"

# --- gate parity ----------------------------------------------------------
# One rule, three callers. The point of `zavet gate`.
R="$TMP/gate"
new_repo "$R"
printf -- '---\nid: D-0001\ntitle: Guarded\nstatus: active\nguards:\n  - src/**\n---\nb\n' \
    >"$R/.zavet/decisions/D-0001-guarded.md"
mkdir -p "$R/src"
echo x >"$R/src/a.rs"
gc add -A >/dev/null 2>&1
gc commit -qm "chore: scaffold" >/dev/null 2>&1
echo y >"$R/src/a.rs"
gc add -A >/dev/null 2>&1

(cd "$R" && sh "$Z" gate --staged --message 'feat: no trailer') >/dev/null 2>&1
assert_eq "gate blocks a guarded change with no trailer" "1" "$?"
(cd "$R" && sh "$Z" gate --staged --message 'feat: x

Refs: D-0001') >/dev/null 2>&1
assert_eq "gate passes a Refs: trailer" "0" "$?"
(cd "$R" && sh "$Z" gate --staged --message 'feat: x

Supersedes: D-0001') >/dev/null 2>&1
assert_eq "gate passes a Supersedes: trailer" "0" "$?"

# --message-file is the commit-msg hook's path into the same rule. Identical
# message, identical verdict — anything else means the floor is not the wall.
printf 'feat: no trailer\n' >"$TMP/msg.bad"
printf 'feat: x\n\nRefs: D-0001\n' >"$TMP/msg.good"
(cd "$R" && sh "$Z" gate --staged --message-file "$TMP/msg.bad") >/dev/null 2>&1
assert_eq "gate --message-file blocks the same message --message blocks" "1" "$?"
(cd "$R" && sh "$Z" gate --staged --message-file "$TMP/msg.good") >/dev/null 2>&1
assert_eq "gate --message-file passes the same message --message passes" "0" "$?"

# An unreadable message file must read as UNREFERENCED, never as a free pass:
# fail-open on the wall would make the floor decorative.
(cd "$R" && sh "$Z" gate --staged --message-file "$TMP/does-not-exist") >/dev/null 2>&1
assert_eq "gate treats a missing message file as unreferenced" "1" "$?"

# --- dira guard events ----------------------------------------------------
# REGRESSION: the guard wall fires three event kinds at dira, and they have no
# other observable surface — `zavet emit` is fire-and-forget and silently no-ops
# when dira is absent, which is every CI run and most dev machines. So an event
# that stops firing stops firing quietly, forever.
#
# That is exactly what happened extracting the wall into `zavet gate`:
# `Supersedes:[[:space:]]*$id_re` was composed with an `id_re` that had become
# the FULL trailer pattern, producing a regex demanding the keyword twice
# (`Supersedes: Refs: D-0001`). No real commit matched, so `decision_superseded`
# became dead code while every other assertion here still passed.
#
# Stubbing `dira` on PATH is the only way to see any of it.
mkdir -p "$TMP/fakebin"
cat >"$TMP/fakebin/dira" <<'FAKE'
#!/bin/sh
# Records the guard events zavet emits, so the suite can assert on them.
cat >>"$DIRA_EVENT_LOG"
printf '\n' >>"$DIRA_EVENT_LOG"
FAKE
chmod 755 "$TMP/fakebin/dira"

event_kinds() { # -> the kinds recorded in DIRA_EVENT_LOG, sorted, space-separated
    tr ',' '\n' <"$DIRA_EVENT_LOG" | sed -n 's/.*"kind":"\([a-z_]*\)".*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

emitted() { # $1 = commit message, $2 = optional --emit form -> the kinds fired
    DIRA_EVENT_LOG="$TMP/events.log"
    export DIRA_EVENT_LOG
    : >"$DIRA_EVENT_LOG"
    (cd "$R" && PATH="$TMP/fakebin:$PATH" sh "$Z" gate --staged "${2:---emit}" --message "$1") >/dev/null 2>&1
    # `zavet emit` backgrounds the pipe to dira so a slow daemon can never stall
    # a hook, so the write lands after gate exits. One second is generous.
    sleep 1
    event_kinds
}

assert_eq "a Refs: trailer emits guard_complied" "guard_complied" \
    "$(emitted 'feat: x

Refs: D-0001')"
# The assertion that would have caught the double-prefixed regex.
assert_eq "a Supersedes: trailer emits BOTH complied and superseded" \
    "decision_superseded guard_complied" \
    "$(emitted 'feat: x

Supersedes: D-0001')"
assert_eq "an untrailered commit emits guard_blocked" "guard_blocked" \
    "$(emitted 'feat: no trailer')"

# REGRESSION: the git floor must report under its OWN kinds. A repo can run both
# the live hook and the floor — recommended on Claude Code, since the floor also
# catches commits made outside the agent loop — and `zavet_guard_events` has no
# uniqueness constraint, so sharing kinds would silently double-count one commit.
# `--emit` alone must keep meaning what it means today, or every live hook moves.
assert_eq "--emit=git suffixes the blocked kind" "guard_blocked_git" \
    "$(emitted 'feat: no trailer' --emit=git)"
assert_eq "--emit=git suffixes complied" "guard_complied_git" \
    "$(emitted 'feat: x

Refs: D-0001' --emit=git)"
assert_eq "--emit=git suffixes superseded too, so a replacement cannot count twice" \
    "decision_superseded_git guard_complied_git" \
    "$(emitted 'feat: x

Supersedes: D-0001' --emit=git)"
assert_eq "--emit=live is the explicit spelling of bare --emit" "guard_blocked" \
    "$(emitted 'feat: no trailer' --emit=live)"
(cd "$R" && sh "$Z" gate --staged --emit=bogus --message 'feat: x') >/dev/null 2>&1
assert_eq "an unknown --emit source is an error, not a silent bare emit" "1" "$?"
unset DIRA_EVENT_LOG

# --- direct zavet emit -----------------------------------------------------
# `zavet emit` only had INDIRECT coverage, through `zavet gate --emit`, which
# exercises the guard-event kinds but never the command's own contract: the
# payload shape and the fire-and-forget silence when dira is absent — the
# state of every CI run and most dev machines.
DIRA_EVENT_LOG="$TMP/events-emit.log"
export DIRA_EVENT_LOG
: >"$DIRA_EVENT_LOG"
(cd "$R" && PATH="$TMP/fakebin:$PATH" sh "$Z" emit guard_shown D-0001 src/a.rs) >/dev/null 2>&1
rc=$?
# Backgrounded pipe to dira, same as the gate-driven emits above.
sleep 1
payload=$(cat "$DIRA_EVENT_LOG")
assert_eq "emit exits 0" "0" "$rc"
if printf '%s' "$payload" | grep -qF '"v":1'; then
    pass "emit payload carries the schema version"
else
    fail "emit payload carries the schema version"
    printf '  actual: %s\n' "$payload"
fi
if printf '%s' "$payload" | grep -qF '"kind":"guard_shown"'; then
    pass "emit payload carries the kind"
else
    fail "emit payload carries the kind"
fi
if printf '%s' "$payload" | grep -qF '"decision_id":"D-0001"'; then
    pass "emit payload carries the decision id"
else
    fail "emit payload carries the decision id"
fi
# Not an exact match on $R: `repo_toplevel` resolves through git, which can
# differ from the test harness's own path by a symlink (e.g. macOS /tmp vs
# /private/tmp) — the contract is that a cwd is present, not which spelling.
cwd_val=$(printf '%s' "$payload" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')
if [ -n "$cwd_val" ]; then
    pass "emit payload carries a cwd"
else
    fail "emit payload carries a cwd"
    printf '  actual: %s\n' "$payload"
fi
unset DIRA_EVENT_LOG

# Fire-and-forget contract: with no dira on PATH, emit must still exit 0 and
# print nothing — a hook that stalls or fails over a missing daemon is worse
# than one that silently skips the telemetry. A bare `PATH=""` would also make
# `sh` itself unresolvable and pass for the wrong reason (the command never
# ran at all), so this uses a minimal-but-real PATH that has no dira on it —
# this dev machine has a real `dira` installed, unlike CI, so the absence has
# to be constructed rather than assumed.
out=$(cd "$R" && PATH="/usr/bin:/bin" sh "$Z" emit guard_shown D-0001 src/a.rs 2>&1)
rc=$?
assert_eq "emit exits 0 with no dira on PATH" "0" "$rc"
assert_eq "emit is silent with no dira on PATH" "" "$out"

# --- git hook floor -------------------------------------------------------
(cd "$R" && sh "$Z" adapters) >/dev/null 2>&1
(cd "$R" && sh "$Z" hooks install) >/dev/null 2>&1
assert_eq "hooks install sets core.hooksPath" ".zavet/githooks" "$(gc config --get core.hooksPath)"

gc commit -qm "feat: no trailer" >/dev/null 2>&1
assert_eq "commit-msg blocks a guarded commit with no trailer" "1" "$?"
gc commit -qm "feat: x

Refs: D-0001" >/dev/null 2>&1
assert_eq "commit-msg passes a trailered commit" "0" "$?"
assert_eq "and the commit really landed" "feat: x" "$(gc log -1 --format=%s)"

# The floor is the ONLY enforcement surface on Codex, Gemini CLI, OpenCode and
# Copilot, so if the generated hook loses `--emit=git` those harnesses go dark
# in dira and `dira zavet why <ID>` reports their guards as never having fired.
# Asserting through a real `git commit` covers the template, not just the flag.
echo z >"$R/src/a.rs"
gc add -A >/dev/null 2>&1
DIRA_EVENT_LOG="$TMP/events-githook.log"
export DIRA_EVENT_LOG
: >"$DIRA_EVENT_LOG"
(cd "$R" && PATH="$TMP/fakebin:$PATH" git commit -qm "feat: no trailer") >/dev/null 2>&1
sleep 1
assert_eq "the commit-msg hook emits guard_blocked_git" "guard_blocked_git" "$(event_kinds)"

: >"$DIRA_EVENT_LOG"
(cd "$R" && PATH="$TMP/fakebin:$PATH" git commit -qm "feat: y

Refs: D-0001") >/dev/null 2>&1
sleep 1
assert_eq "and guard_complied_git on a trailered one" "guard_complied_git" "$(event_kinds)"
unset DIRA_EVENT_LOG

# Refusing to hijack someone else's hooksPath. Husky, lefthook and pre-commit
# all own that setting; repointing it silently would disable every hook the
# repo already depends on in order to install one it merely wants.
gc config core.hooksPath .husky
(cd "$R" && sh "$Z" hooks install) >/dev/null 2>&1
assert_eq "hooks install refuses a foreign core.hooksPath" "1" "$?"
assert_eq "and leaves it untouched" ".husky" "$(gc config --get core.hooksPath)"
gc config --unset core.hooksPath

# --- the floor under hk ---------------------------------------------------
# A repo with an hk.pkl has handed its hooks to hk, which installs them through
# git config (Git 2.54+) or .git/hooks. zavet must then leave core.hooksPath
# alone and run as hk steps instead, from a generated module.
RH="$TMP/hk"
new_repo "$RH"
cp "$ROOT/templates/RULES.md" "$RH/.zavet/RULES.md"
hc() { git -C "$RH" "$@"; }

(cd "$RH" && sh "$Z" adapters) >/dev/null 2>&1
if [ -f "$RH/.zavet/hk/Zavet.pkl" ]; then
    fail "adapters without hk.pkl does NOT write .zavet/hk/Zavet.pkl"
else
    pass "adapters without hk.pkl does NOT write .zavet/hk/Zavet.pkl"
fi

# Without hk the closing hint is the usual one.
out=$(cd "$RH" && sh "$Z" adapters 2>&1)
case $out in
    *'next step — "zavet hooks install"'*) pass "non-hk adapters hint is unchanged" ;;
    *) fail "non-hk adapters hint is unchanged"; printf '  actual: %s\n' "$out" ;;
esac

printf 'amends "package://example.invalid/hk#/Config.pkl"\n' >"$RH/hk.pkl"
# hk.pkl not wired: the hint is the import lines, not `zavet hooks install`.
out=$(cd "$RH" && sh "$Z" adapters 2>&1)
case $out in
    *'import "./.zavet/hk/Zavet.pkl"'*'Zavet.guard'*) pass "hk hint names the import when hk.pkl is not wired" ;;
    *) fail "hk hint names the import when hk.pkl is not wired"; printf '  actual: %s\n' "$out" ;;
esac
case $out in
    *'zavet hooks install'*) fail "hk hint does not say zavet hooks install" ;;
    *) pass "hk hint does not say zavet hooks install" ;;
esac
if [ -f "$RH/.zavet/hk/Zavet.pkl" ]; then
    pass "adapters writes .zavet/hk/Zavet.pkl when the repo has hk.pkl"
else
    fail "adapters writes .zavet/hk/Zavet.pkl when the repo has hk.pkl"
fi
# The steps call the generated githooks, so the wording and the warn-only
# contract stay in one place.
for marker in 'guard = new Dynamic' 'nudge = new Dynamic' \
    '.zavet/githooks/commit-msg {{commit_msg_file}}' '"'.zavet/githooks/pre-commit'"'; do
    if grep -qF "$marker" "$RH/.zavet/hk/Zavet.pkl" 2>/dev/null; then
        pass "Zavet.pkl carries $marker"
    else
        fail "Zavet.pkl carries $marker"
    fi
done
(cd "$RH" && sh "$Z" adapters --check) >/dev/null 2>&1
assert_eq "adapters --check passes with the hk module" "0" "$?"
printf '// tampered\n' >>"$RH/.zavet/hk/Zavet.pkl"
(cd "$RH" && sh "$Z" adapters --check) >/dev/null 2>&1
assert_eq "adapters --check reports a stale hk module" "1" "$?"
(cd "$RH" && sh "$Z" adapters) >/dev/null 2>&1

# Not wired yet: hooks install says what to add and touches no hooksPath.
out=$(cd "$RH" && sh "$Z" hooks install 2>&1)
rc=$?
assert_eq "hooks install under hk fails until hk.pkl is wired" "1" "$rc"
assert_eq "and never sets core.hooksPath" "" "$(hc config --get core.hooksPath)"
case $out in
    *'import "./.zavet/hk/Zavet.pkl"'*) pass "and prints the import to add" ;;
    *) fail "and prints the import to add"; printf '  actual: %s\n' "$out" ;;
esac

# Wired, but hk's hook is not installed.
cat >>"$RH/hk.pkl" <<'EOF'
import "./.zavet/hk/Zavet.pkl"
hooks {
  ["commit-msg"] { steps { ["zavet-guard"] = Zavet.guard } }
  ["pre-commit"] { steps { ["zavet-nudge"] = Zavet.nudge } }
}
EOF
(cd "$RH" && sh "$Z" hooks --check) >/dev/null 2>&1
assert_eq "hooks --check fails while hk's hook is not installed" "1" "$?"
# Wired but not installed: the hint is `hk install`, and no longer the import.
out=$(cd "$RH" && sh "$Z" adapters 2>&1)
case $out in
    *'run "hk install"'*) pass "hk hint names hk install when wired but not installed" ;;
    *) fail "hk hint names hk install when wired but not installed"; printf '  actual: %s\n' "$out" ;;
esac
case $out in
    *'import "./'*|*'zavet hooks install'*) fail "and says nothing about the import or zavet hooks install" ;;
    *) pass "and says nothing about the import or zavet hooks install" ;;
esac

# hk's config hook (Git 2.54+) counts as installed.
# shellcheck disable=SC2016 # hk's literal hook command; it must not expand here
hc config hook.hk-commit-msg.command 'test "${HK:-1}" = "0" || hk run commit-msg --from-hook'
hc config hook.hk-commit-msg.event commit-msg
out=$(cd "$RH" && sh "$Z" hooks --check 2>&1)
assert_eq "hooks --check passes via hk's config hook" "0:zavet: git-hook floor active (via hk)" "$?:$out"
hc config --unset hook.hk-commit-msg.command
hc config --unset hook.hk-commit-msg.event

# So does hk's legacy shim in .git/hooks.
shim=$(hc rev-parse --git-path hooks/commit-msg)
case $shim in /*) ;; *) shim="$RH/$shim" ;; esac
mkdir -p "$(dirname -- "$shim")"
# shellcheck disable=SC2016 # hk's literal shim; it must not expand here
printf '#!/bin/sh\ntest "${HK:-1}" = "0" || exec hk run commit-msg --from-hook "$@"\n' >"$shim"
(cd "$RH" && sh "$Z" hooks --check) >/dev/null 2>&1
assert_eq "hooks --check passes via hk's .git/hooks shim" "0" "$?"
out=$(cd "$RH" && sh "$Z" adapters 2>&1)
case $out in
    *'next step'*|*'hk install'*) fail "no hint once the floor is active under hk"; printf '  actual: %s\n' "$out" ;;
    *) pass "no hint once the floor is active under hk" ;;
esac

# A core.hooksPath zavet set earlier would hide that shim from git. install
# hands the hooks back to hk; --check only reports it.
hc config core.hooksPath .zavet/githooks
(cd "$RH" && sh "$Z" hooks --check) >/dev/null 2>&1
assert_eq "hooks --check fails while zavet's hooksPath hides hk" "1" "$?"
(cd "$RH" && sh "$Z" hooks install) >/dev/null 2>&1
assert_eq "hooks install under hk succeeds once wired" "0" "$?"
assert_eq "and unsets zavet's own core.hooksPath" "" "$(hc config --get core.hooksPath)"

# End to end through a real hk, when one is on PATH (CI does not install it).
if hk --version >/dev/null 2>&1; then
    rm -f "$shim"
    printf 'amends "package://github.com/jdx/hk/releases/download/v2.4.0/hk@2.4.0#/Config.pkl"\n' >"$RH/hk.pkl.new"
    grep -v '^amends' "$RH/hk.pkl" >>"$RH/hk.pkl.new"
    mv "$RH/hk.pkl.new" "$RH/hk.pkl"
    printf -- '---\nid: D-0001\ntitle: Guarded\nstatus: active\nguards:\n  - src/**\n---\n' \
        >"$RH/.zavet/decisions/D-0001-guarded.md"
    hc add -A >/dev/null 2>&1
    # `git`, not `hc`: an assignment before a function call can outlive it in sh.
    HK=0 git -C "$RH" commit -qm "chore: setup" >/dev/null 2>&1
    (cd "$RH" && hk install --legacy) >/dev/null 2>&1
    mkdir -p "$RH/src" && echo z >"$RH/src/a.rs"
    hc add -A >/dev/null 2>&1
    hc commit -qm "feat: no trailer" >/dev/null 2>&1
    assert_eq "hk: commit-msg blocks a guarded commit with no trailer" "1" "$?"
    hc commit -qm "feat: x

Refs: D-0001" >/dev/null 2>&1
    assert_eq "hk: a trailered commit passes" "0" "$?"
else
    printf 'skip hk end-to-end (no hk on PATH)\n'
fi

# --- generated skills -----------------------------------------------------
# The plugin repo's own .agents/skills/ must match its sources, and must carry
# nothing Claude-specific: `${CLAUDE_PLUGIN_ROOT}` does not exist off Claude
# Code, and `argument-hint` is rejected outright as a SKILL.md key.
sh "$ROOT/scripts/gen-adapters.sh" --check >/dev/null 2>&1
assert_eq "gen-adapters --check passes on a clean tree" "0" "$?"

for pat in 'CLAUDE_PLUGIN_ROOT' 'argument-hint:' '/zavet:[a-z]'; do
    hits=$(grep -rlE "$pat" "$ROOT/.agents/skills" 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "no '$pat' survives into .agents/skills" "0" "$hits"
done

# Agent Skills requires name == parent directory, lowercase-hyphen, and a
# non-empty description. A skill that fails validation is silently not loaded.
bad=""
for d in "$ROOT"/.agents/skills/*/; do
    n=$(basename -- "$d")
    fn=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^name:/{sub(/^name:[[:space:]]*/,"");print;exit}' "$d/SKILL.md")
    de=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^description:[[:space:]]*[^[:space:]]/{print;exit}' "$d/SKILL.md")
    [ "$n" = "$fn" ] || bad="$bad name!=dir:$n"
    [ -n "$de" ] || bad="$bad no-desc:$n"
    case "$n" in *[!a-z0-9-]* | -* | *- | *--*) bad="$bad bad-chars:$n" ;; esac
done
assert_eq "every generated skill is spec-valid" "" "$bad"

# Every skill the marketplace manifest publishes must exist, or `npx skills
# add` silently installs fewer than advertised.
if command -v jq >/dev/null 2>&1; then
    missing=""
    for p in $(jq -r '.plugins[].skills[]? // empty' "$ROOT/.claude-plugin/marketplace.json"); do
        [ -f "$ROOT/${p#./}/SKILL.md" ] || missing="$missing $p"
    done
    assert_eq "every manifest-declared skill exists" "" "$missing"
fi

# --- harness flavor detection --------------------------------------------
# Reading the wrong field means no path, which fails open. Getting the FLAVOR
# wrong is worse: the deny goes out in a shape the harness ignores.
printf -- '-- harness envelopes\n'
if ! command -v jq >/dev/null 2>&1; then
    printf 'skip harness envelopes (no jq)\n'
else
    R="$TMP/envelopes"
    new_repo "$R"
    # Session ids key a state file under $TMPDIR that OUTLIVES the run (that is
    # how show-once survives across hook invocations). Fixed ids would therefore
    # pass on a clean machine and fail on every re-run — so make them unique
    # per run, which is also what a real session id is.
    S="e$$"
    printf -- '---\nid: D-0001\ntitle: Guarded\nstatus: active\nguards:\n  - src/**\n---\nb\n' \
        >"$R/.zavet/decisions/D-0001-guarded.md"
    mkdir -p "$R/src"
    echo x >"$R/src/a.rs"

    # Claude: snake_case envelope, snake_case input.
    out=$(jq -nc --arg f "$R/src/a.rs" --arg s "${S}c1" '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$f}}' |
        sh "$Z" hook guard-edit)
    if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
        pass "claude envelope -> claude deny shape"
    else
        fail "claude envelope -> claude deny shape"
        printf '  actual: %s\n' "$out"
    fi

    # Grok: camelCase envelope around a snake_case tool input. Detected from
    # the envelope alone — no --flavor passed — because Grok also loads
    # .claude/settings.json, so a script cannot infer the caller from config.
    out=$(jq -nc --arg f "$R/src/a.rs" --arg s "${S}g1" '{sessionId:$s,hookEventName:"pre_tool_use",toolName:"search_replace",toolInput:{file_path:$f}}' |
        sh "$Z" hook guard-edit)
    if printf '%s' "$out" | grep -q '"decision":"deny"'; then
        pass "grok envelope -> grok deny shape (detected, not configured)"
    else
        fail "grok envelope -> grok deny shape (detected, not configured)"
        printf '  actual: %s\n' "$out"
    fi

    # GROK_HOOK_EVENT is set by Grok's runner on every hook process, so it
    # settles the flavor even when the payload looks Claude-shaped.
    out=$(jq -nc --arg f "$R/src/a.rs" --arg s "${S}g2" '{session_id:$s,tool_input:{file_path:$f}}' |
        GROK_HOOK_EVENT=pre_tool_use sh "$Z" hook guard-edit)
    if printf '%s' "$out" | grep -q '"decision":"deny"'; then
        pass "GROK_HOOK_EVENT overrides envelope shape"
    else
        fail "GROK_HOOK_EVENT overrides envelope shape"
    fi

    # An explicit --flavor from a generated config beats every heuristic.
    out=$(jq -nc --arg f "$R/src/a.rs" --arg s "${S}x1" '{session_id:$s,tool_input:{file_path:$f}}' |
        sh "$Z" hook guard-edit --flavor cursor)
    if printf '%s' "$out" | grep -q '"permission":"deny"'; then
        pass "--flavor cursor wins over detection"
    else
        fail "--flavor cursor wins over detection"
    fi

    # Show-once-per-session: the second touch under the same decision passes,
    # or the agent can never actually make the edit it was just taught about.
    jq -nc --arg f "$R/src/a.rs" --arg s "${S}once" '{session_id:$s,tool_input:{file_path:$f}}' |
        sh "$Z" hook guard-edit >/dev/null
    out=$(jq -nc --arg f "$R/src/a.rs" --arg s "${S}once" '{session_id:$s,tool_input:{file_path:$f}}' |
        sh "$Z" hook guard-edit)
    assert_eq "guard-edit is show-once-per-session" "" "$out"

    # An unguarded path is silent in every flavor.
    echo x >"$R/README.md"
    out=$(jq -nc --arg f "$R/README.md" --arg s "${S}u1" '{session_id:$s,tool_input:{file_path:$f}}' |
        sh "$Z" hook guard-edit)
    assert_eq "guard-edit ignores an unguarded path" "" "$out"

    # No jq on PATH must fail OPEN, not wedge the loop. Simulated with an
    # empty PATH; `zavet` is invoked through `sh` so it still runs.
    out=$(jq -nc --arg f "$R/src/a.rs" --arg s "${S}nojq" '{session_id:$s,tool_input:{file_path:$f}}' |
        PATH="" sh "$Z" hook guard-edit 2>/dev/null)
    assert_eq "guard-edit fails open without jq" "" "$out"
fi

# ------------------------------------------------------------------- sdlc --
printf -- '-- sdlc\n'
SDLC="$ROOT/test/fixtures/sdlc"

assert_has() { # $1 label, $2 haystack, $3 needle
    case "$2" in
        *"$3"*) pass "$1" ;;
        *)
            fail "$1"
            printf '  missing: [%s]\n  in:      [%s]\n' "$3" "$2"
            ;;
    esac
}
assert_lacks() { # $1 label, $2 haystack, $3 needle
    case "$2" in
        *"$3"*)
            fail "$1"
            printf '  unexpected: [%s]\n' "$3"
            ;;
        *) pass "$1" ;;
    esac
}

# A repo seeded with one fixture, one config line, one commit.
sdlc_repo() { # $1 dir, $2 fixture, $3.. = config lines
    _d=$1
    _f=$2
    shift 2
    new_repo "$_d"
    cp -R "$SDLC/$_f/." "$_d/"
    printf 'prefix: ZAVET\nprefix-aliases:\nid-width: 5\n' >"$_d/.zavet/config"
    for _l in "$@"; do printf '%s\n' "$_l" >>"$_d/.zavet/config"; done
    git -C "$_d" add -A
    git -C "$_d" commit -qm "chore: seed"
}

# One JSON row, by slug, out of `zavet specs --json` run in $R.
sdlc_row() { # $1 slug, rest = extra specs flags
    _s=$1
    shift
    (cd "$R" && sh "$Z" specs --json "$@") | grep -F "\"slug\":\"$_s\""
}

# --- config: write_config preserves every line it does not own.
R="$TMP/sdlc-config"
new_repo "$R"
cat >"$R/.zavet/config" <<'EOF'
# hand-written note that must survive
prefix: ZAVET
prefix-aliases:
spec-source: openspec openspec
spec-source: superpowers docs/superpowers src/**
future-key: some value
id-width: 5
EOF
(cd "$R" && sh "$Z" prefix ACME) >/dev/null 2>&1
assert_eq "prefix change keeps spec-source lines, comments and unknown keys" "# hand-written note that must survive
prefix: ACME
prefix-aliases: ZAVET
spec-source: openspec openspec
spec-source: superpowers docs/superpowers src/**
future-key: some value
id-width: 5" "$(cat "$R/.zavet/config")"
assert_eq "retired prefix is still resolved" "ACME ZAVET" "$( (cd "$R" && sh "$Z" prefixes) )"
# A config missing an owned key gets it appended, not the file rewritten.
printf 'prefix: ZAVET\nspec-source: bmad _bmad-output\n' >"$R/.zavet/config"
(cd "$R" && sh "$Z" prefix ACME) >/dev/null 2>&1
assert_eq "missing owned keys are appended" "prefix: ACME
spec-source: bmad _bmad-output
prefix-aliases: ZAVET
id-width: 4" "$(cat "$R/.zavet/config")"
# The empty-aliases case keeps no trailing space (the #22 regression).
R="$TMP/sdlc-config-empty"
new_repo "$R"
rm -rf "$R" && mkdir -p "$R" && git -C "$R" init -q
(cd "$R" && sh "$Z" init --prefix ZAVET) >/dev/null 2>&1
if grep -q '^prefix-aliases:$' "$R/.zavet/config"; then
    pass "empty prefix-aliases has no trailing space"
else
    fail "empty prefix-aliases has no trailing space"
fi

# --- spec_sources: kinds, roots, globs; unknown lines are ignored and reported.
R="$TMP/sdlc-sources"
new_repo "$R"
cat >"$R/.zavet/config" <<'EOF'
prefix: ZAVET
spec-source: openspec openspec
spec-source: openspec ./openspec/
spec-source: speckit specs src/** docs/**   # trailing comment
spec-source: kiro .kiro
spec-source: bmad ../outside
spec-source: bmad /abs
spec-source: openspec open*spec
spec-source: superpowers
  spec-source: superpowers indented
EOF
mkdir -p "$R/openspec/changes" "$R/specs"
assert_eq "spec-source rows: ok kinds, deduped, globs kept" "openspec	openspec	
speckit	specs	src/** docs/**" "$(cd "$R" && sh "$Z" spec-sources | awk -F '\t' '$1 == "source" { print $2 "\t" $3 "\t" $6 }')"
assert_has "unknown kind is reported" "$(cd "$R" && sh "$Z" spec-sources)" "source-unknown-kind	kiro	.kiro"
assert_has "a root escaping the repo is reported" "$(cd "$R" && sh "$Z" spec-sources)" "source-invalid-root	bmad	../outside"
assert_has "a glob character in a root is reported" "$(cd "$R" && sh "$Z" spec-sources)" "source-invalid-root	openspec	open*spec"
assert_has "an absolute root is reported" "$(cd "$R" && sh "$Z" spec-sources)" "source-invalid-root	bmad	/abs"
assert_has "a line with no root is reported" "$(cd "$R" && sh "$Z" spec-sources)" "source-incomplete	superpowers	-"

# --- native specs ride the same JSON, kind zavet.
R="$TMP/sdlc-native"
new_repo "$R"
cat >"$R/.zavet/specs/billing.md" <<'EOF'
---
title: Billing \ core
origin: designed
verified: true
confidence: high
date: 2026-07-01
paths: [billing/**]
---
body
EOF
gc add -A && gc commit -qm "feat: billing spec"
row=$(sdlc_row billing)
assert_has "native row has kind zavet" "$row" '"kind":"zavet"'
assert_has "native title is JSON-escaped" "$row" '"title":"Billing \\ core"'
assert_has "native verified comes from the frontmatter" "$row" '"verified":true'
assert_has "native origin is its own" "$row" '"origin":"designed"'
assert_has "native declared paths" "$row" '"paths":["billing/**"]'
assert_has "native primary is the spec file" "$row" '"primary":".zavet/specs/billing.md"'
assert_has "native rows carry no drift claim" "$row" '"drift":null'
assert_has "native history is filled" "$row" '"firstCommit":"'
if command -v jq >/dev/null 2>&1; then
    if (cd "$R" && sh "$Z" specs --json) | jq -e . >/dev/null 2>&1; then
        pass "specs --json parses as JSON (jq)"
    else
        fail "specs --json parses as JSON (jq)"
    fi
fi

# --- OpenSpec ----------------------------------------------------------------
R="$TMP/sdlc-openspec"
sdlc_repo "$R" openspec 'spec-source: openspec openspec'
row=$(sdlc_row openspec:add-csv-import)
assert_has "openspec: slug, kind, id, root" "$row" '"slug":"openspec:add-csv-import","kind":"openspec","id":"add-csv-import","root":"openspec"'
assert_has "openspec: title from the proposal heading, Change: prefix dropped" "$row" '"title":"Add CSV import"'
assert_has "openspec: origin external, verified false" "$row" '"origin":"external","verified":false'
assert_has "openspec: frameworkVersion from config.yaml" "$row" '"frameworkVersion":"0.9.1"'
assert_has "openspec: a change folder is active" "$row" '"state":"active","nativeState":"changes"'
assert_has "openspec: capabilities are the delta dirs" "$row" '"capabilities":["csv-import","history"]'
assert_has "openspec: primary is the proposal" "$row" '"primary":"openspec/changes/add-csv-import/proposal.md"'
assert_has "openspec: ordinal ids per delta file with scenario counts" "$row" '{"id":"R1","state":"added","scenarios":2,"capability":"csv-import"},{"id":"R2","state":"added","scenarios":1,"capability":"csv-import"},{"id":"R3","state":"modified","scenarios":1,"capability":"csv-import"},{"id":"R4","state":"removed","scenarios":0,"capability":"csv-import"}'
assert_has "openspec: RENAMED is one renamed requirement, not removal plus addition" "$row" '{"id":"R1","state":"renamed","scenarios":0,"capability":"history"},{"id":"R2","state":"added","scenarios":1,"capability":"history"}'
assert_has "openspec: tasks.md checkboxes with their numbers" "$row" '{"id":"1.1","done":true,"story":null,"parallel":false,"status":null},{"id":"1.2","done":false,'
assert_has "openspec: a declared unit starts with no paths" "$row" '"paths":[]'
assert_has "openspec: every unit file has a blob oid" "$row" '"path":"openspec/changes/add-csv-import/design.md","oid":"'
# Archive: the date prefix is dropped, the state is archived, the date is closedOn.
row=$(sdlc_row openspec:fix-date-parse)
assert_has "openspec: archive folder keeps the bare id" "$row" '"slug":"openspec:fix-date-parse"'
assert_has "openspec: archived state" "$row" '"state":"archived","nativeState":"archive"'
assert_has "openspec: closedOn is the archive date" "$row" '"closedOn":"2026-09-30"'
assert_lacks "openspec: no dated slug leaks out" "$(cd "$R" && sh "$Z" specs --json)" '"slug":"openspec:2026-09-30'
# A change with no proposal is unresolved, with the reason and no claims.
row=$(sdlc_row openspec:orphan-change)
assert_has "openspec: missing proposal is unresolved" "$row" '"state":"unresolved"'
assert_has "openspec: the reason is stated" "$row" '"unresolved":"proposal.md missing"'
assert_has "openspec: unresolved rows carry no requirements or tasks" "$row" '"requirements":[],"tasks":[],"drift":null'
assert_eq "openspec: the canonical specs/ tree is never a unit" "3" "$( (cd "$R" && sh "$Z" specs --json) | wc -l | tr -d ' ')"

# Archive rename identity: the same slug before and after `archive`, with the
# unit's history spanning both locations.
R="$TMP/sdlc-archive"
new_repo "$R"
printf 'prefix: ZAVET\nspec-source: openspec openspec\n' >"$R/.zavet/config"
mkdir -p "$R/openspec/changes/add-thing/specs/thing"
printf '# Change: Add thing\n\n## Why\nbecause\n' >"$R/openspec/changes/add-thing/proposal.md"
printf '## ADDED Requirements\n\n### Requirement: Thing\nSHALL\n\n#### Scenario: One\n- **WHEN** x\n' >"$R/openspec/changes/add-thing/specs/thing/spec.md"
gc add -A && gc commit -qm "feat: propose"
c1=$(gc rev-parse HEAD)
before=$(sdlc_row openspec:add-thing)
assert_has "archive identity: active before" "$before" '"state":"active"'
mkdir -p "$R/openspec/changes/archive"
gc mv openspec/changes/add-thing openspec/changes/archive/2026-10-01-add-thing
gc commit -qm "chore: archive add-thing"
c2=$(gc rev-parse HEAD)
after=$(sdlc_row openspec:add-thing)
assert_has "archive identity: same slug, now archived" "$after" '"slug":"openspec:add-thing","kind":"openspec","id":"add-thing"'
assert_has "archive identity: archived state" "$after" '"state":"archived"'
assert_has "archive identity: firstCommit is the proposal commit" "$after" "\"firstCommit\":\"$c1\""
assert_has "archive identity: lastCommit is the archive commit" "$after" "\"lastCommit\":\"$c2\""
assert_eq "archive identity: exactly one row for the unit" "1" "$( (cd "$R" && sh "$Z" specs --json) | wc -l | tr -d ' ')"
# JSON escaping of a hostile title.
printf '# Change: Say "hi" \\ there\n\n## Why\nx\n' >"$R/openspec/changes/archive/2026-10-01-add-thing/proposal.md"
row=$(sdlc_row openspec:add-thing)
assert_has "titles are JSON-escaped (quote and backslash)" "$row" '"title":"Say \"hi\" \\ there"'

# --- Spec Kit ----------------------------------------------------------------
R="$TMP/sdlc-speckit"
sdlc_repo "$R" speckit 'spec-source: speckit specs'
row=$(sdlc_row speckit:001-photo-albums)
assert_has "speckit: slug is the folder name" "$row" '"slug":"speckit:001-photo-albums","kind":"speckit","id":"001-photo-albums"'
assert_has "speckit: title drops the template label" "$row" '"title":"Photo albums"'
assert_has "speckit: frameworkVersion from .specify" "$row" '"frameworkVersion":"0.4.2"'
assert_has "speckit: nativeState is the spec Status line" "$row" '"nativeState":"Draft"'
assert_has "speckit: group is the feature number" "$row" '"group":{"kind":"feature","id":"001"}'
assert_has "speckit: some tasks done is in-progress" "$row" '"state":"in-progress"'
assert_has "speckit: FR lines are requirements, clarification marks one open" "$row" '{"id":"FR-001","state":"declared","scenarios":0,"capability":null},{"id":"FR-002","state":"declared","scenarios":0,"capability":null},{"id":"FR-003","state":"open","scenarios":0,"capability":null}'
assert_has "speckit: task done, parallel and story markers" "$row" '{"id":"T002","done":true,"story":null,"parallel":true,"status":null},{"id":"T012","done":false,"story":"US1","parallel":true,"status":null},{"id":"T013","done":false,"story":"US1","parallel":false,"status":null},{"id":"T014","done":false,"story":"US2","parallel":true,"status":null}'
assert_has "speckit: planned paths come from task lines, as a claim" "$row" '"plannedPaths":["src/albums","src/albums/storage.py","src/models/album.py","src/services/album_service.py"]'
assert_has "speckit: planned paths are never coverage" "$row" '"paths":[]'
assert_has "speckit: planned-untouched drift is counted" "$row" '"drift":{"plannedUntouched":4,"touchedUnplanned":0,"editedWithImplementation":false}'
row=$(sdlc_row speckit:20260918-143000-csv-import)
assert_has "speckit: timestamp-style folders resolve" "$row" '"id":"20260918-143000-csv-import"'
assert_has "speckit: no tasks.md is proposed" "$row" '"state":"proposed"'
assert_has "speckit: timestamp group id" "$row" '"group":{"kind":"feature","id":"20260918-143000"}'
row=$(sdlc_row speckit:002-broken)
assert_has "speckit: a folder with no spec.md is unresolved with the reason" "$row" '"unresolved":"spec.md missing"'
assert_lacks "speckit: a non-feature folder is not a unit" "$(cd "$R" && sh "$Z" specs --json)" 'notes'
assert_lacks "speckit: the constitution is never imported" "$(cd "$R" && sh "$Z" specs --json)" 'constitution'
assert_has "speckit: the constitution is reported, not imported" "$(cd "$R" && sh "$Z" spec-sources)" "constitution	.specify/memory/constitution.md"
# All tasks done is done.
sed 's/\[ \]/[x]/' "$R/specs/001-photo-albums/tasks.md" >"$R/tasks.tmp" && mv "$R/tasks.tmp" "$R/specs/001-photo-albums/tasks.md"
assert_has "speckit: all tasks done is done" "$(sdlc_row speckit:001-photo-albums)" '"state":"done"'

# --- BMAD v6.12 ticket tree --------------------------------------------------
R="$TMP/sdlc-bmad"
sdlc_repo "$R" bmad-612 'spec-source: bmad _bmad-output'
row=$(sdlc_row bmad:epic-cart)
assert_has "bmad: the unit is the epic" "$row" '"slug":"bmad:epic-cart","kind":"bmad","id":"epic-cart"'
assert_has "bmad: title and version" "$row" '"frameworkVersion":"6.12.0","title":"Cart"'
assert_has "bmad: epic status maps verbatim" "$row" '"state":"in-progress","nativeState":"in-progress"'
assert_has "bmad: the initiative is the group" "$row" '"group":{"kind":"initiative","id":"initiative-checkout"}'
assert_has "bmad: risk from the frontmatter" "$row" '"risk":"medium"'
assert_has "bmad: R and E ids under Requirements" "$row" '{"id":"R1","state":"declared","scenarios":0,"capability":null},{"id":"R2","state":"declared","scenarios":0,"capability":null},{"id":"E1","state":"declared","scenarios":0,"capability":null}'
assert_has "bmad: tickets with the story plan status" "$row" '{"id":"story-cart-ui-shell","done":true,"story":null,"parallel":false,"status":"done"},{"id":"story-cart-api","done":false,"story":null,"parallel":false,"status":"review"},{"id":"story-cart-empty-state","done":false,"story":null,"parallel":false,"status":null}'
assert_has "bmad: epic, tickets and story files are the unit" "$row" '"path":"_bmad-output/initiative-checkout/epic-cart/tickets.toml"'
all=$(cd "$R" && sh "$Z" specs --json)
assert_lacks "bmad: the assignee is never emitted" "$all" 'jdoe'
assert_lacks "bmad: the assignee key is never emitted" "$all" 'assignee'
assert_lacks "bmad: standalone backlog tickets are not units" "$all" 'standalone'
assert_has "bmad: absent status is proposed" "$(sdlc_row bmad:epic-payments)" '"state":"proposed","nativeState":null'
assert_has "bmad: high risk" "$(sdlc_row bmad:epic-payments)" '"risk":"high"'
assert_has "bmad: a dropped epic is archived, the word is kept" "$(sdlc_row bmad:epic-dropped)" '"state":"archived","nativeState":"dropped"'
assert_has "bmad: an epic with no epic file is unresolved" "$(sdlc_row bmad:epic-nofile)" '"unresolved":"epic file missing"'
# The store is found through _bmad/custom/config.toml when the declared root is gone.
R="$TMP/sdlc-bmad-config"
sdlc_repo "$R" bmad-612 'spec-source: bmad out-of-date'
assert_has "bmad: output_folder from config.toml is the fallback store" "$(sdlc_row bmad:epic-cart)" '"root":"_bmad-output"'

# --- BMAD legacy sprint-status.yaml -------------------------------------------
R="$TMP/sdlc-bmad-legacy"
sdlc_repo "$R" bmad-legacy 'spec-source: bmad _bmad-output'
row=$(sdlc_row bmad:epic-1)
assert_has "bmad legacy: one unit per epic key" "$row" '"slug":"bmad:epic-1","kind":"bmad","id":"epic-1"'
assert_has "bmad legacy: epic status" "$row" '"state":"in-progress","nativeState":"in-progress"'
assert_has "bmad legacy: stories are tasks, ready-for-dev is ready" "$row" '{"id":"1-1-user-registration","done":true,"story":null,"parallel":false,"status":"done"},{"id":"1-2-login","done":false,"story":null,"parallel":false,"status":"in-progress"},{"id":"1-3-password-reset","done":false,"story":null,"parallel":false,"status":"ready"}'
assert_has "bmad legacy: version from the manifest" "$row" '"frameworkVersion":"6.0.4"'
assert_has "bmad legacy: backlog epic is proposed" "$(sdlc_row bmad:epic-2)" '"state":"proposed","nativeState":"backlog"'
assert_has "bmad legacy: done epic is done" "$(sdlc_row bmad:epic-3)" '"state":"done","nativeState":"done"'
assert_lacks "bmad legacy: retrospectives are not tasks" "$row" 'retrospective'

# --- superpowers --------------------------------------------------------------
R="$TMP/sdlc-superpowers"
sdlc_repo "$R" superpowers 'spec-source: superpowers docs/superpowers'
row=$(sdlc_row superpowers:2026-09-18-csv-import)
assert_has "superpowers: slug drops the -design suffix" "$row" '"slug":"superpowers:2026-09-18-csv-import","kind":"superpowers","id":"2026-09-18-csv-import"'
assert_has "superpowers: title is the document heading" "$row" '"title":"CSV Import Design"'
assert_has "superpowers: a design with a plan is in-progress" "$row" '"state":"in-progress"'
assert_has "superpowers: no requirements are inferred" "$row" '"requirements":[]'
assert_has "superpowers: tasks are the paired plan checkboxes" "$row" '"tasks":[{"id":"1.1","done":true,"story":null,"parallel":false,"status":null},{"id":"1.2","done":true,"story":null,"parallel":false,"status":null},{"id":"2.1","done":false,"story":null,"parallel":false,"status":null},{"id":"2.2","done":false,"story":null,"parallel":false,"status":null}]'
assert_has "superpowers: Files lines are planned paths, line ranges dropped" "$row" '"plannedPaths":["src/import/parser.ts","src/import/parser.test.ts","src/api/upload.ts"]'
assert_has "superpowers: the plan is part of the unit" "$row" '"path":"docs/superpowers/plans/2026-09-19-csv-import.md"'
row=$(sdlc_row superpowers:2026-09-20-orphan)
assert_has "superpowers: a design with no plan is proposed" "$row" '"state":"proposed"'
assert_has "superpowers: and has no tasks" "$row" '"tasks":[]'
assert_lacks "superpowers: an unpaired plan is not a unit" "$(cd "$R" && sh "$Z" specs --json)" 'unpaired'
assert_has "superpowers: an unpaired plan is reported" "$(cd "$R" && sh "$Z" spec-sources)" "unpaired-plan	docs/superpowers/plans/2026-09-01-unpaired.md"
# All checked is done.
sed 's/\[ \]/[x]/' "$R/docs/superpowers/plans/2026-09-19-csv-import.md" >"$R/plan.tmp" && mv "$R/plan.tmp" "$R/docs/superpowers/plans/2026-09-19-csv-import.md"
assert_has "superpowers: all checked is done" "$(sdlc_row superpowers:2026-09-18-csv-import)" '"state":"done"'

# --- --with-text: nothing leaks by default -------------------------------------
R="$TMP/sdlc-text"
sdlc_repo "$R" openspec 'spec-source: openspec openspec'
plain=$(cd "$R" && sh "$Z" specs --json)
for needle in 'CSV file of at most' 'Create the CSV parser' 'Operators re-key' '"text"' '"summary"' '"docs"' 'trackerRefs'; do
    assert_lacks "default output has no text: $needle" "$plain" "$needle"
done
full=$(sdlc_row openspec:add-csv-import --with-text)
assert_has "with-text: requirement text is the heading name" "$full" '"id":"R1","state":"added","scenarios":2,"capability":"csv-import","text":"CSV upload"'
assert_has "with-text: task text" "$full" '"id":"1.1","done":true,"story":null,"parallel":false,"status":null,"text":"Create the CSV parser"'
assert_has "with-text: the Why section is the summary" "$full" '"summary":"Operators re-key spreadsheets by hand.'
assert_has "with-text: primary documents travel as markdown" "$full" '"docs":[{"path":"openspec/changes/add-csv-import/proposal.md","md":"# Change: Add CSV import\n'
assert_has "with-text: renamed requirements read old -> new" "$full" '"text":"Import log -> Import history"'
R2="$TMP/sdlc-text-bmad"
sdlc_repo "$R2" bmad-612 'spec-source: bmad _bmad-output'
R=$R2
full=$(sdlc_row bmad:epic-cart --with-text)
assert_has "with-text: tracker refs only here" "$full" '"trackerRefs":["PROJ-42"]'
assert_has "with-text: the epic Description is the summary" "$full" '"summary":"Shoppers collect items before paying."'
assert_lacks "with-text: the assignee still never travels" "$full" 'jdoe'
if (cd "$R" && sh "$Z" specs --with-text) >/dev/null 2>&1; then
    fail "--with-text without --json is refused"
else
    pass "--with-text without --json is refused"
fi
if command -v jq >/dev/null 2>&1; then
    if (cd "$R" && sh "$Z" specs --json --with-text) | jq -e . >/dev/null 2>&1; then
        pass "specs --json --with-text parses as JSON (jq)"
    else
        fail "specs --json --with-text parses as JSON (jq)"
    fi
fi

# --- plain TSV ---------------------------------------------------------------
R="$TMP/sdlc-openspec"
tsv=$(cd "$R" && sh "$Z" specs)
assert_has "plain specs lists source units" "$tsv" "openspec:add-csv-import	external	-		Add CSV import"
assert_has "plain specs reports unresolved units with the reason" "$tsv" "openspec:orphan-change	external	unresolved		proposal.md missing"

# --- accretion, comma trailers, and the per-slug trailer grammar ----------------
R="$TMP/sdlc-accrete"
sdlc_repo "$R" superpowers 'spec-source: superpowers docs/superpowers'
cat >"$R/.zavet/specs/native-one.md" <<'EOF'
---
title: Native one
origin: session
confidence: high
date: 2026-07-01
paths: [lib/**]
---
body
EOF
mkdir -p "$R/src/import" "$R/src/api" "$R/lib"
echo a >"$R/src/import/parser.ts"
echo b >"$R/src/api/other.ts"
gc add -A
S=superpowers:2026-09-18-csv-import
assert_has "paths are learned, never guessed: none before a citing commit" "$(sdlc_row $S)" '"paths":[]'
gc commit -qm "feat: parser" -m "Spec: native-one, superpowers:2026-09-18-csv-import"
assert_eq "a comma list accretes for every value" "$S	src/api/other.ts
$S	src/import/parser.ts" "$( (cd "$R" && sh "$Z" spec-paths) | grep -F "$S" | sort )"
assert_has "accreted paths are in the JSON row" "$(sdlc_row $S)" '"paths":["src/api/other.ts","src/import/parser.ts"]'
assert_has "touched-not-planned is counted" "$(sdlc_row $S)" '"touchedUnplanned":1,'
assert_eq "spec-match answers for an accreted path" "$S" "$(echo src/import/parser.ts | (cd "$R" && sh "$Z" spec-match))"
assert_eq "an uncited path matches nothing" "" "$(echo src/import/never.ts | (cd "$R" && sh "$Z" spec-match))"
memo=$(find "$R/.git" -maxdepth 1 -name 'zavet-accrete*' | head -1)
if [ -n "$memo" ]; then pass "accretion is memoized beside the repo"; else fail "accretion is memoized beside the repo"; fi
head1=$(gc rev-parse HEAD)
assert_eq "the memo records the HEAD it covers" "#zavet-head $head1" "$(head -n 1 "$memo")"
echo c >"$R/src/import/second.ts"
gc add -A && gc commit -qm "feat: second" -m "Spec: $S"
assert_has "a new HEAD re-walks and sees the new commit" "$( (cd "$R" && sh "$Z" spec-paths) )" "$S	src/import/second.ts"
assert_eq "one memo per worktree, advanced to the new HEAD" "1:#zavet-head $(gc rev-parse HEAD)" "$(find "$R/.git" -maxdepth 1 -name 'zavet-accrete*' | wc -l | tr -d ' '):$(head -n 1 "$memo")"

# Gate: the trailer must NAME the spec. Native specs get the same rule.
printf 'x\n' >"$R/lib/l.rs"
out=$(printf 'lib/l.rs\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x"))
rc=$?
assert_eq "gate nags a covered native path with no trailer" "1" "$rc"
out=$(printf 'lib/l.rs\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x

Spec: native-one"))
assert_eq "gate: a trailer naming the spec satisfies it" "0:" "$?:$out"
out=$(printf 'lib/l.rs\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x

Spec: some-other-spec"))
assert_eq "gate: a trailer for ANOTHER spec no longer satisfies (latent bug fixed)" "1" "$?"
out=$(printf 'lib/l.rs\nsrc/import/parser.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x

Spec: native-one"))
assert_eq "gate: citing one of two covering specs still owes the other" "1" "$?"
assert_has "gate: and names the owed one" "$out" "$S"
out=$(printf 'lib/l.rs\nsrc/import/parser.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x

Spec: native-one, $S"))
assert_eq "gate: a comma list names both" "0:" "$?:$out"
out=$(printf 'lib/l.rs\nsrc/import/parser.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x
Spec:   native-one ,   $S  "))
assert_eq "gate: whitespace around comma values is tolerated" "0:" "$?:$out"
# The nudge for a source unit asks for the trailer only.
out=$(printf 'src/import/parser.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x"))
assert_has "gate: source nudge asks for the trailer" "$out" "Add a \`Spec: $S\` trailer"
assert_has "gate: source nudge says the unit is read-only" "$out" "read-only here"
assert_lacks "gate: source nudge never asks to update the spec" "$out" "update the sections"
assert_lacks "gate: source nudge never asks to stage the spec file" "$out" "stage the spec file"
# Once per session, like the native nudge.
sess="sdlc-$$"
rm -f "${TMPDIR:-/tmp}/zavet-spec-shown-$sess"
printf 'src/import/parser.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x" --session "$sess") >/dev/null
out=$(printf 'src/import/parser.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x" --session "$sess"))
assert_eq "gate: second nudge in one session is silent" "0:" "$?:$out"
rm -f "${TMPDIR:-/tmp}/zavet-spec-shown-$sess"

# check: the same rule over commits.
base=$(gc rev-parse HEAD)
echo d >>"$R/lib/l.rs" && gc add -A && gc commit -qm "feat: cites the wrong spec" -m "Spec: some-other-spec"
echo e >>"$R/lib/l.rs" && gc add -A && gc commit -qm "feat: cites the right spec" -m "Spec: native-one"
echo f >>"$R/src/import/parser.ts" && gc add -A && gc commit -qm "feat: cites the unit in a list" -m "Spec: native-one, $S"
echo g >>"$R/src/import/parser.ts" && gc add -A && gc commit -qm "feat: cites nothing"
out=$( (cd "$R" && sh "$Z" check "$base..HEAD" 2>/dev/null) )
assert_eq "check: only commits not naming the covering spec warn" "warn-spec	native-one	feat: cites the wrong spec
warn-spec	$S	feat: cites nothing" "$(printf '%s\n' "$out" | awk -F '\t' '{ print $1 "\t" $3 "\t" $4 }' | sort)"

# --- memo is optional: an unwritable git dir fails open -------------------------
R="$TMP/sdlc-accrete"
chmod a-w "$R/.git"
rm -f "$R"/.git/zavet-accrete* 2>/dev/null
out=$( (cd "$R" && sh "$Z" spec-paths 2>/dev/null) )
rc=$?
chmod u+w "$R/.git"
assert_eq "unwritable memo location still answers" "0" "$rc"
assert_has "and the answer is the same" "$out" "$S	src/import/parser.ts"

# --- read-only invariants ----------------------------------------------------------
R="$TMP/sdlc-readonly"
sdlc_repo "$R" openspec 'spec-source: openspec openspec' 'spec-source: superpowers docs/superpowers'
cp -R "$SDLC/superpowers/docs" "$R/" && gc add -A && gc commit -qm "chore: add superpowers" >/dev/null
cat >"$R/.zavet/decisions/ZAVET-00001-first.md" <<'EOF'
---
id: ZAVET-00001
title: First
status: active
guards: [guarded/**]
---
body
EOF
printf -- '---\ntitle: N\norigin: session\nconfidence: high\ndate: 2026-07-01\npaths: [nat/**]\n---\nsee ZAVET-00001\n' >"$R/.zavet/specs/nat.md"
gc add -A && gc commit -qm "chore: records" >/dev/null
digest() { (cd "$R" && find openspec docs -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(git hash-object "$f")"; done); }
before=$(digest)
(cd "$R" && sh "$Z" renumber --force ZAVET-00001 ZAVET-00009) >/dev/null 2>&1
(cd "$R" && sh "$Z" index) >/dev/null 2>&1
(cd "$R" && sh "$Z" audit) >/dev/null 2>&1
(cd "$R" && sh "$Z" specs --json --with-text) >/dev/null 2>&1
(cd "$R" && sh "$Z" adapters) >/dev/null 2>&1
assert_eq "renumber, index, audit, specs and adapters never write into a source root" "$before" "$(digest)"
assert_eq "the native spec WAS rewritten by renumber (the control)" "see ZAVET-00009" "$(tail -1 "$R/.zavet/specs/nat.md")"
# A staged source file never satisfies the gate or the check.
S=openspec:add-csv-import
echo y >"$R/src.txt"
(cd "$R" && sh "$Z" prefix ZAVET) >/dev/null 2>&1
mkdir -p "$R/lib"
echo 1 >"$R/lib/impl.ts"
gc add -A && gc commit -qm "feat: impl" -m "Spec: $S" >/dev/null
out=$(printf 'lib/impl.ts\nopenspec/changes/add-csv-import/tasks.md\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: more"))
assert_eq "gate: staging the unit's own files does not satisfy it" "1" "$?"
assert_has "gate: still asks for the trailer" "$out" "Add a \`Spec: $S\` trailer"
base=$(gc rev-parse HEAD)
echo 2 >>"$R/lib/impl.ts"
echo '- [x] 1.2 done' >>"$R/openspec/changes/add-csv-import/tasks.md"
gc add -A && gc commit -qm "feat: edits the spec files alongside" >/dev/null
out=$( (cd "$R" && sh "$Z" check "$base..HEAD" 2>/dev/null) )
assert_has "check: touching the unit's files is not an exemption" "$out" "warn-spec"
# The context payload never tells an agent to update a source spec.
ctx=$(cd "$R" && sh "$Z" context)
assert_has "context: names the declared source kinds" "$ctx" "### Spec sources (read-only: cite them, never edit them)"
assert_has "context: lists active units with task counts" "$ctx" "- openspec:add-csv-import — Add CSV import (tasks "
assert_has "context: says to cite the unit" "$ctx" 'Spec: <kind>:<id>'
assert_has "context: scopes spec maintenance to .zavet/specs" "$ctx" "covers .zavet/specs/ only"
assert_lacks "context: no unit is listed as a living spec to maintain" "$(printf '%s\n' "$ctx" | awk '/^### Living specs/,/^Capture bar/')" "openspec:"
agents=$(cd "$R" && sh "$Z" adapters >/dev/null 2>&1; cat AGENTS.md)
assert_has "AGENTS.md carries the stable source section" "$agents" "- openspec in openspec"
assert_lacks "AGENTS.md carries no churning unit list" "$agents" "add-csv-import"

# --- audit drift classes ---------------------------------------------------------------
R="$TMP/sdlc-audit"
sdlc_repo "$R" superpowers 'spec-source: superpowers docs/superpowers'
S=superpowers:2026-09-18-csv-import
audit=$(cd "$R" && sh "$Z" audit | grep -v '^adapter-\|^githook')
assert_has "audit: a unit with no accreted or declared path says so" "$audit" "paths-none-yet	$S"
assert_has "audit: the orphan design too" "$audit" "paths-none-yet	superpowers:2026-09-20-orphan"
assert_lacks "audit: no planned-not-touched without a citing commit" "$audit" "planned-not-touched"
mkdir -p "$R/src/import"
echo 1 >"$R/src/import/parser.ts"
echo 2 >"$R/src/import/extra.ts"
gc add -A && gc commit -qm "feat: parser" -m "Spec: $S" >/dev/null
audit=$(cd "$R" && sh "$Z" audit | grep -v '^adapter-\|^githook')
assert_has "audit: planned files nothing touched" "$audit" "planned-not-touched	$S	2	src/import/parser.test.ts,src/api/upload.ts"
assert_has "audit: touched files nobody planned" "$audit" "touched-not-planned	$S	1"
assert_lacks "audit: a unit with paths is not paths-none-yet" "$audit" "paths-none-yet	$S"
assert_lacks "audit: no edit-with-implementation yet" "$audit" "source-spec-edited-in-implementing-change"
echo 3 >>"$R/src/import/parser.ts"
echo '' >>"$R/docs/superpowers/specs/2026-09-18-csv-import-design.md"
gc add -A && gc commit -qm "feat: parser again and a design edit" -m "Spec: $S" >/dev/null
sha7=$(gc rev-parse --short=7 HEAD)
audit=$(cd "$R" && sh "$Z" audit | grep -v '^adapter-\|^githook')
assert_has "audit: the spec edited in the implementing commit" "$audit" "source-spec-edited-in-implementing-change	$S	$sha7"
# A commit that edits only the checkboxes with code is not that signature.
R2="$TMP/sdlc-audit-tasks"
sdlc_repo "$R2" superpowers 'spec-source: superpowers docs/superpowers'
mkdir -p "$R2/src/import"
echo 1 >"$R2/src/import/parser.ts"
sed 's/\[ \]/[x]/' "$R2/docs/superpowers/plans/2026-09-19-csv-import.md" >"$R2/p.tmp" && mv "$R2/p.tmp" "$R2/docs/superpowers/plans/2026-09-19-csv-import.md"
git -C "$R2" add -A && git -C "$R2" commit -qm "feat: parser, boxes ticked" -m "Spec: $S"
assert_lacks "audit: ticking plan checkboxes alongside code is not a spec edit" "$(cd "$R2" && sh "$Z" audit)" "source-spec-edited"
# stale-spec for a source unit anchors on its own files and ignores citing commits.
R3="$TMP/sdlc-audit-stale"
sdlc_repo "$R3" superpowers 'spec-source: superpowers docs/superpowers'
mkdir -p "$R3/src"
echo 1 >"$R3/src/a.ts"
git -C "$R3" add -A && git -C "$R3" commit -qm "feat: a" -m "Spec: $S"
assert_lacks "audit: commits citing the unit are not stale drift" "$(cd "$R3" && sh "$Z" audit)" "stale-spec"
echo 2 >>"$R3/src/a.ts"
git -C "$R3" commit -qam "feat: a again, uncited"
assert_has "audit: an uncited commit on the unit's paths is stale drift" "$(cd "$R3" && sh "$Z" audit)" "stale-spec	$S	1	"
# Unresolved units are reported.
assert_has "audit: unresolved units are reported" "$(cd "$TMP/sdlc-openspec" && sh "$Z" audit)" "source-unresolved	openspec:orphan-change	proposal.md missing"

# --- declared globs are coverage, from the config line ----------------------------------
R="$TMP/sdlc-declared"
sdlc_repo "$R" superpowers 'spec-source: superpowers docs/superpowers src/import/** lib/*.rs'
assert_eq "declared globs cover every unit under the source" "superpowers:2026-09-18-csv-import" \
    "$(echo src/import/x.ts | (cd "$R" && sh "$Z" spec-match) | sort | head -1)"
assert_has "declared globs show up in the JSON paths" "$(sdlc_row superpowers:2026-09-18-csv-import)" '"paths":["src/import/**","lib/*.rs"]'

# --- detection and adoption -----------------------------------------------------------------
R="$TMP/sdlc-detect"
new_repo "$R"
printf 'prefix: ZAVET\n# keep me\n' >"$R/.zavet/config"
mkdir -p "$R/openspec/changes" "$R/.specify" "$R/specs" "$R/_bmad/custom" "$R/docs/superpowers/specs"
printf '[core]\noutput_folder = "{project-root}/planning-out"\n' >"$R/_bmad/custom/config.toml"
mkdir -p "$R/planning-out"
det=$(cd "$R" && sh "$Z" spec-sources --detect)
assert_eq "detect finds every framework, each marked new" "detect	openspec	openspec	new
detect	speckit	specs	new
detect	bmad	planning-out	new
detect	superpowers	docs/superpowers	new" "$det"
assert_eq "detect alone writes nothing" "prefix: ZAVET
# keep me" "$(cat "$R/.zavet/config")"
(cd "$R" && sh "$Z" spec-sources --write) >/dev/null
assert_eq "write appends the missing lines and keeps the rest" "prefix: ZAVET
# keep me
spec-source: openspec openspec
spec-source: speckit specs
spec-source: bmad planning-out
spec-source: superpowers docs/superpowers" "$(cat "$R/.zavet/config")"
assert_eq "write is idempotent" "0" "$( (cd "$R" && sh "$Z" spec-sources --write | grep -c '^written') )"
printf 'spec-source: openspec openspec' >"$R/.zavet/config"
(cd "$R" && sh "$Z" spec-sources --write) >/dev/null
assert_eq "write repairs a config with no final newline" "spec-source: openspec openspec
spec-source: speckit specs
spec-source: bmad planning-out
spec-source: superpowers docs/superpowers" "$(cat "$R/.zavet/config")"
# init adopts what is already there.
R="$TMP/sdlc-init"
rm -rf "$R" && mkdir -p "$R/openspec/changes" "$R/docs/superpowers"
git -C "$R" init -q
git -C "$R" config user.email zavet-test@example.invalid
git -C "$R" config user.name "zavet test"
out=$( (cd "$R" && sh "$Z" init --prefix ZAVET) 2>&1 )
assert_has "init declares detected spec sources" "$out" "declared spec source openspec openspec"
assert_has "init keeps the scaffolded keys" "$(cat "$R/.zavet/config")" "prefix: ZAVET"
assert_has "init wrote the source line" "$(cat "$R/.zavet/config")" "spec-source: superpowers docs/superpowers"
R="$TMP/sdlc-init-plain"
rm -rf "$R" && mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email zavet-test@example.invalid
git -C "$R" config user.name "zavet test"
assert_lacks "init with no frameworks says nothing about sources" "$( (cd "$R" && sh "$Z" init --prefix ZAVET) 2>&1 )" "spec source"

# --- a repo with no spec-source lines pays nothing and changes nothing --------------------------
R="$TMP/sdlc-none"
new_repo "$R"
printf -- '---\ntitle: N\norigin: session\nconfidence: high\ndate: 2026-07-01\npaths: [nat/**]\n---\nb\n' >"$R/.zavet/specs/nat.md"
assert_eq "no sources: spec-paths is exactly the native table" "nat	nat/**" "$( (cd "$R" && sh "$Z" spec-paths) )"
assert_eq "no sources: specs TSV is exactly the native rows" "nat	session	high	2026-07-01	N" "$( (cd "$R" && sh "$Z" specs) )"
assert_eq "no sources: nothing in git dir" "" "$(find "$R/.git" -maxdepth 1 -name 'zavet-*')"
assert_eq "no sources: spec-sources reports nothing" "" "$( (cd "$R" && sh "$Z" spec-sources) )"

# --- accretion and history memos: incremental, per worktree, never poisoned ---------------------
R="$TMP/sdlc-incr"
sdlc_repo "$R" superpowers 'spec-source: superpowers docs/superpowers'
S=superpowers:2026-09-18-csv-import
mkdir -p "$R/src"
n=0
while [ "$n" -lt 4 ]; do
    n=$((n + 1))
    echo "$n" >"$R/src/f$n.ts"
    gc add -A && gc commit -qm "feat: f$n" -m "Spec: $S"
done
(cd "$R" && sh "$Z" specs --json) >/dev/null
memo="$R/.git/zavet-accrete.memo"
hist=$(find "$R/.git" -maxdepth 1 -name 'zavet-unithist-*.memo' | head -1)
assert_eq "incremental: the memo covers HEAD" "#zavet-head $(gc rev-parse HEAD)" "$(head -n 1 "$memo")"
echo 5 >"$R/src/f5.ts"
gc add -A && gc commit -qm "feat: f5" -m "Spec: $S"
echo 6 >>"$R/docs/superpowers/specs/2026-09-18-csv-import-design.md"
gc add -A && gc commit -qm "docs: design edit"
(cd "$R" && sh "$Z" specs --json) >"$TMP/incr.json"
cp "$memo" "$TMP/incr.acc"
cp "$hist" "$TMP/incr.hist"
rm -f "$R"/.git/zavet-accrete* "$R"/.git/zavet-unithist*
(cd "$R" && sh "$Z" specs --json) >"$TMP/full.json"
assert_file "incremental: the accretion memo is byte-identical to a full rebuild" "$memo" "$TMP/incr.acc"
sort "$(find "$R/.git" -maxdepth 1 -name 'zavet-unithist-*.memo' | head -1)" >"$TMP/full.hist.sorted"
sort "$TMP/incr.hist" >"$TMP/incr.hist.sorted"
assert_file "incremental: the history memo holds the same rows as a full rebuild" "$TMP/full.hist.sorted" "$TMP/incr.hist.sorted"
assert_file "incremental: specs --json is unchanged by the memo path" "$TMP/full.json" "$TMP/incr.json"
assert_lacks "oid: a committed regular file never has a null oid" "$(cat "$TMP/full.json")" '"oid":null'
# A stage failure must surface as a non-zero exit, never as an empty list.
mkdir -p "$TMP/failbin"
realawk=$(command -v awk)
# shellcheck disable=SC2016 # the generated script must keep its own $@ literal
printf '#!/bin/sh\nfor a in "$@"; do\n    [ "$a" = mode=json ] && exit 2\ndone\nexec "%s" "$@"\n' "$realawk" >"$TMP/failbin/awk"
chmod +x "$TMP/failbin/awk"
out=$( (cd "$R" && PATH="$TMP/failbin:$PATH" sh "$Z" specs --json 2>/dev/null) )
rc=$?
if [ "$rc" -ne 0 ]; then pass "specs --json: a failing emit stage exits non-zero"; else fail "specs --json: a failing emit stage exits non-zero"; fi
assert_eq "specs --json: and prints no partial list" "" "$out"
# A history rewrite (HEAD no longer descends from the memo) rebuilds.
gc reset -q --hard HEAD~1
echo 7 >"$R/src/f7.ts"
gc add -A && gc commit -qm "feat: f7" -m "Spec: $S"
assert_has "rewrite: the rebuilt table has the new commit" "$( (cd "$R" && sh "$Z" spec-paths) )" "$S	src/f7.ts"
assert_eq "rewrite: and the memo covers the new HEAD" "#zavet-head $(gc rev-parse HEAD)" "$(head -n 1 "$memo")"
# One memo per worktree: a linked worktree neither reads nor clobbers the main one.
gc worktree add -q -b wt-branch "$TMP/sdlc-incr-wt" >/dev/null 2>&1
mainhead=$(head -n 1 "$memo")
(cd "$TMP/sdlc-incr-wt" && sh "$Z" spec-paths) >/dev/null
assert_eq "worktree: the main memo is untouched" "$mainhead" "$(head -n 1 "$memo")"
wtmemo=$(find "$R/.git/worktrees" -name 'zavet-accrete.memo' | head -1)
if [ -n "$wtmemo" ]; then pass "worktree: it keeps its own memo in its own git dir"; else fail "worktree: it keeps its own memo in its own git dir"; fi
gc worktree remove --force "$TMP/sdlc-incr-wt" >/dev/null 2>&1
# Memos nobody touched for a week are pruned when a new one is written.
touch -t 202001010000 "$R/.git/zavet-accrete-0123456789abcdef" "$R/.git/zavet-unithist-0123-4567"
echo 8 >"$R/src/f8.ts"
gc add -A && gc commit -qm "feat: f8" -m "Spec: $S"
(cd "$R" && sh "$Z" spec-paths) >/dev/null
assert_eq "stale memos older than a week are pruned" "" "$(find "$R/.git" -maxdepth 1 \( -name 'zavet-accrete-0123*' -o -name 'zavet-unithist-0123*' \))"
# A failed `git log` must not leave a poisoned (empty) memo behind.
R="$TMP/sdlc-poison"
sdlc_repo "$R" superpowers 'spec-source: superpowers docs/superpowers'
mkdir -p "$R/src" "$TMP/fakebin"
echo 1 >"$R/src/a.ts"
gc add -A && gc commit -qm "feat: a" -m "Spec: $S"
realgit=$(command -v git)
# shellcheck disable=SC2016 # the generated script must keep its own $@ literal
printf '#!/bin/sh\nfor a in "$@"; do\n    [ "$a" = log ] && exit 3\ndone\nexec "%s" "$@"\n' "$realgit" >"$TMP/fakebin/git"
chmod +x "$TMP/fakebin/git"
(cd "$R" && PATH="$TMP/fakebin:$PATH" sh "$Z" spec-paths) >/dev/null
rc=$?
assert_eq "git log failure: still answers (fail open)" "0" "$rc"
assert_eq "git log failure: no memo is written" "" "$(find "$R/.git" -maxdepth 1 \( -name 'zavet-accrete*' -o -name 'zavet-unithist*' \))"
assert_has "git log working again: the table is complete" "$( (cd "$R" && sh "$Z" spec-paths) )" "$S	src/a.ts"

# --- archived and removed units keep only accreted paths -----------------------------------------
R="$TMP/sdlc-archived"
new_repo "$R"
printf 'prefix: ZAVET\nspec-source: openspec openspec src/**\n' >"$R/.zavet/config"
mkdir -p "$R/openspec/changes/live" "$R/openspec/changes/archive/2026-10-01-old" "$R/src"
printf '# Change: Live\n\n## Why\nx\n' >"$R/openspec/changes/live/proposal.md"
printf '# Change: Old\n\n## Why\nx\n' >"$R/openspec/changes/archive/2026-10-01-old/proposal.md"
echo 1 >"$R/src/a.ts"
gc add -A && gc commit -qm "feat: seed" -m "Spec: openspec:old"
paths=$( (cd "$R" && sh "$Z" spec-paths) )
assert_has "archived: the live unit still claims the declared glob" "$paths" "openspec:live	src/**"
assert_lacks "archived: the archived unit does not claim the declared glob" "$paths" "openspec:old	src/**"
assert_has "archived: but keeps what its own commits touched" "$paths" "openspec:old	src/a.ts"

# --- the gate nudge names at most five slugs ------------------------------------------------------
R="$TMP/sdlc-cap"
new_repo "$R"
printf 'prefix: ZAVET\nspec-source: openspec openspec src/**\n' >"$R/.zavet/config"
n=0
while [ "$n" -lt 8 ]; do
    n=$((n + 1))
    mkdir -p "$R/openspec/changes/u$n"
    printf '# Change: U%s\n\n## Why\nx\n' "$n" >"$R/openspec/changes/u$n/proposal.md"
done
gc add -A && gc commit -qm "chore: units"
out=$(printf 'src/x.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x"))
assert_has "cap: names the first five and the rest as a count" "$out" "openspec:u1 openspec:u2 openspec:u3 openspec:u4 openspec:u5 +3 more"
assert_lacks "cap: and not the sixth" "$out" "openspec:u6"
assert_has "cap: the trailer hint is capped the same way" "$out" "Spec: openspec:u1, openspec:u2, openspec:u3, openspec:u4, openspec:u5, +3 more"

# --- never read through a symlink ------------------------------------------------------------------
R="$TMP/sdlc-symlink"
new_repo "$R"
printf 'prefix: ZAVET\nspec-source: openspec openspec\n' >"$R/.zavet/config"
mkdir -p "$R/openspec/changes/linked" "$R/openspec/changes/plain" "$TMP/outside"
printf '# Change: SECRET-OUTSIDE\n\n## Why\nTOPSECRET\n' >"$TMP/outside/proposal.md"
ln -s "$TMP/outside/proposal.md" "$R/openspec/changes/linked/proposal.md"
printf '# Change: Plain\n\n## Why\nfine\n' >"$R/openspec/changes/plain/proposal.md"
gc add -A && gc commit -qm "chore: seed"
all=$(cd "$R" && sh "$Z" specs --json --with-text)
assert_lacks "symlink: the outside file's text never leaves" "$all" "TOPSECRET"
assert_lacks "symlink: nor its title" "$all" "SECRET-OUTSIDE"
assert_has "symlink: the regular file still reads" "$all" "fine"
assert_lacks "symlink: the link is not a listed file" "$(printf '%s\n' "$all" | grep -F '"slug":"openspec:linked"')" 'linked/proposal.md'
# A directory that escapes the repo is skipped as well.
mkdir -p "$TMP/outside-dir"
printf '# Change: ESCAPED\n\n## Why\nTOPSECRET2\n' >"$TMP/outside-dir/proposal.md"
rm -rf "$R/openspec/changes/plain"
ln -s "$TMP/outside-dir" "$R/openspec/changes/plain"
all=$(cd "$R" && sh "$Z" specs --json --with-text)
assert_lacks "symlink: a linked directory outside the repo is not read" "$all" "TOPSECRET2"

# --- trailer grammar: CRLF, uppercase and plus in ids --------------------------------------------
R="$TMP/sdlc-grammar"
new_repo "$R"
printf 'prefix: ZAVET\nspec-source: superpowers docs/superpowers src/**\n' >"$R/.zavet/config"
printf -- '---\ntitle: N\norigin: session\nconfidence: high\ndate: 2026-07-01\npaths: [lib/**]\n---\nb\n' >"$R/.zavet/specs/native-one.md"
mkdir -p "$R/docs/superpowers/specs" "$R/src" "$R/lib"
printf '# Design\n\n## Summary\nleft\tright\n' >"$R/docs/superpowers/specs/2026-10-01-Upper+Plus-design.md"
gc add -A && gc commit -qm "chore: seed"
U=superpowers:2026-10-01-Upper+Plus
out=$(printf 'lib/l.rs\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "$(printf 'feat: x\n\nSpec: native-one\r')"))
assert_eq "crlf: a CRLF message satisfies the trailer" "0:" "$?:$out"
out=$(printf 'src/a.ts\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "$(printf 'feat: x\n\nSpec: %s\r' "$U")"))
assert_eq "uppercase and plus: an id from a file name is a valid slug" "0:" "$?:$out"
echo 1 >"$R/src/a.ts"
printf 'feat: a\n\nSpec: %s\r\n' "$U" >"$TMP/crlf.msg"
gc add -A && gc commit -q -F "$TMP/crlf.msg"
assert_has "crlf and uppercase: the accretion keeps the path" "$( (cd "$R" && sh "$Z" spec-paths) )" "$U	src/a.ts"
assert_lacks "plus: the citing commit is not stale drift (regex metacharacters are escaped)" "$(cd "$R" && sh "$Z" audit)" "stale-spec"
assert_has "tabs in a summary do not split the stream" "$(cd "$R" && sh "$Z" specs --json --with-text | grep -F '"slug":"superpowers:2026-10-01-Upper+Plus"')" '"summary":"left right"'
# A native title holding a tab keeps the TSV columns where they are.
printf -- '---\ntitle: tab\there\norigin: session\nconfidence: high\ndate: 2026-07-01\npaths: [lib/**]\n---\nb\n' >"$R/.zavet/specs/tabbed.md"
assert_eq "tabs in a native title do not shift the columns" "5" "$( (cd "$R" && sh "$Z" specs) | grep '^tabbed' | awk -F '\t' '{ print NF }')"

# --- gate details: quotepath, fixed-string session memory -----------------------------------------
R="$TMP/sdlc-gate"
new_repo "$R"
printf 'prefix: ZAVET\n' >"$R/.zavet/config"
printf -- '---\ntitle: Docs\norigin: session\nconfidence: high\ndate: 2026-07-01\npaths: [docs/**]\n---\nb\n' >"$R/.zavet/specs/docs-spec.md"
gc add -A && gc commit -qm "chore: seed"
mkdir -p "$R/docs"
echo x >"$R/docs/caf$(printf '\303\251').md"
gc add -A
out=$(cd "$R" && sh "$Z" gate --staged --message "feat: x")
assert_eq "gate --staged sees a non-ASCII path unquoted" "1" "$?"
assert_has "gate --staged names the covering spec" "$out" "docs-spec"
printf -- '---\ntitle: V1\norigin: session\nconfidence: high\ndate: 2026-07-01\npaths: [lib/**]\n---\nb\n' >"$R/.zavet/specs/v1x2.md"
printf -- '---\ntitle: V1b\norigin: session\nconfidence: high\ndate: 2026-07-01\npaths: [lib/**]\n---\nb\n' >"$R/.zavet/specs/v1.2.md"
sess="fixed-$$"
printf 'v1x2\n' >"${TMPDIR:-/tmp}/zavet-spec-shown-$sess"
out=$(printf 'lib/l.rs\n' | (cd "$R" && sh "$Z" gate --paths-from - --message "feat: x" --session "$sess"))
assert_has "session memory compares slugs literally (v1x2 does not hide v1.2)" "$out" "v1.2"
rm -f "${TMPDIR:-/tmp}/zavet-spec-shown-$sess"

# --- spec-sources --write refuses a root it cannot write unambiguously ----------------------------
R="$TMP/sdlc-badroot"
new_repo "$R"
printf 'prefix: ZAVET\n' >"$R/.zavet/config"
mkdir -p "$R/_bmad/custom" "$R/my out"
printf '[core]\noutput_folder = "{project-root}/my out"\n' >"$R/_bmad/custom/config.toml"
out=$(cd "$R" && sh "$Z" spec-sources --write)
assert_has "write: a root with whitespace is reported invalid" "$out" "source-root-invalid	bmad	my out"
assert_lacks "write: and never written" "$(cat "$R/.zavet/config")" "spec-source"

# ----------------------------------------------------------- rule sources --
printf -- '-- rule sources\n'
# The rule rows of `spec-sources --json`, and the Framework rules section of
# the hook and file context forms, run in $R.
rule_json() { (cd "$R" && sh "$Z" spec-sources --json) | grep '"type":"rule-source"'; }
rule_hook() { (cd "$R" && sh "$Z" context) | sed -n '/^### Framework rules/,/stop and ask/p'; }
# Replace every .zavet/config line of $R matching $1 (a grep pattern) with $2.
set_cfg_line() { # $1 pattern, $2 new line
    printf '%s\n' "$2" >"$R/c.tmp"
    grep -v -- "$1" "$R/.zavet/config" >>"$R/c.tmp"
    mv "$R/c.tmp" "$R/.zavet/config"
}

# --- Spec Kit: on by default once the framework is linked ---------------------
R="$TMP/rule-speckit"
sdlc_repo "$R" speckit 'spec-source: speckit specs'
row=$(rule_json)
assert_has "speckit rule: on by default, no extra config line" "$row" '"kind":"speckit-constitution","path":".specify/memory/constitution.md","source":"default","enabled":true'
assert_has "speckit rule: version and dates from the footer" "$row" '"version":"1.2.0","ratified":"2026-06-01","lastAmended":"2026-09-10","ruleCount":2'
assert_has "speckit rule: external and never verified" "$row" '"origin":"external","verified":false,"state":"ok"'
assert_has "speckit rule: the blob oid fingerprints the file" "$row" "\"oid\":\"$(git -C "$R" hash-object .specify/memory/constitution.md)\""
assert_lacks "speckit rule: --json carries no rule text" "$row" 'Test first'
assert_has "speckit rule: a spec-source row sits beside it" "$( (cd "$R" && sh "$Z" spec-sources --json) )" '{"v":1,"type":"spec-source","kind":"speckit","root":"specs","globs":[],"state":"ok","units":3,"unresolved":1}'
assert_has "speckit rule: report row" "$( (cd "$R" && sh "$Z" spec-sources) )" "rule-source	speckit-constitution	.specify/memory/constitution.md	ok	1.2.0	2026-09-10"
ctx=$(rule_hook)
assert_has "speckit rule: hook context labels the source" "$ctx" '- .specify/memory/constitution.md (Spec Kit constitution, v1.2.0, amended 2026-09-10)'
assert_has "speckit rule: hook context quotes the principles" "$ctx" '> ### I. Test first'
assert_lacks "speckit rule: the H1 is dropped" "$ctx" '# Photo Albums Constitution'
assert_has "speckit rule: the closing line names who owns the rules" "$ctx" 'These rules belong to their framework and zavet has not verified them.'
assert_lacks "speckit rule: specs --json still never mentions the constitution" "$( (cd "$R" && sh "$Z" specs --json) )" 'constitution'
(cd "$R" && sh "$Z" agents-md) >/dev/null
assert_has "speckit rule: AGENTS.md gets the pointer" "$(cat "$R/AGENTS.md")" '- .specify/memory/constitution.md (Spec Kit constitution'
assert_lacks "speckit rule: AGENTS.md never gets the text" "$(cat "$R/AGENTS.md")" 'Test first'
# An amendment leaves the committed context file current: it holds no text.
gc add -A && gc commit -qm "chore: agents" >/dev/null
sed 's/before the code/before any code/' "$R/.specify/memory/constitution.md" >"$R/c.tmp" && mv "$R/c.tmp" "$R/.specify/memory/constitution.md"
assert_eq "speckit rule: an amendment does not stale AGENTS.md" "0" "$( (cd "$R" && sh "$Z" agents-md --check >/dev/null 2>&1); echo $?)"
# The cap, then pointer-only at zero.
printf 'rule-source-max-lines: 3\n' >>"$R/.zavet/config"
ctx=$(rule_hook)
assert_has "speckit rule: the cap truncates and says where to read on" "$ctx" '> … truncated after 3 lines; read .specify/memory/constitution.md for the rest'
assert_lacks "speckit rule: nothing past the cap" "$ctx" 'Plain storage'
set_cfg_line '^rule-source-max-lines' 'rule-source-max-lines: 0'
ctx=$(rule_hook)
assert_lacks "speckit rule: a zero cap is pointer-only" "$ctx" '> '
# Off, one kind.
printf 'rule-source: speckit-constitution off\n' >>"$R/.zavet/config"
assert_eq "speckit rule: a kind switched off leaves the context" "" "$(rule_hook)"
assert_has "speckit rule: and reports enabled false" "$(rule_json)" '"enabled":false'
assert_has "speckit rule: with state off" "$(rule_json)" '"state":"off"'

# --- the newer-than-rules audit row fires and clears --------------------------
R="$TMP/rule-audit"
sdlc_repo "$R" speckit 'spec-source: speckit specs'
printf '# Standing rules\n\n- One.\n' >"$R/.zavet/RULES.md"
gc add -A && gc commit -qm "docs: rules" >/dev/null
assert_lacks "audit: a constitution older than RULES.md is quiet" "$( (cd "$R" && sh "$Z" audit) )" 'rule-source-newer-than-rules'
printf '\nAmended.\n' >>"$R/.specify/memory/constitution.md"
gc add -A && gc commit -qm "docs: amend constitution" >/dev/null
sha=$(git -C "$R" rev-parse --short=7 HEAD)
assert_has "audit: an amendment after RULES.md is reported" "$( (cd "$R" && sh "$Z" audit) )" "rule-source-newer-than-rules	speckit-constitution	.specify/memory/constitution.md	$sha"
printf -- '- Two.\n' >>"$R/.zavet/RULES.md"
gc add -A && gc commit -qm "docs: review rules" >/dev/null
assert_lacks "audit: reviewing RULES.md clears it" "$( (cd "$R" && sh "$Z" audit) )" 'rule-source-newer-than-rules'

# --- Spec Kit, unratified ------------------------------------------------------
R="$TMP/rule-unratified"
sdlc_repo "$R" speckit-unratified 'spec-source: speckit specs'
row=$(rule_json)
assert_has "unratified: state and reason" "$row" '"state":"unratified","reason":"Sync Impact Report comment is still committed"'
assert_has "unratified: placeholder version is null" "$row" '"version":null,"ratified":null,"lastAmended":"2026-10-01"'
assert_has "unratified: audit row" "$( (cd "$R" && sh "$Z" audit) )" "rule-source-unratified	speckit-constitution	.specify/memory/constitution.md"
ctx=$(rule_hook)
assert_lacks "unratified: the Sync Impact Report is stripped from context" "$ctx" 'Sync Impact Report'
assert_has "unratified: the label says so" "$ctx" 'not ratified yet'

# --- OpenSpec ------------------------------------------------------------------
R="$TMP/rule-openspec"
sdlc_repo "$R" openspec 'spec-source: openspec openspec'
row=$(rule_json)
assert_has "openspec rule: config.yaml is on by default" "$row" '"kind":"openspec-config","path":"openspec/config.yaml","source":"default","enabled":true'
assert_has "openspec rule: rules are counted" "$row" '"ruleCount":3'
ctx=$(rule_hook)
assert_has "openspec rule: the context block, unindented" "$ctx" '> Fixture project. Tech stack: TypeScript.'
assert_has "openspec rule: blank lines inside the block survive" "$ctx" '> All timestamps are UTC.'
assert_has "openspec rule: rules keyed by artifact" "$ctx" '> - specs: Keep one scenario per requirement.'
assert_lacks "openspec rule: the schema key is not a rule" "$ctx" 'spec-driven'
R="$TMP/rule-openspec-legacy"
sdlc_repo "$R" openspec-legacy 'spec-source: openspec openspec'
row=$(rule_json)
assert_has "openspec legacy: project.md is legacy" "$row" '"kind":"openspec-project-md","path":"openspec/project.md","source":"default","enabled":true'
assert_has "openspec legacy: with the replacement" "$row" '"state":"legacy","reason":"deprecated by OpenSpec: move it into openspec/config.yaml context"'
assert_has "openspec legacy: audit row" "$( (cd "$R" && sh "$Z" audit) )" "rule-source-legacy	openspec-project-md	openspec/project.md"
assert_lacks "openspec legacy: project.md is a pointer, never text" "$(rule_hook)" 'Python 3.12'

# --- BMAD ------------------------------------------------------------------------
R="$TMP/rule-bmad"
sdlc_repo "$R" bmad-612 'spec-source: bmad _bmad-output'
row=$(rule_json)
assert_has "bmad rule: the AGENTS.md block" "$row" '"kind":"bmad-agents-block","path":"AGENTS.md","source":"default","enabled":true'
assert_has "bmad rule: block lines counted" "$row" '"ruleCount":2'
assert_lacks "bmad rule: the block is a pointer, never re-injected" "$(rule_hook)" 'integer cents'
block() { awk '/<!-- bmad:context -->/,/<!-- \/bmad:context -->/' "$R/AGENTS.md"; }
before=$(block)
(cd "$R" && sh "$Z" agents-md) >/dev/null
assert_eq "bmad rule: agents-md round-trips the bmad block byte for byte" "$before" "$(block)"
assert_has "bmad rule: and adds its own block beside it" "$(cat "$R/AGENTS.md")" '<!-- zavet:agents:start -->'
R="$TMP/rule-bmad-legacy"
sdlc_repo "$R" bmad-legacy 'spec-source: bmad _bmad-output'
row=$(rule_json)
assert_has "bmad legacy: project-context.md is legacy" "$row" '"kind":"bmad-project-context","path":"_bmad-output/project-context.md","source":"default","enabled":true'
assert_has "bmad legacy: audit row" "$( (cd "$R" && sh "$Z" audit) )" "rule-source-legacy	bmad-project-context	_bmad-output/project-context.md"

# --- superpowers, undeclared frameworks, the global switch ------------------------
R="$TMP/rule-superpowers"
sdlc_repo "$R" superpowers 'spec-source: superpowers docs/superpowers'
assert_eq "superpowers: no rule source" "" "$(rule_json)"
R="$TMP/rule-undeclared"
sdlc_repo "$R" speckit
assert_eq "undeclared: an unlinked framework contributes nothing" "" "$(rule_json)"
assert_eq "undeclared: and nothing to context" "" "$(rule_hook)"
assert_has "undeclared: --detect shows what linking would bring" "$( (cd "$R" && sh "$Z" spec-sources --detect) )" "rule-source	speckit-constitution	.specify/memory/constitution.md	on"
R="$TMP/rule-alloff"
sdlc_repo "$R" speckit 'spec-source: speckit specs' 'rule-sources: off'
assert_eq "all off: context is silent" "" "$(rule_hook)"
assert_has "all off: --detect says off" "$( (cd "$R" && sh "$Z" spec-sources --detect) )" "rule-source	speckit-constitution	.specify/memory/constitution.md	off"

# --- overrides and fail-open --------------------------------------------------------
R="$TMP/rule-override"
sdlc_repo "$R" speckit 'spec-source: speckit specs' 'rule-source: speckit-constitution docs/constitution.md'
mkdir -p "$R/docs"
printf '# C\n\n### I. Moved\nRules live here now.\n' >"$R/docs/constitution.md"
assert_has "override: a non-default path" "$(rule_json)" '"kind":"speckit-constitution","path":"docs/constitution.md","source":"override"'
assert_has "override: its text reaches context" "$(rule_hook)" '> Rules live here now.'
R="$TMP/rule-failopen"
sdlc_repo "$R" speckit 'spec-source: speckit specs' 'rule-source: openspec-config ../outside.yaml' 'rule-source: openspec-project-md gone.md' 'rule-source: kiro-steering .kiro'
row=$(rule_json)
assert_has "fail-open: a path escaping the repo is unresolved" "$row" '"kind":"openspec-config","path":"../outside.yaml","source":"override","enabled":true,"oid":null'
assert_has "fail-open: with the reason" "$row" '"state":"unresolved","reason":"invalid path"'
assert_has "fail-open: a missing file" "$row" '"state":"file-missing","reason":"file missing"'
assert_has "fail-open: an unknown kind" "$row" '"kind":"kiro-steering"'
assert_has "fail-open: context still renders the good one" "$(rule_hook)" '> ### I. Test first'
assert_has "fail-open: audit reports the bad ones" "$( (cd "$R" && sh "$Z" audit) )" "rule-source-unresolved	openspec-config	../outside.yaml	invalid path"
ln -s /etc/hosts "$R/.specify/memory/constitution.md.lnk"
set_cfg_line speckit-constitution 'rule-source: speckit-constitution .specify/memory/constitution.md.lnk'
assert_has "fail-open: a symlink is never opened" "$(rule_json)" '"state":"unresolved","reason":"symlink or path outside the repo"'
assert_lacks "fail-open: nor quoted" "$(rule_hook)" 'localhost'
: >"$R/empty.md"
set_cfg_line speckit-constitution 'rule-source: speckit-constitution empty.md'
assert_has "fail-open: an empty file is unresolved" "$(rule_json)" '"state":"unresolved","reason":"empty file"'
printf 'context: |\nrules:\n' >"$R/bad.yaml"
set_cfg_line openspec-config 'rule-source: openspec-config bad.yaml'
assert_has "fail-open: a config.yaml with no rules is unresolved" "$(rule_json)" '"reason":"no context or rules"'
assert_eq "fail-open: context exits 0" "0" "$( (cd "$R" && sh "$Z" context >/dev/null 2>&1); echo $?)"

# --- read-only over every rule file -------------------------------------------------
R="$TMP/rule-readonly"
sdlc_repo "$R" bmad-612 'spec-source: bmad _bmad-output'
cp -R "$SDLC/speckit/.specify" "$R/"
cp -R "$SDLC/openspec/openspec" "$R/"
printf 'spec-source: speckit specs\nspec-source: openspec openspec\n' >>"$R/.zavet/config"
mkdir -p "$R/specs"
gc add -A && gc commit -qm "chore: frameworks" >/dev/null
rdigest() { (cd "$R" && { git hash-object .specify/memory/constitution.md openspec/config.yaml; awk '/<!-- bmad:context -->/,/<!-- \/bmad:context -->/' AGENTS.md | git hash-object --stdin; }); }
before=$(rdigest)
for c in "spec-sources --write" "spec-sources --json" "index" "rules" "agents-md" "audit" "context" "adapters"; do
    # shellcheck disable=SC2086 # $c is a command line, split on purpose
    (cd "$R" && sh "$Z" $c) >/dev/null 2>&1
done
assert_eq "read-only: no command writes a rule file" "$before" "$(rdigest)"

# ---------------------------------------------------------------- summary --
if [ "$fails" -gt 0 ]; then
    printf '%s test(s) FAILED\n' "$fails"
    exit 1
fi
printf 'all tests passed\n'
