# run-agency-action

Run an [Agency](https://github.com/agency-lang/agency-lang) `.agency` file in GitHub Actions.
Composite action — no Docker, no Node setup required in your workflow.

## Usage

```yaml
- uses: egonSchiele/run-agency-action@v1.0.0
  with:
    file: agents/my-agent.agency
```

Or pin to an exact commit SHA (recommended for security):

```yaml
- uses: egonSchiele/run-agency-action@<40-char-sha>  # v1.0.0
```

## Inputs

| Input          | Required | Default | Description                                                       |
| -------------- | -------- | ------- | ----------------------------------------------------------------- |
| `file`         | yes      | —       | Path to the `.agency` file to run.                                |
| `node-version` | no       | `20`    | Node version passed to `actions/setup-node`.                      |
| `extra-deps`   | no       | `''`    | Space-separated npm packages installed alongside the bundled stdlib. |

## Versioning

- `@v1.0.0` (etc.) — exact tag, immutable.
- `@<sha>` — exact pin to a commit (most secure).
- **No floating `v1` tag is published.** This is intentional — see the design doc for rationale. To pick up a new release, update your workflow file.

## Exit codes

| Condition                       | Exit | Notes                                              |
| ------------------------------- | ---- | -------------------------------------------------- |
| Success                         | 0    |                                                    |
| Missing `.agency` file          | 1    | message contains `Agent file not found`            |
| Compile error                   | 1    | standard Agency compile output                     |
| Top-level failure               | 1    | prints the failure value                           |
| Top-level interrupt unanswered  | 1    | message contains `Interrupts cannot be answered`   |

## Provenance

Releases are signed with [Sigstore](https://www.sigstore.dev/) via
`actions/attest-build-provenance`. Verify with `gh attestation verify`.
