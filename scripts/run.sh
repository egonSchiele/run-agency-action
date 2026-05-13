#!/usr/bin/env bash
set -euo pipefail

# Inputs: AGENCY_FILE, AGENCY_EXTRA_DEPS — read from env, never interpolated.

cd "$GITHUB_ACTION_PATH/bundled"
npm ci

cd "$GITHUB_WORKSPACE"

export NODE_PATH="$GITHUB_ACTION_PATH/bundled/node_modules${NODE_PATH:+:$NODE_PATH}"
export PATH="$GITHUB_ACTION_PATH/bundled/node_modules/.bin:$PATH"

if [ -n "${AGENCY_EXTRA_DEPS:-}" ]; then
  # Install extras into the bundled tree so they share the same node_modules
  # as the stdlib. --no-save keeps the committed lockfile untouched.
  # Intentionally word-split: AGENCY_EXTRA_DEPS is a space-separated package list.
  # shellcheck disable=SC2086
  npm i --no-save --prefix "$GITHUB_ACTION_PATH/bundled" $AGENCY_EXTRA_DEPS
fi

if [ -f package.json ]; then
  npm ci
fi

# Make the bundled stdlib resolvable from the compiled .js file. Node's ESM
# loader walks up from the source file looking for node_modules and ignores
# NODE_PATH for bare-specifier resolution, so we expose the bundle via a
# symlink. Skip if the user has their own node_modules (their pins win).
if [ ! -e node_modules ]; then
  ln -s "$GITHUB_ACTION_PATH/bundled/node_modules" node_modules
fi

export AGENCY_RUN_ACTION_VERSION="${AGENCY_RUN_ACTION_VERSION:-${GITHUB_ACTION_REF:-local}}"

agency run "$AGENCY_FILE"
