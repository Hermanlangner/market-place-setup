# acme — one Claude Code marketplace for multiple teams

Test bed proving that a **single marketplace** can serve multiple teams: users add
one source, then install a team-managed set in one command or handpick plugins by
category, with cross-plugin dependencies resolved automatically.

All mechanics below verified locally on Claude Code v2.1.233.
Governance (vetting public plugins, org lockdown) is covered at the end;
org-wide distribution via claude.ai admin is in [ORG-DISTRIBUTION.md](ORG-DISTRIBUTION.md).
New to the terminology? See [docs/agent-anatomy.md](docs/agent-anatomy.md)
(visual: [docs/agent-anatomy.html](docs/agent-anatomy.html)) and the
[concept-to-folder breakdown](docs/concepts-and-layout.md).

## Design

**One marketplace, groups as categories.** Claude Code only reads a git-hosted
catalog from `.claude-plugin/marketplace.json` at the repo root, so one repo can't
host several marketplaces. Groups (`core`, `team`, `medic`, `shared`) are instead:
folders under `plugins/` (ownership boundary — CODEOWNERS per folder) and
`category`/`tags` on catalog entries (filtering in `/plugin`).

**Dependencies auto-install.** Each plugin declares needs in its own
`plugin.json` (`dependencies` array); names resolve within the same marketplace.

```
core-a  ──▶ shared-a
team-a  ──▶ core-b  (^1.0)

core-set  = core-a + core-b          (bundle; shared-a arrives transitively)
team-set  = team-a + team-b + team-c (bundle; core-b arrives transitively)
medic-set = diagnose                 (bundle)
```

Nobody installs `shared/` directly — it exists to be depended on.

**Team sets are bundle plugins**: a manifest with only `name`, `version`,
`dependencies`. Managing a set is a one-line PR to the bundle plus a version bump;
users pick it up via `plugin update` or auto-update.

**Version constraints** resolve against git tags named `{plugin}--v{version}`
(e.g. `core-b--v1.0.0`) — that convention gives each plugin an independent version
line in one repo. With no matching tag, the current copy installs and the
constraint is checked at load time, so untagged local testing works.

**Guard rails**: disabling a plugin another enabled plugin needs is refused (with
the correct chained command); `uninstall --prune` / `plugin prune` remove orphaned
auto-installed dependencies.

## Layout

```
.claude-plugin/marketplace.json      catalog (marketplace name: acme)
plugins/
  shared/   shared-a, shared-b       dependency-only
  core/     core-a, core-b
  team/     team-a, team-b, team-c
  medic/    diagnose
  bundles/  core-set, team-set, medic-set
```

Each non-bundle plugin has a `ping` skill replying `🏓 pong from <name> v1.0.0` —
the marker for checking what's loaded.

## Local testing

From the repo root:

```bash
claude plugin validate .              # passes (author warnings are fine)
claude plugin marketplace add ./      # note: "." is rejected, "./" works
claude plugin install team-set@acme   # → + 4 dependencies: team-a, team-b, team-c, core-b
```

Then in a session: `ping team-a` → `🏓 pong from team-a v1.0.0`.
Ping `core-b` too — proves the transitive dependency *loads*, not just installs.
For the handpick flow, open `/plugin`, browse `acme`, search `team` / `medic`.

Component types — `team-a` (v1.1.0) carries one of each, all replying with a
`🏓` marker (see [docs/concepts-and-layout.md](docs/concepts-and-layout.md)):

- **Skill**: say `ping team-a` → `🏓 pong from team-a v1.1.0`
- **Sub agent**: say `use the team-a-pong agent` → the Agent tool spawns it,
  it returns `🏓 pong from team-a sub agent v1.1.0`
- **Hook + script**: start a *new* session after installing team-a → a
  SessionStart hook runs `scripts/ping.sh` and its `🏓 pong from team-a script`
  line appears in the session-start output
- Verify what got discovered: `claude plugin details team-a@acme`
  (expects 1 skill, 1 agent, 1 SessionStart hook)

Hooks execute arbitrary commands on the user's machine — exactly the component
the vetting review below exists for.

Guard rails:

```bash
claude plugin disable core-b@acme            # refused: still required by team-a
claude plugin install core-a@acme            # + 1 dependency: shared-a
claude plugin uninstall core-a@acme --prune  # removes shared-a (orphan)
```

Version pinning (needs a git commit):

```bash
git tag core-b--v1.0.0
claude plugin install team-a@acme    # resolves core-b via ^1.0 against tags
# change team-a's constraint to ^2.0 and reinstall → no-matching-tag error
```

Central-management loop: add `"shared-b"` to `team-set`'s dependencies, bump its
version, then `claude plugin marketplace update acme && claude plugin update
team-set@acme` → shared-b installs for everyone on the bundle.

Cleanup: `claude plugin marketplace remove acme` (also uninstalls its plugins).

## Vetting public plugins

The marketplace doubles as the curation point: review a public plugin once,
re-list it here **pinned to the reviewed commit**, and lock the org to this
marketplace only.

### Curate: sha-pinned entries

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

The `sha` wins over `ref`, so upstream tag moves change nothing. Re-vetting a
release = a PR bumping ref/sha, so PR history is the audit trail. Options:
vendor the code into `plugins/vendored/` (relative path, full control), or use
`strict: false` to expose only approved components (e.g. skills but not hooks).
Review effort goes to **hooks, MCP servers, scripts** — those execute; skills are
prompts. Cross-marketplace dependencies are blocked unless
`allowCrossMarketplaceDependenciesOn` names the other marketplace.

### Enforce: managed settings (MDM)

A policy file IT deploys to managed machines via MDM (Mobile Device Management —
Jamf, Intune, Kandji, etc.), at
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

- `strictKnownMarketplaces`: hard allowlist, checked on every add/install/update —
  pre-existing non-matching marketplaces stop working too. `[]` = total lockdown;
  owner wildcards (`"your-org/*"`) need v2.1.223+.
- `extraKnownMarketplaces`: auto-registers acme so users never run `add`.
- The two `disable*` flags close side doors (CLI sideloading; plugin entries that
  run arbitrary local commands). The allowlist checks where a marketplace comes
  from, not what's inside — so set them.
- Gotcha: the allowlist breaks local `./` marketplaces. Maintainers need a
  `pathPattern` entry (e.g. `"^/Users/[^/]+/Projects/"`) or exclusion from the
  MDM policy group.

### Test the lockdown locally

Needs sudo; affects every session on the machine — remove when done.

```bash
sudo mkdir -p "/Library/Application Support/ClaudeCode"
sudo tee "/Library/Application Support/ClaudeCode/managed-settings.json" > /dev/null <<'EOF'
{ "strictKnownMarketplaces": [ { "source": "pathPattern", "pathPattern": "^/Users/" } ] }
EOF

claude plugin marketplace add ./                                # allowed
claude plugin marketplace add anthropics/claude-plugins-official # refused

sudo rm "/Library/Application Support/ClaudeCode/managed-settings.json"
```

## Production checklist

- Push to GitHub; teammates: `claude plugin marketplace add <owner>/<repo>`.
  Private repos work via normal git credentials.
- Tag releases with `claude plugin tag --push` so constraints resolve.
- CODEOWNERS per `plugins/<group>/`; platform team owns the catalog and `shared/`.
- Mandatory sets: bundle in `enabledPlugins` (managed settings), or use the
  [org-distribution route](ORG-DISTRIBUTION.md) for per-group install policy.
- Treat bundles as the managed unit; users shouldn't toggle members individually.
- Version floors: dependency auto-enable/disable v2.1.143+, local-folder tag
  resolution v2.1.196+.

## CLI quirks (v2.1.233)

- `metadata.pluginRoot` (documented) is rejected by `validate` — use explicit
  `./plugins/...` source paths.
- `marketplace add .` is rejected; `add ./` works.
