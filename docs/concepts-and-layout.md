# Concepts → disk: the breakdown and where everything lives

Companion to [`agent-anatomy.md`](agent-anatomy.md). Two views: each concept as
a table row, then the folder layout that carries them.

## The breakdown

| Concept | What it is | Lives on disk | Reaches the session how |
|---|---|---|---|
| **Harness** | Machinery around the model: loop, tool execution, permissions, context management | The `claude` binary itself (or your own build on the Agent SDK) | Is the session runtime |
| **Claude Code** | One specific harness product (CLI, plugins, MCP, permission modes) | Installed CLI | — |
| **Agent** | Model + harness + tools + instructions looping toward a goal | Nowhere — it's the *running* system | Every session is one |
| **Tools & scripts** | How the agent acts: built-ins, your scripts/CLIs, MCP servers | Built-ins ship with the harness; scripts in `<plugin>/scripts/` or your repo; MCP configs in `plugin.json` / `.mcp.json` | Model calls them; results append to context |
| **Skill** | Packaged know-how, loaded into context on demand | `<plugin>/skills/<name>/SKILL.md`, project `.claude/skills/`, user `~/.claude/skills/` | Pulled into context when relevant or via `/name` |
| **Sub agent** | Fresh agent spawned as a tool call; own context, own tools; returns a report | `<plugin>/agents/<name>.md`, project `.claude/agents/` | Spawned via the Agent tool |
| **Orchestration** | Coordination pattern over many agents: fan-out, pipeline, verify | Encoded in orchestrator agents/skills or workflow scripts (`.claude/workflows/`) | A pattern at runtime, not a component |
| **Plugin** | Shipping container for skills, agents, hooks, MCP/LSP configs | `plugins/<group>/<name>/` in this repo | Installed from a marketplace |
| **Marketplace** | Catalog that distributes plugins | `.claude-plugin/marketplace.json` at repo root | Added once (`marketplace add`) |

Three scopes carry the same shapes — plugin (shipped via marketplace, this
repo's concern), project (`.claude/` in a codebase, versioned with it), and
user (`~/.claude/`, personal). Plugin wins for anything two teams should share.

## Folder layout

What this repo looks like when a plugin carries every concept above —
`team-a` is the live example (the other plugins are skills-only):

```
market-place-setup/                        ← MARKETPLACE (one per repo)
├── .claude-plugin/
│   └── marketplace.json                   catalog: entries, categories, sources
├── docs/
│   ├── agent-anatomy.html                 the visual
│   ├── agent-anatomy.md                   its markdown companion
│   └── concepts-and-layout.md             this file
├── plugins/
│   ├── shared/…  core/…  medic/…  bundles/…
│   └── team/
│       └── team-a/                        ← PLUGIN (shipping container)
│           ├── .claude-plugin/
│           │   └── plugin.json            name, version, dependencies,
│           │                              mcpServers / hooks config
│           ├── skills/                    ← SKILLS (knowledge → context)
│           │   └── ping/SKILL.md
│           ├── agents/                    ← SUB AGENTS (delegation)
│           │   └── pong.md                one .md per agent type; an agent
│           │                              that coordinates other agents is
│           │                              ORCHESTRATION — same file type
│           ├── hooks/
│           │   └── hooks.json             harness automation — this one runs
│           │                              scripts/ping.sh at SessionStart
│           └── scripts/                   ← TOOLS & SCRIPTS (action)
│               └── ping.sh                referenced by hooks/skills via
│                                          ${CLAUDE_PLUGIN_ROOT}
├── README.md
└── ORG-DISTRIBUTION.md
```

And the two things that live outside this repo:

```
some-project/.claude/                      ← PROJECT scope (versioned with the code)
├── settings.json                          enabledPlugins, extraKnownMarketplaces
├── skills/  agents/  workflows/           project-specific variants
└── CLAUDE.md                              standing context for every session

~/.claude/                                 ← USER scope (personal)
├── settings.json                          global permissions, marketplaces
├── skills/  agents/
└── plugins/cache/                         where installed plugins actually land
```

## Placement rules of thumb

- **Two teams need it** → plugin in this repo, distributed via the marketplace.
- **Only one codebase needs it** → that repo's `.claude/`.
- **Only you need it** → `~/.claude/`.
- **A skill needs code** → put the script in the plugin's `scripts/` and
  reference it with `${CLAUDE_PLUGIN_ROOT}/scripts/…` — installed plugins are
  copied to the cache, so relative paths outside the plugin break.
- **An agent coordinates other agents** → it's still just an `agents/*.md`
  file; orchestration is what it *does*, not a different file type.
