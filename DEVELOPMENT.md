# Development

Notes for maintainers of `egonSchiele/run-agency-action`. If you only want to
*use* the action, see the main [README](./README.md).

## Repository layout

```
action.yml                  # The composite action definition.
scripts/run.sh              # Entrypoint: installs deps, runs `agency run`.
bundled/
  package.json              # Pinned versions of agency-lang + @agency-lang/github.
  package-lock.json         # Lockfile — caches keyed on this.
  .gitignore                # Ignores node_modules/.
tests/
  canary.agency             # Smallest possible .agency file, used by CI.
examples/
  review-agent/             # Reference agent: scheduled doc-review + PR.
.github/workflows/
  ci.yml                    # Runs canary on every push / PR.
  release.yml               # Fires on `v*` tag push: tarball + attestation + release.
CHANGELOG.md                # One section per published version (## v1.0.0, …).
```

---

## Release process

This repo deliberately publishes **only immutable semver tags** (`v1.0.0`,
`v1.0.1`, …). There is no floating `v1` tag, because updating one requires
`git push --force`, which would let an attacker (or an accidental
mis-publish) silently change the code under a consumer's pin.

### Triggers

```diagram
╭─────────────────╮     ╭────────────────────╮
│  push to main   │────▶│ CI (ci.yml)        │  every commit + PR
│  or open PR     │     │ canary + missing-  │
│                 │     │ file tests         │
╰─────────────────╯     ╰────────────────────╯

╭─────────────────╮     ╭────────────────────╮
│ git tag v1.0.1  │────▶│ Release            │  fires only on tags matching v*
│ git push --tags │     │ (release.yml)      │  builds tarball, attests,
│                 │     │                    │  creates GitHub release
╰─────────────────╯     ╰────────────────────╯
```

CI catches regressions before you tag. The release workflow only fires when
you push a tag, not on every commit.

### Cutting a release — step by step

1. **Make code changes**, merge to `main` as usual. Wait for CI to go green.
2. **Update `CHANGELOG.md`.** Add a new top-level section for the version
   you're about to cut. The release workflow extracts exactly the lines
   under `## vX.Y.Z` (up to the next `## ` heading) and uses them as the
   release notes, so the format matters:

   ```markdown
   ## v1.0.1

   - Whatever changed.
   - Another bullet.
   ```

   Commit + push.
3. **Tag and push the tag.**
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```
4. **Watch the release workflow** in the Actions tab. When it finishes you
   get a GitHub release with `run-agency-action-v1.0.1.tar.gz` attached and
   a Sigstore attestation on Rekor.

### What the release workflow does

See [.github/workflows/release.yml](./.github/workflows/release.yml). In
order:

1. **Checkout** the repo at the pushed tag (`fetch-depth: 0` so we have
   full history if we ever need it for note extraction).
2. **Build the tarball.** `tar --exclude='.git' --exclude='node_modules'
   -czf run-agency-action-${tag}.tar.gz .` — source only, deterministic.
3. **Attest.** `actions/attest-build-provenance` signs the tarball with
   Sigstore and records the signature in the public Rekor transparency log.
4. **Extract the changelog section** for the tag into `release-notes.md`.
   Fails the workflow if the tag has no matching section, which forces
   you to remember to update the changelog.
5. **Create the GitHub release** via `gh release create`, attaching the
   tarball and using `release-notes.md` as the body.

---

## Attestation: what it is, how it works, how consumers use it

### What it is

A **build provenance attestation** is a signed JSON statement (in-toto /
SLSA format) saying:

> "Artifact X (sha256: …) was produced by GitHub Actions workflow Y,
> running on commit Z of repo W, at time T."

It's signed by [Sigstore](https://www.sigstore.dev/)'s public-good signing
service. Sigstore uses **keyless signing**: the workflow proves its
identity to Sigstore via OIDC (the `id-token: write` permission you see in
[release.yml](./.github/workflows/release.yml)), Sigstore issues a
short-lived certificate, signs the statement, and records the signature in
the public Rekor transparency log.

Nothing is stored as a long-lived signing key on the runner — the
private key exists only for the duration of one workflow run.

### What it protects against

- A mirror or CDN serving a tampered copy of `run-agency-action-v1.0.0.tar.gz`.
- An account compromise that publishes a release whose source doesn't match
  the public commit history (the attestation pins the commit SHA).
- Silent retroactive changes to a released artifact.

It does **not** protect against:
- A malicious commit that you intentionally tag and release. (Code review
  is the defense for that.)
- A compromised dependency *inside* `bundled/package-lock.json`. (Pinning
  + `--ignore-scripts` are the defenses there.)

### How a consumer verifies a release

```bash
# Download the release tarball.
gh release download v1.0.0 --repo egonSchiele/run-agency-action

# Verify the attestation.
gh attestation verify run-agency-action-v1.0.0.tar.gz \
  --repo egonSchiele/run-agency-action
```

`gh attestation verify` checks:
- The signature is valid.
- The cert chains back to Sigstore's trusted root.
- The Rekor transparency-log entry exists and matches.
- The signing identity (workflow + repo + ref) matches what you asked for.

### Can a consumer verify *automatically* in CI before running the action?

Mostly no, with a useful caveat.

The honest answer: **the practical defense is to pin to a commit SHA**, not
a tag. When you write
```yaml
uses: egonSchiele/run-agency-action@a1b2c3d4…  # v1.0.0
```
GitHub Actions clones the repo at that exact commit. There is no tarball
in the loop, so there's nothing for `gh attestation verify` to check
against — and even if there were, you can't verify an action *before* the
`uses:` line runs (it's the first thing the runner does for that step).

What you *can* do as defense-in-depth, in a separate verification job
that runs first:

```yaml
jobs:
  verify-action:
    runs-on: ubuntu-latest
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release download v1.0.0 --repo egonSchiele/run-agency-action \
            --pattern 'run-agency-action-*.tar.gz'
          gh attestation verify run-agency-action-v1.0.0.tar.gz \
            --repo egonSchiele/run-agency-action

  run-agent:
    needs: verify-action
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
      - uses: egonSchiele/run-agency-action@a1b2c3d4…  # v1.0.0
        with:
          file: agents/my-agent.agency
```

This proves "the released v1.0.0 tarball was built by the legitimate
release workflow" before the second job pulls in the action. It does not
prove that the *git ref you pinned to* matches the tarball — for that you'd
need to also `git clone` and `git diff`. In practice, **commit-SHA pinning
+ Dependabot to bump the SHA + reading the diff before merging** gives you
the same protection with less ceremony.

GitHub is rolling out [signed Actions
artifacts](https://github.blog/2024-05-02-introducing-artifact-attestations-now-in-public-beta/)
with first-class native verification by the runner. Once that lands and
this action publishes those, consumers will get automatic verification on
every `uses:` line. Until then, SHA-pinning is the operational answer.

---

## How to update to a newer `agency-lang` version

```bash
cd bundled

# 1. Look up the new versions you want.
npm view agency-lang version          # e.g. 0.1.5
npm view @agency-lang/github version  # e.g. 0.1.2

# 2. Edit bundled/package.json — bump the pinned versions there.
#    (Don't use ranges like ^0.1.5 — pin exactly.)

# 3. Regenerate the lockfile.
npm install

# 4. Sanity-check locally if you can.
cd ..
GITHUB_ACTION_PATH="$PWD" \
GITHUB_WORKSPACE="$PWD" \
AGENCY_FILE=tests/canary.agency \
AGENCY_EXTRA_DEPS='' \
bash scripts/run.sh

# 5. Commit + push. CI will run the canary against the new version.
git add bundled/package.json bundled/package-lock.json
git commit -m "Bump agency-lang to 0.1.5"
git push
```

If CI passes, follow the [release process](#release-process) above to cut a
new tag.

The cache key in [action.yml](./action.yml) is
`bundled/package-lock.json`, so changing the lockfile automatically
invalidates `actions/setup-node`'s npm cache for downstream consumers — no
manual cache busting needed.

### Updating the third-party actions (`actions/checkout`, `actions/setup-node`, etc.)

All third-party actions are pinned by 40-character commit SHA, with a
trailing `# vX.Y.Z` comment for human readers. To bump:

```bash
# Look up the latest commit SHA for the v6 tag.
gh api repos/actions/setup-node/git/refs/tags/v6 --jq '.object.sha'

# Edit action.yml / .github/workflows/*.yml — replace the SHA, update the
# comment to the new version. Commit + push.
```

Dependabot can do this automatically if you enable the `github-actions`
ecosystem in `.github/dependabot.yml`.

---

## Environment variables

Variables read or written by [scripts/run.sh](./scripts/run.sh):

| Variable | Direction | Source / consumer | Purpose |
|---|---|---|---|
| `AGENCY_FILE` | read | Set by `action.yml` from the `file:` input. | Path to the `.agency` file to run, relative to `$GITHUB_WORKSPACE`. The script resolves it to an absolute path before `cd`-ing away. |
| `AGENCY_EXTRA_DEPS` | read | Set by `action.yml` from the `extra-deps:` input. | Space-separated list of npm packages to install into the bundled tree alongside the stdlib. Word-split intentionally (`shellcheck disable=SC2086`). |
| `AGENCY_RUN_ACTION_VERSION` | written | Read by `@agency-lang/github` (e.g. for the `Generated-by-Agency-Action` git trailer on commits). | The tag/SHA the consumer pinned to. Defaults to `$GITHUB_ACTION_REF`, then to `local`. |
| `NODE_PATH` | written (prepended) | Node.js (CommonJS resolution only). | Adds the bundled `node_modules` to Node's CommonJS lookup path. ESM ignores this for bare specifiers, which is why the symlinked scratch directory exists too. |
| `PATH` | written (prepended) | All shells. | Puts the bundled `agency` CLI on `$PATH` so `agency run …` resolves. |
| `GITHUB_ACTION_PATH` | read | Set by GitHub Actions runner. | Filesystem path where this action's repo is checked out. Used to find `bundled/`. |
| `GITHUB_WORKSPACE` | read | Set by GitHub Actions runner. | Filesystem path of the consumer's checked-out repo. Initial cwd for resolving `AGENCY_FILE`. |
| `GITHUB_ACTION_REF` | read | Set by GitHub Actions runner. | The ref the consumer pinned to (e.g. `v1.0.0` or a SHA). Used as the default for `AGENCY_RUN_ACTION_VERSION`. |
| `GITHUB_TOKEN` | passed through | Auto-injected by GitHub Actions when `permissions:` allows it; read by `@agency-lang/github`. | Auth for any GitHub API calls the agent makes (commits, PRs, comments). |

The agent itself (the user's `.agency` file) sees all of the above plus
whatever the consumer's workflow puts in its `env:` block — typically LLM
provider keys like `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`.

### Variables the script does **not** set

- It does not `export GITHUB_TOKEN` itself. The token is provided by the
  consumer's workflow `env:` (or auto-injected by `actions/checkout` for
  git operations). The agent code is responsible for reading it.
- It does not set any `AGENCY_*` config values that affect the runtime
  beyond `AGENCY_RUN_ACTION_VERSION`. The `agency-lang` runtime has its
  own env-var conventions (see the agency-lang docs); those flow through
  unchanged from the consumer's `env:` block.
