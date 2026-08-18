# acme: one Claude Code marketplace for multiple teams

This test bed proves that a single marketplace can serve multiple teams. Users
add one source, then install a team-managed set with one command or handpick
plugins by category. Cross-plugin dependencies resolve automatically.

Unless noted otherwise, the Claude Code behavior below was verified locally with
v2.1.233.

For governance, see [Vetting public plugins](#vetting-public-plugins). For
organization-wide distribution through claude.ai admin, see
[ORG-DISTRIBUTION.md](ORG-DISTRIBUTION.md). New to the terminology? Start with
[docs/agent-anatomy.md](docs/agent-anatomy.md), its
[visual version](docs/agent-anatomy.html), and the
[concept-to-folder breakdown](docs/concepts-and-layout.md).

## Design

### One marketplace, category-based groups

Claude Code reads a Git-hosted catalog only from
`.claude-plugin/marketplace.json` at the repository root, so one repository
cannot host several marketplaces. Instead, the `core`, `team`, `medic`, and
`shared` groups use:

- Folders under `plugins/` as ownership boundaries, ready for CODEOWNERS rules
  per folder.
- `category` and `tags` on catalog entries for filtering in `/plugin`.

### Automatic dependency installation

Each plugin declares its requirements in the `dependencies` array of its own
`plugin.json`. Names resolve within the same marketplace.

```text
core-a  ──▶ shared-a
team-a  ──▶ core-b  (^1.0)

core-set  = core-a + core-b          (bundle; shared-a arrives transitively)
team-set  = team-a + team-b + team-c (bundle; core-b arrives transitively)
medic-set = diagnose                 (bundle)
```

Shared plugins are dependency-oriented. `shared-a` arrives transitively.
`shared-b` starts unreferenced so you can test handpicking, then add it to a
bundle in the central-management exercise below.

### Bundle plugins

Team sets are bundle plugins: small manifests containing `name`, `version`,
`description`, and `dependencies`. Managing a set takes a one-line PR to the
bundle plus a version bump. Users receive the change through `plugin update` or
auto-update.

### Independent plugin versions

Version constraints resolve against Git tags named `{plugin}--v{version}`, such
as `core-b--v1.0.0`. This convention gives each plugin an independent version
line in one repository. If no tag matches, the current copy installs and the
constraint is checked at load time, which allows untagged local testing.

### Guardrails

Claude Code refuses to disable a plugin required by another enabled plugin and
provides the correct chained command. Use `uninstall --prune` or `plugin prune`
to remove orphaned, auto-installed dependencies.

## Layout

```text
.claude-plugin/marketplace.json      catalog (marketplace name: acme)
plugins/
  shared/   shared-a, shared-b       shared building blocks
  core/     core-a, core-b
  team/     team-a, team-b, team-c
  medic/    diagnose
  bundles/  core-set, team-set, medic-set
tools/                               build-dist.py + install-skills.sh
dist/agents/skills/                  generated portable skills for other
                                     harnesses (see docs/multi-harness.md)
```

Each non-bundle plugin has a `ping` skill that replies with
`🏓 pong from <name> v<version>`. This marker confirms what is loaded.

## Local testing

### Install and verify

From the repository root:

```bash
claude plugin validate .              # passes (author warnings are fine)
claude plugin marketplace add ./      # note: "." is rejected, "./" works
claude plugin install team-set@acme   # → + 4 dependencies: team-a, team-b, team-c, core-b
```

Then verify the installation:

1. In a session, run `ping team-a`. Expect `🏓 pong from team-a v1.1.0`.
2. Ping `core-b` to prove that the transitive dependency loads, not merely
   installs.
3. Test handpicking in `/plugin`: browse `acme`, then search for `team` or
   `medic`.

### Verify every component type

`team-a` v1.1.0 includes one of each component type. Each returns a `🏓` marker.
See [docs/concepts-and-layout.md](docs/concepts-and-layout.md).

- **Skill**: say `ping team-a` → `🏓 pong from team-a v1.1.0`
- **Sub agent**: say `use the team-a-pong agent` → the Agent tool spawns it
  and returns `🏓 pong from team-a sub agent v1.1.0`
- **Hook + script**: start a *new* session after installing team-a → a
  SessionStart hook runs `scripts/ping.sh` and its `🏓 pong from team-a script`
  line appears in the session-start output
- Verify what got discovered: `claude plugin details team-a@acme`
  (expects 1 skill, 1 agent, 1 SessionStart hook)

> [!WARNING]
> Hooks execute arbitrary commands on the user's machine. This is why the
> [vetting review](#vetting-public-plugins) covers them.

### Exercise guardrails

```bash
claude plugin disable core-b@acme            # refused: still required by team-a
claude plugin install core-a@acme            # + 1 dependency: shared-a
claude plugin uninstall core-a@acme --prune  # removes shared-a (orphan)
```

### Test version pinning

This test requires a Git commit:

```bash
git tag core-b--v1.0.0
claude plugin install team-a@acme    # resolves core-b via ^1.0 against tags
# change team-a's constraint to ^2.0 and reinstall → no-matching-tag error
```

### Test central management

Add `"shared-b"` to `team-set`'s dependencies and bump its version. Then run:

```bash
claude plugin marketplace update acme && claude plugin update team-set@acme
```

`shared-b` installs for everyone using the bundle.

Cleanup: `claude plugin marketplace remove acme` (also uninstalls its plugins).

## Vetting public plugins

Use the marketplace as the curation point: review a public plugin once, re-list
it here pinned to the reviewed commit, and lock the organization to this
marketplace.

### Curate SHA-pinned entries

Plugin sources (unlike marketplace sources) support exact-commit pins:

```json
{
  "name": "some-public-tool",
  "source": {
    "source": "github",
    "repo": "someone/cool-plugin",
    "ref": "v3.2.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  },
  "category": "vetted-external"
}
```

The `sha` takes precedence over `ref`, so moving an upstream tag changes
nothing. Re-vetting a release requires a PR that updates `ref` and `sha`, and
the PR history becomes the audit trail.

Either vendor the code under `plugins/vendored/` for a relative path and full
control, or use `strict: false` to expose only approved components, such as
skills but not hooks. Focus reviews on hooks, MCP servers, and scripts because
they execute code. Skills are only prompts. Cross-marketplace dependencies
remain blocked unless `allowCrossMarketplaceDependenciesOn` names the other
marketplace.

### Enforce with managed settings (MDM)

IT can deploy an MDM policy to managed machines with Mobile Device Management
tools such as Jamf, Intune, or Kandji. Place the policy at
`/Library/Application Support/ClaudeCode/managed-settings.json`:

```json
{
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "your-org/market-place-setup" }
  ],
  "extraKnownMarketplaces": {
    "acme": { "source": { "source": "github", "repo": "your-org/market-place-setup" } }
  },
  "disableSideloadFlags": true,
  "disableCommandPluginSources": true
}
```

- `strictKnownMarketplaces` is a hard allowlist checked on every add, install,
  and update. Pre-existing, non-matching marketplaces also stop working. An
  empty list, `[]`, creates a total lockdown. Owner wildcards such as
  `"your-org/*"` require v2.1.223+.
- `extraKnownMarketplaces` auto-registers `acme`, so users never run `add`.
- The two `disable*` flags block CLI sideloading and plugin entries that run
  arbitrary local commands. The allowlist checks where a marketplace comes
  from, not what it contains, so set both flags.
- The allowlist breaks local `./` marketplaces. Maintainers need either a
  `pathPattern` entry such as `"^/Users/[^/]+/Projects/"` or exclusion from the
  MDM policy group.

### Test the lockdown locally

> [!WARNING]
> This test requires sudo and affects every session on the machine. Remove the
> policy when finished.

```bash
sudo mkdir -p "/Library/Application Support/ClaudeCode"
sudo tee "/Library/Application Support/ClaudeCode/managed-settings.json" > /dev/null <<'EOF'
{ "strictKnownMarketplaces": [ { "source": "pathPattern", "pathPattern": "^/Users/" } ] }
EOF

claude plugin marketplace add ./                                # allowed
claude plugin marketplace add anthropics/claude-plugins-official # refused

sudo rm "/Library/Application Support/ClaudeCode/managed-settings.json"
```

## Other harnesses (OpenCode, Codex)

OpenCode and Codex both read skills as an open standard. Everything else,
including dependencies, bundles, agents, hooks, and vetting, remains
Claude-first. A small build projects the skills into a shared layout and has
been verified in OpenCode:

```bash
python3 tools/build-dist.py   # plugins/*/*/skills → dist/agents/skills (namespaced)
tools/install-skills.sh       # symlink into ~/.agents/skills (Codex + OpenCode)
opencode run "ping team-a"    # → loads skill team-a-ping → 🏓 pong from team-a v1.1.0
```

Details and portability rules: [docs/multi-harness.md](docs/multi-harness.md).

## Telemetry

Claude Code exports adoption, token and cost, and skill and agent usage through
built-in OpenTelemetry. Enable it organization-wide through the same managed
settings used for marketplace lockdown.

Lab tests with this repository's plugins found:

- Cost and token metrics classify third-party skills as `"third-party"`, whether
  or not `OTEL_LOG_TOOL_DETAILS=1` is set.
- `plugin_loaded` events report plugin adoption verbatim.
- The tracing beta provides per-skill names such as `skill_name=team-a:ping`.

Prompts and responses remain redacted in every posture. For full findings,
privacy postures, and the local test rig, see
[docs/telemetry.md](docs/telemetry.md) and
[telemetry-lab/](telemetry-lab/). Its commands are `mise run lab:up`,
`mise run lab:ping`, and `mise run lab:trace`.

## Automation

Vendored third-party plugins auto-update through Renovate and vendir, with
skill-scanner in CI and human merge as the vetting gate. Bots load their
behavior from this marketplace: claude-code-action natively, the headless CLI
through seed directories, and the Agent SDK through a repo checkout. Scheduled
cloud routines are the one gap. Research-backed design:
[docs/automation.md](docs/automation.md).

## Production checklist

- Push to GitHub. Teammates run
  `claude plugin marketplace add <owner>/<repo>`. Private repositories work
  through normal Git credentials.
- Tag releases with `claude plugin tag --push` so constraints resolve.
- Set CODEOWNERS per `plugins/<group>/`. The platform team owns the catalog and
  `shared/`.
- For mandatory sets, put the bundle in `enabledPlugins` in managed settings or
  use the [organization-distribution route](ORG-DISTRIBUTION.md) for per-group
  install policy.
- Treat bundles as the managed unit. Users should not toggle members
  individually.
- Version floors are v2.1.143+ for dependency auto-enable and disable, and
  v2.1.196+ for local-folder tag resolution.

## CLI quirks (v2.1.233)

- Although documented, `metadata.pluginRoot` is rejected by `validate`. Use
  explicit `./plugins/...` source paths.
- `marketplace add .` is rejected. `add ./` works.
