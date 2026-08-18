#!/usr/bin/env bash
# Deterministic red-flag scan for a plugin directory. Exit 1 on any flag.
# Catches the mechanical tells; the AI audit (plugins/bots/vendor-auditor)
# judges intent. Both run in the vendor-update pipeline (docs/automation.md).
set -uo pipefail
DIR="${1:?usage: scan-plugin.sh <plugin-dir>}"
findings=0

flag() { echo "FLAG: $1"; findings=$((findings + 1)); }

check() { # $1 = grep -E pattern, $2 = message
  local matches
  matches=$(grep -rInE "$1" "$DIR" --exclude=vendor.json 2>/dev/null | head -3)
  [ -n "$matches" ] && { echo "$matches"; flag "$2"; }
}

# invisible / direction-override unicode (homoglyph & bidi source attacks)
if python3 - "$DIR" <<'EOF'
import pathlib, sys
bad = {chr(c) for c in [*range(0x202A, 0x202F), *range(0x2066, 0x206A), 0x200B]}
hits = [str(f) for f in pathlib.Path(sys.argv[1]).rglob("*")
        if f.is_file() and bad & set(f.read_text(errors="ignore"))]
print("\n".join(hits[:3]))
sys.exit(0 if hits else 1)
EOF
then flag "invisible/bidi unicode characters"; fi

check '(curl|wget)[^|;]*\|[[:space:]]*(ba|z)?sh' "download piped to shell"
check 'base64[[:space:]]+(-d|--decode)[^|]*\|[[:space:]]*(ba)?sh|eval[[:space:]]+"?\$\(' "obfuscated / eval execution"
check '\.aws/credentials|\.ssh/id_|ANTHROPIC_API_KEY|security[[:space:]]+find-generic-password' "touches credential stores or keys"
check 'ignore (all )?(previous|prior) instructions|do not (tell|inform) the user' "prompt-injection phrasing in content"

# components that execute automatically deserve human eyes even when clean
[ -f "$DIR/hooks/hooks.json" ] && echo "note: ships hooks (auto-executes) — review hooks/hooks.json"
grep -qs mcpServers "$DIR/.claude-plugin/plugin.json" && echo "note: ships MCP servers — review their commands"

if [ "$findings" -gt 0 ]; then
  echo "RESULT: $findings red flag(s) — do not merge without investigation"
  exit 1
fi
echo "RESULT: no deterministic red flags (AI audit still required)"
