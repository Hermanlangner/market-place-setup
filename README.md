# acme — single-marketplace plugin distribution

A working test bed for distributing Claude Code plugins to multiple teams from
**one marketplace**, instead of maintaining a marketplace per group.

The question it answers: *can people add one marketplace, then either install a
team-managed set in one command, or handpick individual plugins filtered by team —
with dependencies between plugins handled automatically?*

**Yes.** Every mechanism below has been verified locally on Claude Code v2.1.233.

It also covers the governance follow-up: using this same marketplace as the
**vetting point** for public third-party plugins (sha-pinned re-listing) and
locking an org down so it's the only allowed plugin source — see
[Vetting public plugins](#vetting-public-plugins-through-the-central-marketplace).

---

## The design

### One marketplace; groups are categories, not marketplaces

Claude Code reads a git-hosted marketplace only from `.claude-plugin/marketplace.json`
at the **repo root**, so one repo can't cleanly expose several git-source
marketplaces. Instead, the groups (`core`, `team`, `medic`, `shared`) are:

- **folders** under `plugins/` — the ownership boundary (add CODEOWNERS per folder), and
- **`category` / `tags`** on each catalog entry — the discovery/filtering surface in `/plugin`.

Users add the marketplace once and browse everything, filterable by group.

### Cross-plugin dependencies with auto-install

Each plugin declares what it needs in its own `.claude-plugin/plugin.json` via the
`dependencies` array. Names resolve within the same marketplace automatically.
The graph in this repo:

```
core-a  ──requires──▶ shared-a
team-a  ──requires──▶ core-b   (semver constraint ^1.0)

core-set  (bundle) ──▶ core-a, core-b         shared-a arrives transitively
team-set  (bundle) ──▶ team-a, team-b, team-c core-b arrives transitively
medic-set (bundle) ──▶ diagnose
```

Installing `core-a` silently brings in `shared-a`. Nobody installs the `shared`
group directly — it exists only to be depended on.

### Team sets are "bundle plugins"

A plugin manifest may consist of nothing but `name`, `version`, and
`dependencies`. Installing it installs the whole set, transitively. That's what
`plugins/bundles/*` are: one install command per team set.

Central management is a one-line PR: add a plugin name to the bundle's
`dependencies`, bump the bundle's `version`, push. Everyone on the bundle picks
it up via `claude plugin update` or marketplace auto-update.

### Version constraints

`team-a` pins `core-b` to `^1.0`. Constraints resolve against git tags named
`{plugin-name}--v{version}` (e.g. `core-b--v1.0.0`) on this repo — the naming
convention is what lets many plugins share one repo with independent version
lines. With no matching tag, Claude Code installs the marketplace's current copy
and checks the constraint at load time, so local testing works without tags.

### Guard rails

- Disabling a plugin that another enabled plugin depends on is **refused**, with
  a chained command that disables the dependents in the right order.
- `claude plugin uninstall <p> --prune` removes auto-installed dependencies that
  nothing else needs; `claude plugin prune` cleans up orphans globally.

---

## Repo layout

```
.claude-plugin/marketplace.json      the catalog users add (marketplace name: acme)
plugins/
  shared/   shared-a, shared-b       dependency-only group
  core/     core-a, core-b
  team/     team-a, team-b, team-c
  medic/    diagnose
  bundles/  core-set, team-set, medic-set
```

Every non-bundle plugin carries one trivial `ping` skill that replies
`🏓 pong from <name> v1.0.0` — the marker used to verify what's actually loaded
in a session.

---

## Testing it locally

Run everything from the repo root. Interactive `/plugin …` slash-command
equivalents work too.

### 1. Validate

```bash
claude plugin validate .
```

Expect `Validation passed` (warnings about missing authors are fine).

### 2. Add the marketplace

```bash
claude plugin marketplace add ./
claude plugin marketplace list
```

Expect `acme` listed with a local path source.

### 3. Handpick flow: browse and filter

Open `/plugin` in a session → browse `acme` → search `team`, `core`, or `medic`
to filter by group. This is the cherry-picking experience.

### 4. Bundle flow: install a team set

```bash
claude plugin install team-set@acme
```

Verified result: `Successfully installed plugin: team-set@acme
(+ 4 dependencies: team-a, team-b, team-c, core-b)` — core-b was never asked
for; it came transitively through team-a.

### 5. Confirm plugins are live

In a session, say `ping team-a` (or invoke `/team-a:ping`). Expect
`🏓 pong from team-a v1.0.0`. Ping `core-b` too — that proves the transitive
dependency loads, not just sits on disk.

### 6. Dependency guard rail

```bash
claude plugin disable core-b@acme
```

Verified result: refused with `core-b is still required by team-a` and a chained
disable command ending in core-b.

### 7. Auto-install + prune

```bash
claude plugin install core-a@acme            # + 1 dependency: shared-a
claude plugin uninstall core-a@acme --prune  # Removed 1 auto-installed plugin: shared-a
```

### 8. Version pinning via tags (optional)

Requires the repo to be a git repo with at least one commit:

```bash
git tag core-b--v1.0.0
claude plugin install team-a@acme    # resolves core-b at the highest tag matching ^1.0
```

To see a constraint fail, change team-a's constraint to `^2.0` in
`plugins/team/team-a/.claude-plugin/plugin.json` and reinstall — expect
`no-matching-tag` naming `core-b@acme`.

### 9. The central-management loop

1. Add `"shared-b"` to `dependencies` in `plugins/bundles/team-set/.claude-plugin/plugin.json`.
2. Bump that file's `version` to `1.1.0`.
3. Refresh and update:

```bash
claude plugin marketplace update acme
claude plugin update team-set@acme
```

Expect shared-b to be installed for everyone on the bundle — the one-line-PR
rollout story.

### Cleanup

```bash
claude plugin marketplace remove acme   # also uninstalls its plugins
```

---

## Vetting public plugins through the central marketplace

The marketplace doubles as the **curation point** for third-party plugins: instead
of users adding public marketplaces themselves, we review a public plugin once,
re-list it in this catalog pinned to the reviewed commit, and (optionally) lock
the org down so this marketplace is the only door in.

### Curation: re-list external plugins pinned by commit

Plugin entries support git sources with a `sha` pin (plugin sources support exact
commits; marketplace sources only support `ref`). Review the code at a commit,
then freeze the entry to it:

```json
{
  "name": "some-public-tool",
  "source": {
    "source": "github",
    "repo": "someone/cool-plugin",
    "ref": "v3.2.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  },
  "category": "vetted-external",
  "tags": ["external", "vetted"]
}
```

When both are set, the `sha` is the effective pin — upstream can move or
force-push the tag and users still get exactly the reviewed bytes. Re-vetting a
new release is a PR bumping `ref`/`sha`, so the repo's PR history *is* the audit
trail. Variants:

- **Vendor** the plugin's code into `plugins/vendored/<name>` (relative path)
  for full control and offline installs.
- **`strict: false`** on the entry to expose only approved components — e.g.
  keep a plugin's skills but drop its hooks.
- What to actually review: **hooks, MCP servers, and scripts** — those execute.
  Skills are just prompts.
- Cross-marketplace dependencies are blocked by default; a plugin here can only
  depend on another marketplace if `allowCrossMarketplaceDependenciesOn` in
  `marketplace.json` names it. Nothing unreviewed can be pulled in silently.

### Enforcement: lock users to this marketplace

Managed settings (deployed via MDM; macOS path
`/Library/Application Support/ClaudeCode/managed-settings.json`):

```json
{
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "your-org/market-place-setup" }
  ],
  "extraKnownMarketplaces": {
    "acme": {
      "source": { "source": "github", "repo": "your-org/market-place-setup" }
    }
  },
  "disableSideloadFlags": true,
  "disableCommandPluginSources": true
}
```

- `strictKnownMarketplaces` is a hard allowlist checked on every add, install,
  update, and refresh — marketplaces added *before* the policy also stop
  working if they don't match. An empty array `[]` is total lockdown (blocks
  even the official Anthropic marketplace; add
  `anthropics/claude-plugins-official` to keep it). Owner wildcards
  (`"your-org/*"`) cover a whole GitHub org (v2.1.223+).
- `extraKnownMarketplaces` auto-registers the marketplace so users never run
  `marketplace add`.
- `disableSideloadFlags` closes the CLI flags that sideload plugins/MCP servers
  for a single run; `disableCommandPluginSources` blocks plugin entries that
  execute an arbitrary local command as their source. Both are worth setting:
  the allowlist checks where a marketplace comes from, not what's inside it.
- Optional: `blockedMarketplaces` (blocklist, same matching rules) and
  `pluginSuggestionMarketplaces` (which marketplaces' plugins Claude may
  contextually suggest).

**Gotcha**: with the allowlist active, a local `./` marketplace no longer
matches — maintainers testing this repo need a `pathPattern` entry, e.g.
`{ "source": "pathPattern", "pathPattern": "^/Users/[^/]+/Projects/" }`, or
their machines left out of the MDM policy group.

On Team/Enterprise plans there's a parallel admin route (claude.ai →
Organization settings → Plugins) that distributes a marketplace org-wide without
MDM, with per-plugin install policy (Required / default / self-service) and
group overrides. It has stricter source rules and combines well with the MDM
allowlist — full write-up in [ORG-DISTRIBUTION.md](ORG-DISTRIBUTION.md).

### Testing governance locally

The allowlist can be tested on one machine by writing the managed settings file
directly (needs sudo; **affects every Claude Code session on the machine —
remove it when done**):

```bash
sudo mkdir -p "/Library/Application Support/ClaudeCode"
sudo tee "/Library/Application Support/ClaudeCode/managed-settings.json" > /dev/null <<'EOF'
{
  "strictKnownMarketplaces": [
    { "source": "pathPattern", "pathPattern": "^/Users/" }
  ]
}
EOF
```

This allows only local-path marketplaces under `/Users/` — so this repo still
works while everything else is blocked. Then verify:

```bash
claude plugin marketplace add ./                          # allowed (pathPattern match)
claude plugin marketplace add anthropics/claude-plugins-official
# expect: refused — not in strictKnownMarketplaces
```

To test sha-pinning, add a `vetted-external` entry (like the example above)
pointing at any public plugin repo, `claude plugin marketplace update acme`,
install it, and confirm the installed version stays fixed even after upstream
tags a newer release and you run `claude plugin update`.

Clean up when finished:

```bash
sudo rm "/Library/Application Support/ClaudeCode/managed-settings.json"
```

---

## Taking this to production

- **Push to GitHub**; teammates run `claude plugin marketplace add <owner>/<repo>`.
  Private repos authenticate through normal git credentials (`gh auth login`,
  SSH agent). Relative plugin sources keep working because the repo is cloned.
- **Tag releases** with `claude plugin tag --push` from each plugin directory so
  semver constraints have something to resolve against.
- **Ownership**: CODEOWNERS per `plugins/<group>/`; the platform team owns
  `.claude-plugin/marketplace.json` and `plugins/shared/`.
- **Mandatory sets**: to make a bundle required rather than opt-in, add it to
  `enabledPlugins` in managed settings — same artifacts, no restructuring.
- **Convention**: treat bundles as the unit teams manage; users shouldn't
  install a bundle and separately toggle its members.
- Dependency auto-enable/disable requires Claude Code **v2.1.143+**; tag reading
  on local-folder marketplaces requires **v2.1.196+**.

## CLI quirks found on v2.1.233

- The docs' `metadata.pluginRoot` shorthand is rejected by `claude plugin
  validate`; use explicit `./plugins/...` source paths (as this catalog does).
- `claude plugin marketplace add .` is rejected as an invalid source; `add ./` works.
