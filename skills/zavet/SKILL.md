---
name: zavet
description: Use when working in a repository that has a .zavet/ directory — defines when and how to capture decisions (commit trailers vs decision records), how guards work, and the honesty rules for recorded knowledge.
---

# Zavet — capturing decisions as a byproduct of work

This repo records the *reasoning* behind its code in `.zavet/`. Your job while
working here: leave no non-obvious decision unrecorded, and never contradict a
recorded decision silently.

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
