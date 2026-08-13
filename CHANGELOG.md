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
runner unpacks the action to `…/_actions/…`, a sibling of the workspace. The
npm cache is now keyed on a `sha256` of the lockfile computed in bash and
applied with `actions/cache`, which has no such restriction. Caching behavior
is unchanged for users.

- Added the `external-consumer` CI job, which invokes the action as
  `owner/repo@sha` so it runs from `_actions/` like a real consumer. The
  existing `uses: ./` canary structurally could not catch this.
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
