---
description: Answer "why is it like this?" from recorded knowledge, with decision-id citations
argument-hint: [question or decision id]
---

Answer from recorded knowledge: $ARGUMENTS

1. If dira is installed (`command -v dira`), ask it first — `dira zavet why
   "$ARGUMENTS"` accepts plain questions as well as ids, resolves them against
   captured decisions and trailers, and returns the record **plus its time
   cost** (engaged/agent time, tokens). A confident match answers directly;
   ranked matches tell you which records to open.
2. Index-first on the repo layer (always, and alone when dira is absent):
   read `.zavet/INDEX.md`; open a named decision directly
   (`sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" decision-path <id>`); otherwise grep
   `.zavet/` for the key terms, open at most 3 documents, and check
   `git log --grep=<term>` trailers (`Why:`, `Constraint:`, `Refs:`) for
   micro-decisions that never got a record.
3. Answer with explicit citations (decision ids, commit shas). Distinguish
   recorded fact (`verified: true`) from reverse-engineered hypothesis
   (`verified: false`) — cite the latter only as hypothesis.
4. If nothing recorded answers the question, say so plainly and offer to
   record the answer now via /zavet:decide once established. Never invent
   rationale.
