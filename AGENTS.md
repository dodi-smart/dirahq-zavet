# Contributing to zavet, as an agent

Zavet is a knowledge layer for AI-assisted development, and it ships as both a
Claude Code plugin and a set of portable Agent Skills. It should be workable
from any harness — so this file exists rather than only a `CLAUDE.md`.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the human-facing rules (release
channel, commit conventions, how to run `claude plugin validate`). This file
covers only what an agent gets wrong here.

## The shape of the thing

| Path | What it is |
|---|---|
| `bin/zavet` | The whole implementation. POSIX sh, ~2900 lines, no runtime deps beyond `git`/`awk`/`sed` (`jq` is a soft dep of the hooks only). |
| `commands/*.md` | The eight workflows, as Claude Code slash commands. **Canonical prose.** |
| `skills/zavet/SKILL.md` | The ambient knowledge-layer skill. **Canonical prose.** |
| `.agents/skills/**` | **Generated.** Portable Agent Skills derived from the two rows above. |
| `hooks/hooks.json`, `hooks/scripts/*.sh` | Claude Code plugin hook manifest and thin wrappers over `zavet hook`. |
| `templates/*.md` | What `zavet init` copies into a repo's `.zavet/`. |
| `test/run.sh` | The whole test suite. POSIX sh, no framework. |
| `test/fixtures/dialect/` | The frontmatter-dialect corpus shared with `dirahq-cli`. Vendored — see below. |

## Rules that are not negotiable

**Never hand-edit `.agents/skills/**`.** It is generated. Edit
`commands/<slug>.md` or `skills/zavet/SKILL.md`, then run:

```bash
sh scripts/gen-adapters.sh
```

CI runs `--check` and fails the build on drift. If you find yourself wanting to
say something in the portable skill that is not true of the Claude Code command,
change the generator, not the output.

**POSIX sh only, and it has to survive both awks.** No bashisms — no arrays, no
`[[`, no `local`, no `${var,,}`, no `$'...'`. CI runs the suite on
`ubuntu-latest` (dash + gawk) *and* `macos-latest` (BSD awk + Apple's
`/bin/sh`); those two legs together **are** the portability test for the
frontmatter dialect, so a change that only passes on one is not done. `shellcheck`
must be clean at info level — the repo has no accepted findings, so a new
`# shellcheck disable=` needs a comment saying why the finding is wrong.

**The CI runner's `shellcheck` is newer than the one you probably have.** It
reports findings that a released build does not — SC2317 alongside SC2329, for
instance — so a clean local run is not proof. Reproduce the CI version with:

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:latest bin/zavet hooks/scripts/*.sh test/*.sh scripts/*.sh
```

**Hooks fail open, always.** Every path in `zavet hook` and every script under
`hooks/scripts/` must exit 0 and print nothing when anything is unexpected — no
`jq`, no `git`, an unreadable file, a repo without `.zavet/`. A guard that wedges
the agent loop gets uninstalled, and an uninstalled guard protects nothing. The
one exception is a real, deliberate `deny`.

**The guard wall has exactly one implementation.** It is `zavet gate`. The Claude
Code hook, the Grok Build hook, the Cursor hook and the `commit-msg` git hook are
all callers; `zavet check` shares its two trailer patterns via `zavet_refs_re`
and `ZAVET_SPEC_RE`. Do not add a fifth place that re-derives the rule — a repo
that enforces one rule in the agent loop and a different one at `git commit`
teaches a lesson CI then rejects.

**The live hook's `git commit` detection cannot resolve aliases.** It is a
cheap text gate on the Bash command string, not a shell parse, so `git ci` — a
user alias for `commit` — passes the live hook undetected. The commit-msg git
hook and `zavet check` in CI are what catch those, since both see the real
commit after Git has already expanded the alias.

**`zavet deny` output shapes are per-harness and cannot be guessed.** Claude Code
reads `hookSpecificOutput.permissionDecision`; Grok Build reads a flat
`decision`/`reason` and ignores `hookSpecificOutput` outside Stop hooks; Cursor
reads `permission` plus `agent_message`. Handing a harness the wrong shape is a
silent **allow** — a guard that looks installed and enforces nothing. That is why
the flavor is detected (`GROK_HOOK_EVENT`, then envelope shape) or passed
explicitly, never assumed.

**`zavet deny` bare output is frozen.** `zavet deny <reason>` and
`--format claude` must stay byte-identical to each other and to what shipped
before formats existed. README's *Integration contract* §3 is a real contract
with `dirahq-cli`; changing it needs a coordinated release, not a same-day fix.
`test/run.sh` pins the exact string.

**`zavet verify` is the only subcommand that may execute repository content.**
Never wire it into a hook, and never run a `checks:` command because a record
mentions one. See [SECURITY.md](SECURITY.md).

**Decision records are append-only for meaning.** The only permitted frontmatter
edits are `status: active → superseded` plus `superseded-by:`, and adding
`corrected-by:`. A body may get a prose-only pass that changes no claim: fixing a
title, a typo, a broken link, or wording that breaks the house writing style,
while every section still asserts exactly what it asserted before. Say "reword
only, no meaning change" in the commit so the diff is trusted without a re-read.
Never use that path to soften, hedge, or add a claim. That is a correction
(`corrected-by:`) or a new decision. This applies to the fixtures too.

## The vendored fixture corpus

`test/fixtures/dialect/` is a copy; the canonical one lives in `dirahq-cli` at
`cli/core/testdata/zavet-dialect/`. Two parsers read the same frontmatter
dialect, and drift between them is the failure mode the corpus exists to catch.

After changing any fixture:

```bash
sh test/sync-check.sh --write   # regenerate MANIFEST
```

CI additionally diffs this MANIFEST against `dirahq-cli`'s `develop` branch, so
a dialect change here needs the matching change there. If that job fails, do not
"fix" it by regenerating the MANIFEST — the two corpora genuinely disagree, and
one of them is wrong.

## Verifying a change

```bash
sh test/run.sh
```

Runs everything: the dialect corpus, glob matching, the CI trailer floor,
audit, the version contract, verify, id collisions, prefix derivation, the
hooks, the cross-harness adapters, and the per-harness deny envelopes. There
is no watch mode and no partial run — it takes seconds.

Before touching anything under `.agents/skills/`, `AGENTS.md`, `.grok/` or
`.zavet/githooks/` in a *consuming* repo, remember those are all generated by
`zavet adapters`. The templates for them live in `bin/zavet` itself
(`ctx_render_*`), not in `templates/`.

## This file has no `zavet:agents` block

In a repo that uses zavet, `zavet adapters` maintains a generated block here
carrying the standing rules and decision index. This repo has no `.zavet/` — it
builds the tool, it does not yet record its own decisions with it — so there is
nothing to generate and no markers to keep current. Everything above is
hand-written and stays that way until that changes.
