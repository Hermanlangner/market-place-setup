# Bot runtimes

> **Objective.** Ship, version, and vet automated agent behavior through the
> same marketplace that serves humans.

A bot is a Claude session with nobody watching it. Three of the four official
runtimes can load plugins from this marketplace, so bot behavior becomes a
catalog entry rather than a prompt pasted into a workflow file.

That one change carries the rest. Updating a bot becomes a version-bump PR.
Rolling one back becomes a version pin. Both go through the same review as human
tooling.

```text
   this marketplace
        │
        ├──▶ claude-code-action     native inputs          ✓ full plugins
        ├──▶ headless CLI           add, or seed dir       ✓ full plugins
        ├──▶ Agent SDK              local path checkout    ✓ full plugins
        ├──▶ Managed Agents        from dist/agents/     ~ skills only, max 20
        └──✗  cloud routines        MCP connectors only    ✗ the gap
```

Three of five reach the catalog in full. One takes skills only. One cannot reach
it at all, and that last row is the only thing here that needs a workaround.

## Runtime support

| Runtime | Plugin support | How this marketplace plugs in |
| --- | --- | --- |
| [claude-code-action](https://code.claude.com/docs/en/github-actions.md) (GitHub CI) | Native, through `plugin_marketplaces` and `plugins` inputs | `plugin_marketplaces: <this repo git URL>`, `plugins: review-bot@acme` |
| Headless CLI (`claude -p` on cron or own infra) | Full | `claude plugin marketplace add` during provisioning, or [CLAUDE_CODE_PLUGIN_SEED_DIR](https://code.claude.com/docs/en/plugin-marketplaces#pre-populate-plugins-for-containers) to bake plugins into the container image |
| [Agent SDK](https://code.claude.com/docs/en/agent-sdk/plugins.md) (self-hosted bots) | Local paths only | Check this repo out in the bot image, point `plugins: [{type: "local", path: "plugins/team/team-blue"}]` at it. The monorepo layout is what the SDK wants |
| [Cloud routines](https://code.claude.com/docs/en/scheduled-tasks.md) (`/schedule`) | None, MCP connectors only | The gap. Keep scheduled bots on CI cron or self-hosted, or express the capability as an MCP server |
| [Managed Agents](https://claude.com/blog/claude-managed-agents) (Anthropic-hosted) | Skills (max 20) and MCP, not full plugins | Feed it from `dist/agents/skills/`. The [skill portability](skill-portability.md) build doubles as the source |

The cloud-routines row is the one real gap. Everything else has a route.

## What this buys

```text
plugins/bots/
├── pr-reviewer/       a plugin, versioned, CODEOWNER'd
├── triage/            a plugin
└── vendor-auditor/    the audit rubric, already in use

updating a bot     = version-bump PR
rolling one back   = pin the old version
vetting a bot      = the same review as human plugins
telemetry on a bot = the same pipeline as human sessions
```

Four consequences worth naming:

**Reproducibility.** Pin bot plugins by version, or install from a tagged ref,
and a bot's behavior is deterministic per deploy. A prompt inside a workflow
file is not.

**Identity and telemetry.** Run bots on service accounts with
`user.slug=bot-<name>`. The `app.entrypoint` attribute already separates `cli`,
`sdk`, and action traffic, so bot cost and usage report through the same
[adoption measurement](adoption-measurement.md) as people. Splitting bot spend
from human spend needs no new instrumentation.

**Governance carries over.** `strictKnownMarketplaces` on bot infrastructure
pins bots to this marketplace exactly the way it pins laptops. See
[plugin vetting](plugin-vetting.md).

**One review surface.** A bot that reviews PRs is reviewed the same way as a
skill a developer types. There is no second approval path to maintain.
