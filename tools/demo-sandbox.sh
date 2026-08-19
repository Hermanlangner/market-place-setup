#!/usr/bin/env bash
# Create a throwaway clone of this repo for the agentic demo, so acts that
# commit, tag, or check out releases (ship.sh, timewarp.sh) never touch the
# engineer's checkout. Clones committed state only, tags included.
set -euo pipefail

SANDBOX="${TMPDIR:-/tmp}/acme-demo-sandbox"
REPO_ROOT="$(git rev-parse --show-toplevel)"

if [ -e "$SANDBOX" ]; then
  if [ "${1:-}" = "--fresh" ]; then
    rm -rf "$SANDBOX"
  else
    echo "sandbox already exists: $SANDBOX"
    echo "reuse it, or rerun with --fresh to recreate"
    exit 0
  fi
fi

git clone --quiet --no-hardlinks "$REPO_ROOT" "$SANDBOX"

echo "sandbox ready: $SANDBOX"
echo "it holds committed state and tags; uncommitted edits stay behind"
echo "next: cd \"$SANDBOX\" && claude plugin marketplace add ./"
