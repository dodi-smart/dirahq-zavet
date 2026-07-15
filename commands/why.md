---
description: Answer "why is it like this?" from recorded knowledge, with decision-id citations
argument-hint: [question or decision id]
---

Answer from recorded knowledge: $ARGUMENTS

Index-first retrieval — do NOT scan the whole tree:

1. Read `.zavet/INDEX.md`. If the question names a decision id (D-NNNN), open
   that record directly (`sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" decision-path <id>`).
2. Otherwise grep `.zavet/` for the key terms, open at most 3 documents, and
   check `git log --grep=<term>` trailers (`Why:`, `Constraint:`, `Refs:`) for
   micro-decisions that never got a record.
3. Answer with explicit citations (decision ids, commit shas). Distinguish
   recorded fact (`verified: true`) from reverse-engineered hypothesis
   (`verified: false`) — cite the latter only as hypothesis.
4. If dira is installed, also run `dira zavet why <id>` for the time/cost panel
   (what the decision cost in engaged and agent time) and include it.
5. If nothing recorded answers the question, say so plainly and offer to record
   the answer now via /zavet:decide once established. Never invent rationale.
