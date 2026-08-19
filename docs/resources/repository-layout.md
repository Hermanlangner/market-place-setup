# Repository layout

> **Supporting resource.** Every concept from [agent anatomy](agent-anatomy.md)
> mapped to a real path, plus the three scopes and the rules for choosing
> between them.

## Concept to disk

| Concept | What it is | Where it lives, and how it behaves in a session |
| --- | --- | --- |
| **Harness** | The runtime around the model: loop, tool execution, permissions, context management | The `claude` binary, or a build on the Agent SDK. It provides the session runtime |
| **Claude Code** | A harness product with a CLI, plugins, MCP, and permission modes | The installed CLI. It starts and runs the session |
| **Agent** | Model, harness, tools, context, and instructions running toward a goal | Runtime only, never a file. Each session is one |
| **Tools and scripts** | How the agent acts: built-ins, scripts and CLIs, MCP servers | Built-ins ship with the harness. Scripts live in `<plugin>/scripts/` or the repo. MCP config sits in `plugin.json` or `.mcp.json`. Results return to context |
| **Skill** | Packaged instructions loaded into context on demand | `<plugin>/skills/<name>/SKILL.md`, project `.claude/skills/`, or user `~/.claude/skills/`. Loaded when relevant, or through `/name` |
| **Sub agent** | A fresh agent with separate context and tools that returns a report | `<plugin>/agents/<name>.md` or project `.claude/agents/`. Spawned through the Agent tool |
| **Orchestration** | The coordination pattern across agents: fan out, pipeline, verify | Orchestrator agents or skills, or workflow scripts in `.claude/workflows/`. Behavior, not a component |
| **Meta-harness** | An external app managing whole sessions: UI, parallel worktrees, review queues | Its own app, outside this repo. It starts Claude Code headless or through the Agent SDK. Plugins, skills, hooks, and telemetry keep running |
| **Plugin** | The shipping container for skills, agents, hooks, MCP and LSP config | `plugins/<group>/<name>/` here. Installed from a marketplace |
| **Marketplace** | The catalog that distributes plugins | `.claude-plugin/marketplace.json` at the repo root. Added once with `marketplace add` |

## The tree, annotated

`team-blue` is the live example carrying one of every component type. The other
non-bundle plugins carry a subset. Bundle plugins contain only a manifest.

```text
market-place-setup/                        ← MARKETPLACE: one per repo
├── .claude-plugin/
│   └── marketplace.json                   catalog entries, categories, sources
├── docs/                                  these documents
│   ├── objectives/  investigations/  resources/
├── plugins/
│   ├── shared/...
│   ├── core/...
│   ├── agents/
│   │   └── scout/                         independent agent, alone in a plugin
│   ├── vendored/
│   │   └── party-parrot/                  vendored third party
│   ├── bundles/...
│   └── team/
│       ├── team-green/                    orchestration lives in its agents/
│       │                                  as behavior, not a new file type
│       └── team-blue/                     ← PLUGIN: shipping container
│           ├── .claude-plugin/
│           │   └── plugin.json            name, version, dependencies,
│           │                              hooks configuration
│           ├── skills/                    ← SKILLS: knowledge into context
│           │   └── standup/SKILL.md
│           ├── agents/                    ← SUB AGENTS: delegation
│           │   └── blue-reporter.md       one .md per agent type; an agent
│           │                              coordinating others is
│           │                              ORCHESTRATION, not a new file type
│           ├── hooks/
│           │   └── hooks.json             harness automation; this one runs
│           │                              scripts/ping.sh at SessionStart
│           └── scripts/                   ← TOOLS AND SCRIPTS: action
│               └── ping.sh                referenced by the hook through
│                                          ${CLAUDE_PLUGIN_ROOT}
├── tools/                                 acme, ship.sh, timewarp.sh,
│                                          build-dist.py, install-skills.sh
├── dist/agents/skills/                    generated portable skills
│                                          (see skill-portability.md)
└── telemetry-lab/                         the verified local OTel rig
```

## Two more scopes, outside this repo

```text
some-project/.claude/                      ← PROJECT scope: versioned with code
├── settings.json                       enabledPlugins, extraKnownMarketplaces,
│                                       and the telemetry env block
├── skills/  agents/  workflows/           project-specific variants
└── CLAUDE.md                              standing context for every session

~/.claude/                                 ← USER scope: personal
├── settings.json                          global permissions, marketplaces
├── skills/  agents/
└── plugins/cache/                      where installed plugins really land
```

Skills and agents can live at any of the three scopes. Use plugin scope when two
teams should share the asset, because that is the only scope a marketplace can
distribute.

## Picking a scope

```text
shared by two teams   →  a plugin in this repo, through the marketplace
needed by one codebase →  that repo's .claude/
needed by one person   →  ~/.claude/
```

Two rules that catch people out:

```text
   you edit here      plugins/shared/shared-kit/scripts/banner.sh
        │
        │  claude plugin install
        ▼
   claude runs here   ~/.claude/plugins/cache/.../scripts/banner.sh
                      ${CLAUDE_PLUGIN_ROOT} points HERE, not at your repo.
                      a path reaching ../../ outside the plugin now breaks
```

That one catches everybody, because it works perfectly on the machine where you
wrote it and fails for every person who installs it.

**A skill that needs code.** Put the script in the plugin's `scripts/` and
reference it as `${CLAUDE_PLUGIN_ROOT}/scripts/...`. Claude Code copies installed
plugins into the cache, so any relative path pointing outside the plugin breaks
on install. It works locally and fails for everyone else, which is the worst
failure shape.

**An agent that coordinates other agents.** It stays an `agents/*.md` file.
Orchestration is behavior, not a different file type, and there is no directory
for it.
