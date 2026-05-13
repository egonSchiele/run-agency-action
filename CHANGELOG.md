# Changelog

## v1.0.0

Initial release of `egonSchiele/run-agency-action`.

- Composite action that runs an Agency `.agency` file in CI.
- Bundled `agency-lang` and `@agency-lang/github` (versions pinned in `bundled/package-lock.json`).
- Inputs: `file` (required), `node-version` (default `20`), `extra-deps` (default empty).
- Sigstore build-provenance attestation on the release tarball.
