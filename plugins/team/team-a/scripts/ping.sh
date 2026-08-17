#!/usr/bin/env bash
# Test marker for the team-a plugin's scripts/ directory.
# Called by the SessionStart hook in hooks/hooks.json; can also be run directly.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
echo "🏓 pong from team-a script v1.1.0 (plugin root: ${PLUGIN_ROOT})"
