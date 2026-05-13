# Periodic doc-review agent

A self-contained example: an Agency agent that scans the repo's markdown
files on a schedule, asks an LLM for typo / dead-link fixes, and opens a PR
with the changes.

- [`review.agency`](./review.agency) — the agent.
- [`workflow.yml`](./workflow.yml) — the GitHub Actions workflow that runs it.
  Copy this into the consuming repo as `.github/workflows/doc-review.yml`.

## How to use it in your repo

1. Copy `review.agency` into your repo (anywhere — e.g. `agents/review.agency`).
2. Copy `workflow.yml` into `.github/workflows/doc-review.yml` and update the
   `file:` input to point at where you put the `.agency` file.
3. Add an LLM provider key (e.g. `ANTHROPIC_API_KEY`) as a repo secret.
4. In **Settings → Actions → General**, enable both:
   - "Read and write permissions" for the `GITHUB_TOKEN`.
   - "Allow GitHub Actions to create and approve pull requests".

That's it — no Node setup, no `package.json`, no installing `agency-lang`
locally. The action bundles the runtime and the `@agency-lang/github`
stdlib; the only extra dep this agent pulls in is `fast-glob` (declared via
`extra-deps:`).
