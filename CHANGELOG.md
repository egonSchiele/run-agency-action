# Changelog

## v1.2.0

**Fixes a bug that made v1.1.0 fail for every consumer.** The action died
during `npm ci`, before running the `.agency` file, with:

```
npm error ERESOLVE could not resolve
npm error peer agency-lang@"0.1.1" from @agency-lang/github@0.1.0
```

`@agency-lang/github` 0.1.0 requires exactly `agency-lang` 0.1.1, and v1.1.0
bundled `agency-lang` 0.16.0. Version 0.1.1 of `@agency-lang/github` accepts
any `agency-lang` from 0.9.0 up.

- `bundled/package.json` now depends on `@agency-lang/github@0.1.1` and
  `agency-lang@^0.39.2` (the lockfile pins 0.39.2), so `.agency` files run
  against the current language.
- The `node-version` input now defaults to `22` instead of `20`. `agency-lang`
  requires Node 22.13 or newer, and Node 20 is no longer supported.
- The `out-of-workspace` CI job runs on Node 22 to match.

## v1.1.0

Upgrades the bundled Agency runtime from `agency-lang` 0.1.1 to 0.16.0, so
`.agency` files run against the current language rather than a version 15
minors old.

- `bundled/package.json` now depends on `agency-lang@^0.16.0` (lockfile pins
  0.16.0). `@agency-lang/github` stays at 0.1.0.
- The dependency tree shrank considerably in the process (~1650 fewer lockfile
  lines).
- No input or output changes to the action itself. Upgrading is a version bump
  only, but the language your `.agency` files are evaluated against changes.

## v1.0.3

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
