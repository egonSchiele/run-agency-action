#!/usr/bin/env bash
set -euo pipefail

# Inputs: AGENCY_FILE, AGENCY_EXTRA_DEPS.
# Both are passed via env vars so GitHub Actions YAML expansion never
# interpolates user-controlled strings into the shell command. Inside this
# script, `$AGENCY_FILE` is always quoted; `$AGENCY_EXTRA_DEPS` is parsed
# into an array and each entry is regex-validated before being passed as
# argv to `npm i`.

cd "$GITHUB_ACTION_PATH/bundled"
npm ci --ignore-scripts

cd "$GITHUB_WORKSPACE"

export NODE_PATH="$GITHUB_ACTION_PATH/bundled/node_modules${NODE_PATH:+:$NODE_PATH}"
export PATH="$GITHUB_ACTION_PATH/bundled/node_modules/.bin:$PATH"

if [ -n "${AGENCY_EXTRA_DEPS:-}" ]; then
  # Install extras into the bundled tree so they share the same node_modules
  # as the stdlib. --no-save + --no-package-lock keep the committed
  # package.json AND lockfile untouched on disk.
  #
  # Parse the space-separated input into an array and validate each entry
  # against npm's package-name rules (optionally with a @version suffix) so
  # shell metacharacters can never reach `npm i`'s argv.
  read -r -a deps <<<"$AGENCY_EXTRA_DEPS"
  name_re='^(@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*(@[A-Za-z0-9._^~>=<*+|-]+)?$'
  for dep in "${deps[@]}"; do
    if ! [[ "$dep" =~ $name_re ]]; then
      echo "Refusing to install dep with disallowed characters: '$dep'" >&2
      exit 1
    fi
  done
  npm i --no-save --no-package-lock --ignore-scripts \
    --prefix "$GITHUB_ACTION_PATH/bundled" \
    "${deps[@]}"
fi

# Install the user's own deps if they have any. Prefer `npm ci` when a lockfile
# is present; otherwise fall back to `npm install` so users with just a
# package.json don't hit a confusing "EUSAGE: ci requires a lockfile" error.
if [ -f package.json ]; then
  if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
    npm ci --ignore-scripts
  else
    npm install --ignore-scripts
  fi
fi

# Make the bundled stdlib resolvable from the compiled .js file. Node's ESM
# loader walks up from the source file looking for node_modules and ignores
# NODE_PATH for bare-specifier resolution, so we expose the bundle via a
# symlink in a scratch directory we own. We symlink any package the user
# already has into the scratch dir first, so user pins still win for shared
# packages, but the bundled stdlib is always resolvable.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

mkdir "$SCRATCH/node_modules"
# 1. Bundled stdlib (and transitive deps) — link every entry individually so
#    we can override them with user packages below.
for entry in "$GITHUB_ACTION_PATH/bundled/node_modules"/*; do
  name="$(basename "$entry")"
  ln -s "$entry" "$SCRATCH/node_modules/$name"
done
# 2. User packages override the bundled ones (their pins win).
if [ -d node_modules ]; then
  for entry in node_modules/*; do
    name="$(basename "$entry")"
    rm -f "$SCRATCH/node_modules/$name"
    ln -s "$PWD/$entry" "$SCRATCH/node_modules/$name"
  done
fi

export AGENCY_RUN_ACTION_VERSION="${AGENCY_RUN_ACTION_VERSION:-${GITHUB_ACTION_REF:-local}}"

# Resolve to absolute path so cwd change doesn't break it.
AGENCY_FILE_ABS="$(cd "$(dirname "$AGENCY_FILE")" && pwd)/$(basename "$AGENCY_FILE")"
cd "$SCRATCH"
agency run "$AGENCY_FILE_ABS"
