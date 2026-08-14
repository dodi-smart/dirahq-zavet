## [1.4.1](https://github.com/dodi-smart/dirahq-zavet/compare/v1.4.0...v1.4.1) (2026-08-14)

### 🐛 Bug Fixes

* **plugin:** close guard-wall bypasses, id-counter inflation, and per-edit refresh churn ([fdf79a3](https://github.com/dodi-smart/dirahq-zavet/commit/fdf79a350bf7c99e8f566b6d776dce41fbaa3989))

### 👷 Continuous Integration

* **plugin:** bound fixture-sync and fail gen-adapters loudly on a missing source ([fe8d83d](https://github.com/dodi-smart/dirahq-zavet/commit/fe8d83d2f5cd2b77f7149121d88a82abed854eed))

## [1.4.0](https://github.com/dodi-smart/dirahq-zavet/compare/v1.3.0...v1.4.0) (2026-08-09)

### ✨ Features

* **plugin:** report guard events from the git-hook floor under _git kinds ([3db2558](https://github.com/dodi-smart/dirahq-zavet/commit/3db2558032069d549a322f0de2729cc147f67b2a)), closes [#13](https://github.com/dodi-smart/dirahq-zavet/issues/13)

### 🐛 Bug Fixes

* **ci:** fetch the canonical MANIFEST over raw, not the rate-limited API ([e36fbed](https://github.com/dodi-smart/dirahq-zavet/commit/e36fbed8e6e0af10ca16c3c47db2f556f2e96ca2))

## [1.3.0](https://github.com/dodi-smart/dirahq-zavet/compare/v1.2.0...v1.3.0) (2026-08-07)

### ✨ Features

* **plugin:** make zavet work on every harness, not just Claude Code ([92778f9](https://github.com/dodi-smart/dirahq-zavet/commit/92778f9cb883e3650f4f6e805c31869288d8bbb8))

## [1.2.0](https://github.com/dodi-smart/dirahq-zavet/compare/v1.1.1...v1.2.0) (2026-08-07)

### ✨ Features

* **plugin:** give each repo its own decision-id prefix ([9d724f2](https://github.com/dodi-smart/dirahq-zavet/commit/9d724f25966e3797b3225e612240c00a5eb132fa)), closes [dodi-smart/dirahq-cli#97](https://github.com/dodi-smart/dirahq-cli/issues/97)

## [1.1.1](https://github.com/dodi-smart/dirahq-zavet/compare/v1.1.0...v1.1.1) (2026-08-02)

### 🐛 Bug Fixes

* **plugin:** stop two branches from claiming the same decision id ([19f3000](https://github.com/dodi-smart/dirahq-zavet/commit/19f3000e934ad63e947d58e1e5ef18a8f69a0a08))

## [1.1.0](https://github.com/dodi-smart/dirahq-zavet/compare/v1.0.0...v1.1.0) (2026-08-01)

### ✨ Features

* **plugin:** record how an invariant is verified, and correct without replacing ([#9](https://github.com/dodi-smart/dirahq-zavet/issues/9)) ([35fbdc3](https://github.com/dodi-smart/dirahq-zavet/commit/35fbdc3313b99a0c6b359c012b637ab40181beb6)), closes [dodi-smart/dirahq-cli#82](https://github.com/dodi-smart/dirahq-cli/issues/82)

### 👷 Continuous Integration

* **ci:** make cross-repo dialect drift a hard failure ([#8](https://github.com/dodi-smart/dirahq-zavet/issues/8)) ([9909250](https://github.com/dodi-smart/dirahq-zavet/commit/99092504fe8cf51084914c0de9b92c41cb235930))

## 1.0.0 (2026-07-20)

### ✨ Features

* **plugin:** /zavet:audit — report-only knowledge health sweep ([7571e66](https://github.com/dodi-smart/dirahq-zavet/commit/7571e662c5bc054d73b00289ff456126fb5518f5))
* **plugin:** /zavet:backfill — reverse-engineer existing codebases into unverified records ([a83fd5f](https://github.com/dodi-smart/dirahq-zavet/commit/a83fd5f81237616fd8ac07dc03d248722a0cddae))
* **plugin:** /zavet:wiki browse command; /zavet:why leans on dira's free-text search when present ([883ce7b](https://github.com/dodi-smart/dirahq-zavet/commit/883ce7b52034071d5ae778847ef02064040991ed))
* **plugin:** add a version subcommand and the version --json contract ([fcd2a88](https://github.com/dodi-smart/dirahq-zavet/commit/fcd2a88ba57941875401b22c519c600843eff41e))
* **plugin:** living specs — transparent document flow, /zavet:spec, spec-currency nudge ([80b4ffb](https://github.com/dodi-smart/dirahq-zavet/commit/80b4ffb78946ba3c59d121f3e613069234973045)), closes [dodi-smart/dirahq-zavet#2](https://github.com/dodi-smart/dirahq-zavet/issues/2)
* **plugin:** zavet audit plumbing — stale specs, stale decisions, guard pressure ([dd7c928](https://github.com/dodi-smart/dirahq-zavet/commit/dd7c928175785afd1babbc5283d3e8399a4bb594))
* **plugin:** zavet check — CI trailer floor over a commit range ([1473ddd](https://github.com/dodi-smart/dirahq-zavet/commit/1473ddd15ebb85fc697ca8f1133eca53895fd250))
* **plugin:** zavet knowledge-layer plugin — guard hooks, commands, skill, templates, zavet helper ([d25fcc0](https://github.com/dodi-smart/dirahq-zavet/commit/d25fcc04fe941cb50a628d12a9ae5f559ba2d20f))
* **release:** automate releases with semantic-release ([2fca0e3](https://github.com/dodi-smart/dirahq-zavet/commit/2fca0e3fd0e8eedb0dccff5fe9a28e1a8913e890))

### 🐛 Bug Fixes

* **plugin:** align block-list edge semantics with the Rust reference dialect ([4f8b2bd](https://github.com/dodi-smart/dirahq-zavet/commit/4f8b2bd013866c6a49fd4f5cd7ad96c44f03b964))
* **plugin:** expose spec-paths in dispatch and usage ([e63bdf8](https://github.com/dodi-smart/dirahq-zavet/commit/e63bdf8d40afff8f0e5207e6c272ee5f5bc5148d))
* **plugin:** scaffold the decision template outside decisions/ ([3b25e54](https://github.com/dodi-smart/dirahq-zavet/commit/3b25e54e4e76f53f45d60ab49989fadeb509e324))

### ⚡ Performance Improvements

* **plugin:** single-pass guards parsing, batch path matching, shared deny/root helpers ([4b5436a](https://github.com/dodi-smart/dirahq-zavet/commit/4b5436a5e4e3248aaf5687242c81926c2d9ea15c))

### 📚 Documentation

* **repo:** document install, the dira contract, and going public ([b05e15b](https://github.com/dodi-smart/dirahq-zavet/commit/b05e15b1ab428478167b7fbc251e5e7d839aed1b))

### ♻️ Code Refactoring

* **plugin:** factor glob normalization out of run_match ([1fb6411](https://github.com/dodi-smart/dirahq-zavet/commit/1fb64112b1660fe67b20a36fb055d396ad18e528))
* **plugin:** one commit hook, parser parity with dira, leaner spec listing ([e5a00f3](https://github.com/dodi-smart/dirahq-zavet/commit/e5a00f30202d2e1eef0096bcfdd152080045a103)), closes [dodi-smart/dirahq-zavet#2](https://github.com/dodi-smart/dirahq-zavet/issues/2)

### ✅ Tests

* **plugin:** frontmatter dialect goldens + POSIX test runner ([9b54741](https://github.com/dodi-smart/dirahq-zavet/commit/9b5474168227b634018b1d6bd6d7210c8b6847ba))

### 👷 Continuous Integration

* **plugin:** appease newer shellcheck — single gc helper, SC2015 disables at guard idioms ([080d8b9](https://github.com/dodi-smart/dirahq-zavet/commit/080d8b9ac9bfa84eeec9cbb5b3fd14318f6f51bb))
* **plugin:** GitHub Actions — sh tests on ubuntu+macos, shellcheck, fixture sync guard ([2a220cb](https://github.com/dodi-smart/dirahq-zavet/commit/2a220cb979b7843b5b8c85d22ab4dc4844071af4))
* **plugin:** harden CI and make fixture-sync tell drift from unavailability ([4dc61e3](https://github.com/dodi-smart/dirahq-zavet/commit/4dc61e3c7285729e04ca5891ebbbbdafa92c9f2a))
