# Concepts and disk layout

Companion to [`agent-anatomy.md`](agent-anatomy.md). This reference maps each
concept to runtime and disk, then shows the plugin, project, and user layouts.

## Concept map

| Concept | What it is | Location and session behavior |
| --- | --- | --- |
| **Harness** | Runtime around the model: loop, tool execution, permissions, and context management | The `claude` binary, or a build on the Agent software development kit (SDK). It provides the session runtime. |
| **Claude Code** | A harness product with a CLI, plugins, Model Context Protocol (MCP), and permission modes | The installed CLI. It starts and runs the session. |
| **Agent** | Model, harness, tools, context, and instructions running toward a goal | Runtime only, not a file. Each session is one. |
| **Tools and scripts** | How the agent acts: built-ins, scripts and CLIs, and MCP servers | Built-ins ship with the harness; scripts live in `<plugin>/scripts/` or the repo; MCP configuration lives in `plugin.json` or `.mcp.json`. Results return to context. |
| **Skill** | Packaged instructions loaded into context on demand | `<plugin>/skills/<name>/SKILL.md`, project `.claude/skills/`, or user `~/.claude/skills/`. Loaded when relevant or through `/name`. |
| **Sub agent** | Fresh agent with separate context and tools that returns a report | `<plugin>/agents/<name>.md` or project `.claude/agents/`. Spawned through the Agent tool. |
| **Orchestration** | Coordination pattern across agents: fan out, pipeline, or verify | Orchestrator agents or skills, or workflow scripts in `.claude/workflows/`. It is behavior, not a component. |
| **Meta-harness** | External app that manages whole sessions: UI, parallel worktrees, review queues, and runtime integration | Its own app, outside this repo. It starts Claude Code in headless mode or through the Agent SDK. Claude Code plugins, skills, hooks, and telemetry continue to run. |
| **Plugin** | Shipping container for skills, agents, hooks, and MCP or Language Server Protocol (LSP) configuration | `plugins/<group>/<name>/` in this repo. Installed from a marketplace. |
| **Marketplace** | Catalog that distributes plugins | `.claude-plugin/marketplace.json` at the repo root. Added once with `marketplace add`. |

Skills and agents can use three scopes: plugin scope for marketplace-shipped
shared assets, project scope in versioned `.claude/`, and user scope in personal
`~/.claude/`. Use plugin scope when two teams should share an asset.

## Repository layout

This repo shows each file-backed plugin concept. `team-a` is the live example.
The other non-bundle plugins contain skills only. Bundle plugins contain only
their manifests.

```text
market-place-setup/                        ← MARKETPLACE: one per repo
├── .claude-plugin/
│   └── marketplace.json                   catalog entries, categories, sources
├── docs/
│   ├── agent-anatomy.html                 the visual
│   ├── agent-anatomy.md                   Markdown companion
│   └── concepts-and-layout.md             this file
├── plugins/
│   ├── shared/...
│   ├── core/...
│   ├── medic/...
│   ├── bundles/...
│   └── team/
│       └── team-a/                        ← PLUGIN: shipping container
│           ├── .claude-plugin/
│           │   └── plugin.json            name, version, dependencies,
│           │                              and hooks configuration
│           ├── skills/                    ← SKILLS: knowledge into context
│           │   └── ping/SKILL.md
│           ├── agents/                    ← SUB AGENTS: delegation
│           │   └── pong.md                one .md per agent type; an agent
│           │                              that coordinates other agents is
│           │                              ORCHESTRATION, not a new file type
│           ├── hooks/
│           │   └── hooks.json             harness automation; this one runs
│           │                              scripts/ping.sh at SessionStart
│           └── scripts/                   ← TOOLS AND SCRIPTS: action
│               └── ping.sh                referenced by the hook via
│                                          ${CLAUDE_PLUGIN_ROOT}
├── README.md
└── ORG-DISTRIBUTION.md
```

Two scopes live outside this repo:

```text
some-project/.claude/                      ← PROJECT scope: versioned with the code
├── settings.json                          enabledPlugins, extraKnownMarketplaces
├── skills/  agents/  workflows/           project-specific variants
└── CLAUDE.md                              standing context for every session

~/.claude/                                 ← USER scope: personal
├── settings.json                          global permissions, marketplaces
├── skills/  agents/
└── plugins/cache/                         where installed plugins actually land
```

## Placement rules of thumb

- Shared by two teams: a plugin in this repo, distributed through the
  marketplace.
- Needed by one codebase: that repo's `.claude/`.
- Needed by one person: `~/.claude/`.
- A skill needs code: put the script in the plugin's `scripts/` and reference it
  with `${CLAUDE_PLUGIN_ROOT}/scripts/...`. Installed plugins are copied to the
  cache, so relative paths outside the plugin break.
- An agent coordinates other agents: it remains an `agents/*.md` file.
  Orchestration is behavior, not a different file type.
