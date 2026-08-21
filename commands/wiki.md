---
description: Browse this repo's knowledge base — decisions, rules, glossary, recent rationale — wiki style
argument-hint: [optional topic]
---

Present this repo's recorded knowledge as a readable wiki page. Topic: $ARGUMENTS

1. If dira is installed (`command -v dira`), start from its correlated view:
   `dira zavet wiki` (or `dira zavet wiki <topic>`) — it adds capture counts,
   guard telemetry, and verification badges the files alone don't carry.
2. Enrich from the repo layer (works without dira):
   - `.zavet/INDEX.md` — the decision + spec index;
   - `.zavet/RULES.md` — standing rules (always in force);
   - `.zavet/specs/` — living feature specs (follow their `decisions:` links);
   - `.zavet/glossary.md` — project terms;
   - with a topic: grep `.zavet/` and `git log --grep=<topic>` trailers.
3. Follow the writing-style rule in the zavet skill: plain, active voice, one idea
   per sentence, no em dashes, no jargon nouns, sentence case.
   Compose a clean summary for the human: standing rules first, then active
   decisions (one line each: id — title — what it guards), living specs
   (slug — title — origin/confidence, with the decisions they link),
   superseded history, and notable recent trailers. Cite ids everywhere; mark
   anything `verified: false` as **unverified — hypothesis**, never as fact.
4. Offer natural next steps: `/zavet:why <question>` for a specific "why",
   `dira zavet why <ID>` for a decision's full record + time cost.
