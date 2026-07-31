---
description: Record a structural decision as an append-only D-NNNN record
argument-hint: [short description of the decision]
---

Record a decision: $ARGUMENTS

1. Get the next id: `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" next-id`
2. Create `.zavet/decisions/<id>-<slug>.md` from the template at
   `${CLAUDE_PLUGIN_ROOT}/templates/decision.md`. Rules:
   - **Keep it under 60 lines.** A decision is a record, not an essay. Past
     that, `zavet audit` reports it as a `long-record`, and every guarded edit
     pays for the length — usually it means a feature spec is hiding in a
     decision, and belongs in `/zavet:spec` instead.
   - Frontmatter: `id`, `title`, `status: active`, `guards` (path globs of the
     code this decision shapes — as narrow as possible; over-broad guards cause
     alert fatigue), optional `supersedes: D-NNNN`, optional `checks`,
     `origin: recorded`, `verified: true`.
   - Body sections: Decision, Why, Rejected, Agent directives, Verification,
     and Open questions when anything could not be established.
   - **Say how the directives are verified.** If an invariant here is
     mechanically checkable, add a `checks:` entry (`label :: command`) using
     the runner this repo already has — read `package.json`, `justfile`,
     `Makefile`, `Cargo.toml` or the CI workflow; never invent one, and never
     assume a stack. If it is not checkable, say so under `## Verification`.
     Both are honest; silence is not, because it reads as coverage. A check
     that cannot fail is worse than no check.
   - Capture bar: only record what a future reader could NOT reconstruct from
     the code. If it's obvious from the diff, use a commit trailer instead.
3. If this REPLACES an older decision, edit ONLY the old record's frontmatter:
   `status: superseded` plus `superseded-by: <new-id>`. Never rewrite its body —
   records are append-only.

   If instead it CORRECTS one claim inside a record that otherwise still
   stands, do not supersede it: add `corrected-by: <new-id>` to the old
   record's frontmatter and leave its status `active` and its body untouched.
   Every recall path — the guard hook, `/zavet:why`, `dira zavet why` — then
   leads with the correction. This is the case that used to get written as
   prose inside an unrelated record, leaving the wrong claim standing
   unmarked; `zavet check` fails on a pointer that names a record which does
   not exist.
4. Regenerate the index: `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" index`
5. If a living spec in `.zavet/specs/` covers the area this decision shapes,
   add the new id to that spec (its `decisions:` list or an inline reference
   in the relevant section) — specs link decisions, never the reverse.
6. Commit the new record (and index) with trailer `Refs: <id>`; when
   superseding, also add `Supersedes: <old-id>`.
