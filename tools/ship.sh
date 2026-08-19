#!/usr/bin/env bash
# Ship blue-set 1.1.0: add party-parrot to its dependencies, commit, and tag.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO_ROOT/plugins/bundles/blue-set/.claude-plugin/plugin.json"

if [ ! -f "$MANIFEST" ]; then
  echo "error: $MANIFEST not found" >&2
  exit 1
fi

if python3 - "$MANIFEST" <<'EOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
deps = [d if isinstance(d, str) else d.get("name") for d in data.get("dependencies", [])]
sys.exit(0 if "party-parrot" in deps else 1)
EOF
then
  echo "already shipped"
  exit 0
fi

python3 - "$MANIFEST" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
data["version"] = "1.1.0"
data.setdefault("dependencies", []).append("party-parrot")
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
EOF

cd "$REPO_ROOT"
git add "$MANIFEST"
git commit -m "ship: blue-set 1.1.0 adds party-parrot"
git tag blue-set--v1.1.0

echo "shipped blue-set 1.1.0. Follow-up commands:"
echo "  claude plugin marketplace update acme"
echo "  claude plugin update blue-set@acme"
