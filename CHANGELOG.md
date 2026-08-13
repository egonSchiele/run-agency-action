# Changelog

## Unreleased

**Fixes a bug that made the action fail for every consumer.** Any workflow
using `v1.0.0`–`v1.0.2` died after ~14 seconds, before running the `.agency`
file at all, with:

```
##[error]Some specified paths were not resolved, unable to cache dependencies.
```

`actions/setup-node`'s `cache-dependency-path` was pointed at the bundled
lockfile inside the action's own directory. That input resolves through
`@actions/glob`, which discards anything outside `$GITHUB_WORKSPACE` — and the
runner unpacks the action to `…/_actions/…`, a sibling of the workspace.

**npm caching has been removed entirely** rather than repaired. Measured, it
saved ~0.3s: the 56 MB of packages move either way, just from Azure instead of
npm's CDN, and unpacking 181 MB into `node_modules` dominates regardless. It
was also the source of every bug this action has shipped.

- Added two CI jobs that exercise the action from outside the workspace, which
  the existing `uses: ./` canary structurally cannot do: `out-of-workspace`
  (pre-merge, runs the entrypoint from `$RUNNER_TEMP`) and `external-consumer`
  (post-merge, `uses: …@main` so the runner fetches into `_actions/`).
- No input or output changes. Upgrading is a version bump only.

## v1.0.2
Update with a few bug fixes to make the release workflow work.

## v1.0.1
Update with a few bug fixes to make the release workflow work.

## v1.0.0

Initial release of `egonSchiele/run-agency-action`.

- Composite action that runs an Agency `.agency` file in CI.
- Bundled `agency-lang` and `@agency-lang/github` (versions pinned in `bundled/package-lock.json`).
- Inputs: `file` (required), `node-version` (default `20`), `extra-deps` (default empty).
- Sigstore build-provenance attestation on the release tarball.
