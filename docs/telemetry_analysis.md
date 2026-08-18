# Telemetry analysis for Claude Code, Codex, and OpenCode

<!-- markdownlint-disable MD013 -->

Reviewed: August 18, 2026

This audit compares the telemetry and extension interfaces that Claude Code,
Codex, and OpenCode expose. It focuses on organization-managed skills, user
adoption, and privacy-preserving reporting.

The findings use three evidence levels:

- **Documented**: The vendor describes the behavior in public documentation.
- **Source verified**: The behavior appears in the vendor's official source at
  the cited revision.
- **Locally observed**: This repository's test lab reproduced the behavior on a
  named client version.

APIs and event schemas can change independently of skill content. Re-run the
validation plan before an organization-wide rollout or client upgrade.

## Executive summary

The clients don't expose equivalent telemetry.

- Claude Code provides the broadest native telemetry. Its
  `claude_code.skill_activated` event is an invocation boundary for direct,
  proactive, and nested skill use. Custom skill names require a detail setting
  that also exposes other tool details.
- Codex provides a native `codex.skill.injected` counter by skill and status.
  Use it as the primary signal that Codex injected a skill into context. The
  public docs omit trigger type, but official source emits explicit or implicit.
  The signal does not prove that the workflow completed.
- OpenCode exports OTLP logs and traces, but no native OTLP metrics or
  Prometheus exporter was found. A JavaScript or TypeScript plugin can capture
  successful `skill` tool calls exactly through `tool.execute.after`.
- No client provides a complete, privacy-safe, cross-client adoption model by
  itself. Normalize the client signals in an authenticated ingestion service.
- Keep pseudonymous user-level facts in a restricted analytics store. Send only
  bounded aggregate metrics to Prometheus.

The recommended primary signals are:

| Client | Primary skill signal | Strength | Main limitation |
| --- | --- | --- | --- |
| Claude Code | Sanitized managed hooks for named skills; `claude_code.skill_activated` for native validation | Exact invocation boundaries | Native custom names are redacted unless tool details are enabled |
| Codex | `codex.skill.injected` with `status=ok` | Exact context-injection boundary | Trigger is source verified, but absent from public metric docs |
| OpenCode | `tool.execute.after` where `tool == "skill"` | Exact successful tool invocation | Requires an organization plugin |

## Terms

This document uses the following terms consistently:

- **Available**: The client discovered a skill and can offer it to the model or
  user.
- **Invoked**: The client loaded or injected the full skill instructions.
- **Activated user**: An eligible user who invoked a skill at least once in a
  defined window.
- **Active user**: An eligible user who invoked the same skill during the
  measurement window.
- **Adopted user**: An activated user who meets the organization's repeat-use
  threshold.
- **Completed**: The skill produced a defined domain outcome. Client activation
  alone doesn't prove completion.
- **Eligible user**: A person in the identity provider (IdP) group or license
  roster that should have access to the skill.
- **OpenTelemetry (OTel)**: The observability framework and data model used for
  metrics, logs, and traces.
- **OpenTelemetry Protocol (OTLP)**: The transport protocol used to export OTel
  data.

## Claude Code audit

### Claude Code native telemetry

Claude Code has documented OTel export for metrics, events through the logs
protocol, and beta traces. Telemetry is disabled until
`CLAUDE_CODE_ENABLE_TELEMETRY=1` is set. The client supports OTLP over gRPC,
HTTP/JSON, and HTTP/Protobuf. It can also expose a local Prometheus endpoint.

The [Claude Code monitoring reference](https://code.claude.com/docs/en/monitoring-usage)
defines these core metrics:

| Metric | Purpose | Useful dimensions |
| --- | --- | --- |
| `claude_code.session.count` | Session adoption | Start type and standard identity attributes |
| `claude_code.active_time.total` | Active use rather than session starts | User and CLI activity type |
| `claude_code.cost.usage` | Estimated model cost | Model, agent, skill, plugin, and query source |
| `claude_code.token.usage` | Input, output, and cache tokens | Model, agent, skill, plugin, and token type |
| `claude_code.lines_of_code.count` | Added and removed lines | Model and change type |
| `claude_code.commit.count` | Commits created | Standard attributes |
| `claude_code.pull_request.count` | Pull requests created | Standard attributes |
| `claude_code.code_edit_tool.decision` | Edit acceptance | Tool, decision, source, and language |

Cost and token metrics attribute requests made while a skill is active. They do
not count skill invocations. One invocation can cause several model requests,
and a loaded skill can remain active across more than one request.

Claude Code emits structured events that include prompts, API calls, tool
decisions and results, plugin lifecycle, and skill activation. Prompt and
assistant content is redacted by default.

### Skill and plugin signals

The current [monitoring contract](https://code.claude.com/docs/en/monitoring-usage#skill-activated-event)
defines
`claude_code.skill_activated` as the exact skill invocation event. It covers:

- `user-slash`: The user invokes a `/` skill.
- `claude-proactive`: Claude invokes the `Skill` tool.
- `nested-skill`: An active skill invokes another skill.

The event includes `skill.name`, `skill.source`, `invocation_trigger`, and,
when applicable, plugin and marketplace attribution. It also receives standard
event fields such as timestamp, sequence, session, organization, and user
identity.

Names for user-defined and third-party plugin skills become `custom_skill`
unless `OTEL_LOG_TOOL_DETAILS=1` is enabled. That setting also enables Bash
commands, file paths, MCP names, tool arguments, and other details on related
events. Do not enable it only to obtain skill names without a redaction plan.

Claude Code also exposes these adoption signals:

| Event | Meaning | Adoption use |
| --- | --- | --- |
| `claude_code.plugin_installed` | A plugin install action completed | New installation count and install channel |
| `claude_code.plugin_loaded` | An enabled plugin loaded at session start | Active plugin inventory by version and scope |
| `claude_code.user_prompt` | A user submitted a prompt or command | Direct command use when `command_name` is available |
| `claude_code.tool_result` | A tool completed | Tool success, duration, and detailed Skill-tool parameters when enabled |

`plugin_loaded` is more useful than `plugin_installed` for active coverage. A
plugin can remain installed but disabled, or it can arrive through an
organization policy rather than a user install action.

### Hooks and custom collection

The [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
provides lifecycle hooks in local, IDE, desktop, and web sessions. Two events
cover skill invocation paths:

- `UserPromptExpansion` covers direct `/skill-name` expansion.
- `PostToolUse` with matcher `Skill` covers successful model tool calls.

An organization plugin can use these hooks to emit only a sanitized skill
event. This approach avoids enabling `OTEL_LOG_TOOL_DETAILS=1` for every tool.
Use managed settings or an organization-required plugin if coverage must not
depend on user configuration.

Use the sanitized hook adapter as the production source for named organization
skills. Keep `claude_code.skill_activated` enabled as a native aggregate and
validation signal. An alternative is to enable tool details and send OTel to a
device-local collector that removes commands, paths, and tool input before
forwarding data. Do not map the redacted `custom_skill` placeholder to a
specific catalog entry.

### Identity and privacy

Documented standard attributes include `organization.id`, `user.account_uuid`,
`user.account_id`, `user.id`, `user.email`, `session.id`, and terminal type.
The defaults include account and session dimensions on metrics, which can
create high cardinality. See [standard attributes and cardinality controls](https://code.claude.com/docs/en/monitoring-usage#standard-attributes).

`user.id` is normally a random installation identifier stored in
`~/.claude.json`. When Claude Code uses the Claude apps gateway, the client can
attach the IdP subject, email, groups, and `identity.source=gateway-oidc`.

Use these controls before exporting through the production OTel pipeline:

- Set `OTEL_METRICS_INCLUDE_SESSION_ID=false`.
- Set `OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false` unless the metrics pipeline
  removes the attribute before Prometheus.
- Keep `OTEL_LOG_USER_PROMPTS=0`.
- Keep `OTEL_LOG_ASSISTANT_RESPONSES=0`.
- Keep `OTEL_LOG_RAW_API_BODIES` disabled.
- Remove email, raw account identifiers, commands, paths, inputs, and outputs
  before long-term storage unless an approved use requires them.

Claude Code doesn't provide controls that remove every identity attribute from
its native Prometheus endpoint. In particular, `user.id` and authenticated
`user.email` can remain. Use the native endpoint only for controlled local
validation. Route production metrics through an OTLP collector that removes all
user and session identifiers before Prometheus receives them.

Managed settings can pin exporters, endpoints, protocols, and credentials.
They can also remove conflicting developer-set OTLP destinations. See the
[managed settings reference](https://code.claude.com/docs/en/settings) and
[server-managed settings reference](https://code.claude.com/docs/en/server-managed-settings).

### Version-specific local evidence

The existing [`docs/telemetry.md`](telemetry.md) lab used Claude Code v2.1.233.
It found that cost, token, and API-request signals kept third-party skill names
as `third-party` even when `OTEL_LOG_TOOL_DETAILS=1` was enabled. Beta tool
spans preserved a name such as `team-a:ping`.

The current public contract now defines `claude_code.skill_activated`. The
v2.1.233 lab did not establish its custom-name behavior. Treat the old result
as evidence for v2.1.233 cost attribution, not as evidence against the current
activation event. Add this event to the lab before relying on it.

### Enterprise analytics

Claude Team and Enterprise analytics provide broad adoption, active-user,
session, spend, and contribution reporting. The administrative analytics
surfaces don't provide the same per-skill event contract as OTel. Use them for
the organization baseline and OTel for skill-level analysis. See the
[Claude Code analytics reference](https://code.claude.com/docs/en/analytics).

## Codex audit

### Codex native telemetry

Codex configures OTel under `[otel]` in user-level or managed `config.toml`.
Project-level `.codex/config.toml` cannot redirect telemetry. Codex supports
OTLP HTTP and gRPC exporters for logs, metrics, and traces.

The [Codex advanced configuration reference](https://developers.openai.com/codex/config-file/config-advanced)
documents these representative logs:

- `codex.conversation_starts`
- `codex.api_request`
- `codex.sse_event`
- `codex.websocket_request`
- `codex.websocket_event`
- `codex.user_prompt`
- `codex.tool_decision`
- `codex.tool_result`

`otel.log_user_prompt` defaults to `false`. Keep it disabled for adoption
reporting. Event metadata includes client version, environment, conversation,
model, and sandbox or approval settings.

Codex exposes counters and histograms for API, stream, WebSocket, turn, token,
tool, approval, MCP, hook, thread, and plugin synchronization activity. Default
metric dimensions include `auth_mode`, `originator`, `session_source`, `model`,
and `app.version`.

The [Codex configuration reference](https://developers.openai.com/codex/config-file/config-reference)
states that `otel.metrics_exporter` defaults to `statsig`, which sends anonymous
usage and health metrics to OpenAI. Replace that exporter with the
organization's OTLP endpoint. Do not set `[analytics] enabled = false` when the
design depends on `codex.skill.injected`: source verification shows that this
setting disables the metrics exporter, including a custom OTLP metrics
exporter. Log and trace exporters remain separate. See the pinned
[OTel provider initialization](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/core/src/otel_init.rs#L13-L78).

### Codex skill signals

The public [Codex metric catalog](https://developers.openai.com/codex/config-file/config-advanced#threads-tasks-and-features)
lists `status` and `skill` on the native
`codex.skill.injected` counter. Official source at revision
[`b5ea64a`](https://github.com/openai/codex/tree/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9)
also emits `invoke_type=explicit|implicit` and `status=ok|error`. A successful
implicit injection emits `status=ok`. An explicit mention emits `error` when
Codex does not inject the mentioned skill. See the pinned
[skill telemetry implementation](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/core/src/skills.rs#L36-L148).

Use positive `status=ok` deltas as the primary signal that Codex injected a
skill into context. Treat `invoke_type` as source-verified rather than a stable
public schema until the field appears in the public metric reference. Preserve
unknown values and validate them during every client upgrade.

The following metrics describe discovery pressure, not invocation:

| Metric | Meaning | Interpretation |
| --- | --- | --- |
| `codex.thread.skills.enabled_total` | Skills enabled for a new thread | Availability volume |
| `codex.thread.skills.kept_total` | Skills retained after prompt rendering | Discoverability after context budgeting |
| `codex.thread.skills.truncated` | Whether Codex truncated the skill list | Catalog pressure and missed-discovery risk |
| `codex.thread.skills.description_truncated_chars` | Description text removed | Description-budget pressure |

The [Codex skills reference](https://developers.openai.com/codex/build-skills)
documents explicit `$skill` selection and implicit matching from the skill
description. The source-verified `invoke_type` distinguishes those paths. The
metric does not prove that the user followed the workflow or produced an
outcome.

### Hooks and plugins

Codex now provides documented lifecycle hooks for sessions, prompts, tools,
compaction, subagents, and stop events. Hooks can come from user or project
configuration, plugins, or managed `requirements.toml`.

The [Codex hooks reference](https://developers.openai.com/codex/hooks) covers
local function tools, shell commands, patches, and MCP calls. It does not
document skill injection as a tool-hook event. Do not parse prompts or
transcripts to infer implicit skill use. That approach collects unnecessary
content and still misses activation paths.

Managed hooks are trusted by policy and cannot be disabled through the user
hook browser. Non-managed plugin hooks require user review and trust. The
native `codex.skill.injected` metric remains the more direct skill signal.

### Identity and administrative reporting

The documented default OTel metric dimensions don't include a stable user or
employee identity. Add identity outside the Codex payload by using one of these
methods:

- Route Codex OTel through a managed local collector that authenticates with a
  per-device certificate.
- Map the managed device identifier to the signed-in employee at ingestion.
- Validate whether the deployed Codex version honors a safe, managed OTel
  resource attribute before depending on that mechanism.

Do not infer identity from a repository path, operating-system username, prompt,
or transcript.

The [Codex workspace analytics guidance](https://developers.openai.com/codex/enterprise/workspace-analytics)
describes broad workspace and Codex reporting. The Analytics API provides
programmatic aggregates. The Compliance API provides auditable records for
security, legal, and investigation use. Treat those surfaces as separate from
the local OTel skill metric.

Use [managed configuration](https://developers.openai.com/codex/enterprise/managed-configuration)
to set OTel defaults and managed hooks. Confirm client-version support before
assigning requirements to the full fleet.

## OpenCode audit

### OpenCode native telemetry

OpenCode has no public telemetry guide. Official source at revision
[`4e81a0b`](https://github.com/anomalyco/opencode/tree/4e81a0b73f6e614afebf9c7ff8862904a3674455)
shows that `OTEL_EXPORTER_OTLP_ENDPOINT` enables:

- Structured logs at `<endpoint>/v1/logs`.
- Traces at `<endpoint>/v1/traces`.
- Headers from `OTEL_EXPORTER_OTLP_HEADERS`.
- Resource attributes from `OTEL_RESOURCE_ATTRIBUTES`.

The [OTLP implementation](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/core/src/observability/otlp.ts)
sets service name and version, installation channel, OpenCode client, run ID,
and service instance ID. The reviewed source contains no native OTLP metrics
pipeline or Prometheus exporter.

The `experimental.openTelemetry` setting enables AI SDK spans. OpenCode adds
the session ID and config `username` to those spans. This surface is explicitly
experimental and inherits AI SDK telemetry semantics. Do not use it as the
primary contract for skill counts. See the pinned
[AI SDK telemetry integration](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/opencode/src/session/llm.ts#L208-L220).

### OpenCode skill signals

The [OpenCode skills reference](https://opencode.ai/docs/skills/) states that
OpenCode loads skills on demand through the native `skill` tool. The source
defines:

```text
tool: skill
input:  { name: string }
output: { name: string, directory: string, output: string }
```

OpenCode does not document a separate direct slash-command path for skills.
The agent sees skill names and descriptions, then calls `skill({name})` to load
the full instructions.

The [documented plugin API](https://opencode.ai/docs/plugins/#events) provides
`tool.execute.before` and `tool.execute.after`. Source verification shows that
the runtime wraps registered built-in tools with both hooks. The after hook
receives `tool`, `sessionID`, `callID`, `args`, and the successful result. A
plugin can therefore count a successful skill load with the following filter:

```ts
"tool.execute.after": async (input) => {
  if (input.tool !== "skill") return

  const skill = input.args.name
  // Send a sanitized event through the organization telemetry helper.
}
```

`tool.execute.before` can count calls that reach the execution hook.
`tool.execute.after` runs only after successful execution in the reviewed
source path. The difference between matching before and after counts measures
aggregate non-successful execution, but it does not distinguish a permission
denial from a missing skill, cancellation, or process failure. Correlate
`callID` with permission and source-verified tool-failure events in the pilot
before publishing reason-specific metrics.

The relevant source contracts are:

- [Skill tool implementation](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/core/src/tool/skill.ts)
- [Plugin hook types](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/plugin/src/index.ts)
- [Built-in tool hook dispatch](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/opencode/src/session/tools.ts#L92-L133)

### Event, server, and SDK surfaces

OpenCode's [server API](https://opencode.ai/docs/server/) exposes server-sent
event (SSE) streams at `/event` and `/global/event`. The SDK exposes
`event.subscribe()`. Events include session, message, permission, command, and
tool lifecycle data.

Current source also defines replayable `session.next.tool.called`,
`session.next.tool.success`, and `session.next.tool.failed` events with session,
message, and call identifiers. These event shapes are useful for an external
sidecar, but they expose more data and are changing alongside the event-sourced
session implementation. Prefer the documented plugin hook for skill counting.
See the pinned
[session tool event schemas](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/schema/src/session-event.ts#L273-L372).

### OpenCode identity and privacy

The default OTLP resource includes a per-run identifier, not a stable employee
identity. AI SDK spans use config `username`, which defaults to the operating
system username. That value is neither authoritative corporate identity nor a
safe Prometheus label.

Derive actor identity at the ingestion boundary from a device certificate,
OIDC token, or internal gateway. Use the config username only as a temporary
pilot signal after a privacy review.

OpenCode states that the OpenCode service does not store code or context data
by default. The local client can persist session data, and it sends context to
the selected model provider. The optional share feature also sends conversation
data to the share service. Set `share: "disabled"` in managed configuration for
an internal telemetry rollout, and review the selected provider separately.
See the [OpenCode enterprise guidance](https://opencode.ai/docs/enterprise/).

## Comparison matrix

The following matrix compares the reviewed public and source-verified surfaces.

| Capability | Claude Code | Codex | OpenCode |
| --- | --- | --- | --- |
| Native OTLP metrics | Yes | Yes | No verified support |
| Native OTLP logs | Yes | Yes | Yes, source verified |
| Native OTLP traces | Beta | Yes; public span catalog is limited | Yes; AI spans require an experimental setting |
| Native Prometheus exporter | Yes | No documented direct exporter; use OTLP | No verified support |
| Exact skill boundary | `skill_activated` event | `skill.injected{status="ok"}` context boundary | Plugin `tool.execute.after` for `skill` |
| Explicit versus implicit trigger | Yes, documented | Yes, source-verified `invoke_type` | No separate direct path documented |
| Named custom skill by default | No; `custom_skill` | Yes in `skill` metric | Yes from plugin args |
| Plugin install signal | `plugin_installed` | Startup synchronization only; not a per-plugin adoption contract | No native adoption event reviewed |
| Plugin active signal | `plugin_loaded` | No equivalent documented per-plugin signal | Telemetry plugin can emit its own startup heartbeat |
| Skill availability signal | Plugin inventory and skill path count | Counts for enabled, kept, and truncated skills | Organization plugin or installer inventory |
| Stable per-user identity in OTel | Several documented identities | Not documented in default dimensions | No authoritative default identity |
| User-level hooks | Yes | Yes | JavaScript or TypeScript plugin hooks |
| Managed hook enforcement | Yes | Yes through `requirements.toml` | Central or global plugin config; enforcement depends on deployment |
| SSE or SDK event stream | Hooks and SDK surfaces | App server and hook surfaces | `/event`, `/global/event`, and SDK subscription |
| Product analytics control | Separate from managed OTel exporters | `analytics.enabled=false` disables the metrics exporter, including custom OTLP | No separate product analytics control reviewed |
| Prompt content default | Redacted | Redacted | Operational logs depend on code path; custom plugin should not send content |
| Hosted-client coverage | Managed and repository hooks can cover supported cloud sessions | Local OTel does not imply ChatGPT web/mobile coverage | Primarily local or organization-hosted OpenCode runtime |

## Proposed telemetry architecture

### Use a normalized event pipeline

Use this data flow:

```text
Claude Code native OTel ----+
                            |
Codex native OTel ----------+--> local relay or collector
                            |        |
OpenCode telemetry plugin --+        +--> authenticated ingestion
                                             |
                                             +--> analytics event store
                                             |
                                             +--> aggregate job
                                                     |
                                                     +--> Prometheus
```

The local relay is optional for a pilot and recommended for production. It can
remove sensitive attributes before they leave the device, attach authenticated
device identity, and queue events during network outages.

The central ingestion service must:

- Authenticate the device or user.
- Validate the client and catalog version.
- Allow only known organization skill identifiers.
- Normalize client-specific names to one canonical skill ID.
- Reject prompt, response, command, path, and repository fields.
- Deduplicate events before persistence and preserve OTel metric temporality.
- Derive the pseudonymous actor key rather than trusting one from the client.

### Normalize skill identifiers

The same skill can have different names in each harness. For example, Claude
Code can report `team-a:ping`, while the generated Agent Skills projection uses
`team-a-ping`.

Add a manifest entry such as:

```json
{
  "skill_id": "acme/team-a/ping",
  "version": "1.1.0",
  "catalog_release": "2026.08.1",
  "aliases": {
    "claude_code": ["team-a:ping", "ping"],
    "codex": ["team-a-ping"],
    "opencode": ["team-a-ping"]
  }
}
```

Resolve aliases at ingestion. Do not put unvalidated client strings into metric
labels.

### Use common observation schemas

Store one event for each discrete Claude Code or OpenCode observation:

```json
{
  "schema_version": 1,
  "event_id": "evt_01...",
  "event_type": "skill.invoked",
  "occurred_at": "2026-08-18T12:00:00Z",
  "client": "claude_code",
  "client_version": "2.1.250",
  "actor_key": "act_7da18...",
  "installation_key": "ins_31c2...",
  "skill_id": "acme/team-a/ping",
  "skill_version": "1.1.0",
  "catalog_release": "2026.08.1",
  "trigger": "implicit",
  "outcome": "success",
  "source_signal": "claude_code.skill_activated"
}
```

Keep `actor_key`, `installation_key`, and `event_id` in the analytics store.
Do not send them to Prometheus.

Codex supplies an aggregated metric data point rather than one event per
invocation. Preserve it with a separate observation shape:

```json
{
  "schema_version": 1,
  "observation_type": "skill.metric_observation",
  "interval_start": "2026-08-18T11:59:00Z",
  "interval_end": "2026-08-18T12:00:00Z",
  "client": "codex",
  "client_version": "0.139.0",
  "actor_key": "act_7da18...",
  "skill_id": "acme/team-a/ping",
  "status": "ok",
  "trigger": "explicit",
  "temporality": "delta",
  "count": 1,
  "source_signal": "codex.skill.injected"
}
```

Keep the source interval, OTel temporality, resource identity, and reset state.
Do not manufacture a new invocation ID for each count in an aggregated data
point. If the source uses cumulative temporality, convert it to a delta with
reset detection before creating daily adoption facts.

Generate IDs as follows:

- Claude Code: Hash the source session ID and event sequence, then discard the
  raw identifiers.
- OpenCode: Hash `sessionID`, `callID`, and event phase.
- Codex: Preserve OTel counter temporality and source intervals. For adoption,
  upsert a daily actor-skill fact from positive `status=ok` deltas so exporter
  retries do not inflate distinct-user counts.

### Map client signals

Use the following source mapping:

| Normalized event | Claude Code | Codex | OpenCode |
| --- | --- | --- | --- |
| `client.reporting` | Session or plugin-loaded event | Thread or process metric | Telemetry plugin heartbeat |
| `catalog.available` | `plugin_loaded` plus manifest | Managed installer or local relay inventory | Telemetry plugin plus manifest |
| `skill.invoked` | Sanitized managed hook, or named `skill_activated` after local redaction | Positive `skill.injected{status="ok"}` delta | Successful `tool.execute.after` for `skill` |
| `skill.attempted` | Hook or tool decision when needed | No separate documented signal | `tool.execute.before` for `skill` |
| `skill.completed` | Domain event from a deterministic tool or service | Domain event from a deterministic tool or service | Domain event from a deterministic tool or service |
| `plugin.installed` | `plugin_installed` | Organization distribution inventory | Installer inventory |
| `plugin.active` | `plugin_loaded` | Managed plugin inventory | Telemetry plugin startup heartbeat |

Do not instruct the model to report its own completion as the only signal. The
model can skip the step, repeat it, or report success before the outcome exists.
Instrument a project-owned script, MCP service, deployment API, or other
deterministic boundary instead.

## Measure adoption per user

### Separate identity from metrics

The ingestion service should derive:

```text
actor_key = HMAC(org_secret, immutable_idp_subject)
```

Keep the reverse mapping in a separate, access-controlled identity service.
Most dashboards and analysts should see pseudonymous actors or cohorts.

Use the IdP group, license roster, or device-management inventory as the
eligible-user denominator. Telemetry alone cannot distinguish a non-user from a
user whose client is offline, outdated, or blocked from reporting.

### Calculate the adoption funnel

Use these definitions:

```text
telemetry coverage
  = reporting eligible users / eligible users

availability rate
  = users with the catalog available / eligible users

activation rate
  = users who invoked the skill / users with the skill available

28-day activation rate
  = eligible users who invoked the skill in 28 days / eligible users

repeat-use rate
  = activated users invoking the same skill on at least 2 distinct days
    / activated users

28-day adoption rate
  = eligible users meeting the repeat-use threshold / eligible users

four-week retention
  = week-1 first-activation cohort users active in week 4
    / users first active in week 1
```

Report telemetry coverage beside every adoption rate. A drop in reporting must
not appear as a drop in skill adoption.

### Store per-user facts outside Prometheus

Use an analytical database such as ClickHouse, BigQuery, Snowflake, or a small
PostgreSQL deployment. Store the minimum fields needed for distinct-user,
retention, and cohort queries.

Publish only aggregates such as:

```text
org_skill_eligible_users{skill="acme_team_a_ping",team="platform"} 120
org_skill_available_users{skill="acme_team_a_ping",team="platform"} 105
org_skill_active_users{skill="acme_team_a_ping",team="platform",window="28d"} 72
org_skill_adopted_users{skill="acme_team_a_ping",team="platform",window="28d"} 52
org_skill_activation_ratio{skill="acme_team_a_ping",team="platform",window="28d"} 0.60
org_skill_adoption_ratio{skill="acme_team_a_ping",team="platform",window="28d"} 0.43
org_skill_invocations_total{client="claude_code",skill="acme_team_a_ping",outcome="success"} 845
```

Bound Prometheus labels to reviewed values such as client, canonical skill,
catalog release, team, trigger bucket, outcome, and reporting window. Do not use
user, session, event, installation, repository, branch, or path labels.

## Measure other useful outcomes

### Reliability

Track attempts, successful loads, failed loads, and latency where the client
exposes them. Useful measures include:

- Skill-load success rate.
- Permission-denial rate.
- Hook or telemetry-export failure rate.
- Client and catalog versions that produce failures.
- Offline queue age and dropped-event count.

### Discovery quality

Use Codex's enabled, kept, and truncated skill metrics to detect catalogs that
exceed the description budget. For all clients, test whether representative
prompts invoke the expected skill and avoid adjacent skills.

Track explicit and implicit invocation separately only where the client reports
the distinction. Codex source reports `invoke_type`, but its public metric docs
do not yet guarantee the field. Validate it during upgrades. Use `tool_call`
for the documented OpenCode path. Do not infer trigger type from prompt text.

### Efficiency and cost

Claude Code can attribute cost and tokens to an active skill, but custom names
can be redacted. Correlate `skill_activated` with request events by prompt ID
when the deployed version provides both fields. Keep the invocation count and
request count separate.

Codex and OpenCode don't expose an equivalent stable per-skill cost contract in
the reviewed surfaces. Use provider-gateway accounting or instrumented internal
services if per-skill cost is required across all clients.

### Outcome quality

Client telemetry provides directional proxies, not business outcomes. Useful
proxies include:

- Edit acceptance or rejection.
- Tool success and failure.
- Commit and pull-request creation.
- Review findings produced.
- Deployment verification results.
- Reverts, incident links, or downstream CI failures from engineering systems.

Join these outcomes to a pseudonymous actor, prompt, or workflow correlation ID
in the analytics store. Do not add those identifiers to Prometheus.

## Privacy and security requirements

Apply these controls before production rollout:

- Publish a telemetry notice that defines purpose, fields, retention, and
  access.
- Keep prompts, responses, reasoning, commands, tool content, file paths, and
  repository names out of the adoption pipeline.
- Authenticate every ingestion request with OIDC, mutual TLS, or a managed
  device credential.
- Derive actor identity server-side and HMAC the immutable IdP subject.
- Keep raw normalized events for 30 to 90 days unless policy requires another
  period.
- Keep daily pseudonymous adoption facts longer only when retention analysis
  requires them.
- Restrict identity reversal to approved administrators.
- Hide cohort reports below an approved minimum, such as five users.
- Record collector configuration and schema changes in version control.
- Fail open for the developer workflow: telemetry failure must not block a
  skill, prompt, or tool.

## Rollout plan

1. Extend `telemetry-lab/` to capture `claude_code.skill_activated` and compare
   it with the v2.1.233 observations.
2. Install a current Codex build in the lab and verify `codex.skill.injected`,
   its status values, OTel temporality, and explicit and implicit coverage.
3. Build a minimal OpenCode telemetry plugin and verify `tool.execute.before`
   and `tool.execute.after` for successful, denied, and missing skills.
4. Define the canonical skill manifest and alias mapping in this repository.
5. Deploy a local relay to the platform team and verify redaction before data
   leaves the device.
6. Store normalized events in a restricted analytics database and publish only
   aggregate Prometheus metrics.
7. Compare reporting users with the IdP denominator for two weeks.
8. Publish the data policy and expand through managed configuration.

The pilot exit criteria are:

- At least 95% of pilot users send a daily reporting heartbeat.
- Duplicate retries don't change daily distinct-user counts.
- No prohibited content reaches central ingestion or storage.
- Each client reports the expected canonical skill in explicit and implicit
  test cases where that distinction is supported.
- Prometheus contains no user, session, event, repository, branch, or path
  labels.

## Known gaps

- Claude Code's current `skill_activated` contract requires a new lab test for
  third-party and organization marketplace names.
- Codex public docs do not define `skill.injected` status values or trigger
  source. The pinned source does, but the public contract can change. Default
  metric resources also lack a documented stable user identity.
- OpenCode's native OTel surface has no public telemetry guide and no verified
  metrics exporter. Its AI SDK spans are experimental.
- Hosted ChatGPT skill use is not guaranteed to pass through local Codex OTel
  configuration or hooks. Use workspace analytics for that product surface.
- Instruction-only skills do not have a universal completion boundary.
- No client-native signal proves that a skill improved engineering outcomes.

## References

### Claude Code

- [Monitoring and OpenTelemetry](https://code.claude.com/docs/en/monitoring-usage)
- [Hooks reference](https://code.claude.com/docs/en/hooks)
- [Skills reference](https://code.claude.com/docs/en/skills)
- [Plugins reference](https://code.claude.com/docs/en/plugins)
- [Settings reference](https://code.claude.com/docs/en/settings)
- [Server-managed settings](https://code.claude.com/docs/en/server-managed-settings)
- [Cloud environments](https://code.claude.com/docs/en/cloud-environments)
- [Analytics](https://code.claude.com/docs/en/analytics)

### Codex

- [Advanced configuration and OTel](https://developers.openai.com/codex/config-file/config-advanced)
- [Configuration reference](https://developers.openai.com/codex/config-file/config-reference)
- [Hooks reference](https://developers.openai.com/codex/hooks)
- [Build skills](https://developers.openai.com/codex/build-skills)
- [Build plugins](https://developers.openai.com/codex/build-plugins)
- [Managed configuration](https://developers.openai.com/codex/enterprise/managed-configuration)
- [Workspace analytics](https://developers.openai.com/codex/enterprise/workspace-analytics)
- [Analytics API](https://developers.openai.com/codex/enterprise/analytics-api)
- [Compliance API](https://developers.openai.com/codex/enterprise/compliance-api)
- [Pinned source revision](https://github.com/openai/codex/tree/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9)
- [Skill telemetry implementation](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/core/src/skills.rs#L36-L148)
- [OTel provider initialization](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/core/src/otel_init.rs#L13-L78)
- [Core OTel metric names](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/otel/src/metrics/names.rs)

### OpenCode

- [Agent Skills](https://opencode.ai/docs/skills/)
- [Plugins](https://opencode.ai/docs/plugins/)
- [SDK](https://opencode.ai/docs/sdk/)
- [Server API](https://opencode.ai/docs/server/)
- [Enterprise and data handling](https://opencode.ai/docs/enterprise/)
- [Pinned source revision](https://github.com/anomalyco/opencode/tree/4e81a0b73f6e614afebf9c7ff8862904a3674455)
- [OTLP implementation](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/core/src/observability/otlp.ts)
- [AI SDK telemetry integration](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/opencode/src/session/llm.ts#L208-L220)
- [Skill tool implementation](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/core/src/tool/skill.ts)
- [Plugin hook types](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/plugin/src/index.ts)
- [Tool hook dispatch](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/opencode/src/session/tools.ts#L92-L133)
- [Session tool events](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/schema/src/session-event.ts#L273-L372)

### Documentation style

This document follows the applicable guidance in the
[Google developer documentation style guide](https://developers.google.com/style).
The main references are:

- [Headings](https://developers.google.com/style/headings)
- [Active voice](https://developers.google.com/style/voice)
- [Present tense](https://developers.google.com/style/tense)
- [Paragraph structure](https://developers.google.com/style/paragraph-structure)
- [Cross-references](https://developers.google.com/style/cross-references)
- [Lists](https://developers.google.com/style/lists)
- [Tables](https://developers.google.com/style/tables)
- [Code in text](https://developers.google.com/style/code-in-text)
- [Accessibility](https://developers.google.com/style/accessibility)
- [Anthropomorphism](https://developers.google.com/style/anthropomorphism)
