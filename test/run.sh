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

# ---------------------------------------------------------------- summary --
if [ "$fails" -gt 0 ]; then
    printf '%s test(s) FAILED\n' "$fails"
    exit 1
fi
printf 'all tests passed\n'
