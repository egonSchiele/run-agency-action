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

# Make the bundled stdlib resolvable from the compiled .js file.
#
# `agency run foo.agency` compiles to `foo.js` next to the source and runs
# it. Node's ESM loader walks up from THAT file (not from cwd) looking for
# `node_modules`, and it ignores `NODE_PATH` for bare-specifier resolution.
# So we have to put the bundle's packages somewhere Node will actually
# find them — i.e. inside `$GITHUB_WORKSPACE/node_modules`.
#
# We do this with surgical symlinks + a trap that removes only what we
# created, so the workspace looks unchanged to subsequent workflow steps.
WS_NM="$GITHUB_WORKSPACE/node_modules"
CREATED_DIR=0
CREATED_ENTRIES=()

cleanup() {
  # `${arr[@]+"${arr[@]}"}` expands to nothing when the array is unset/empty,
  # which is required under `set -u`.
  for n in ${CREATED_ENTRIES[@]+"${CREATED_ENTRIES[@]}"}; do
    rm -f "$WS_NM/$n"
  done
  if [ "$CREATED_DIR" = "1" ]; then
    rmdir "$WS_NM" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [ ! -d "$WS_NM" ]; then
  mkdir "$WS_NM"
  CREATED_DIR=1
fi

for entry in "$GITHUB_ACTION_PATH/bundled/node_modules"/*; do
  name="$(basename "$entry")"
  # Skip npm's internal dotfiles like .package-lock.json and .bin.
  case "$name" in .*) continue;; esac
  # Don't clobber a package the user already has — their pins win.
  if [ ! -e "$WS_NM/$name" ]; then
    ln -s "$entry" "$WS_NM/$name"
    CREATED_ENTRIES+=("$name")
  fi
done

export AGENCY_RUN_ACTION_VERSION="${AGENCY_RUN_ACTION_VERSION:-${GITHUB_ACTION_REF:-local}}"

agency run "$AGENCY_FILE"
