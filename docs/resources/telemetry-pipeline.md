# Telemetry pipeline

> **Supporting resource.** The data flow, event schemas, alias manifest, and
> label rules that turn three incompatible client signals into one adoption
> model. The evidence behind each client signal is in
> [cross-harness telemetry](../investigations/cross-harness-telemetry.md).

## The flow

```text
Claude Code native OTel ────┐
                            │
Codex native OTel ──────────┼──▶ local relay or collector
                            │           │
OpenCode telemetry plugin ──┘           └──▶ authenticated ingestion
                                                   │
                                                   ├──▶ analytics event store
                                                   │      (per-user facts)
                                                   └──▶ aggregate job
                                                            │
                                                            └──▶ Prometheus
                                                                  (aggregates
                                                                   only)
```

The local relay is optional for a pilot and recommended for production. It
strips sensitive attributes before they leave the device, attaches
authenticated device identity, and queues events through a network outage.

## What ingestion must do

Every one of these is load-bearing. Skip the last and distinct-user counts
inflate on exporter retries.

```text
authenticate the device or user
validate the client and catalog version
allow only known organization skill identifiers
normalize client-specific names to one canonical skill ID
reject prompt, response, command, path, and repository fields
deduplicate before persistence, preserving OTel metric temporality
derive the pseudonymous actor key rather than trusting one from the client
```

## Normalize the names

The same skill has a different name in each harness. Claude Code reports
`team-blue:standup`, while the generated Agent Skills projection uses
`team-blue-standup`.

```text
plugins/team/team-blue/skills/standup/
  ├── Claude Code   →  team-blue:standup   or   standup
  ├── Codex         →  team-blue-standup
  └── OpenCode      →  team-blue-standup
                            │
                            └──▶ canonical: acme/team-blue/standup
```

Keep the mapping in a manifest in this repository:

```json
{
  "skill_id": "acme/team-blue/standup",
  "version": "1.0.0",
  "catalog_release": "2026.08.1",
  "aliases": {
    "claude_code": ["team-blue:standup", "standup"],
    "codex": ["team-blue-standup"],
    "opencode": ["team-blue-standup"]
  }
}
```

Resolve aliases at ingestion. Never put an unvalidated client string into a
metric label.

## Two observation shapes, because Codex differs

Claude Code and OpenCode produce one observation per event. Codex produces an
aggregated counter data point. Forcing them into one shape loses the interval
and the temporality, so keep two.

### Discrete event

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
  "skill_id": "acme/team-blue/standup",
  "skill_version": "1.0.0",
  "catalog_release": "2026.08.1",
  "trigger": "implicit",
  "outcome": "success",
  "source_signal": "claude_code.skill_activated"
}
```

### Aggregated metric observation

```json
{
  "schema_version": 1,
  "observation_type": "skill.metric_observation",
  "interval_start": "2026-08-18T11:59:00Z",
  "interval_end": "2026-08-18T12:00:00Z",
  "client": "codex",
  "client_version": "0.139.0",
  "actor_key": "act_7da18...",
  "skill_id": "acme/team-blue/standup",
  "status": "ok",
  "trigger": "explicit",
  "temporality": "delta",
  "count": 1,
  "source_signal": "codex.skill.injected"
}
```

Keep the source interval, OTel temporality, resource identity, and reset state.
Do not manufacture an invocation ID per count inside an aggregated data point.
If the source is cumulative, convert to a delta with reset detection before
building daily adoption facts.

`actor_key`, `installation_key`, and `event_id` stay in the analytics store.
None of them reach Prometheus.

### Generating IDs

```text
Claude Code  hash the source session ID and event sequence, then discard
             the raw identifiers
OpenCode     hash sessionID, callID, and event phase
Codex        preserve counter temporality and source intervals; for adoption,
             upsert a daily actor-skill fact from positive status=ok deltas so
             exporter retries cannot inflate distinct-user counts
```

## Signal mapping

| Normalized event | Claude Code | Codex | OpenCode |
| --- | --- | --- | --- |
| `client.reporting` | Session or plugin-loaded event | Thread or process metric | Telemetry plugin heartbeat |
| `catalog.available` | `plugin_loaded` plus manifest | Managed installer or relay inventory | Telemetry plugin plus manifest |
| `skill.invoked` | Sanitized managed hook, or named `skill_activated` after local redaction | Positive `skill.injected{status="ok"}` delta | Successful `tool.execute.after` for `skill` |
| `skill.attempted` | Hook or tool decision, where needed | No separate documented signal | `tool.execute.before` for `skill` |
| `skill.completed` | Domain event from a deterministic tool or service | Same | Same |
| `plugin.installed` | `plugin_installed` | Org distribution inventory | Installer inventory |
| `plugin.active` | `plugin_loaded` | Managed plugin inventory | Telemetry plugin startup heartbeat |

Note what the `skill.completed` row does *not* say. There is no client signal
for it in any harness. Instrument a project-owned script, an MCP service, or a
deployment API. Never take the model's word that it finished, because it can
skip the step, repeat it, or claim success before the outcome exists.

## Identity

```text
actor_key = HMAC(org_secret, immutable_idp_subject)
```

Derive it server-side. Keep the reverse mapping in a separate, access-controlled
identity service. Most dashboards and most analysts should only ever see
pseudonymous actors or cohorts.

## Storage split

Per-user facts belong in an analytical database: ClickHouse, BigQuery,
Snowflake, or a small PostgreSQL. Store the minimum needed for distinct-user,
retention, and cohort queries.

Publish only bounded aggregates:

```text
org_skill_eligible_users{skill="acme_team_blue_standup",team="platform"} 120
org_skill_available_users{skill="acme_team_blue_standup",team="platform"} 105
org_skill_active_users{skill="...",team="platform",window="28d"} 72
org_skill_adopted_users{skill="...",team="platform",window="28d"} 52
org_skill_activation_ratio{skill="...",team="platform",window="28d"} 0.60
org_skill_adoption_ratio{skill="...",team="platform",window="28d"} 0.43
org_skill_invocations_total{client="claude_code",skill="...",outcome="ok"} 845
```

Restrict Prometheus labels to reviewed values:

```text
allowed  client · canonical skill · catalog release · team ·
         trigger bucket · outcome · reporting window

banned   user · session · event · installation · repository ·
         branch · path
```

The funnel definitions these metrics implement are in
[adoption measurement](../objectives/adoption-measurement.md).

## Beyond adoption

Four other things worth measuring once the pipeline exists.

**Reliability.** Skill-load success rate, permission-denial rate, hook and
export failure rate, which client and catalog versions produce failures, offline
queue age, dropped-event count.

**Discovery quality.** Codex's enabled, kept, and truncated skill metrics detect
a catalog that has outgrown its description budget. For every client, test
whether representative prompts invoke the expected skill and skip adjacent ones.
Track explicit versus implicit separately only where the client reports it, and
never infer trigger type from prompt text.

**Efficiency and cost.** Claude Code can attribute cost and tokens to an active
skill, though custom names may be redacted. Correlate `skill_activated` with
request events by prompt ID where the deployed version supplies both. Keep
invocation count and request count separate. Codex and OpenCode expose no stable
per-skill cost contract, so use provider-gateway accounting or instrumented
internal services if you need that across clients.

**Outcome quality.** Edit acceptance and rejection, tool success and failure,
commit and pull-request creation, review findings produced, deployment
verification results, and reverts or incident links from engineering systems.
Join these to a pseudonymous actor, prompt, or workflow correlation ID in the
analytics store. None of those identifiers go to Prometheus.
