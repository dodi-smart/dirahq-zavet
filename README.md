# Zavet

**Repo-local knowledge layer for AI-assisted development.** Zavet captures the
*reasoning* behind your code — as a byproduct of agent work, not a
documentation chore — and mechanically stops agents (and humans) from
reverting intentional behavior they never knew was intentional.

Zavet is the knowledge sibling of [dira](https://github.com/dodi-smart/dirahq-cli),
the AI-first time tracker. dira answers *"where did the time go?"* — zavet
answers *"what did that time produce, and why?"* Each works fully without the
other; together they correlate every decision with the sessions (human engaged
time, agent wall-clock, tokens) that produced it.

## What it does

- **Decision records** — append-only `<PREFIX>-NNNN` markdown files in
  `.zavet/decisions/`, under 60 lines: decision, why, rejected alternatives,
  agent directives. The prefix is per repo (`CLOUD-00042`, `CLI-00007`), so an
  id stays unambiguous when several repos sit under one project. Superseding is
  explicit and tracked; rewriting history is not possible by convention or
  hook. A record that only needs ONE claim corrected gets
  `corrected-by: <NEW-ID>` and stays `active` — every recall path then leads
  with the correction, instead of the reader hitting the wrong claim first.
- **Checks** — a record can say *how* its invariants are verified, as
  `label :: command`. The command is opaque: any runner, any stack, exit 0 is
  pass, no output is parsed. `zavet verify` runs them; nothing else does.
- **Guards** — a decision declares path globs over the code it shapes. The
  first time in a session an agent edits a guarded path, the edit is held and
  the decision is shown (*teach before change*); a commit touching guarded
  paths without a `Refs:`/`Supersedes:` trailer is blocked.
- **Commit trailers** — micro-decision capture in commit footers: `Why:`,
  `Rejected:`, `Constraint:`, `Refs:`, `Supersedes:`, `Spec:`.
- **Living specs** — sectioned feature documents in `.zavet/specs/<slug>.md`,
  **maintained transparently while agents work**: the skill instructs the
  agent to keep the covering spec current as part of implementing, and the
  commit hook nudges (once per session) when staged work touches spec-covered
  paths without the spec staged or a `Spec:` trailer. PRs arrive carrying the
  spec of what was implemented, the decisions that shaped it, and its
  trailers — no command invoked.
- **Index-first recall** — `/zavet:why` answers "why is it like this?" from
  `INDEX.md` → grep → at most 3 documents, with decision-id citations.
- **Session context** — standing rules, the decision index, and the living
  specs are injected at session start, so agents begin every session knowing
  what has been decided.
- **Cross-harness** — the workflows ship as [Agent
  Skills](https://agentskills.io), so they run on Claude Code, Grok Build,
  Codex, Cursor, Gemini CLI, OpenCode, Copilot and ~70 other harnesses. Guards
  hold for every teammate regardless of what they run: natively where the
  harness has a blocking hook, and through a `commit-msg` git hook plus CI
  everywhere else. See [Cross-harness support](#cross-harness-support).

Everything is plain markdown + git. No daemon, no cloud, no lock-in: the
`.zavet/` directory is fully functional offline and readable without any tool.

## Install

Two halves, installed independently:

1. **Your harness** needs zavet's workflows. Claude Code takes them as a plugin;
   everything else takes them as Agent Skills.
2. **Your repo** needs its knowledge layer and its enforcement wiring —
   `/zavet:init`, once, committed. Every teammate then gets it from the clone,
   whatever they run.

| Your harness | Install |
|---|---|
| Claude Code | `/plugin install zavet@dirahq` (below) |
| Grok Build, Codex, Cursor, Gemini CLI, OpenCode, Copilot, Amp, Factory, … | `npx skills add dodi-smart/dirahq-zavet` |

### Claude Code

Installed from this repo's marketplace manifest
(`.claude-plugin/marketplace.json`). Pick whichever of these three paths fits how
you work — they all end at the same installed plugin.

**Interactive (Claude Code REPL):**

```
/plugin marketplace add dodi-smart/dirahq-zavet
/plugin install zavet@dirahq
```

**Scriptable (CI, dotfiles, bootstrap scripts)** — the `claude` CLI exposes
the same two steps outside the REPL:

```sh
claude plugin marketplace add dodi-smart/dirahq-zavet && \
  claude plugin install zavet@dirahq
```

**From dira** — if you already run dira, one command does both steps:

```sh
dira zavet install
```

It shells out to the same `claude plugin` calls above rather than
hand-writing plugin state, detects an existing install and no-ops (pass
`--update` to refresh), and prints an advisory line if this dira build is
older than the `min_dira` below. `--dry-run` shows the exact `claude`
invocations without running them.

Every install path takes an optional `--scope <user|project|local>` (default
`user`); see `claude plugin install --help`. **Claude Code must be restarted
after install** for the plugin's commands and hooks to become active.

### Every other harness

The same eight workflows are published as [Agent
Skills](https://agentskills.io) under `.agents/skills/`, installed with the
ecosystem's own installer:

```sh
npx skills add dodi-smart/dirahq-zavet
```

It auto-detects the harnesses you have installed and wires the skills into each
one's directory, symlinked to a single canonical copy. Useful flags: `-a grok`
(or `codex`, `cursor`, …) to target one harness, `-g` for user-wide instead of
this project, `--copy` where symlinks are not available, and `npx skills update`
to refresh. The skills are `zavet` plus `zavet-init`, `zavet-decide`,
`zavet-why`, `zavet-wiki`, `zavet-backfill`, `zavet-spec`, `zavet-audit` and
`zavet-verify` — invoke them the way your harness invokes skills (`/zavet-why`
on most, `$zavet-why` in Codex).

This path works for Claude Code too, if you would rather not install a plugin.
You lose the live hooks; you keep the workflows.

### Then, in each repo

```
/zavet:init
```

Scaffolds `.zavet/` **and** the cross-harness layer: a vendored
`.zavet/bin/zavet`, an `AGENTS.md` block, `.grok/rules/` + `.grok/hooks/`, and
`.zavet/githooks/`. Commit all of it — that is what makes the repo's guards
hold for teammates on other harnesses. Then activate the git-hook floor:

```sh
.zavet/bin/zavet hooks install
```

Requirements: `git`, POSIX `sh`, `awk`. Hooks additionally use `jq` (they
silently no-op without it). `dira` is optional.

## Cross-harness support

Zavet is built for Claude Code and Grok Build first, and degrades honestly
everywhere else. The table is what was actually verified against each harness's
documentation and, for Grok Build, its source — not what ought to work.

| | Claude Code | Grok Build | Cursor | Codex / Gemini / OpenCode / Copilot / … |
|---|---|---|---|---|
| Workflows as slash commands | plugin `commands/` | `.agents/skills/` | `.agents/skills/` | `.agents/skills/` |
| Ambient knowledge skill | plugin `skills/` | `.agents/skills/` | `.agents/skills/` | `.agents/skills/` |
| Knowledge index in context | **live** — SessionStart hook | **live** — `.grok/rules/zavet.md` | `AGENTS.md` | `AGENTS.md` |
| Index refreshed mid-session | next session | **yes** | no | no |
| Teach-before-change on edit | **yes** | **yes** | unverified¹ | no — check by hand² |
| Commit guard wall | **yes**, live | **yes**, live | **yes**, live | git `commit-msg` |
| Guard events to dira | `guard_*` | `guard_*` | `guard_*` | `guard_*_git`³ |
| CI enforcement | `zavet check` | `zavet check` | `zavet check` | `zavet check` |

**Claude Code and Grok Build are both first-class.** Both deny a guarded edit
and show you the record; both block an untrailered commit; both carry the
decision index in context from the first turn. Grok's index is arguably the
better of the two — Claude Code's is injected once at session start, while Grok
re-reads its project rules on every prompt build, so a decision recorded
mid-session shows up without a restart. Grok gates project hooks behind folder
trust, so run `/hooks-trust` (or launch with `--trust`) once per repo; until you
do, Grok skips them silently.

¹ Cursor's docs confirm that `beforeShellExecution` can deny, which is what the
commit wall needs, but do not say whether `preToolUse` can deny a file edit. The
hook is wired either way: if it can, the guard behaves as it does on Claude Code
and Grok Build; if it cannot, the hook is a no-op and the git-hook floor is what
holds. Enable it with `zavet adapters --cursor`.

² Nothing intercepts the edit, so the ambient skill and `AGENTS.md` both instruct
the agent to run `.zavet/bin/zavet match <path>` before editing. The commit is
still caught — by the `commit-msg` hook locally and `zavet check` in CI — but by
then the code is already written against an unread decision. This is the real
gap, and it is a limit of those harnesses, not of the guard.

³ The `commit-msg` floor reports to dira under its own kinds, so a repo running
both it and a live hook — the recommended setup on Claude Code, since the floor
also catches commits made outside the agent loop — records both surfaces
without one commit being counted as two. See
[Guard event schema](#guard-event-schema-v1).

**The wall is one implementation.** Every surface above calls `zavet gate`, and
`zavet check` shares its trailer patterns. A repo cannot enforce one rule in the
agent loop and a different one at `git commit`, or teach a rule locally that CI
then rejects.

## Commands

| Command | Purpose |
|---|---|
| `/zavet:init` | Scaffold `.zavet/{INDEX.md,RULES.md,decisions/,specs/,glossary.md}` |
| `/zavet:decide` | Record a structural decision as an append-only `<PREFIX>-NNNN` record with guards |
| `/zavet:why` | Answer a "why" question from recorded knowledge, with citations (and time cost via dira when present) |
| `/zavet:wiki` | Browse the knowledge base wiki-style — rules, decisions, glossary, recent rationale |
| `/zavet:backfill` | Reverse-engineer an existing codebase into decision records — proposed to you first, written as `verified: false` hypotheses with open questions, never invented rationale |
| `/zavet:spec` | Living feature specs. Bare = *document* this session's work (normally happens transparently, no command needed); `design <feature>` = spec before code; `backfill <feature>` = reconstruct from existing code under the honesty rules |
| `/zavet:audit` | Report-only knowledge health sweep — code-vs-decision conflicts, stale specs, over-broad guards, unverified invariants, over-long records. Judges nothing it didn't open; changes nothing |
| `/zavet:verify` | Run the checks bound to decisions and specs, and report what is recorded but unchecked. The only command that executes repository content — always explicitly, never from a hook |

The `bin/zavet` helper is also usable directly (and from CI) — run
`bin/zavet help` for the full usage text:
`init [--prefix P] · root · bin · prefix [<NEW>] · prefixes ·
renumber [--base <ref>] [--force] <old> <new> · next-id · list · guards ·
checks · errata · match <path> · match-batch · decision-path <id> ·
section <id> <heading> · specs · spec-paths · spec-checks · spec-match ·
check <range> · gate · verify · audit · index · context · rules [--check] ·
agents-md [--check] · adapters [--check] [--cursor] · hooks [install|--check] ·
hook <kind> · deny [--format claude|grok|cursor] <reason> ·
emit <kind> <id> [file] · version [--json]`.

The cross-harness subcommands, in the order you would meet them:

| Command | Purpose |
|---|---|
| `zavet adapters [--check] [--cursor]` | Write (or drift-check) everything a repo needs off Claude Code: the vendored CLI, the `AGENTS.md` block, `.grok/rules/` + `.grok/hooks/`, the git-hook templates, and optionally `.cursor/hooks.json`. Run by `zavet init`; re-run after upgrading the plugin. |
| `zavet hooks install` | Point `core.hooksPath` at `.zavet/githooks` to activate the enforcement floor. Refuses to take over a `core.hooksPath` that already belongs to Husky or lefthook, and prints the one line to add instead. |
| `zavet gate` | The guard wall over a prospective commit — staged paths plus the message it is about to carry. What every hook calls. |
| `zavet hook <kind>` | Run a guard over a harness event on stdin (`guard-edit`, `guard-commit`, `refresh`). The generated hook configs call this. |
| `zavet rules` / `zavet agents-md` | Regenerate one context file. `zavet index` does both, so you rarely call these directly; `--check` is for CI. |
| `zavet context` | The session-start payload on stdout, for a harness whose SessionStart hook can inject it. |
| `zavet bin` | Print the resolved zavet executable (`$ZAVET_BIN` → `.zavet/bin/zavet` → `PATH` → `$CLAUDE_PLUGIN_ROOT/bin/zavet`). |

## Decision ids

An id is `<PREFIX>-<number>`. The prefix belongs to the repo and lives in
`.zavet/config`:

```
prefix: CLOUD
prefix-aliases: D
id-width: 5
```

### Deriving one

A prefix has to carry the **product**, not just the role. `cloud`, `cli`,
`web` and `api` are exactly the segments that repeat across sibling repos, so
keying on the last segment hands them all the same prefix — the ambiguity
prefixes exist to remove. So the default is a product stem plus a canonical
role code:

| repo | prefix | why |
|---|---|---|
| `dirahq-cloud` | `DIRABE` | `dira` + backend (`cloud`/`server`/`api` all mean backend) |
| `dirahq-cli` | `DIRASH` | `dira` + shell |
| `dirahq-zavet` | `ZAVET` | no role segment — the name *is* the identity |
| `teamschedule/time-schedule-application` | `TIMEAP` | `schedule` echoes the org, so `time` is what distinguishes it |
| `infrasensing-supabase-platform` | `INFRPF` | `supabase` is stack, not identity |

Segments are classified rather than truncated. Corporate noise (`hq`, `inc`,
`labs`) is dropped, including as a suffix *inside* a segment — that is how
`DIRAHQ` becomes `DIRA`. Stack names (`supabase`, `react`, `postgres`) are
dropped too: they describe how a thing is built, not what it is. Role words
map to a short code — `BE FE SH AP PF WK GW LIB DOC` — and the stem takes
whatever the six-character budget leaves.

Tokens that merely echo the org are dropped, because inside one workspace they
disambiguate nothing. The org comes from the remote's owner, falling back to
the parent directory name, so `~/src/teamschedule/time-schedule-application`
derives the same as a fresh clone. A repo named after its own org keeps its
name rather than deriving from the role alone.

`zavet suggest` prints the ranked candidates with their rationale, plus any
prefix a **sibling repo already holds** — one level up, reading `.zavet/config`
only, offline. `/zavet:init` puts that list in front of you before scaffolding,
because a rule can only lower the odds of a collision; reading the siblings
detects one.

**A repo with no `.zavet/config` mints plain `D-NNNN` at width 4, exactly as
before prefixes existed.** Nothing to migrate: adopting a prefix is per repo
and opt-in.

`zavet prefix <NEW>` changes only what FUTURE ids are minted with. Existing
records are never renamed — their ids are load-bearing in commit trailers
already in the log — so the old prefix is retired into `prefix-aliases`, where
it stays resolvable forever, and the counter continues unbroken (`D-0041` is
followed by `CLOUD-0042`). Numbers are never reused, across prefixes or after
a deletion.

`id-width` is fixed when the repo is scaffolded (new repos get 5, config-less
repos stay at 4). It is a key, not a display choice: an id minted at one width
would never join a shorthand ref resolved at another.

### When two branches claim one id

Ids are chosen per branch, so this is possible; `zavet check` catches it in CI
against the merge result and prints the repair:

```
violation-duplicate-id	CLOUD-00042	CLOUD-00042-ours.md CLOUD-00042-theirs.md
  → sh bin/zavet renumber CLOUD-00042 CLOUD-00043
```

`zavet renumber` moves the record, rewrites its own `id:`, every
`supersedes` / `superseded-by` / `corrected-by` pointer, spec `decisions:`
lists and inline refs, and regenerates the index. It **refuses** a record
already reachable from the base branch (`--base`, default `origin/HEAD`),
because from that point the id is referenced by commit trailers it cannot
rewrite — correct that with a new decision, not a rename. It also cannot
rewrite trailers in your own local commits, so it names them and leaves the
amend to you.

## CI enforcement

`zavet check` is the enforcement floor for machines without hooks: over a
commit range, any non-merge commit whose changed files match an **active
guard glob** must carry a `Refs: <ID>` or `Supersedes: <ID>` trailer in its
commit message — exactly the rule the commit hook applies interactively. `<ID>`
may carry any prefix the repo mints or has retired, so commits predating a
`zavet prefix` change stay compliant.
Commits touching **spec-covered paths** without a `Spec: <slug>` trailer
produce warnings only (the hook is a nudge; CI is not stricter).

Two tree-wide checks run on every invocation, whatever the range covers,
because both are properties of the records rather than of the commits:

- **duplicate ids** — two records claiming one id. Ids are chosen per branch,
  so two branches open at once can both pick the same number; in CI this runs
  against the merge result, so the collision fails the PR instead of landing,
  and the summary names the `zavet renumber` command that repairs it. Compared
  canonically within a prefix, so `CLOUD-7` cannot hide behind `CLOUD-00007` —
  and across prefixes it is not a collision at all, since `CLOUD-00007` and
  `CLI-00007` are different decisions.
- **dangling `corrected-by`** — a pointer naming a record that does not exist.

Exit code `1` on any of the three; repos without `.zavet/` pass, so one
org-wide workflow is safe.

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0            # zavet check walks real history
- name: zavet guard floor
  run: sh path/to/bin/zavet check "${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }}"
```

For push builds: `git fetch origin main && sh bin/zavet check origin/main..HEAD`.
Output is TSV (`violation` / `warn-spec` / `violation-duplicate-id` /
`violation-errata` rows) with a human summary on stderr.

`fetch-depth: 0` matters for a second reason: `zavet next-id` takes the next
free id from the working tree **and every decision filename that has ever
existed on any ref**, so a shallow clone that cannot see the other branches
hands out an id someone else already took. History counts as well as the
current tree — ids are append-only, and a deleted record still burns its
number, or the `Refs:` trailers already in the log would start pointing at a
different decision. The scan counts every prefix the repo has ever minted, so
retiring one does not reset the counter.

That scan is best-effort by construction: a branch this clone has never
fetched is invisible to it. The duplicate-id check above is the guarantee —
`next-id` just makes it rare that the guarantee has to fire.

## dira integration (optional)

When [dira](https://github.com/dodi-smart/dirahq-cli) is installed and its
daemon runs, every guard event is forwarded — fire-and-forget, never blocking —
to the local daemon, which attributes it to the active session:

- `dira zavet why D-0042` → the decision **plus its cost**: human engaged time,
  agent wall-clock, and tokens of the sessions that originated and referenced it.
- `dira zavet status` / `dira zavet decisions` → capture health per repo.

Without dira nothing changes except that guard events go nowhere.

### Guard event schema (v1)

What the hooks send to `dira zavet emit` on stdin:

```json
{
  "v": 1,
  "kind": "guard_shown | guard_blocked | guard_complied | guard_overridden | decision_superseded (each guard/superseded kind also has a _git form — see below)",
  "decision_id": "D-0042",
  "file_path": "src/auth/session.ts",
  "cwd": "/abs/path/inside/repo",
  "ts": "2026-07-15T12:00:00Z"
}
```

`v`, `kind`, `decision_id`, `cwd` are required. Unknown fields are ignored;
unknown kinds are stored verbatim. The daemon resolves the repo from `cwd` and
never trusts a caller-supplied repo identity. Delivery is best-effort: a
missing daemon, an older dira, or a dropped event must never affect the hooks.

**The surface is part of the kind.** The `commit-msg` git hook — the
[enforcement floor](#cross-harness-support) for harnesses with no hook API —
emits `guard_blocked_git`, `guard_complied_git` and `decision_superseded_git`.
A repo can legitimately run both surfaces at once: the live hook catches the
agent's commit, the git floor also catches a terminal `git commit`, an IDE
commit button, a `git rebase --continue`. `zavet_guard_events` has no
uniqueness constraint that would collapse one commit reported twice, so the two
surfaces are named apart instead — nothing is lost, and nothing is silently
counted twice. Aggregation groups by `kind` with no fixed list, so the `_git`
kinds appear on their own row (`12 blocked · 3 blocked_git`) with no dira
release. Folding the two for display is a dira-side choice.

## Integration contract (stable)

`dira zavet install` (see [Install](#install)) and every other point of
contact between this plugin and dira depend on four things staying stable.
Changing any of them is a breaking change requiring a coordinated dirahq-cli
release, not a same-day fix:

1. **Identity** — marketplace `dirahq` + plugin `zavet` ⇒ install id
   `zavet@dirahq`.
2. **Location** — repo slug `dodi-smart/dirahq-zavet`, marketplace manifest
   at `.claude-plugin/marketplace.json`, default branch `main` (the
   marketplace source records no `ref`, so installs always clone the
   default branch — see [Releases](#releases--versioning)).
3. **Executable surface** — `bin/zavet` at the plugin root, supporting
   `version` and `version --json` (see [Version compatibility](#version-compatibility)).
   Also the hook-denial envelope: `zavet deny <reason>` and
   `zavet deny --format claude <reason>` are byte-identical to each other and to
   every build that predates formats. `--format grok` and `--format cursor` are
   additive — new shapes for new harnesses, never a change to the default.
   `test/run.sh` pins the exact default string.
4. **Wire format** — the guard-event schema on stdin of `dira zavet emit` is
   `v: 1` (see [Guard event schema](#guard-event-schema-v1) above).

## Version compatibility

`zavet version --json` is the machine-readable half of that contract:

```json
{"v":1,"plugin":"zavet","version":"0.1.0","emit_schema":1,"min_dira":"0.1.0"}
```

| Field | Meaning |
|---|---|
| `v` | Contract format version of this JSON blob itself (not the guard-event schema). |
| `plugin` | Always `"zavet"`. |
| `version` | The plugin's own version, read from `.claude-plugin/plugin.json`. |
| `emit_schema` | The guard-event schema version this build of `bin/zavet` emits (currently `1`). |
| `min_dira` | **Advisory only** — see below. |

**Posture: surface skew, never gate on it.** The whole premise of this
plugin is that each half of the dira + zavet pair works fully without the
other, so neither half is allowed to refuse to talk to the other over a
version mismatch. `zavet emit` stays fire-and-forget and unconditional
regardless of what `dira zavet version` reports. A plugin newer than the
installed dira already degrades correctly today: dira stores unknown guard
event `kind`s verbatim and filters at query time rather than rejecting them
(`dirahq-cli`'s [`docs/zavet.md:48-49`](https://github.com/dodi-smart/dirahq-cli/blob/develop/docs/zavet.md)).
dira is expected to keep accepting `v: 1` indefinitely. There is no
minimum-dira gate anywhere in this plugin, and there will not be one —
`min_dira` exists for humans and dashboards to read, never for `bin/zavet`
or the hooks to act on.

## Decision record format

```markdown
---
id: D-0042
title: Poll git instead of watching the filesystem
status: active
guards:
  - cli/dirad/src/capture.rs
  - "cli/core/src/project.rs"
checks:
  - capture survives a rebase :: <your runner here>
origin: recorded        # recorded | reverse-engineered
verified: true
---

## Decision
...

## Why
...

## Rejected
- ...

## Agent directives
- ...
```

Status transitions are append-only: the only permitted mutations are
`status: superseded` + `superseded-by: <NEW-ID>` (the record is REPLACED), and
`corrected-by: <NEW-ID>` (one claim inside it is wrong; the record stays
`active` and its body is untouched). Both are frontmatter-only. `zavet check`
fails on a `corrected-by` naming a record that does not exist.

### Checks

A check binds an invariant to the command that proves it:

```yaml
checks:
  - pg suite forbids module mocks :: <command>   # label :: command
  - <command>                                    # no separator: command is its own label
  - "keeps a hash :: <command with a # in it>"   # quote to survive decomment
```

**Zavet declares the binding; your repo owns the runner.** Nothing here
detects, infers or special-cases a framework, language or package manager, and
no output format is implied — *exit 0 is pass* is the entire contract. A
decision's checks are invariants ("this must never become true again"); a
spec's are scenarios ("this flow still works").

`zavet verify` is the only thing that runs them, and only when you ask:

```sh
zavet verify                    # everything
zavet verify --id D-0042        # one decision
zavet verify --spec mobile-shell
zavet verify --paths src/a.ts   # whatever guards/specs cover these paths
```

Recording an invariant with no check is fine — many genuinely cannot be
checked. Recording one and saying nothing about verification is not, because
silence reads as coverage; `zavet audit` reports those as
`uncovered-invariant`.

`zavet audit` also reports the cross-harness layer, because every way it breaks
is silent:

| Row | Means |
|---|---|
| `adapter-missing` | No `AGENTS.md` block or `.grok/rules/zavet.md`. Agents off Claude Code see no decisions at all — which reads as "this repo has none". Run `zavet adapters`. |
| `adapter-stale` | The generated index no longer matches the records. Worse than missing: a stale index reads as authoritative, so an agent will confidently cite a decision that was superseded three commits ago. |
| `adapter-ignored` | The file is gitignored. Grok Build's rules discovery honors `.gitignore` (its *skill* discovery deliberately does not), so the file is invisible on every machine, including the one that wrote it. |
| `githook-floor` | `core.hooksPath` does not point at `.zavet/githooks`, so the wall is not enforced for anyone whose harness has no hook API. An unenforced floor looks exactly like a compliant repo until someone commits over a guard. |

`zavet check` warns on `adapter-stale` too, but never fails the build over it —
the file is derived and one command repairs it, and failing a PR over a derived
artifact just teaches people to ignore the check.

**Honesty rule:** knowledge reconstructed from existing code is marked
`origin: reverse-engineered`, `verified: false`, with open questions instead of
invented rationale. A wrong recorded "why" is worse than none.

## Spec format

Living documents in `.zavet/specs/<slug>.md` — flat kebab-case filenames (the
slug is the identity; dira captures the directory by name). This frontmatter
is the interface contract dira parses:

```markdown
---
title: Zavet capture pipeline
version: 1
origin: session          # designed | session | reverse-engineered
verified: false          # true only after a human confirms spec matches code
confidence: high         # low | med | high
date: 2026-07-16
paths:                   # git pathspecs the spec covers (globs allowed)
  - cli/dirad/src/capture.rs
decisions: [D-0001]      # optional; body D-refs auto-link too
---
## Overview
## Behavior
## Interfaces & data
## Invariants
## Open Questions        <!-- mandatory + non-empty when reverse-engineered -->
```

Specs link decisions, never the reverse — decisions stay append-only, the
living doc carries the pointers. With dira installed, commits touching a
spec's `paths` after its last update mark it **stale** in `dira zavet wiki`,
and `dira zavet why` resolves free-text questions against specs and decisions
together.

## Releases & versioning

`main` is the single release channel — there is no `develop` prerelease
branch here, because the marketplace source in `known_marketplaces.json`
records no `ref` and always installs the default branch, so a second
channel would simply be invisible to every install. Releases are cut by
[semantic-release](https://semantic-release.gitbook.io/) from Conventional
Commit history on `main`; tags are `v${version}`. The version of record is the
`"version"` key in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json),
bumped automatically by `scripts/set-version.sh` as part of each release.
**Do not hand-edit that version** — a manually bumped `plugin.json` and the
next automated release will disagree.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
