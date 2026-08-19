# Cross-harness telemetry

> **Investigation.** What Claude Code, Codex, and OpenCode each expose for
> measuring skill use. Reviewed August 18, 2026. The design that consumes these
> signals is [telemetry pipeline](../resources/telemetry-pipeline.md).

Findings carry one of three evidence levels, and the difference matters when
deciding what to depend on:

```text
documented       the vendor describes it in public docs
source verified  it appears in official source at the cited revision
locally observed this repo's lab reproduced it on a named client version
```

APIs and event schemas change independently of skill content. Re-run the
validation plan before an org-wide rollout or a client upgrade.

## The short version

Each client marks a different moment as "the skill was used", and the moment it
marks decides what you can measure:

```text
   Claude Code   user types /skill, or the model calls the Skill tool
                 └──▶ skill_activated event          the INVOCATION
                      names redacted to custom_skill unless a flag is set

   Codex         the skill text is injected into the prompt
                 └──▶ skill.injected{status=ok}      the CONTEXT INJECTION
                      named, but an aggregated counter, not an event

   OpenCode      the model calls the built-in skill tool
                 └──▶ tool.execute.after             the SUCCESSFUL CALL
                      named, but only if you ship a plugin to catch it
```

None of the three marks completion. A skill that loaded and then failed to help
looks identical to one that worked, in all three.

The three clients are not equivalent, and no single one gives a complete,
privacy-safe adoption model.

| Client | Primary skill signal | Strength | Main limitation |
| --- | --- | --- | --- |
| Claude Code | Sanitized managed hooks for named skills, with `claude_code.skill_activated` as native validation | Exact invocation boundaries | Native custom names are redacted unless tool details are on |
| Codex | `codex.skill.injected` with `status=ok` | Exact context-injection boundary | Trigger field is source verified, absent from public metric docs |
| OpenCode | `tool.execute.after` where `tool == "skill"` | Exact successful tool invocation | Needs an organization plugin to exist at all |

Normalize the client signals in an authenticated ingestion service. Keep
pseudonymous user-level facts in a restricted analytics store, and send only
bounded aggregates to Prometheus.

## Vocabulary

These words get used loosely elsewhere. Here they mean one thing each.

| Term | Meaning |
| --- | --- |
| Available | The client discovered a skill and can offer it to the model or user |
| Invoked | The client loaded or injected the full skill instructions |
| Activated user | An eligible user who invoked a skill at least once in a window |
| Active user | An eligible user who invoked *the same* skill during the window |
| Adopted user | An activated user meeting the org's repeat-use threshold |
| Completed | The skill produced a defined domain outcome. Activation does not prove this |
| Eligible user | A person in the IdP group or license roster who should have access |

## Claude Code

Documented OTel export for metrics, events over the logs protocol, and beta
traces. Nothing exports until `CLAUDE_CODE_ENABLE_TELEMETRY=1`. OTLP over gRPC,
HTTP/JSON, and HTTP/Protobuf, plus a local Prometheus endpoint.

Core metrics, from the
[monitoring reference](https://code.claude.com/docs/en/monitoring-usage):

| Metric | Purpose | Useful dimensions |
| --- | --- | --- |
| `claude_code.session.count` | Session adoption | Start type, standard identity |
| `claude_code.active_time.total` | Real use rather than session starts | User, CLI activity type |
| `claude_code.cost.usage` | Estimated model cost | Model, agent, skill, plugin, query source |
| `claude_code.token.usage` | Input, output, cache tokens | Model, agent, skill, plugin, token type |
| `claude_code.lines_of_code.count` | Added and removed lines | Model, change type |
| `claude_code.commit.count` | Commits created | Standard attributes |
| `claude_code.pull_request.count` | Pull requests created | Standard attributes |
| `claude_code.code_edit_tool.decision` | Edit acceptance | Tool, decision, source, language |

One trap worth stating loudly: cost and token metrics attribute requests made
*while a skill is active*. They do not count invocations. One invocation can
cause several model requests, and a loaded skill can stay active across more
than one.

### The skill boundary

[`claude_code.skill_activated`](https://code.claude.com/docs/en/monitoring-usage#skill-activated-event)
is the exact invocation event. It covers three triggers:

```text
user-slash        the user invokes a / skill
claude-proactive  Claude invokes the Skill tool
nested-skill      an active skill invokes another skill
```

It carries `skill.name`, `skill.source`, `invocation_trigger`, plugin and
marketplace attribution where applicable, plus standard timestamp, sequence,
session, organization, and identity fields.

Names for user-defined and third-party plugin skills become `custom_skill`
unless `OTEL_LOG_TOOL_DETAILS=1` is set. That same flag turns on Bash commands,
file paths, MCP names, and tool arguments on related events. Do not enable it
just to get skill names without a redaction plan. Our own lab result on
v2.1.233 is in [skill name redaction](skill-name-redaction.md).

Adoption events:

| Event | Meaning | Use |
| --- | --- | --- |
| `claude_code.plugin_installed` | An install action completed | New installs and install channel |
| `claude_code.plugin_loaded` | An enabled plugin loaded at session start | Active plugin inventory by version and scope |
| `claude_code.user_prompt` | A prompt or command was submitted | Direct command use where `command_name` exists |
| `claude_code.tool_result` | A tool completed | Success, duration, and Skill-tool parameters when enabled |

`plugin_loaded` beats `plugin_installed` for coverage. A plugin can sit
installed but disabled, or arrive through org policy rather than a user action.

### Hooks are the better production source

The [hooks reference](https://code.claude.com/docs/en/hooks) provides lifecycle
hooks in local, IDE, desktop, and web sessions. Two cover skill invocation:

```text
UserPromptExpansion         direct /skill-name expansion
PostToolUse matcher=Skill   successful model tool calls
```

An organization plugin can use these to emit one sanitized skill event, which
avoids turning on `OTEL_LOG_TOOL_DETAILS=1` for every tool. Use managed settings
or an org-required plugin when coverage must not depend on user configuration.

Recommendation: the sanitized hook adapter is the production source for named
org skills. Keep `skill_activated` on as a native aggregate and cross-check. The
alternative, enabling tool details and stripping in a device-local collector,
also works. Either way, never map the `custom_skill` placeholder to a specific
catalog entry.

### Enterprise analytics

Team and Enterprise analytics give broad adoption, active-user, session, spend,
and contribution reporting, with no per-skill event contract. Use them for the
org baseline and OTel for skill-level analysis.
[Reference](https://code.claude.com/docs/en/analytics).

## Codex

OTel configures under `[otel]` in user-level or managed `config.toml`.
Project-level `.codex/config.toml` cannot redirect telemetry. OTLP HTTP and gRPC
for logs, metrics, and traces.

Representative logs, from the
[advanced configuration reference](https://developers.openai.com/codex/config-file/config-advanced):
`codex.conversation_starts`, `codex.api_request`, `codex.sse_event`,
`codex.websocket_request`, `codex.websocket_event`, `codex.user_prompt`,
`codex.tool_decision`, `codex.tool_result`.

Counters and histograms cover API, stream, WebSocket, turn, token, tool,
approval, MCP, hook, thread, and plugin-sync activity. Default dimensions
include `auth_mode`, `originator`, `session_source`, `model`, `app.version`.

Two configuration traps are written up in
[telemetry configuration](../resources/telemetry-configuration.md): the `statsig` default
exporter, and `[analytics] enabled = false` killing a custom OTLP metrics
exporter. The second is source verified at
[otel_init.rs](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/core/src/otel_init.rs#L13-L78).

### The skill boundary

The [public metric catalog](https://developers.openai.com/codex/config-file/config-advanced#threads-tasks-and-features)
lists `status` and `skill` on `codex.skill.injected`. Official source at
[`b5ea64a`](https://github.com/openai/codex/tree/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9)
emits two more fields:

```text
codex.skill.injected
  skill        the skill name              documented
  status       ok | error                  source verified
  invoke_type  explicit | implicit         source verified, NOT in public docs

  implicit injection that succeeds  → status=ok
  explicit $mention not injected    → status=error
```

Source: [skills.rs](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/core/src/skills.rs#L36-L148).

Use positive `status=ok` deltas as the primary injection signal. Treat
`invoke_type` as source verified rather than a stable public schema until it
appears in the public reference. Preserve unknown values and re-validate on
every client upgrade.

These four measure discovery pressure, not invocation. They are also the best
early warning that a catalog has outgrown its budget:

| Metric | Meaning |
| --- | --- |
| `codex.thread.skills.enabled_total` | Skills enabled for a new thread |
| `codex.thread.skills.kept_total` | Skills retained after prompt rendering |
| `codex.thread.skills.truncated` | Whether Codex truncated the skill list |
| `codex.thread.skills.description_truncated_chars` | Description text removed |

### Hooks and identity

Codex documents lifecycle hooks for sessions, prompts, tools, compaction,
subagents, and stop events, from user config, project config, plugins, or
managed `requirements.toml`. The [hooks reference](https://developers.openai.com/codex/hooks)
does not document skill injection as a tool-hook event. Do not parse prompts or
transcripts to infer implicit skill use. That collects content you do not need
and still misses activation paths.

Default OTel metric dimensions carry no stable user or employee identity. Add it
outside the Codex payload:

- Route Codex OTel through a managed local collector authenticating with a
  per-device certificate.
- Map the managed device identifier to the signed-in employee at ingestion.
- Check whether the deployed version honours a safe managed OTel resource
  attribute before depending on that route.

Never infer identity from a repository path, OS username, prompt, or transcript.

[Workspace analytics](https://developers.openai.com/codex/enterprise/workspace-analytics)
covers broad reporting, with an Analytics API for aggregates and a Compliance
API for auditable records. Both are separate from the local OTel skill metric.

## OpenCode

No public telemetry guide exists. Official source at
[`4e81a0b`](https://github.com/anomalyco/opencode/tree/4e81a0b73f6e614afebf9c7ff8862904a3674455)
shows `OTEL_EXPORTER_OTLP_ENDPOINT` enables structured logs at `/v1/logs`,
traces at `/v1/traces`, headers from `OTEL_EXPORTER_OTLP_HEADERS`, and resource
attributes from `OTEL_RESOURCE_ATTRIBUTES`. The
[OTLP implementation](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/core/src/observability/otlp.ts)
sets service name and version, install channel, client, run ID, and service
instance ID.

The reviewed source has no native OTLP metrics pipeline and no Prometheus
exporter. `experimental.openTelemetry` enables AI SDK spans with session ID and
config `username` attached, but that surface is explicitly experimental and
inherits AI SDK semantics. Do not build the skill count on it.

### The skill boundary

OpenCode loads skills on demand through a native `skill` tool. There is no
documented separate slash-command path. The agent sees names and descriptions,
then calls the tool:

```text
tool:   skill
input:  { name: string }
output: { name: string, directory: string, output: string }
```

The [plugin API](https://opencode.ai/docs/plugins/#events) provides
`tool.execute.before` and `tool.execute.after`. Source verification shows the
runtime wraps registered built-in tools with both. The after hook receives
`tool`, `sessionID`, `callID`, `args`, and the successful result:

```ts
"tool.execute.after": async (input) => {
  if (input.tool !== "skill") return

  const skill = input.args.name
  // Send a sanitized event through the organization telemetry helper.
}
```

`tool.execute.before` counts calls that reach the execution hook.
`tool.execute.after` runs only on success in the reviewed path. The gap between
them measures aggregate non-success, but it cannot tell a permission denial from
a missing skill, a cancellation, or a process failure. Correlate `callID` with
permission and tool-failure events during the pilot before publishing
reason-specific metrics.

Source contracts:
[skill tool](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/core/src/tool/skill.ts) ·
[plugin hook types](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/plugin/src/index.ts) ·
[hook dispatch](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/opencode/src/session/tools.ts#L92-L133)

The [server API](https://opencode.ai/docs/server/) also exposes SSE streams at
`/event` and `/global/event`, and the SDK exposes `event.subscribe()`. Current
source defines replayable `session.next.tool.called`, `.success`, and `.failed`
events. Useful for an external sidecar, but they expose more data and are
changing alongside the event-sourced session rewrite. Prefer the documented
plugin hook.

### Identity

The default OTLP resource carries a per-run identifier, not a stable employee
identity. AI SDK spans use config `username`, which defaults to the OS username.
That is neither authoritative corporate identity nor a safe Prometheus label.
Derive actor identity at the ingestion boundary from a device certificate, an
OIDC token, or an internal gateway.

OpenCode states the service stores no code or context data by default. The local
client persists session data and sends context to the selected model provider.
The optional share feature sends conversation data to the share service, so set
`share: "disabled"` in managed configuration.
[Enterprise guidance](https://opencode.ai/docs/enterprise/).

## Comparison matrix

| Capability | Claude Code | Codex | OpenCode |
| --- | --- | --- | --- |
| Native OTLP metrics | Yes | Yes | No verified support |
| Native OTLP logs | Yes | Yes | Yes, source verified |
| Native OTLP traces | Beta | Yes, limited public span catalog | Yes, AI spans need an experimental setting |
| Native Prometheus exporter | Yes | No direct exporter documented, use OTLP | No verified support |
| Exact skill boundary | `skill_activated` event | `skill.injected{status="ok"}` | Plugin `tool.execute.after` for `skill` |
| Explicit versus implicit trigger | Yes, documented | Yes, source-verified `invoke_type` | No separate direct path documented |
| Named custom skill by default | No, `custom_skill` | Yes, in the `skill` metric | Yes, from plugin args |
| Plugin install signal | `plugin_installed` | Startup sync only, no per-plugin adoption contract | No native adoption event reviewed |
| Plugin active signal | `plugin_loaded` | No documented equivalent | A telemetry plugin can emit its own heartbeat |
| Skill availability signal | Plugin inventory and skill path count | Enabled, kept, truncated counts | Org plugin or installer inventory |
| Stable per-user identity in OTel | Several documented identities | Not in default dimensions | No authoritative default |
| User-level hooks | Yes | Yes | JS or TS plugin hooks |
| Managed hook enforcement | Yes | Yes, through `requirements.toml` | Central or global plugin config, depends on deployment |
| SSE or SDK event stream | Hooks and SDK surfaces | App server and hook surfaces | `/event`, `/global/event`, SDK subscription |
| Product analytics control | Separate from managed OTel exporters | `analytics.enabled=false` kills the metrics exporter, custom OTLP included | None reviewed |
| Prompt content default | Redacted | Redacted | Depends on code path; a custom plugin should send no content |
| Hosted-client coverage | Managed and repo hooks can cover supported cloud sessions | Local OTel does not imply ChatGPT web or mobile coverage | Mainly local or org-hosted runtime |

## Rollout plan

1. Extend `telemetry-lab/` to capture `claude_code.skill_activated` and compare
   it against the v2.1.233 observations.
2. Install a current Codex build in the lab. Verify `codex.skill.injected`, its
   status values, OTel temporality, and explicit versus implicit coverage.
3. Build a minimal OpenCode telemetry plugin. Verify `tool.execute.before` and
   `tool.execute.after` for successful, denied, and missing skills.
4. Define the canonical skill manifest and alias mapping in this repository.
5. Deploy a local relay to the platform team, and verify redaction before data
   leaves the device.
6. Store normalized events in a restricted analytics database. Publish only
   aggregate Prometheus metrics.
7. Compare reporting users against the IdP denominator for two weeks.
8. Publish the data policy and expand through managed configuration.

Pilot exit criteria:

```text
✓ ≥95% of pilot users send a daily reporting heartbeat
✓ duplicate retries do not change daily distinct-user counts
✓ no prohibited content reaches central ingestion or storage
✓ each client reports the expected canonical skill in explicit and implicit
  test cases, where that distinction is supported
✓ Prometheus contains no user, session, event, repository, branch, or path
  labels
```

## Known gaps

- Claude Code's `skill_activated` contract needs a fresh lab test for
  third-party and org marketplace names.
- Codex public docs define neither `skill.injected` status values nor trigger
  source. The pinned source does, but the public contract can move. Default
  metric resources also lack a documented stable user identity.
- OpenCode has no public telemetry guide and no verified metrics exporter. Its
  AI SDK spans are experimental.
- Hosted ChatGPT skill use is not guaranteed to pass through local Codex OTel
  config or hooks. Use workspace analytics for that surface.
- Instruction-only skills have no universal completion boundary.
- No client-native signal proves a skill improved an engineering outcome.

## References

**Claude Code:**
[monitoring and OTel](https://code.claude.com/docs/en/monitoring-usage) ·
[hooks](https://code.claude.com/docs/en/hooks) ·
[skills](https://code.claude.com/docs/en/skills) ·
[plugins](https://code.claude.com/docs/en/plugins) ·
[settings](https://code.claude.com/docs/en/settings) ·
[server-managed settings](https://code.claude.com/docs/en/server-managed-settings) ·
[cloud environments](https://code.claude.com/docs/en/cloud-environments) ·
[analytics](https://code.claude.com/docs/en/analytics)

**Codex:**
[advanced config and OTel](https://developers.openai.com/codex/config-file/config-advanced) ·
[config reference](https://developers.openai.com/codex/config-file/config-reference) ·
[hooks](https://developers.openai.com/codex/hooks) ·
[build skills](https://developers.openai.com/codex/build-skills) ·
[build plugins](https://developers.openai.com/codex/build-plugins) ·
[managed configuration](https://developers.openai.com/codex/enterprise/managed-configuration) ·
[workspace analytics](https://developers.openai.com/codex/enterprise/workspace-analytics) ·
[analytics API](https://developers.openai.com/codex/enterprise/analytics-api) ·
[compliance API](https://developers.openai.com/codex/enterprise/compliance-api) ·
[pinned revision](https://github.com/openai/codex/tree/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9) ·
[metric names](https://github.com/openai/codex/blob/b5ea64a203ce1b04629010d3ef0a0d18c3c870a9/codex-rs/otel/src/metrics/names.rs)

**OpenCode:**
[agent skills](https://opencode.ai/docs/skills/) ·
[plugins](https://opencode.ai/docs/plugins/) ·
[SDK](https://opencode.ai/docs/sdk/) ·
[server API](https://opencode.ai/docs/server/) ·
[enterprise and data handling](https://opencode.ai/docs/enterprise/) ·
[pinned revision](https://github.com/anomalyco/opencode/tree/4e81a0b73f6e614afebf9c7ff8862904a3674455) ·
[AI SDK telemetry](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/opencode/src/session/llm.ts#L208-L220) ·
[session tool events](https://github.com/anomalyco/opencode/blob/4e81a0b73f6e614afebf9c7ff8862904a3674455/packages/schema/src/session-event.ts#L273-L372)
