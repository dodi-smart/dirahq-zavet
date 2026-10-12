---
name: zavet-why
description: Answer "why is it like this?" from recorded knowledge, with decision-id citations
allowed-tools: Bash(.zavet/bin/zavet:*) Read Grep Glob
metadata:
  source: "commands/why.md"
  generated: "true"
---

<!-- GENERATED from commands/why.md by scripts/gen-adapters.sh — do not edit. -->

Commands below use this repo's vendored CLI at `.zavet/bin/zavet`, written by
`zavet adapters`. If zavet is on your PATH instead, use plain `zavet`.

Arguments: `[question or decision id]` — available as $ARGUMENTS.

Answer from recorded knowledge: $ARGUMENTS

1. If dira is installed (`command -v dira`), ask it first — `dira zavet why
   "$ARGUMENTS"` accepts plain questions as well as ids, resolves them against
   captured decisions and trailers, and returns the record **plus its time
   cost** (engaged/agent time, tokens). A confident match answers directly;
   ranked matches tell you which records to open.
2. Index-first on the repo layer (always, and alone when dira is absent):
   read `.zavet/INDEX.md`; open a named decision directly
   (`sh ".zavet/bin/zavet" decision-path <id>`); otherwise grep
   `.zavet/` for the key terms — decisions AND specs (`.zavet/specs/` living
   documents often carry the fuller picture and link the decisions that
   shaped them) — open at most 3 documents, and check
   `git log --grep=<term>` trailers (`Why:`, `Constraint:`, `Refs:`, `Spec:`)
   for micro-decisions that never got a record.
   **Source-backed specs.** When the question names a `<kind>:<id>` slug
   (`openspec:add-csv-import`, `speckit:007-csv-import`, `bmad:epic-cart-rules`,
   `superpowers:2026-09-18-...`), find its row in
   `sh ".zavet/bin/zavet" specs --json` and open the files it
   lists. Add the decisions that reference the slug (grep `.zavet/decisions/`
   and `git log --grep='Spec:'`). With dira present, `dira zavet why <slug>`
   adds the engaged and agent time spent under it. Cite the framework's text as
   what the framework says, never as `verified` fact: these specs are
   permanently unverified in zavet. Say when the row has `paths: none yet` or
   an `unresolved` reason instead of papering over it.
3. Follow the writing-style rule in the zavet skill: plain, active voice, one idea
   per sentence, no em dashes, no jargon nouns, sentence case.
   Answer with explicit citations (decision ids, spec slugs, commit shas).
   Distinguish recorded fact (`verified: true`) from unverified content
   (`verified: false`, any origin) — cite the latter only as hypothesis.
4. If nothing recorded answers the question, say so plainly and offer to
   record the answer now via zavet-decide once established. Never invent
   rationale.
