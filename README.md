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

- **Decision records** — append-only `D-NNNN` markdown files in
  `.zavet/decisions/`, ≤25 lines: decision, why, rejected alternatives, agent
  directives. Superseding is explicit and tracked; rewriting history is not
  possible by convention or hook.
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

Everything is plain markdown + git. No daemon, no cloud, no lock-in: the
`.zavet/` directory is fully functional offline and readable without any tool.

## Install

Zavet is a Claude Code plugin, installed from this repo's marketplace
manifest (`.claude-plugin/marketplace.json`). Pick whichever of these three
paths fits how you work — they all end at the same installed plugin.

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

Then, in a repo you want to track:

```
/zavet:init
```

Requirements: `git`, POSIX `sh`, `awk`. Hooks additionally use `jq` (they
silently no-op without it). `dira` is optional.

## Commands

| Command | Purpose |
|---|---|
| `/zavet:init` | Scaffold `.zavet/{INDEX.md,RULES.md,decisions/,specs/,glossary.md}` |
| `/zavet:decide` | Record a structural decision as an append-only `D-NNNN` record with guards |
| `/zavet:why` | Answer a "why" question from recorded knowledge, with citations (and time cost via dira when present) |
| `/zavet:wiki` | Browse the knowledge base wiki-style — rules, decisions, glossary, recent rationale |
| `/zavet:backfill` | Reverse-engineer an existing codebase into decision records — proposed to you first, written as `verified: false` hypotheses with open questions, never invented rationale |
| `/zavet:spec` | Living feature specs. Bare = *document* this session's work (normally happens transparently, no command needed); `design <feature>` = spec before code; `backfill <feature>` = reconstruct from existing code under the honesty rules |
| `/zavet:audit` | Report-only knowledge health sweep — code-vs-decision conflicts, stale specs, over-broad guards. Judges nothing it didn't open; changes nothing |

The `bin/zavet` helper is also usable directly (and from CI) — run
`bin/zavet help` for the full usage text:
`init · root · next-id · list · guards · match <path> · match-batch ·
decision-path <id> · specs · spec-paths · spec-match · check <range> ·
audit · index · deny <reason> · emit <kind> <id> [file] · version [--json]`.

## CI enforcement

`zavet check` is the enforcement floor for machines without hooks: over a
commit range, any non-merge commit whose changed files match an **active
guard glob** must carry a `Refs: D-NNNN` or `Supersedes: D-NNNN` trailer in
its commit message — exactly the rule the commit hook applies interactively.
Commits touching **spec-covered paths** without a `Spec: <slug>` trailer
produce warnings only (the hook is a nudge; CI is not stricter). Exit code:
`1` only on guard violations; repos without `.zavet/` pass, so one org-wide
workflow is safe.

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0            # zavet check walks real history
- name: zavet guard floor
  run: sh path/to/bin/zavet check "${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }}"
```

For push builds: `git fetch origin main && sh bin/zavet check origin/main..HEAD`.
Output is TSV (`violation`/`warn-spec` rows: sha, ids/slugs, subject) with a
human summary on stderr.

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
  "kind": "guard_shown | guard_blocked | guard_complied | guard_overridden | decision_superseded",
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

Status transitions are append-only: the only permitted mutation is
`status: superseded` + `superseded-by: D-MMMM`.

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
