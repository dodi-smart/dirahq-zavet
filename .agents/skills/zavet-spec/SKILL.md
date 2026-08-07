---
name: zavet-spec
description: Maintain living feature specs — document session work (default), design upfront, or backfill from existing code
allowed-tools: Bash(.zavet/bin/zavet:*) Read Grep Glob
metadata:
  source: "commands/spec.md"
  generated: "true"
---

<!-- GENERATED from commands/spec.md by scripts/gen-adapters.sh — do not edit. -->

Commands below use this repo's vendored CLI at `.zavet/bin/zavet`, written by
`zavet adapters`. If zavet is on your PATH instead, use plain `zavet`.

Arguments: `[design <feature> | backfill <feature> | blank = document this session's work]` — available as $ARGUMENTS.

Maintain the living specs in `.zavet/specs/`. Input: $ARGUMENTS

Specs are normally maintained **transparently** while you work (see the zavet
skill) — this command is the explicit entry point. Pick the flow from the
first word of the input; anything else (including no input) means *document*.

**document** (default — no argument): distill the work completed in this
session into specs.
- Look at what was actually built/changed (the session's diff and commits).
- If a spec in `.zavet/specs/` covers it (list them via
  `sh ".zavet/bin/zavet" specs`, then read the candidates'
  `paths:` frontmatter), update the affected sections and bump `date:`.
- Otherwise create `.zavet/specs/<slug>.md` (kebab-case slug, flat, from
  `.zavet/.spec-template.md` — fall back to
  `.zavet/.spec-template.md` if the repo predates it) with
  `origin: session`. You just wrote the code, so claims are fresh —
  `confidence: high` is normal, but `verified` stays `false` until a human
  confirms.

**design <feature>**: write the specification *before* the code exists.
- Elicit intent from the user/conversation; sections describe intended
  behavior, not current code. `origin: designed`.
- `paths:` name where the code *will* live — staleness only starts once
  commits touch them. Open Questions holds the unresolved design points.

**backfill <feature>**: reverse-engineer an existing feature from real code.
- Honesty rules govern (same as zavet-backfill): index-first exploration,
  every claim traceable to a file you actually opened, `origin:
  reverse-engineered`, `verified: false`, and a **non-empty Open Questions**
  section listing what could not be reconstructed. Never invent behavior.
- `confidence` self-assessed from coverage: `high` only when you read all the
  code the spec describes.

All flows:
- Frontmatter exactly per the template: `title`, `version`, `origin`,
  `verified`, `confidence`, `date` (today), `paths` (git pathspecs, as narrow
  as honest), optional `decisions:` list.
- Reference the decisions that shaped the feature — `decisions: [<ID>]`
  and/or inline D-refs in the body; both auto-link when dira captures the
  spec. Link from the spec, never by editing decision records.
- Regenerate the index: `sh ".zavet/bin/zavet" index`
  (if `.zavet/INDEX.md` predates the spec layer, first add a `## Specs`
  section containing the `<!-- zavet:specs:start -->` / `<!-- zavet:specs:end -->`
  markers).
- Commit spec + index with a `Spec: <slug>` trailer.
- Remind the user: flipping `verified: true` after they review is a normal,
  welcome commit; with dira installed, `dira zavet wiki` shows the spec with
  staleness and confidence badges.
