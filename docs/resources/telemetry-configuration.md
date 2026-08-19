# Telemetry configuration

> **Supporting resource.** The three privacy postures, the exact environment and
> collector blocks to paste, and the controls that keep identifiers out of
> storage.

Exported OTLP data goes to our collector, not to Anthropic or an observability
vendor. Managed settings pin the endpoint so nobody can quietly redirect it.
Prompt and response content stays redacted in all three postures below, because
`OTEL_LOG_USER_PROMPTS` and `OTEL_LOG_ASSISTANT_RESPONSES` stay off.

## The three postures

```text
A  metrics only        cost, tokens, sessions, a "third-party" skill bucket
   └── B  + events    + named plugin adoption, per-tool success, edit decisions
          └── C  + beta traces
                 + named per-skill usage and cost
                 + file paths and commands, which you must strip
```

### A. Metrics only

- Set `OTEL_METRICS_EXPORTER=otlp` and `OTEL_LOGS_EXPORTER=none`.
- You get cost and tokens per user and model, one `"third-party"` skill bucket,
  sessions, active time, lines-of-code counts.
- Names and numbers only. No prompts, commands, or file paths.

### B. Events with central redaction, recommended

- Posture A plus `OTEL_LOGS_EXPORTER=otlp`. Before storage, an OTel Collector
  `attributes` processor deletes `tool_parameters`, `tool_input`, and
  `full_command`.
- You get posture A plus named plugin adoption, per-tool success and duration,
  and edit accept or reject decisions.
- Stripping is defense in depth. Stored data stays names and numbers.

### C. Beta traces

- Posture B plus `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`,
  `OTEL_TRACES_EXPORTER=otlp`, and `OTEL_LOG_TOOL_DETAILS=1`. Apply the same
  stripping to spans, including `full_command` and `file_path`.
- You get posture B plus named per-skill usage and cost, through tool and LLM
  request spans.
- The detail flag adds file paths and commands. Strip them centrally, or
  explicitly accept them for an internal collector.

Pick by the question you actually have:

```text
   question                                      A     B     C
   ───────────────────────────────────────────  ───   ───   ───
   what are we spending, per user and model      ✓     ✓     ✓
   how many sessions, how much active time       ✓     ✓     ✓
   which plugins are installed and loading       ·     ✓     ✓
   which tools fail, and how slow are they       ·     ✓     ✓
   are edits being accepted or rejected          ·     ✓     ✓
   what does skill X cost, by name               ·     ·     ✓
                                                             ↑
                                            beta feature, detail flag,
                                            and span stripping required
```

A covers cost and overall adoption. B is the recommendation, because it adds
named plugin adoption at no content cost. C buys one row for a real price. See
[skill name redaction](../investigations/skill-name-redaction.md) for why that
last row is hard.

## Deploy posture B org-wide

Add this block to the same `managed-settings.json` that carries the
[marketplace allowlist](../objectives/plugin-vetting.md):

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

`OTEL_LOG_TOOL_DETAILS=1` belongs only in posture C, where it supplies
`skill_name` on trace spans.

Attach this processor to the relevant collector pipelines, before storage:

```yaml
processors:
  attributes/strip-sensitive:
    actions:
      - { key: tool_parameters, action: delete }
      - { key: tool_input,      action: delete }
      - { key: full_command,    action: delete }
      - { key: file_path,       action: delete }
```

## Cardinality and identity controls

Claude Code's defaults put account and session dimensions on metrics, which is
a cardinality problem before it is a privacy one. Set these before exporting
through a production pipeline:

```bash
OTEL_METRICS_INCLUDE_SESSION_ID=false
OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false   # unless the pipeline strips it
OTEL_LOG_USER_PROMPTS=0
OTEL_LOG_ASSISTANT_RESPONSES=0
# keep OTEL_LOG_RAW_API_BODIES disabled
```

Then remove email, raw account identifiers, commands, paths, inputs, and outputs
before long-term storage, unless an approved use needs them.

Documented standard attributes are `organization.id`, `user.account_uuid`,
`user.account_id`, `user.id`, `user.email`, `session.id`, and terminal type.
`user.id` is normally a random installation identifier in `~/.claude.json`. When
Claude Code runs through the Claude apps gateway, the client can attach the IdP
subject, email, groups, and `identity.source=gateway-oidc`. See
[standard attributes and cardinality controls](https://code.claude.com/docs/en/monitoring-usage#standard-attributes).

> [!WARNING]
> The native Prometheus endpoint has no control that removes every identity
> attribute. `user.id` and an authenticated `user.email` can survive it. Use
> that endpoint for controlled local validation only, and route production
> metrics through an OTLP collector that strips user and session identifiers
> before Prometheus sees them.

Managed settings can pin exporters, endpoints, protocols, and credentials, and
can remove OTLP destinations a developer set. See the
[managed settings](https://code.claude.com/docs/en/settings) and
[server-managed settings](https://code.claude.com/docs/en/server-managed-settings)
references.

## Codex and OpenCode settings that matter

Two settings will silently break a rollout if you miss them.

| Client | Setting | Why it matters |
| --- | --- | --- |
| Codex | `otel.metrics_exporter` defaults to `statsig` | That sends anonymous usage and health metrics to OpenAI. Replace it with the org OTLP endpoint. |
| Codex | `[analytics] enabled = false` | Source verification shows this disables the metrics exporter *including a custom OTLP one*. Do not set it if the design depends on `codex.skill.injected`. Log and trace exporters stay separate. |
| Codex | Project-level `.codex/config.toml` | Cannot redirect telemetry. Configure at user level or through managed config. |
| Codex | `otel.log_user_prompt` | Defaults to `false`. Keep it there. |
| OpenCode | `share` | Set `share: "disabled"` in managed configuration. The share feature sends conversation data to the share service. |

Details and source pins in
[cross-harness telemetry](../investigations/cross-harness-telemetry.md).

## Privacy requirements before production

- Publish a telemetry notice naming purpose, fields, retention, and access.
- Keep prompts, responses, reasoning, commands, tool content, file paths, and
  repository names out of the adoption pipeline entirely.
- Authenticate every ingestion request with OIDC, mutual TLS, or a managed
  device credential.
- Derive actor identity server-side, by HMAC over the immutable IdP subject.
- Keep raw normalized events 30 to 90 days unless policy says otherwise.
- Keep daily pseudonymous adoption facts longer only when retention analysis
  needs them.
- Restrict identity reversal to approved administrators.
- Hide cohort reports below an approved minimum, such as five users.
- Record collector configuration and schema changes in version control.
- Fail open. A telemetry failure must never block a skill, prompt, or tool.
