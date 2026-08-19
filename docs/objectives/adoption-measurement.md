# Adoption measurement

> **Objective.** Answer who uses which plugin, what it costs, and whether it
> helps, without collecting prompts or responses.

Claude Code exports metrics, events, and beta traces over OpenTelemetry. The
environment variables that switch it on can live in managed settings, so this
becomes an organization policy rather than a per-developer opt-in.

Source: [Monitoring usage](https://code.claude.com/docs/en/monitoring-usage).
The verified local rig is in [`telemetry-lab/`](../../telemetry-lab/), driven by
`mise run lab:up`, `lab:ping`, and `lab:trace`.

## The decisions

- Run **posture B**: export metrics and events to our collector, strip
  sensitive attributes before storage. It answers adoption, cost, and plugin
  adoption by name, and never exports prompt or response content. Full
  configuration in [telemetry configuration](../resources/telemetry-configuration.md).
- Backend is **Prometheus** for aggregates. Per-user facts go to an analytical
  store, never to Prometheus labels.
- Identity dimension is a **`user.slug`** resource attribute. Today that is the
  local username through mise templating. `user.email` flows from auth anyway,
  so the backend can migrate from slug to email later without losing history.
- Keep `OTEL_LOG_USER_PROMPTS` and `OTEL_LOG_ASSISTANT_RESPONSES` off in every
  posture, and publish the active posture as a written policy.

## What Claude Code answers natively

| Question | Signal | What you get |
| --- | --- | --- |
| Adoption | `session.count`, `active_time.total` | Sessions and real usage time per user |
| Adoption | `plugin_loaded`, `plugin_installed` | Installed and active plugins per session, with `plugin.name`, `plugin.version`, `marketplace.name`, install trigger |
| Adoption | `user_prompt` | Explicit `/skill` invocations through `command_name` |
| Cost | `cost.usage` in USD, `token.usage` by input, output, cacheRead, cacheCreation | Cost and tokens, with the third-party name caveat below |
| Cost | `api_request` | Per-request tokens and `cost_usd` |
| Effectiveness | `lines_of_code.count`, `commit.count`, `pull_request.count` | Output proxies |
| Effectiveness | `code_edit_tool.decision` | Accept versus reject rate on proposed edits |
| Effectiveness | `tool_result` | Per-tool `success` and `duration_ms`, which finds failing or slow skills |

Cost and token signals carry `skill.name`, `agent.name`, `plugin.name`,
`marketplace.name`, `mcp_server.name`, and `model`. Identity attributes include
`user.email` or `user.account_uuid`, `organization.id`, and `session.id`. Add
internal dimensions with:

```bash
OTEL_RESOURCE_ATTRIBUTES="team.id=platform,cost_center=eng-123"
```

The one thing this table does not give you is cost per custom skill by name.
That result and its consequences are in
[skill name redaction](../investigations/skill-name-redaction.md).

## The funnel

Adoption is not one number, it is a funnel, and every stage has a different
denominator. Numbers below are illustrative:

```text
   eligible users                      120   from the IdP roster, never
   │                                         from telemetry
   ├── reporting                       114   ◀── coverage        95%
   │   └── catalog available           105   ◀── availability    88%
   │       └── invoked at least once    72   ◀── activation      69%
   │           └── invoked on 2+ days    52  ◀── repeat use      72%
   │               └── active in week 4  41  ◀── retention       57%
   │
   └── not reporting                     6   offline, outdated, or blocked.
                                             NOT the same as "not using
                                             Claude Code"
```

The bottom branch is the one that gets misread. Those six people are invisible,
not absent. Written out precisely:

```text
telemetry coverage   = reporting eligible users / eligible users
availability rate    = users with the catalog available / eligible users
activation rate      = users who invoked the skill / users who had it available
28-day activation    = eligible users who invoked it in 28 days
                       / eligible users
repeat-use rate      = activated users invoking it on 2+ distinct days
                       / activated users
28-day adoption      = eligible users meeting the repeat-use threshold
                       / eligible users
four-week retention  = week-1 first-activation cohort still active in week 4
                       / users first active in week 1
```

Report telemetry coverage next to every adoption rate. Without it, a collector
outage reads as a drop in adoption, and someone will act on that.

The eligible-user denominator comes from the IdP group, the license roster, or
device-management inventory. Telemetry alone cannot tell a non-user apart from
a user whose client is offline, outdated, or blocked from reporting.

## Where the environment variables can live

Managed settings are one of four options, and they are only needed for
enforcement. Everything else works without them. Verified in this repo on
v2.1.233: a session launched with **zero telemetry variables in the shell**
exported to the lab collector and landed in Prometheus with a per-user slug,
configured entirely from repo-local files.

| Scope | Mechanism | Covers | Good for |
| --- | --- | --- | --- |
| Project | `.claude/settings.json` `env` block, committed | Everyone working in that repo, after folder trust | Team opt-in by PR. This repo does it: [.claude/settings.json](../../.claude/settings.json) |
| Per-user in a repo | mise `[env]`, which supports templating such as `user.slug={{env.USER}}` | mise-activated shells in that directory | The per-person slug, which cannot live in shared project settings. See [mise.toml](../../mise.toml) |
| User | `~/.claude/settings.json` `env` block | One developer, all projects | Individual opt-in |
| Managed | `managed-settings.json` through MDM | Every managed machine | Enforcement |

Managed settings add exactly three things:

- **Endpoint lock.** Without it a developer can redirect or disable the export.
  Telemetry is voluntary and best-effort.
- **Coverage guarantees.** Only opted-in repos and users report, so missing data
  means "not opted in", never "not using Claude Code". Fine for a pilot,
  wrong for org-wide cost accounting.
- **Posture consistency.** Nothing stops a repo setting its own flags.

Run the pilot and early rollout on project settings alone. Reach for managed
settings at step 3 below, and only if coverage or enforcement is required by
then.

## Rollout

Each step is useful on its own, and only step 3 needs anyone in IT involved.

```text
   1   claude.ai Analytics       needs: nothing
       │                         gives: usage and spend per user
       │                         misses: any skill or plugin breakdown
       ▼
   2   posture B, our team       needs: project .claude/settings.json
       │                         exit:  3 panels answer adoption, cost, and
       │                                effectiveness for 2 weeks running
       ▼
   3   posture B, org-wide       needs: managed-settings.json, published policy
       │
       ▼
   4   per-skill names           needs: a PostToolUse hook, shipped as a plugin
       (only when asked)         posture C only if per-skill COST becomes a
                                 real question the hook cannot answer
```

1. **Now, zero infrastructure.** Use the claude.ai admin Analytics dashboard
   for baseline usage and spend per user while the collector is being built. It
   has no skill or plugin breakdown, so it is a starting point rather than the
   destination.
2. **Pilot posture B on ourselves.** Point the posture B env block at a real
   collector for the platform team only, through a shell profile or project
   `.claude/settings.json`, no MDM. Build the three starter panels. Exit
   criterion: those panels answer adoption, cost, and effectiveness for our own
   usage across two weeks.
3. **Posture B org-wide.** Move the env block into `managed-settings.json`
   beside the marketplace allowlist, publish this guide internally naming the
   active posture, and state what is never collected.
4. **Per-skill names, when someone actually asks.** Ship a small metrics hook in
   the marketplace first: a `PostToolUse` hook on the Skill tool emitting
   `{skill, plugin, session.id}` counters to the same collector. It is stable
   rather than beta, needs no `OTEL_LOG_TOOL_DETAILS`, and exercises our own
   plugin system. It counts usage, not cost. Adopt posture C only when per-skill
   *cost* by name becomes a real question those counters cannot answer.

## What this will not tell you

Telemetry proves a skill ran. It does not prove the skill helped. Nothing in the
list above closes that gap, and no client-native signal does either. What you
can do is climb toward it:

```text
   proves it RAN     skill_activated, plugin_loaded, tool_result
        │
   cheap             edit accept/reject rate, tool success      per skill
        │
        │            merge and revert rates from the repo,      via user.email
        │              joined to commits and PRs
        │
        │            prompt.id funnels: skill fired →           one prompt
        │              edits accepted → commit landed
        │
   costly            domain events from your own plugin         "review skill
        ▼              via PostToolUse and Stop hooks            flagged N"

   proves it HELPED  nothing here. this is a judgement call, informed above
```

In increasing order of effort:

- Use `code_edit_tool.decision` accept and reject rates, plus `tool_result`
  success, as proxies per skill or agent.
- Correlate `pull_request.count` and `commit.count` with repository merge and
  revert rates through the shared `user.email`.
- Use `prompt.id` to link events from one prompt, and build funnels such as
  skill fired, edits accepted, commit landed.
- Ship custom instrumentation in a plugin. `PostToolUse` and `Stop` hooks
  receive tool-call JSON on stdin and can emit domain events such as "review
  skill flagged N findings".

Never let the model report its own completion as the only signal. It can skip
the step, repeat it, or claim success before the outcome exists. Instrument a
deterministic boundary instead: a project-owned script, an MCP service, a
deployment API.

Two more known holes. OpenCode and Codex usage is invisible here, covered in
[cross-harness telemetry](../investigations/cross-harness-telemetry.md). And a
Git-hosted marketplace has no server-side install counter, so before telemetry
is live the only signals are asking people or running `claude plugin list` on
their machines.

## Starter dashboard

Pick one identity dimension, `user.email` or `user.account_uuid`, and use it in
every panel.

| Panel | Query or signal | How to read it |
| --- | --- | --- |
| Adoption | Distinct user identity per week where `plugin.name` is an acme plugin, stacked by plugin | Named plugin reach and active use |
| Cost | `sum(claude_code.cost.usage)` by `skill.name`, `agent.name`, `model`, and user, for top spenders | Metrics bucket custom skills as `"third-party"`; use joined beta spans for named custom-skill cost |
| Effectiveness | Edit accept rate and `tool_result` success rate by `skill.name`, beside `lines_of_code.count` per user-week | Directional proxies, not proof of business outcomes |
