---
description: Scaffold the .zavet/ knowledge layer in the current repository
---

Initialize the zavet knowledge layer in this repository.

1. **Pick the decision-id prefix with the user, before scaffolding.** Run
   `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" suggest` — it prints
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
   `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" init --prefix <PREFIX>`
   (omit `--prefix` to accept the top candidate).
3. Open the scaffolded `.zavet/RULES.md` and replace the example with 3–7 real
   standing rules for this codebase. Derive them from CLAUDE.md, CI config, and
   anything the maintainers repeatedly correct. Keep each rule to one line.
4. Ask the user whether there are existing intentional-but-undocumented
   behaviors worth recording immediately as first decisions; if so, run
   /zavet:decide for each they can state from memory (those are recorded
   fact), and offer /zavet:backfill to reverse-engineer the rest of the
   codebase into honestly-unverified records. For the features themselves,
   offer `/zavet:spec backfill <feature>` (living specs) — going forward
   specs stay current transparently as agents work.
5. Suggest committing `.zavet/` with message `docs: initialize zavet knowledge layer`.

Do not invent rationale for existing code — anything reverse-engineered must be
marked `origin: reverse-engineered` and `verified: false` with open questions,
never presented as recorded fact.
