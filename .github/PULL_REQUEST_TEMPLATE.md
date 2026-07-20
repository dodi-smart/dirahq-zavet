## Summary

<!-- What does this change, and why? -->

## Test plan

- [ ] `sh test/run.sh` passes
- [ ] `shellcheck bin/zavet hooks/scripts/*.sh test/*.sh scripts/*.sh` is clean
- [ ] `sh test/sync-check.sh` passes (only relevant if you touched `test/fixtures/dialect/`)
- [ ] `claude plugin validate . --strict` passes (only relevant if you touched
      `.claude-plugin/`)

## Checklist

- [ ] Commits are signed off (`git commit -s`) per the
      [DCO](../CONTRIBUTING.md#developer-certificate-of-origin-dco)
- [ ] Commit messages follow Conventional Commits with a scope from
      `plugin, ci, release, repo, docs, deps`
- [ ] This PR targets `main` (zavet has no `develop` branch — see CONTRIBUTING.md)
