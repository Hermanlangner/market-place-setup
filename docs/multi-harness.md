# Multi-harness distribution for OpenCode and Codex

Claude Code remains first-class. Its marketplace, dependencies, bundles,
sub agents, hooks, and vetting stay in Claude Code.

The portable layer is a projection rather than a port because skills follow
the open [Agent Skills standard](https://agentskills.io), which OpenCode and
Codex both read.

## Harness compatibility

| Component | Claude Code | OpenCode | Codex |
| --- | --- | --- | --- |
| Skills (`SKILL.md`) | Plugin `skills/` via marketplace | `.opencode/skills/`, `.claude/skills/`, `.agents/skills/`, `~/.agents/skills/` | `.agents/skills/` (repo, walks up), `~/.agents/skills/` |
| Sub agents | Plugin `agents/*.md` | Own format at `.opencode/agent/`; not compatible | Not distributed |
| Hooks | Plugin `hooks.json` | JS plugins; not compatible | Not distributed |
| Dependencies, bundles, marketplace, and vetting | Supported | Not distributed | Not distributed |

Both non-Claude harnesses read `~/.agents/skills/`, so one generated tree
serves both. OpenCode also reads `~/.claude/skills/`, but not Claude's plugin
cache. Without this build, plugin-shipped skills are invisible to OpenCode.

### Why one projection is enough

Projects such as [pbakaus/impeccable](https://github.com/pbakaus/impeccable)
maintain a `dist/` folder for each harness, including `.cursor/`, `.codex/`,
and `.gemini/`, plus an npx installer. That model is necessary when distributing
harness-specific hooks and formats to many targets.

This repository shares only skills, and both targets read the same standard
layout. One generated tree and one symlink script therefore replace a full
per-harness matrix. If a future target does not read `.agents/skills`, move to
the per-harness distribution model.

## Distribution flow

`plugins/` is the canonical source. Two tools create and install its portable
projection:

| Tool | Purpose |
| --- | --- |
| `tools/build-dist.py` | Copies every `plugins/*/*/skills/<s>/` directory to `dist/agents/skills/<plugin>-<s>/`, namespacing skills to prevent collisions and injecting the required `name:` frontmatter field. |
| `tools/install-skills.sh` | Symlinks `dist/agents/skills/*` into `~/.agents/skills`, or a supplied destination, for OpenCode and Codex users. |

Regenerate and install the skills with:

```bash
python3 tools/build-dist.py      # regenerate after any skill change
tools/install-skills.sh          # link into ~/.agents/skills
```

For a project-scoped installation, copy `dist/agents/` into a repository as
`.agents/`. Codex and OpenCode both discover it from the worktree.

## Verification status

OpenCode is verified. With the links installed, this command loads
`team-a-ping`:

```bash
opencode run "ping team-a"
```

It replies `🏓 pong from team-a v1.1.0`.

Codex is not installed on this machine, so it has not been tested locally. Its
documentation specifies the same layout.

## Portability rules

- Default to skills. Use a sub agent or hook only for Claude-specific behavior;
  neither leaves Claude Code.
- Keep portable skill folders self-contained. Place scripts inside the skill
  folder and use relative paths. `${CLAUDE_PLUGIN_ROOT}` and sibling plugin
  directory references resolve only in Claude Code.
- Avoid cross-plugin assumptions. Dependencies do not exist in the other
  harnesses, so a portable skill cannot assume another plugin is installed.

## Why `dist/` is committed

Committing generated output is deliberate.

| Consideration | Detail |
| --- | --- |
| Benefit | OpenCode and Codex users have no installer or marketplace. They can clone or submodule this repository and symlink the committed `dist/` without additional tooling. The symlinks track updates after each `git pull`. |
| Cost | `dist/` can silently become stale if a skill changes without a rebuild. Claude Code users read `plugins/` directly and would receive the new version, while OpenCode and Codex users would keep the old version without an error. |
| Mitigation | Run `build-dist.py` in the same PR as every skill change. Add a CI step that rebuilds and fails on `git diff --exit-code dist/`. |

## Uninstall

Remove an individual skill symlink:

```bash
rm ~/.agents/skills/<name>
```

The installed entries are symlinks. Remove each link created from this repo;
do not delete `~/.agents/skills/`, which may contain skills from other sources.
