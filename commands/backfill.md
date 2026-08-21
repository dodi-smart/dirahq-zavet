---
description: Reverse-engineer decision records from an existing codebase — honestly marked as unverified hypotheses
argument-hint: [optional area/feature to focus on, e.g. "auth" or "the sync pipeline"]
---

Backfill the knowledge layer for this existing codebase. Focus: $ARGUMENTS
(no focus given = sweep the whole repo for its most load-bearing decisions).

**The honesty rule governs everything here: a wrong recorded "why" is worse
than none.** You are reconstructing hypotheses, not recording facts.

1. Mine the evidence, in order of reliability:
   - explicit intent: CLAUDE.md / AGENTS.md, READMEs, doc comments, ADRs,
     design docs, code comments that say "deliberately", "must", "never",
     "on purpose", "do not";
   - git archaeology: `git log --grep` for revert/redo pairs, commit bodies
     explaining non-obvious choices, `git log --follow` on suspicious files;
   - structural signals: unusual patterns that survived many refactors
     (hand-rolled code where a crate/library exists, apparent duplication,
     disabled features, pinned versions, generous timeouts/clamps).
2. Propose candidates to the user BEFORE writing anything: a short list of
   "this looks intentional because X — worth a record?". Let them cull,
   confirm, or correct. Anything the user confirms from memory may be
   upgraded to `verified: true`; everything else stays a hypothesis.
3. Follow the writing-style rule in the zavet skill: plain, active voice, one idea
   per sentence, no em dashes, no jargon nouns, sentence case.
   For each survivor, get an id (`sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" next-id`)
   and write `.zavet/decisions/<id>-<slug>.md` from
   `${CLAUDE_PLUGIN_ROOT}/templates/decision.md`, with the backfill deltas:
   - `origin: reverse-engineered` and `verified: false` (unless the user
     personally confirmed it);
   - a mandatory `## Open questions` section listing what could NOT be
     reconstructed — never invent rationale to fill a gap;
   - `guards:` as narrow as the evidence supports; when unsure, guard less.
4. Regenerate the index (`sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" index`) and
   commit with `docs: backfill decisions <ids>` plus a `Refs:` trailer per id.
5. Remind the user: unverified records are cited as hypotheses by /zavet:why;
   flipping one to `verified: true` after review is a normal, welcome commit.
