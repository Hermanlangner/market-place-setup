#!/usr/bin/env python3
"""Regenerate dist/agents/skills/ — the portable agentskills.io layout — from
the canonical plugin skills in plugins/.

Claude Code users never need this; they install via the marketplace. OpenCode
and Codex users consume the generated tree (see tools/install-skills.sh).

Each plugins/<group>/<plugin>/skills/<skill>/ is copied to
dist/agents/skills/<plugin>-<skill>/ (namespaced to avoid collisions), and a
`name:` matching the directory is injected into the frontmatter, as the open
skills spec requires.
"""
import re
import shutil
from pathlib import Path

root = Path(__file__).resolve().parent.parent
out = root / "dist" / "agents" / "skills"

if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)

count = 0
for skill_md in sorted(root.glob("plugins/*/*/skills/*/SKILL.md")):
    sdir = skill_md.parent
    plugin = sdir.parent.parent.name
    name = f"{plugin}-{sdir.name}"
    tdir = out / name
    shutil.copytree(sdir, tdir)

    text = (tdir / "SKILL.md").read_text()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    fm = m.group(1) if m else ""
    body = text[m.end():] if m else text
    lines = [l for l in fm.splitlines() if not l.startswith("name:")]
    lines.insert(0, f"name: {name}")
    (tdir / "SKILL.md").write_text("---\n" + "\n".join(lines) + "\n---\n" + body)
    count += 1

print(f"built {count} skills -> {out.relative_to(root)}")
