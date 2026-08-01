---
description: Report-only knowledge health sweep — code-vs-decision conflicts, stale specs, over-broad guards
argument-hint: [optional focus: conflicts | specs | guards]
---

Audit this repo's knowledge health. Focus: $ARGUMENTS

**Report-only: this command modifies nothing** — no spec edits, no status
flips, no verification. It surfaces what a human should look at.

1. If dira is installed (`command -v dira`), start from its correlated view:
   `dira zavet wiki` already carries staleness badges and guard telemetry
   (blocked/complied counts strengthen the pressure signal below).
2. Run the deterministic sweep (works without dira):
   `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" audit` — type-tagged TSV rows:
   `stale-spec slug n since-sha`, `stale-decision id n since-sha`,
   `guard-pressure id glob matched total`, `uncovered-invariant id file`,
   `long-record id lines`.
3. **Conflicts** (unless focused elsewhere): for each `stale-decision`,
   worst drift first, open the record
   (`sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" decision-path <id>`), read its
   Decision and Agent directives, then inspect the drift window —
   `git log --oneline <since-sha>..HEAD -- <its guard globs>` — and judge
   whether the code still complies. Honesty rules govern: every claim must
   trace to a file you actually opened (open at most ~3 per finding);
   records with `verified: false` are cited only as *unverified —
   hypothesis*; never invent rationale. Report each conflict as: decision id
   — what it requires — which commit/file appears to diverge — confidence.
4. **Stale specs**: list slug, commit count, and a couple of sample commit
   subjects from the window. Suggested action is `/zavet:spec` to bring the
   living document current — never edit the spec inside the audit.
5. **Guard pressure**: flag guards whose matched-file count is large in
   absolute terms or relative to the repo. Rationale from /zavet:decide:
   guards should be *as narrow as possible — over-broad guards cause alert
   fatigue*. Suggested action: narrow the glob (a frontmatter-only edit),
   or supersede the decision if its scope truly changed.
6. **Unverified invariants**: `uncovered-invariant` rows are records that
   tell an agent what to do but never say how anyone would know it still
   holds. Report the count and name the ones whose directives look
   mechanically checkable. Do NOT treat the count as a defect list — many
   invariants genuinely cannot be checked, and for those the fix is a
   `## Verification` note saying so, not a check. Suggested action:
   `/zavet:verify`, which proposes checks and runs the existing ones.
7. **Over-long records**: `long-record` rows are records past 60 lines. The
   capture bar is about what a reader could not reconstruct, not length — but
   a record that grew into a feature spec is one nobody re-reads, and the
   guard hook pays for every line of it on each guarded edit. Suggested
   action: move the narrative into a living spec (`/zavet:spec`) and leave
   the decision as the decision.
8. Compose the report in that order — Conflicts, Stale specs, Guard
   pressure, Unverified invariants, Over-long records — each with concrete
   next steps (`/zavet:decide` to supersede or correct, `/zavet:spec` to
   refresh, `/zavet:verify` to check, glob narrowing). End with the one-line
   health summary: N decisions (M stale, U unchecked), K specs (J stale),
   widest guard.
