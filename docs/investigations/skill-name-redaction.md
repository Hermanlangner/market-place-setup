# Skill name redaction

> **Investigation.** Whether Claude Code telemetry preserves custom skill names.
> Tested against a local collector on v2.1.233.

The Claude Code docs suggest `OTEL_LOG_TOOL_DETAILS=1` restores verbatim
third-party names. The lab fired the acme `team-a` ping skill at a local
collector and inspected every signal. That is not what happens on metrics.

The `team-a` plugin has since been retired from the cast. The names below are
kept verbatim because they are the raw observation. The current equivalent
would read `team-blue:standup`.

## Findings

| Signal | Third-party name observed | Evidence |
| --- | --- | --- |
| `cost.usage`, `token.usage` metrics | `"third-party"`, with or without `OTEL_LOG_TOOL_DETAILS=1` | three runs |
| `api_request` events | `"third-party"`, with or without the flag | verified |
| `plugin_loaded`, `plugin_installed` events | verbatim: `plugin.name=team-a`, `marketplace.name=acme`, `plugin.version=1.1.0`, plus a stable `plugin_id_hash` | verified |
| Beta `claude_code.tool` spans with the flag set | verbatim: `tool_name=Skill skill_name=team-a:ping`, plus `duration_ms` | verified |

Read as a map of where the name survives:

```text
metrics   cost.usage / token.usage ────────▶ "third-party"   name lost
events    api_request ────────────────────▶ "third-party"   name lost
events    plugin_loaded / plugin_installed ▶ team-a          name kept
traces    claude_code.tool (beta)  ────────▶ team-a:ping     name kept
                                             requires OTEL_LOG_TOOL_DETAILS=1
```

## What follows from this

- Plugin adoption by name works today, from `plugin_loaded` and
  `plugin_installed`, as soon as the logs exporter is on. No beta feature
  needed.
- Metrics and events cannot give cost per custom skill name. They still separate
  skill-driven spend from baseline, in one `"third-party"` bucket. For most cost
  questions that is enough.
- Per-skill names need beta traces. Join the skill-named `claude_code.tool` span
  to the sibling `claude_code.llm_request` spans that carry token counts in the
  same interaction.
- Without traces, a `PostToolUse` hook can read the skill name from stdin JSON
  and emit a custom counter. That is the cheaper route and it is not beta. Other
  harnesses need their own implementation.

`OTEL_LOG_TOOL_DETAILS=1` is what puts `skill_name` on trace spans. It also adds
tool parameters and command lines to events and spans, so it only belongs in
posture C with the stripping processor attached. See
[telemetry configuration](../resources/telemetry-configuration.md).

## The part this test did not cover

The public monitoring contract now defines `claude_code.skill_activated` as the
exact skill invocation event, covering `user-slash`, `claude-proactive`, and
`nested-skill` triggers. The v2.1.233 lab predates it and established nothing
about its custom-name behavior.

```text
what we proved      v2.1.233 cost and token attribution redacts custom names
what we did NOT     whether skill_activated redacts them too
```

Treat the result above as evidence about cost attribution on v2.1.233, not as
evidence against the current activation event. The published contract says names
for user-defined and third-party plugin skills become `custom_skill` unless
`OTEL_LOG_TOOL_DETAILS=1` is enabled, which is consistent with what we saw but
is not the same test.

Adding `skill_activated` to the lab is step 1 of the rollout plan in
[cross-harness telemetry](cross-harness-telemetry.md). Until then,
do not map the redacted placeholder to a specific catalog entry.
