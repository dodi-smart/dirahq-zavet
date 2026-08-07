---
name: zavet-init
description: Scaffold the .zavet/ knowledge layer in the current repository
allowed-tools: Bash(.zavet/bin/zavet:*) Read Grep Glob
metadata:
  source: "commands/init.md"
  generated: "true"
---

<!-- GENERATED from commands/init.md by scripts/gen-adapters.sh — do not edit. -->

Commands below use this repo's vendored CLI at `.zavet/bin/zavet`, written by
`zavet adapters`. If zavet is on your PATH instead, use plain `zavet`.

Initialize the zavet knowledge layer in this repository.

1. **Pick the decision-id prefix with the user, before scaffolding.** Run
   `sh ".zavet/bin/zavet" suggest` — it prints
   `candidate<TAB>prefix<TAB>rationale` rows, best first, plus
   `taken<TAB>prefix<TAB>repo` for any prefix a sibling repo already holds.

   Present the candidates as a short numbered list with an example id
   (`DIRABE-00001`), say what each encodes, and let them pick one or type
   their own. **If a candidate collides with a `taken` row, say so and do not
   offer it first** — two repos sharing a prefix is precisely the ambiguity
   prefixes exist to remove.

   The default is product + role (`dirahq-cloud` → `DIRABE`,
   `dirahq-cli` → `DIRASH`), because role words like `cloud`, `cli` and `api`
   are exactly what repeats across sibling repos.

   This is the one moment the choice is free. Changing it later works, but
   leaves two prefixes in play forever — records already minted keep their ids.
2. Scaffold with the chosen prefix:
   `sh ".zavet/bin/zavet" init --prefix <PREFIX>`
   (omit `--prefix` to accept the top candidate).

   This also writes the cross-harness layer, so the repo's guards hold for
   teammates who are not on Claude Code: a vendored `.zavet/bin/zavet`, an
   `AGENTS.md` block, `.grok/rules/` + `.grok/hooks/`, and `.zavet/githooks/`.
   All of it is generated and belongs in the commit — that is the point.
3. Activate the git-hook floor: `.zavet/bin/zavet hooks install`. It sets
   `core.hooksPath` and is what enforces the guard wall for anyone whose harness
   has no hook API of its own.

   If it reports that `core.hooksPath` already belongs to something else
   (Husky, lefthook, pre-commit), do not override it — relay the one-line
   delegation the command prints, for the user to add to their existing
   `commit-msg` hook.
4. Open the scaffolded `.zavet/RULES.md` and replace the example with 3–7 real
   standing rules for this codebase. Derive them from CLAUDE.md / AGENTS.md, CI
   config, and anything the maintainers repeatedly correct. Keep each rule to
   one line. `.zavet/RULES.md` is the source — the generated `AGENTS.md` block
   and `.grok/rules/zavet.md` pick the change up on the next `zavet index`.
5. Ask the user whether there are existing intentional-but-undocumented
   behaviors worth recording immediately as first decisions; if so, run
   zavet-decide for each they can state from memory (those are recorded
   fact), and offer zavet-backfill to reverse-engineer the rest of the
   codebase into honestly-unverified records. For the features themselves,
   offer `zavet-spec backfill <feature>` (living specs) — going forward
   specs stay current transparently as agents work.
6. Suggest committing everything scaffolded — `.zavet/`, `AGENTS.md` and
   `.grok/` — with message `docs: initialize zavet knowledge layer`. The
   generated files outside `.zavet/` are not incidental: an uncommitted
   `.grok/rules/zavet.md` means a teammate on Grok Build has no decision index,
   and an uncommitted `.zavet/bin/zavet` means nothing off Claude Code can run at
   all. If the repo's `.gitignore` covers any of them, say so — `zavet adapters`
   warns about the Grok rules file specifically, because Grok skips ignored
   rules files silently.

Do not invent rationale for existing code — anything reverse-engineered must be
marked `origin: reverse-engineered` and `verified: false` with open questions,
never presented as recorded fact.
