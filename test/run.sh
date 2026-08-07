#!/bin/sh
# zavet test runner — POSIX sh + BSD awk + git, nothing else.
#
#   sh test/run.sh
#
# Four suites, all through the public `bin/zavet` interface:
#   dialect — fixture corpus vs the golden TSVs (the cross-parser contract
#             shared with dira-core; see fixtures/dialect/README.md)
#   matcher — run_match glob semantics (** collapse, trailing /, dedup)
#   check   — the CI trailer floor over real commit ranges
#   audit   — staleness + guard-pressure sweeps over real history
#   verify  — running recorded checks (the one command that executes repo
#             content), plus section extraction and the guard-injection budget
#   ids     — decision-id collisions: next-id across refs, duplicate detection,
#             and the refusal to resolve an ambiguous id
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
assert_eq "audit rows (minus shas)" "stale-spec	cap	1
stale-decision	D-0001	1
guard-pressure	D-0001	src/**" "$(printf '%s\n' "$out" | cut -f1-3)"
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
json_expected='{"v":1,"plugin":"zavet","version":"9.9.9-test","emit_schema":1,"min_dira":"0.1.0"}'

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
    '{"v":1,"plugin":"zavet","version":"unknown","emit_schema":1,"min_dira":"0.1.0"}' "$out"

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
assert_eq "each duplicate row gets its OWN free id" \
    "  → sh bin/zavet renumber ACME-0001 ACME-0003
  → sh bin/zavet renumber ACME-0002 ACME-0004" \
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
fi

# ---------------------------------------------------------------- summary --
if [ "$fails" -gt 0 ]; then
    printf '%s test(s) FAILED\n' "$fails"
    exit 1
fi
printf 'all tests passed\n'
