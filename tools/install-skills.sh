#!/usr/bin/env bash
# Link the portable skills into ~/.agents/skills, which both Codex and
# OpenCode read globally. For Claude Code, use the marketplace instead.
#
# Usage: tools/install-skills.sh [dest]   (default: ~/.agents/skills)
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/dist/agents/skills"
DEST="${1:-$HOME/.agents/skills}"

[ -d "$SRC" ] || { echo "dist not built — run tools/build-dist.py first" >&2; exit 1; }
mkdir -p "$DEST"

n=0
for d in "$SRC"/*/; do
  ln -sfn "${d%/}" "$DEST/$(basename "$d")"
  n=$((n + 1))
done
echo "linked $n skills into $DEST"
