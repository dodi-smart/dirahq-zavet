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
gc() { git -C "$R" "$@"; }
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
gc() { git -C "$R" "$@"; }
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

# ---------------------------------------------------------------- summary --
if [ "$fails" -gt 0 ]; then
    printf '%s test(s) FAILED\n' "$fails"
    exit 1
fi
printf 'all tests passed\n'
