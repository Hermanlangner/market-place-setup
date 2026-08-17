# Telemetry lab

This local stack exercises the paths described in
[the telemetry guide](../docs/telemetry.md). An OTel Collector receives Claude
Code's OTLP export, re-exposes metrics as Prometheus text, and sends events and
traces to collector stdout. A no-build React dashboard renders the metrics.

## Takeaways

- Use the dashboard for sessions, cost, tokens, lines of code, and metric
  attribution. It polls every 5 seconds.
- The sample Claude command exports every 3 seconds and intentionally sets
  `OTEL_LOG_TOOL_DETAILS=1` to reproduce the name-redaction test.
- Custom skill names still appear as `"third-party"` in metrics. Plugin events
  and beta tool spans provide the verbatim names described in the main guide.
- This is a high-cardinality lab, not a production collector configuration.

## Architecture

```text
claude
  |
  | OTLP gRPC :4317
  v
otel-collector
  |-- metrics :8889 --> nginx :3000 --> React dashboard
  `-- events and traces --> collector stdout (`docker compose logs`)
```

## Start the stack

From `telemetry-lab/`:

```bash
colima start            # or start Docker Desktop
docker compose up -d
open http://localhost:3000
```

## Send metrics

Run any Claude Code session against the collector:

```bash
CLAUDE_CODE_ENABLE_TELEMETRY=1 \
OTEL_METRICS_EXPORTER=otlp \
OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_LOG_TOOL_DETAILS=1 \
OTEL_METRIC_EXPORT_INTERVAL=3000 \
claude
```

This is the metrics path. The detail flag is present only to demonstrate that
third-party metric names remain redacted with the flag enabled. Production
postures A and B in the [main guide](../docs/telemetry.md#privacy-postures) do
not need it; posture C uses it for `skill_name` on trace spans.

The dashboard shows sessions, total cost, tokens by type, lines of code, and
cost by skill, agent, model, user, and plugin. Fire a skill such as
`ping team-a` with the acme marketplace installed to populate the attribution
panels. Lab tests found `"third-party"` for the custom skill metric label,
regardless of `OTEL_LOG_TOOL_DETAILS`.

## Inspect verbatim names

| Signal path | How to enable it | Expected result |
| --- | --- | --- |
| Plugin events | Add `OTEL_LOGS_EXPORTER=otlp`, then run `docker compose logs -f otel-collector` | `plugin_loaded` includes the verbatim plugin name |
| Beta traces | Run `mise run lab:trace` from the repository root | The existing traces pipeline prints `skill_name=team-a:ping` on a tool span |

See [the verified v2.1.233 findings](../docs/telemetry.md#verified-name-behavior-in-claude-code-v21233)
for the full signal matrix.

## Use mise tasks

Run these from the repository root:

| Command | Purpose |
| --- | --- |
| `mise run lab:up` | Start Colima if needed, the collector, and the dashboard |
| `mise run lab:status` | Check containers and endpoint health |
| `mise run lab:ping` | Exercise the metrics path and show `skill_name="third-party"` |
| `mise run lab:trace` | Exercise the beta trace path and show the verbatim skill name |
| `mise run lab:session` | Start an interactive session against the collector |
| `mise run lab:metrics` | Print the current `claude_code` metric series |
| `mise run lab:logs` | Follow collector output for events and traces |
| `mise run lab:down` | Stop the stack |

## Verified output

A real `claude -p` session produced:

| Metric | Observed value or labels |
| --- | --- |
| `claude_code_session_count` | `1` |
| `claude_code_cost_usage_USD` | Approximately `0.27` |
| `claude_code_token_usage` | Split into input/output/cacheRead/cacheCreation |
| Resource labels | `user_email`, `model`, `organization_id`, `session_id` |

## Lab limits

- `resource_to_telemetry_conversion` promotes every resource attribute,
  including email and session ID, to metric labels for easy browsing. This is
  deliberately high cardinality. A production deployment should use Claude
  Code's [metrics cardinality controls](https://code.claude.com/docs/en/monitoring-usage#metrics-cardinality-control)
  and scrape into Prometheus or Grafana.
- `opentelemetry-collector-contrib:0.116.0` has a broken arm64 image that fails
  with `exec /otelcol-contrib: no such file or directory`. The pinned `0.158.0`
  image works.
- Tear down the stack with `docker compose down` from `telemetry-lab/` or
  `mise run lab:down` from the repository root.
