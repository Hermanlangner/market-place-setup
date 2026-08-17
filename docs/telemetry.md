# Claude Code telemetry

Claude Code has built-in OpenTelemetry export for metrics, events, and beta
traces. It can send OTLP to Grafana, Datadog, New Relic, or another backend,
or expose metrics to Prometheus. Environment variables enable it, so managed
settings can apply one policy across the organization instead of relying on
developer opt-in.

Source: [Monitoring usage](https://code.claude.com/docs/en/monitoring-usage).
Try the verified local setup in [`telemetry-lab/`](../telemetry-lab/).

## Takeaways

- Use posture B: export metrics and events to our collector, then strip
  sensitive attributes before storage. It answers overall adoption, cost, and
  plugin adoption by name without exporting prompt or response content.
- Claude Code natively emits the dimensions needed for adoption, cost, and
  effectiveness reporting. Custom skill and plugin names are not equally
  visible on every signal.
- Tests on Claude Code v2.1.233 found that cost and token metrics, plus
  `api_request` events, label third-party skills as `"third-party"` whether or
  not `OTEL_LOG_TOOL_DETAILS=1` is set.
- `plugin_loaded` and `plugin_installed` events preserve plugin names. Named
  per-skill cost requires beta traces that join `claude_code.tool` spans to
  sibling `claude_code.llm_request` spans.
- Keep `OTEL_LOG_USER_PROMPTS` and `OTEL_LOG_ASSISTANT_RESPONSES` disabled.
  Publish the active posture as an explicit organization policy.

## Native signals

| Question | Signal | What it answers |
| --- | --- | --- |
| Adoption | `session.count`, `active_time.total` | Sessions and real usage time per user |
| Adoption | `plugin_loaded`, `plugin_installed` events | Installed and active plugins per session, including `plugin.name`, `plugin.version`, `marketplace.name`, and install trigger |
| Adoption | `user_prompt` event | Explicit `/skill` invocations through `command_name` |
| Cost | `cost.usage` in USD, `token.usage` by input/output/cacheRead/cacheCreation | Cost and tokens with native attribution dimensions; see the third-party name caveat below |
| Cost | `api_request` event | Per-request tokens and `cost_usd` with the same attribution |
| Effectiveness | `lines_of_code.count` by added/removed, `commit.count`, `pull_request.count` | Output proxies |
| Effectiveness | `code_edit_tool.decision` | Accept versus reject rate for proposed edits |
| Effectiveness | `tool_result` event | Per-tool `success` and `duration_ms` for finding failing or slow skills and agents |

Cost and token signals include `skill.name`, `agent.name`, `plugin.name`,
`marketplace.name`, `mcp_server.name`, and `model`. Standard identity
attributes include `user.email` or `user.account_uuid`, `organization.id`, and
`session.id`, so the signals can be sliced by person and team. Add internal
dimensions such as squad or cost center with:

```bash
OTEL_RESOURCE_ATTRIBUTES="team.id=platform,cost_center=eng-123"
```

## Verified name behavior in Claude Code v2.1.233

The Claude Code docs suggest `OTEL_LOG_TOOL_DETAILS=1` restores verbatim
third-party names. The lab fired the acme `team-a` ping skill against a local
collector and inspected every signal.

| Signal | Observed third-party name | Verification |
| --- | --- | --- |
| `cost.usage`, `token.usage` metrics | `"third-party"` whether or not `OTEL_LOG_TOOL_DETAILS=1` is set | Three runs |
| `api_request` events | `"third-party"` whether or not `OTEL_LOG_TOOL_DETAILS=1` is set | Verified |
| `plugin_loaded`, `plugin_installed` events | Verbatim: `plugin.name=team-a`, `marketplace.name=acme`, `plugin.version=1.1.0`, plus a stable `plugin_id_hash` | Verified |
| Beta `claude_code.tool` spans with `OTEL_LOG_TOOL_DETAILS=1` | Verbatim: `tool_name=Skill skill_name=team-a:ping`, plus `duration_ms` | Verified |

The practical consequences are:

- Plugin adoption by name is available from `plugin_loaded` and
  `plugin_installed` events when the logs exporter is enabled.
- Metrics and events cannot provide cost by custom skill name. They still
  separate skill-driven spend from baseline in one `"third-party"` bucket.
- Beta traces provide per-skill names. Join the skill-named
  `claude_code.tool` span to sibling `claude_code.llm_request` spans carrying
  token counts in the same interaction.
- Without traces, a Claude Code `PostToolUse` hook can read the skill name from
  stdin JSON and emit a custom counter. Other harnesses need their own
  implementation.

`OTEL_LOG_TOOL_DETAILS=1` is required for `skill_name` on trace spans. It also
adds tool parameters and command lines to events and spans, so use it only
with the posture C controls below.

## Privacy postures

The exported OTLP data goes to our collector, not directly to Anthropic or an
observability vendor. Managed settings pin the endpoint so developers cannot
silently redirect it. Prompt and response content stays redacted in every
posture below because `OTEL_LOG_USER_PROMPTS` and
`OTEL_LOG_ASSISTANT_RESPONSES` remain disabled.

### A. Metrics only

- **Configuration:** `OTEL_METRICS_EXPORTER=otlp` and
  `OTEL_LOGS_EXPORTER=none`.
- **Exports:** Cost and tokens per user and model, a `"third-party"` skill
  bucket, sessions, active time, and lines-of-code counts.
- **Privacy:** Names and numbers only. No prompts, commands, or file paths.

### B. Events with central redaction (recommended)

- **Configuration:** Posture A plus `OTEL_LOGS_EXPORTER=otlp`. Before storage,
  an OTel Collector `attributes` processor deletes `tool_parameters`,
  `tool_input`, and `full_command`.
- **Exports:** Posture A plus named plugin adoption, per-tool success and
  duration, and edit accept or reject decisions.
- **Privacy:** Defense-in-depth stripping keeps stored data to names and
  numbers.

### C. Beta traces

- **Configuration:** Posture B plus
  `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`, `OTEL_TRACES_EXPORTER=otlp`, and
  `OTEL_LOG_TOOL_DETAILS=1`. Apply the same stripping to spans, including
  `full_command` and `file_path`.
- **Exports:** Posture B plus named per-skill usage and cost through tool and
  LLM request spans.
- **Privacy:** The detail flag adds file paths and commands. Strip them
  centrally or explicitly accept them for an internal collector.

Posture A covers cost and overall adoption. Posture B is the recommended
balance because it adds named plugin adoption without content exposure.
Posture C adds named per-skill cost at the price of a beta feature and the
tool-details flag.

The environment block lives in the same managed-settings file as the
marketplace allowlist. Treat it as organization policy: publish this guide,
name the active posture, and state that prompts and responses remain redacted.

## How far without managed settings: all the way, minus enforcement

Managed settings are one of four places the telemetry env can live. Verified
in this repo (Claude Code v2.1.233): a session launched with **zero telemetry
variables in the shell** exported to the lab collector and landed in
Prometheus with a per-user slug, configured entirely from repo-local files.

| Scope | Mechanism | Covers | Good for |
| --- | --- | --- | --- |
| Project | `.claude/settings.json` `env` block, committed to a repo | Everyone working in that repo (after folder trust) | Team opt-in by PR — this repo does it; see [.claude/settings.json](../.claude/settings.json) |
| Per-user in a repo | mise `[env]` (supports templating: `user.slug={{env.USER}}`) | mise-activated shells in that directory | The per-person slug, which can't live in shared project settings — see [mise.toml](../mise.toml) |
| User | `~/.claude/settings.json` `env` block | One developer, all projects | Individual opt-in |
| Managed | `managed-settings.json` via MDM | Every managed machine | Enforcement |

What works without managed settings: the entire pipeline — posture B export,
Prometheus, dashboards, plugin adoption by name, the slug dimension. Rollout
becomes "merge this settings block into your repo," which pairs naturally with
the marketplace (both are opt-in adoption artifacts).

What only managed settings add:

- **Endpoint lock** — without it, a developer can redirect or disable the
  export; telemetry is voluntary and best-effort.
- **Coverage guarantees** — only opted-in repos/users report, so absence of
  data means "not opted in," never "not using Claude Code." Fine for a pilot
  and for adoption measurement of participating teams; wrong tool for
  org-wide cost accounting.
- **Posture consistency** — nothing stops a repo from setting its own flags.

Practical read: run the pilot and early rollout entirely on project settings;
reach for managed settings at step 3 only if coverage/enforcement is actually
required by then.

**Identity note**: the slug is a placeholder (`$USER`) for now. `user.email`
is attached automatically from auth regardless, so backend joins can migrate
from slug to email without losing history.

## Deploy posture B org-wide

Add this exact environment block to the `managed-settings.json` used for
[marketplace lockdown](../README.md#vetting-public-plugins):

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://otel-collector.internal:4317"
  }
}
```

`OTEL_LOG_TOOL_DETAILS=1` only earns its keep in posture C, where it supplies
`skill_name` on trace spans. Attach this processor to the relevant collector
pipelines before storage:

```yaml
processors:
  attributes/strip-sensitive:
    actions:
      - { key: tool_parameters, action: delete }
      - { key: tool_input, action: delete }
      - { key: full_command, action: delete }
      - { key: file_path, action: delete }
```

## Gaps and options

### Start without a collector

The Team and Enterprise admin Analytics dashboard on claude.ai provides usage,
spend, and lines of code per user with no setup. It has no skill or plugin
breakdown, so it is a useful first step rather than the end state.

### Measure outcomes, not runs

Telemetry proves that a skill ran, not that it helped. Add confidence in
increasing order of effort:

- Use `code_edit_tool.decision` accept/reject rate and `tool_result` success as
  proxies per skill or agent.
- Correlate `pull_request.count` and `commit.count` with repository merge and
  revert rates through the shared `user.email`.
- Use `prompt.id` to link events from one prompt and build funnels such as
  skill fired -> edits accepted -> commit.
- Ship custom instrumentation in a plugin. `PostToolUse` and `Stop` hooks
  receive tool-call JSON on stdin and can emit domain events such as "review
  skill flagged N findings."

### Cover other harnesses

OpenCode and Codex usage is invisible to Claude Code telemetry. See
[multi-harness.md](multi-harness.md).

- An OpenCode JavaScript plugin can log `skill` tool invocations to the same
  collector. Codex has no equivalent hook today.
- Instrument internal services called by portable skills on the server side,
  independent of the harness.
- If almost all usage is in Claude Code, measure there and treat the rest as a
  known gap.

### Measure marketplace adoption

Once telemetry is active, `plugin_installed` and `plugin_loaded` events cover
installs and active use. Before that, the only signals are asking users or
running `claude plugin list` on their machines. A git-hosted marketplace has no
server-side install counter.

## Recommended rollout

1. **Now, zero infra:** use the claude.ai admin Analytics dashboard for
   baseline usage and spend per user while the collector is being stood up.
2. **Pilot posture B on ourselves:** point the posture B env block at a real
   collector for the platform team only (shell profile or project
   `.claude/settings.json`, no MDM yet). Build the three starter panels below
   against it. Exit criterion: panels answer adoption, cost, and effectiveness
   questions for our own usage for two weeks.
3. **Org-wide posture B:** move the env block into `managed-settings.json`
   alongside the marketplace allowlist, publish this guide internally with the
   posture named, and state what is never collected (prompts, responses).
4. **Per-skill names, when actually asked for:** prefer shipping a small
   metrics hook in the marketplace first — a `PostToolUse` hook on the Skill
   tool that emits `{skill, plugin, session.id}` counters to the same
   collector. It is stable (no beta), needs no `OTEL_LOG_TOOL_DETAILS`, and
   dogfoods our own plugin system; it counts usage rather than cost. Adopt
   posture C (beta traces + detail flag + span stripping) only if per-skill
   *cost* by name becomes a real question the hook counters can't answer.

Pinned decisions: the backend is **Prometheus** (running in the lab at
`:9090`, scraping the collector), and the identity dimension is a
**`user.slug`** resource attribute (placeholder = local username via mise
templating; `user.email` still flows from auth as the migration path). Steps
1–2 need no managed settings at all — see the scopes section below.

## Starter dashboard

Choose one available identity dimension, `user.email` or `user.account_uuid`,
and use it consistently across panels.

| Panel | Query or signal | Interpretation |
| --- | --- | --- |
| Adoption | Distinct configured user identity per week where `plugin.name` belongs to the acme plugins, stacked by plugin | Named plugin reach and active use |
| Cost | `sum(claude_code.cost.usage)` by `skill.name`, `agent.name`, `model`, and the same configured user identity for top spenders | Metrics group custom skills as `"third-party"`; use joined beta spans for named custom-skill cost |
| Effectiveness | Edit accept rate and `tool_result` success rate by `skill.name`, alongside `lines_of_code.count` per user-week | Directional output proxies, not proof of business outcomes |
