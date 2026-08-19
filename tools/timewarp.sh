#!/usr/bin/env bash
# Move blue-set to a tagged release and refresh the local install.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: tools/timewarp.sh <version>   (e.g. tools/timewarp.sh 1.0.0)" >&2
  exit 1
fi

VERSION="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

git checkout "blue-set--v$VERSION" -- plugins/bundles/blue-set
claude plugin marketplace update acme
claude plugin update blue-set@acme

claude plugin list | grep blue-set
echo "new sessions load this version"
