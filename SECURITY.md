# Security Policy

## Why this file matters more than usual here

Zavet is not a passive documentation tool. Once installed, its `hooks/hooks.json` registers
`PreToolUse` hooks that run **shell scripts on every `Edit`, `Write`, `MultiEdit`, and
`NotebookEdit` tool call, and on every `Bash` call**, in a user's Claude Code session:

| Hook | Fires on | Script |
|---|---|---|
| `SessionStart` | every new session | `hooks/scripts/session-context.sh` |
| `PreToolUse` | `Edit \| Write \| MultiEdit \| NotebookEdit` | `hooks/scripts/guard-edit.sh` |
| `PreToolUse` | `Bash` | `hooks/scripts/guard-commit.sh` |

That is a lot of surface: these scripts run, unattended, on effectively every file the agent
touches and every command it runs, for as long as the plugin is installed. Report anything
that looks like it could turn that surface into something other than "read a repo-local
`.zavet/` directory and occasionally deny a tool call with an explanatory message."

## Reporting a vulnerability

**Please report privately, not via a public issue.** Use GitHub's
[private vulnerability reporting](https://github.com/dodi-smart/dirahq-zavet/security/advisories/new)
(Security tab → "Report a vulnerability") on this repository. That opens a private advisory
only maintainers can see, which we can turn into a public disclosure and a coordinated fix
once one exists.

We'll acknowledge new reports within a few business days. There's no bug bounty; there is a
credit in the advisory and the changelog if you want one.

## Design intent: fail-open, always

Every hook script in this repo is written to **fail open** — on any missing dependency,
unreadable file, unexpected input shape, or condition the author didn't anticipate, the
script exits `0` (or `2`/deny with a *specific, expected* reason) rather than blocking the
tool call or crashing the session. Concretely:

- `command -v jq` / `command -v git` failures exit `0` immediately — a missing tool is a
  silent no-op, never a stuck or broken hook.
- Every intermediate step that can plausibly fail (an unreadable file, a `cd` into a path
  that no longer exists, a repo without `.zavet/`) is a guarded `|| exit 0`, not an
  unguarded pipeline.
- The only case where a hook denies a tool call is the one deliberate, documented case each
  script exists for (an unread guard, a commit missing a required trailer) — never as a side
  effect of an error.

This is a considered security posture, not an oversight: a knowledge-capture tool that can
wedge an agent's ability to edit files or run `git commit` on a transient failure is worse
than useless, so every failure mode is designed to degrade to "the plugin did nothing this
time" rather than "the session is stuck." If you find a path where a hook script instead
throws, hangs, or blocks progress on anything other than its one intentional deny condition,
that is a bug worth reporting even if it isn't itself an exploitable vulnerability.

Fail-open is a safety property for availability, not a claim about what the hooks are
authorized to do — see the next section for what they can still act on.

## `zavet verify` executes repository content

`zavet verify` (and the `/zavet:verify` command) runs the shell commands recorded in a
record's `checks:` frontmatter. It is the **only** part of this plugin that executes
anything out of the repository, and the rule that keeps that safe is a hard one:

- It runs **only on an explicit invocation** — a human typing `/zavet:verify`, or a CI job
  that opted in by calling `zavet verify`.
- It is **never wired into a hook**. No `PreToolUse`, no `PostToolUse`, no `SessionStart`.
  Cloning a repository and opening an agent session in it must never be able to run that
  repository's commands, and a `checks:` entry must never turn reading a record into
  running it.
- Nothing else in the plugin ever shells out to a `checks:` value. The edit and commit
  hooks read `guards`, `Agent directives` and `corrected-by`; they do not look at
  `checks:` at all.

The fail-open posture above deliberately does **not** apply here: `verify` reports a
non-zero exit when a check fails, because a check that silently passes on error is worse
than no check.

Treat a pull request that adds a `checks:` entry the way you would treat one that edits a
CI workflow or a `package.json` script — it is a request to run that command on whoever
runs `verify` next.

## Dependency surface

`bin/zavet` and the hook scripts are POSIX `sh`. The exact dependency split:

- **Hard** (the plugin's core functionality does not run without these): `git`, `awk`,
  `sed`. `bin/zavet` says so at the top of the file and never shells out to anything else
  to parse `.zavet/` content or the plugin manifest.
- **Optional**: `jq`. Both `PreToolUse` hook scripts (`guard-edit.sh`, `guard-commit.sh`)
  use `jq` to parse the JSON payload Claude Code passes on stdin, but check
  `command -v jq` first and exit `0` (silent no-op) if it's absent — `jq` is a soft
  dependency of the *hooks*, never of `bin/zavet` itself, which reads its own manifest via
  `sed`/`awk` only.
- **Optional, best-effort**: `dira`. When present and running, guard events are forwarded to
  it fire-and-forget (`command -v dira` gated, never blocking, never required). Its absence,
  or any failure talking to it, changes nothing about zavet's own behavior.

No hook script downloads anything, writes outside the repo it's invoked in (beyond a
session-scoped, PID/session-id-named temp file under `${TMPDIR:-/tmp}`), or executes content
that originated from a file being edited — inputs are treated as data (file paths, commit
messages, staged diffs), never evaluated as code.

## Scope

This policy covers the `zavet` plugin in this repository: `bin/zavet`, `hooks/`,
`commands/`, `skills/`, and the release/CI tooling that ships them. Vulnerabilities in
[dira](https://github.com/dodi-smart/dirahq-cli) (the `dira`/`dirad` binaries) or in Claude
Code itself belong to their respective projects — see
[dirahq-cli's security reporting](https://github.com/dodi-smart/dirahq-cli/security) and
[Anthropic's for Claude Code](https://www.anthropic.com/responsible-disclosure-policy).
