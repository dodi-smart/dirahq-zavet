---
name: zavet
description: Use when working in a repository that has a .zavet/ directory — defines when and how to capture decisions (commit trailers vs decision records), how to keep living feature specs current, how guards work, and the honesty rules for recorded knowledge.
---

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

**Structural decisions → /zavet:decide.** Anything that shapes future changes
(architecture choices, invariants, deliberate non-obvious behavior) becomes an
append-only `D-NNNN` record with `guards:` globs over the code it shapes.

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
  are append-only. A `decisions: [D-NNNN]` frontmatter list and inline D-refs
  in the body both auto-link.
- Never flip `verified: true` yourself — that is the human confirming the
  spec matches the code.

Explicit entry points exist for the non-default flows: `/zavet:spec design
<feature>` (spec before code) and `/zavet:spec backfill <feature>`
(reconstruct from existing code, honesty rules apply).

## Honoring guards

- Editing a guarded path surfaces the decision once per session (the edit hook
  denies your first attempt and shows the record — read it, then retry).
- A commit touching guarded paths must carry `Refs: D-NNNN` (compliance) or
  `Supersedes: D-NNNN` (intentional replacement, after recording the new
  decision). The commit hook enforces this.
- Never work around a guard by re-wording the change. If the decision is wrong
  or stale, supersede it explicitly — that is a feature, not a failure.

## Honesty rules

- Decision records are **append-only**. The only permitted mutation of an
  existing record is `status: active → superseded` + `superseded-by: D-MMMM`.
- Anything reconstructed from existing code is `origin: reverse-engineered`,
  `verified: false`, with an Open Questions section. A wrong recorded "why" is
  worse than none — never invent rationale.
- Cite `verified: false` content only as hypothesis.

## Recall

Answer "why is it like this?" via /zavet:why: INDEX.md → grep → ≤3 documents,
citing decision ids. With dira installed, `dira zavet why D-NNNN` adds what the
decision cost in engaged/agent time.
