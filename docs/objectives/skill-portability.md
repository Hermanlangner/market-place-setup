# Skill portability

> **Objective.** Let OpenCode and Codex users load the same skills, without
> maintaining a second distribution system.

Claude Code stays first class. Its marketplace, dependencies, bundles, sub
agents, hooks, and vetting do not travel anywhere. What travels is skills,
because they follow the open [Agent Skills standard](https://agentskills.io),
which both other harnesses read.

Calling this a projection rather than a port is the honest framing. One layer
crosses over. The rest does not.

## What survives the crossing

| Component | Claude Code | OpenCode | Codex |
| --- | --- | --- | --- |
| Skills (`SKILL.md`) | Plugin `skills/` through the marketplace | `.opencode/skills/`, `.claude/skills/`, `.agents/skills/`, `~/.agents/skills/` | `.agents/skills/` in the repo, walking up, plus `~/.agents/skills/` |
| Sub agents | Plugin `agents/*.md` | Its own format at `.opencode/agent/`, incompatible | Not distributed |
| Hooks | Plugin `hooks.json` | JS plugins, incompatible | Not distributed |
| Dependencies, bundles, marketplace, vetting | Supported | Not distributed | Not distributed |

Both non-Claude harnesses read `~/.agents/skills/`, so one generated tree serves
both. OpenCode also reads `~/.claude/skills/`, but never Claude's plugin cache.
Without this build, plugin-shipped skills are invisible to OpenCode.

## Why one projection is enough

Projects such as [pbakaus/impeccable](https://github.com/pbakaus/impeccable)
keep a `dist/` folder per harness, covering `.cursor/`, `.codex/`, `.gemini/`,
plus an npx installer. That is the right shape when you distribute
harness-specific hooks and formats to many targets.

This repository shares skills only, and both targets read the same standard
layout. One tree and one symlink script replace the whole per-harness matrix.
The day a target appears that does not read `.agents/skills`, move to the
per-harness model.

## The flow

`plugins/` is the source of truth. Two tools produce and install the portable
copy.

```text
plugins/<group>/<plugin>/skills/<skill>/
  │
  │  tools/build-dist.py
  │    namespaces to <plugin>-<skill> so names cannot collide
  │    injects the required name: frontmatter field
  ▼
dist/agents/skills/<plugin>-<skill>/
  │
  │  tools/install-skills.sh
  ▼
~/.agents/skills/<plugin>-<skill>   →  read by OpenCode and Codex
```

```bash
python3 tools/build-dist.py      # regenerate after any skill change
tools/install-skills.sh          # link into ~/.agents/skills
```

For a project-scoped install, copy `dist/agents/` into a repository as
`.agents/`. Codex and OpenCode both find it from the worktree.

## Verification status

OpenCode is verified. With the links installed:

```bash
opencode run "banner hello"
# → loads skill shared-kit-banner
```

The skill loads. Its script does not, and this is the sharp edge of the whole
projection:

```text
plugins/shared/shared-kit/
├── skills/banner/SKILL.md   ──▶ copied to dist/, loads in OpenCode ✓
└── scripts/                 ──▶ NOT copied. the skill calls it through
                                 ${CLAUDE_PLUGIN_ROOT}, which resolves
                                 only in Claude Code ✗
```

So in OpenCode the banner prints and the script's `🏓` marker stays behind. A
portable skill has to keep its scripts inside its own folder and call them by
relative path. See the rules below.

Codex is not installed on this machine, so the layout is unverified there. Its
documentation specifies the same paths.

## Rules for writing a portable skill

- Default to skills. Reach for a sub agent or a hook only when the behavior is
  Claude-specific. Neither leaves Claude Code.
- Keep the skill folder self-contained. Scripts go inside it, referenced by
  relative path. `${CLAUDE_PLUGIN_ROOT}` and sibling-plugin references resolve
  only in Claude Code.
- Assume nothing about other plugins. Dependencies do not exist in the other
  harnesses, so a portable skill cannot rely on one being installed.

## Why `dist/` is committed

Committing generated output is a deliberate trade, not an oversight.

| | |
| --- | --- |
| Benefit | OpenCode and Codex users have no installer and no marketplace. They clone or submodule this repo and symlink the committed `dist/`. The symlinks then track updates on every `git pull`. |
| Cost | `dist/` goes stale silently when a skill changes without a rebuild. Claude Code users read `plugins/` directly and get the new version. OpenCode and Codex users keep the old one, with no error to tell them. |
| Mitigation | Run `build-dist.py` in the same PR as every skill change, and add a CI step that rebuilds and fails on `git diff --exit-code dist/`. |

The silent-staleness failure is the one to take seriously. Nothing surfaces it
to the affected user, so the CI check is not optional.

## Uninstall

```bash
rm ~/.agents/skills/<name>
```

The installed entries are symlinks. Remove the ones this repo created and leave
`~/.agents/skills/` in place, since it can hold skills from elsewhere.

Telemetry does not cross over either. See
[cross-harness telemetry](../investigations/cross-harness-telemetry.md).
