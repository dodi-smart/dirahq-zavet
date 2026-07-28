# Contributing to Zavet

Thank you for your interest in contributing. Zavet is the knowledge-layer sibling of
[dira](https://github.com/dodi-smart/dirahq-cli) — a Claude Code plugin, licensed under
Apache-2.0, from the same org. This document mirrors
[dirahq-cli's `CONTRIBUTING.md`](https://github.com/dodi-smart/dirahq-cli/blob/develop/CONTRIBUTING.md)
deliberately: same org, same license, both repos take outside patches, and there's no good
reason for two different contribution bars across two halves of one product. The differences
that do exist follow from this being a plugin (POSIX `sh`, single release channel) rather
than a set of Rust binaries, and are called out explicitly below.

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

**Found a security issue?** Don't open a public issue — see [SECURITY.md](SECURITY.md) for
private reporting. Note the bar is lower than usual here: these hooks run shell scripts on
every `Edit`/`Write`/`Bash` tool call in a user's session, so anything that widens that
surface is worth reporting even if you can't demonstrate an exploit.

## Developer Certificate of Origin (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/). By signing
off on your commits, you certify that you wrote the patch or have the right to submit it
under the project's Apache-2.0 license.

Add a sign-off line to every commit:

    git commit -s -m "feat(plugin): add ..."

which appends:

    Signed-off-by: Your Name <your.email@example.com>

Pull requests whose commits are not signed off will be asked to amend.

## Ground rules

- Conventional commit messages with a mandatory scope, one of `plugin`, `ci`, `release`,
  `repo`, `docs`, `deps` (enforced by `commitlint.config.mjs` and the `commit-lint` CI job).
  Keep each line under 180 characters.
- Run `sh test/run.sh` and
  `shellcheck bin/zavet hooks/scripts/*.sh test/*.sh scripts/*.sh` before opening a PR — this
  repo's equivalent of dira's `just ci`. Everything shipped here is POSIX `sh`; there is no
  compile step, so these two commands are the whole local gate.
- If your change touches `test/fixtures/dialect/`, also run `sh test/sync-check.sh` and read
  its [`README.md`](test/fixtures/dialect/README.md) first — those fixtures are a
  byte-identical, MANIFEST-guarded mirror of a Rust implementation in a different repo, not
  free-standing test data.
- Contributions to this repository are licensed under Apache-2.0.
- "Zavet", "Dira", and their logos are trademarks of Dodi Smart OOD and are not licensed for
  use in derivative or competing products.

## Branching: PRs target `main`

Unlike dira, zavet has no `develop` / prerelease branch — **open PRs directly against
`main`**.

Why: a Claude Code `github` marketplace source (see `.claude-plugin/marketplace.json`)
records no `ref`, so `claude plugin install` and `claude plugin update` always clone the
default branch. A `develop` channel here would be invisible to every installed user, and
anything on `main` short of release-ready would ship broken or half-finished behavior to
everyone the moment it merges. `main` *is* the release channel, so it must always be
installable — that constraint is what keeps this repo single-branch where dira is not.

## Releases (automated — never bump versions by hand)

Releases are run by [semantic-release](https://semantic-release.gitbook.io/) on every push
to `main`: it tags `v${version}` and
bumps `.claude-plugin/plugin.json`'s `version` field via `scripts/set-version.sh` as part of
that release commit. Don't hand-edit the version, and don't add custom keys to
`plugin.json` — `claude plugin validate --strict` treats unrecognized fields as errors.

Don't cut tags by hand either, including with `claude plugin tag` — that command uses a
different format (`zavet--v${version}`, two dashes) and would start a parallel tag series
that semantic-release does not read. Releasing is the only thing that creates a tag.
