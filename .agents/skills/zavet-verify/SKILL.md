---
name: zavet-verify
description: Run the checks bound to decisions and specs, and report what is unchecked
allowed-tools: Bash(.zavet/bin/zavet:*) Read Grep Glob
metadata:
  source: "commands/verify.md"
  generated: "true"
---

<!-- GENERATED from commands/verify.md by scripts/gen-adapters.sh — do not edit. -->

Commands below use this repo's vendored CLI at `.zavet/bin/zavet`, written by
`zavet adapters`. If zavet is on your PATH instead, use plain `zavet`.

Arguments: `[<decision-id> | <spec-slug> | <path>...] (default: everything)` — available as $ARGUMENTS.

Run the recorded checks and report honestly on what they cover.

**This is the only zavet command that executes repository content.** It runs
because a human asked for it, now. Never wire it into a hook, a `SessionStart`
step, or anything that fires on its own.

1. Resolve the argument:
   - looks like a decision id (`<PREFIX>-NNNN`) → `sh ".zavet/bin/zavet" verify --id <id>`
   - a bare slug matching a spec → `… verify --spec <slug>`
   - one or more paths → `… verify --paths <p>...` (resolves through the same
     guard/spec tables the hooks use, so this matches what a commit would trip)
   - nothing → `… verify` (everything)

2. Report the result as it came back. `PASS`/`FAIL` rows are on stdout, the
   commands' own output on stderr, and the exit status is 1 if anything failed.
   Do not re-run a failing check to "confirm" it, and do not interpret a
   command's output beyond its exit status — exit 0 is the entire contract.

3. For a **FAIL**, the check did its job: something recorded as true no longer
   is. Read the record (`zavet-why <id>`), then say which is wrong — the code
   or the decision. Do not edit the check to make it pass.

4. Then report the gap, which matters as much as the failures. Run
   `sh ".zavet/bin/zavet" audit` and surface the
   `uncovered-invariant` rows in scope: records that tell an agent what to do
   but never say how anyone would know it still holds.

   For each, offer a check — but only where one is real. Many invariants
   genuinely cannot be checked mechanically ("do not describe this as a GDPR
   control"), and for those the honest move is a `## Verification` note saying
   so, not a check that cannot fail. **A check that cannot fail is worse than
   no check**: it reads as coverage and provides none.

5. Never invent a runner. The command is whatever this repo already uses to
   test itself — read `package.json`, `justfile`, `Makefile`, `Cargo.toml`, the
   CI workflow, or the existing test layout, and use that. Zavet has no opinion
   about the stack and must not acquire one.

Adding a check is an edit to the record's frontmatter, so it follows the same
rule as any other record edit. Records are append-only for meaning, and
`checks:` is metadata about how the record is verified, not a claim being
rewritten.
