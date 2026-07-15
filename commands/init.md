---
description: Scaffold the .zavet/ knowledge layer in the current repository
---

Initialize the zavet knowledge layer in this repository.

1. Run: `sh "${CLAUDE_PLUGIN_ROOT}/bin/zavet" init`
2. Open the scaffolded `.zavet/RULES.md` and replace the example with 3–7 real
   standing rules for this codebase. Derive them from CLAUDE.md, CI config, and
   anything the maintainers repeatedly correct. Keep each rule to one line.
3. Ask the user whether there are existing intentional-but-undocumented
   behaviors worth recording immediately as first decisions; if so, run
   /zavet:decide for each.
4. Suggest committing `.zavet/` with message `docs: initialize zavet knowledge layer`.

Do not invent rationale for existing code — anything reverse-engineered must be
marked `origin: reverse-engineered` and `verified: false` with open questions,
never presented as recorded fact.
