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
- **Index-first recall** — `/zavet:why` answers "why is it like this?" from
  `INDEX.md` → grep → at most 3 documents, with decision-id citations.
- **Session context** — standing rules and the decision index are injected at
  session start, so agents begin every session knowing what has been decided.

Everything is plain markdown + git. No daemon, no cloud, no lock-in: the
`.zavet/` directory is fully functional offline and readable without any tool.

## Install

As a Claude Code plugin:

```
/plugin marketplace add dodi-smart/dirahq-zavet
/plugin install zavet@dirahq
```

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
| `/zavet:why` | Answer a "why" question from recorded knowledge, with citations |

The `bin/zavet` helper is also usable directly (and from CI):
`init · list · guards · match <path> · next-id · decision-path <id> · index · emit`.

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

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
