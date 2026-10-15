---
description: Adopt OpenSpec, Spec Kit, BMAD or superpowers specs into zavet — detect, declare, resolve read-only, record the decision
argument-hint: [optional: kind to adopt, e.g. openspec | speckit | bmad | superpowers]
---

Adopt the spec framework(s) this repo already uses. Input: $ARGUMENTS

This is a one-time setup per repo. After it, zavet resolves each framework unit
(an OpenSpec change, a Spec Kit feature, a BMAD epic, a superpowers design) as a
spec you can cite with `Spec: <kind>:<id>`. zavet only **reads** those files.
The framework keeps authoring them.

1. **Detect.** Run `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" spec-sources --detect`.
   It prints what it found: `openspec/`, `.specify/` with `specs/`, `_bmad/`
   (plus its output folder, `_bmad-output` by default), `docs/superpowers/`.
   Show the findings to the user as they are. If nothing is found, say so and
   stop. If the user named a kind in the input, adopt only that one.
2. **Confirm, then declare.** Ask the user to confirm the list. Then run
   `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" spec-sources --write`. It adds
   `spec-source: <kind> <root> [globs...]` lines to `.zavet/config` and leaves
   every other key alone. Glob arguments are optional human-declared paths for
   a unit; ask for them only if the user wants coverage right away.
3. **Resolve and report.** Run `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" specs --json`
   (JSON Lines, one row per unit). Report:
   - every unit that resolved: slug, title, normalised state, task counts as
     the framework's own checkboxes record them;
   - every unresolved unit, with its `unresolved` reason verbatim. Do not guess
     past a reason, and do not repair the framework's files to make a unit
     resolve.
   Most units will show `paths: none yet`. That is correct, see below.
4. **Framework rules.** Linking a framework also turns on its standing-rule
   files: a Spec Kit constitution, OpenSpec's `config.yaml` context and rules,
   BMAD's project context. Show the `rule-source` rows from step 3's
   `spec-sources` report (or from `spec-sources --json`) as they are. Tell the
   user that these rules now appear in session context next to
   `.zavet/RULES.md`, attributed to their framework and unverified, and that
   `rule-source: <kind> off` in `.zavet/config` switches one off. Report any
   `unratified` or `legacy` state with its reason.
   **Do not import it, copy it or merge it.** Two files that both claim to be
   the standing rules go stale unnoticed. Leave the overlap to a human.
5. **Explain the posture** in two or three plain sentences:
   - zavet never writes into a declared source root. Only the framework's own
     commands (`/openspec-*`, `/speckit.*`, `bmad-*`, the superpowers skills)
     change those files.
   - A source-backed spec is permanently `verified: false`. Zavet did not
     author its claims and cannot confirm them. It still counts toward coverage
     once it has paths.
   - Paths are never derived from the artifact's content. They accrete from
     `Spec:` trailers on commits, plus any globs a human declared. Until then
     the unit reports `paths: none yet`, which means uncovered, not clean.
   - Task checkboxes are the framework's claim. Zavet records them as that,
     never as its own finding, and never reports compliance or a percentage.
6. **Record the adoption** through /zavet:decide as one decision. State: the
   kinds and roots adopted, that access is read-only, that source-backed specs
   stay unverified yet count toward coverage, and that paths accrete from
   `Spec:` trailers and are never derived from content. Add a `guards:` glob
   over each declared source root only if the user wants edits there to surface
   this decision. Keep it narrow. Follow the decide command's capture bar and
   honesty rules.
7. Suggest committing `.zavet/config` and the new record together, for example
   `docs: adopt <kinds> as zavet spec sources`. From the next commit on, cite
   the unit you work under with `Spec: <kind>:<id>`.

Never claim a unit is implemented, satisfied or complete. Report what the
framework's files say and what git shows, and stop there.
