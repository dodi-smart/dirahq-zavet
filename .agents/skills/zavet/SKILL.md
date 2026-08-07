---
name: zavet
description: Use when working in a repository that has a .zavet/ directory — defines when and how to capture decisions (commit trailers vs decision records), how to keep living feature specs current, how guards work, and the honesty rules for recorded knowledge.
allowed-tools: Bash(.zavet/bin/zavet:*) Read Grep Glob
metadata:
  source: "skills/zavet/SKILL.md"
  generated: "true"
---

<!-- GENERATED from skills/zavet/SKILL.md by scripts/gen-adapters.sh — do not edit. -->

Commands below use this repo's vendored CLI at `.zavet/bin/zavet`, written by
`zavet adapters`. If zavet is on your PATH instead, use plain `zavet`.

# Zavet — capturing knowledge as a byproduct of work

This repo records the *reasoning* behind its code in `.zavet/`. Your job while
working here: leave no non-obvious decision unrecorded, keep the living specs
current, and never contradict a recorded decision silently.

## The capture bar

Record something only if a future reader **could not reconstruct it from the
code and diff alone**. Obvious mechanics never get recorded — trailer spam
devalues the record.

## Two capture granularities

**Micro-decisions → commit trailers.** Append to the commit message footer:

```
Why: chose polling over inotify — daemon must stay watcher-free on all platforms
Rejected: notify crate — adds platform-specific failure modes for marginal latency
Constraint: hook must exit 0 in <500ms or it breaks the agent loop
Refs: D-0042
```

Allowed keys: `Why:` `Rejected:` `Constraint:` `Refs:` `Supersedes:` `Spec:`.
One line each; multiple trailers per commit are fine.

**Structural decisions → zavet-decide.** Anything that shapes future changes
(architecture choices, invariants, deliberate non-obvious behavior) becomes an
append-only `<PREFIX>-NNNN` record with `guards:` globs over the code it shapes.

**Ids carry a per-repo prefix** — `CLOUD-00042`, `CLI-00007` — set in
`.zavet/config` and printed by `zavet prefix`. It is what keeps ids
unambiguous when several repos sit under one project. Never invent one: take
what `zavet next-id` hands you. A repo with no config mints plain `D-NNNN`,
which is still correct — the prefix is opt-in per repo, not a global rename.

Ids are **immutable once merged**, because commit trailers already reference
them. If two branches claim one number, `zavet check` fails the PR and prints
`zavet renumber <old> <new>`; run it on the unmerged branch. Never renumber a
record that is already on the base branch — record a correcting decision
instead.

## Living specs — maintained transparently, not on request

`.zavet/specs/<slug>.md` are sectioned living documents describing features.
**Maintaining them is part of implementing, not a separate task the human
asks for.** While working:

- Changing behavior a spec covers (its `paths:` globs)? Update the affected
  sections, bump `date:`, reference new decisions, and stage the spec file
  with your commit.
- Building a substantial new feature with no covering spec? Create one from
  `.zavet/.spec-template.md` with `origin: session` — you just wrote the code,
  so the claims are fresh; `confidence: high` is normal.
- Either way, add a `Spec: <slug>` trailer to the commit. The commit hook
  nudges once per session if staged work touches spec-covered paths without
  the spec staged or the trailer present — satisfy it for real, don't
  trailer-spam your way past it.
- Link decisions from specs, never the reverse: specs are living, decisions
  are append-only. A `decisions: [<ID>]` frontmatter list and inline D-refs
  in the body both auto-link.
- Never flip `verified: true` yourself — that is the human confirming the
  spec matches the code.

Explicit entry points exist for the non-default flows: `zavet-spec design
<feature>` (spec before code) and `zavet-spec backfill <feature>`
(reconstruct from existing code, honesty rules apply).

## Honoring guards

- Editing a guarded path surfaces the decision once per session (the edit hook
  denies your first attempt and shows the record — read it, then retry).
- A commit touching guarded paths must carry `Refs: <ID>` (compliance) or
  `Supersedes: <ID>` (intentional replacement, after recording the new
  decision). The commit hook enforces this.
- Never work around a guard by re-wording the change. If the decision is wrong
  or stale, supersede it explicitly — that is a feature, not a failure.
- When several decisions guard one path, the hook shows their **Agent
  directives** rather than the whole records, and names each record path. If
  you need the reasoning behind a directive, open the record it names.

## Checks — saying how a record is verified

- A record's `checks:` bind an invariant to the command that proves it, as
  `label :: command`. An item with no `::` IS the command.
- The command is **opaque and stack-agnostic**: whatever this repo already
  uses to test itself. Read `package.json` / `justfile` / `Makefile` /
  `Cargo.toml` / the CI workflow to find it. Never invent a runner, never
  assume a framework, never parse a command's output — **exit 0 is pass** and
  that is the entire contract.
- Checks run ONLY from `zavet-verify`, which a human invokes. Never wire them
  into a hook or run them because a record happens to mention one.
- When you record an invariant, say how it is verified: a `checks:` entry if it
  is mechanically checkable, or a `## Verification` note saying plainly that it
  is not. **Silence reads as coverage.** And a check that cannot fail is worse
  than no check — it manufactures the confidence it was supposed to earn.
- A FAIL means something recorded as true no longer is. Read the record and say
  which is wrong, the code or the decision. Never edit a check to make it pass.

## Correcting versus superseding

Two different things, and the distinction is why supersession goes unused:

- **Supersede** when a decision is replaced: `status: superseded` +
  `superseded-by: <NEW-ID>` on the old record.
- **Correct** when the decision still stands but ONE claim inside it is wrong.
  Add `corrected-by: <NEW-ID>` to the old record; it stays `active` and its body
  is untouched, and every recall path leads with the correction.

Do not write a correction as prose inside an unrelated later record. That is
the habit this key exists to replace: it leaves the wrong claim standing
unmarked, and the next reader hits it first.

## Honesty rules

- Decision records are **append-only**. The only permitted mutations of an
  existing record are `status: active → superseded` + `superseded-by: <NEW-ID>`,
  and adding `corrected-by: <NEW-ID>`. Both are frontmatter-only; the body of a
  recorded decision is never rewritten.
- Anything reconstructed from existing code is `origin: reverse-engineered`,
  `verified: false`, with an Open Questions section. A wrong recorded "why" is
  worse than none — never invent rationale.
- Cite `verified: false` content only as hypothesis.

## Recall

Answer "why is it like this?" via zavet-why: INDEX.md → grep → ≤3 documents,
citing decision ids. With dira installed, `dira zavet why <ID>` adds what the
decision cost in engaged/agent time.

## Guards may not be enforced by your harness

Claude Code and Grok Build deny a guarded edit and show you the record. Every
other harness does not, so the check is yours to make: run `.zavet/bin/zavet match
<path>` before you edit, and read every record it names. A commit still gets
caught by the `commit-msg` hook and by `zavet check` in CI — but by then you
have already written code against a decision you never read.
