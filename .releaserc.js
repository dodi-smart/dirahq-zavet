// Release config for the Zavet plugin. Single-channel: `main` is the only
// release branch (see CONTRIBUTING.md — the marketplace source has no `ref`,
// so a `develop` prerelease channel would be invisible to installs).
// The version source of truth is the `"version"` key in
// `.claude-plugin/plugin.json`; `scripts/set-version.sh` bumps it in place.
// Tags are `v${version}`. Note this is deliberately NOT the format
// `claude plugin tag` cuts (`zavet--v${version}`, with two dashes) — if that
// command is ever used against this repo it will produce a second, parallel
// tag series. Tag by releasing, not with `claude plugin tag`.
const config = {
  branches: ["main"],
  tagFormat: "v${version}",
  plugins: [
    [
      "@semantic-release/commit-analyzer",
      {
        preset: "conventionalcommits",
        releaseRules: [
          { type: "feat", release: "minor" },
          { type: "fix", release: "patch" },
          { type: "perf", release: "patch" },
          { type: "revert", release: "patch" },
          { type: "docs", release: false },
          { type: "style", release: false },
          { type: "refactor", release: "patch" },
          { type: "test", release: false },
          { type: "build", release: false },
          { type: "ci", release: false },
          { breaking: true, release: "major" },
        ],
      },
    ],
    [
      "@semantic-release/release-notes-generator",
      {
        preset: "conventionalcommits",
        presetConfig: {
          types: [
            { type: "feat", section: "✨ Features", hidden: false },
            { type: "fix", section: "🐛 Bug Fixes", hidden: false },
            { type: "perf", section: "⚡ Performance Improvements", hidden: false },
            { type: "revert", section: "⏪ Reverts", hidden: false },
            { type: "docs", section: "📚 Documentation", hidden: false },
            { type: "style", section: "💄 Styles", hidden: false },
            { type: "refactor", section: "♻️ Code Refactoring", hidden: false },
            { type: "test", section: "✅ Tests", hidden: false },
            { type: "build", section: "📦 Build System", hidden: false },
            { type: "ci", section: "👷 Continuous Integration", hidden: false },
            { type: "chore", section: "🔧 Miscellaneous Chores", hidden: true },
          ],
        },
        writerOpts: { commitsSort: ["scope", "subject"] },
      },
    ],
    [
      "@semantic-release/changelog",
      { changelogFile: "CHANGELOG.md" },
    ],
    [
      "@semantic-release/exec",
      {
        // Bump the plugin manifest version before the commit/tag.
        prepareCmd: "sh scripts/set-version.sh ${nextRelease.version}",
      },
    ],
    [
      "@semantic-release/git",
      {
        assets: [".claude-plugin/plugin.json", "CHANGELOG.md"],
        message:
          "chore(release): v${nextRelease.version} [skip ci]\n\n${nextRelease.notes}",
      },
    ],
    [
      "@semantic-release/github",
      { successComment: false, releasedLabels: false, assets: [] },
    ],
  ],
};

module.exports = config;
