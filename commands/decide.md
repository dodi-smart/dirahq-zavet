---
description: Record a structural decision as an append-only D-NNNN record
argument-hint: [short description of the decision]
---

Record a decision: $ARGUMENTS

1. Get the next id: `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" next-id`
2. Create `.zavet/decisions/<id>-<slug>.md` from the template at
   `${CLAUDE_PLUGIN_ROOT}/templates/decision.md`. Rules:
   - **≤ 25 lines total.** A decision is a record, not an essay.
   - Frontmatter: `id`, `title`, `status: active`, `guards` (path globs of the
     code this decision shapes — as narrow as possible; over-broad guards cause
     alert fatigue), optional `supersedes: D-NNNN`, `origin: recorded`,
     `verified: true`.
   - Body sections: Decision, Why, Rejected, Agent directives.
   - Capture bar: only record what a future reader could NOT reconstruct from
     the code. If it's obvious from the diff, use a commit trailer instead.
3. If this supersedes an older decision, edit ONLY the old record's frontmatter:
   `status: superseded` plus `superseded-by: <new-id>`. Never rewrite its body —
   records are append-only.
4. Regenerate the index: `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" index`
5. Commit the new record (and index) with trailer `Refs: <id>`; when
   superseding, also add `Supersedes: <old-id>`.
