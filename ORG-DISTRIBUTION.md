# Organization-wide distribution through claude.ai

Team and Enterprise admins can distribute this marketplace without MDM (Mobile
Device Management tools such as Jamf or Intune). Connect it once in
[Organization settings → Plugins](https://claude.ai/admin-settings/plugins),
and Anthropic distributes the plugins to members. Members need no repository
access, can browse permitted plugins in Claude Code, and cannot edit
organization-managed plugins locally.

Requirements: a Team or Enterprise plan, an Owner or Primary Owner role, and
Cowork + Skills enabled.

References: [Plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
and the [admin guide](https://support.claude.com/en/articles/13837433).

## Connect the marketplace

| Method | Process | Limits |
| --- | --- | --- |
| **GitHub sync** | Connect a private or internal repository (`owner/repo`) through the Claude GitHub App or GHE App. Initial sync is automatic. | 500 plugins |
| **Manual upload** | Upload one ZIP per plugin. | 50 MB per ZIP; 100 plugins |

Unlike self-service `marketplace add`, which requires each user to access the
repository, organization settings reject public marketplace repositories.

## Meet the source requirements

Organization sync runs without user Git credentials. It can access only
repositories exposed to the installed GitHub App.

- Allowed sources: `github`, `url`, `git-subdir`, and relative paths.
- Disallowed sources: `npm`, `archive`, and `command`.
- Private sources must be on github.com under the same owner as the marketplace,
  or on a GHE host where the App is installed.
- All other sources must be public. This includes GitLab and Bitbucket sources,
  which are fetched anonymously.
- For private code, use relative paths within the marketplace repository. Sync
  packages the plugins, so members still need no repository access.

This repository already uses relative paths. For future SHA-pinned
`vetted-external` entries, follow
[README: Vetting public plugins](README.md#vetting-public-plugins): use a public
or same-owner source, or vendor it under `plugins/vendored/`.

Plugin names must be lowercase, hyphenated, and no longer than 64 characters.

## Install policies

| Level | Behavior |
| --- | --- |
| **Required** | Auto-installed; cannot be removed |
| **Installed by default** | Auto-installed; can be disabled |
| **Available for install** | Listed for self-service installation |
| **Not available** | Hidden |

Enterprise plans support group overrides. Members in multiple groups receive
the most permissive policy.

Recommended mapping:

- `core-set`: **Required** organization-wide
- `team-set`: **Installed by default** for the relevant team group
- Individual plugins: **Available for install** for handpicked installation
- `shared-a`: **Not available** because it arrives as a dependency
- `shared-b`: **Available for install** while testing handpicking; switch it to
  **Not available** after adding it to a bundle

## Updates

- **Manual:** Select **Update** in organization settings.
- **Automatic, opt-in:** Merge a version-bump PR into the default branch.
  Direct pushes do not trigger auto-sync.
- Validation and sync complete within about 30 minutes. Members receive changes
  in their next session or after refreshing plugins.

## Verify before rollout

Two behaviors are not fully documented. Test them before relying on this route.

### Pilot bundle dependencies and install policies

Documented client-side dependency behavior is clear:

- Dependencies install at the same scope.
- Dependencies enable transitively.
- Dependencies resolve within the same marketplace.
- A dependency cannot be disabled while an enabled plugin depends on it.

The docs do not say whether admin-driven installs behave the same way or which
policy wins when it conflicts with the dependency graph.

Run this pilot with one group:

1. Set `team-set` to **Installed by default** and its members to **Available for
   install**.
2. Run `claude plugin list`. Expect `team-a`, `team-b`, `team-c`, and `core-b` to
   be installed and enabled.
3. Run `claude plugin disable core-b@acme`. Expect a refusal identifying
   `team-a` as a dependent.
4. Set `team-b` to **Not available** while it remains in `team-set`; record which
   policy wins.

If bundles work, keep the bundle-based mapping above: require `core-set` and
apply each team policy to `team-set`, not its individual members. If not, mark
individual plugins **Installed by default** per group and reserve bundles for
self-service users.

### Version resolution

| | Self-service | Organization-managed |
| --- | --- | --- |
| **Distributed version** | User machines resolve `{plugin}--v{version}` Git tags. | The server packages the default branch at sync time. |
| **Release trigger** | Push a tag. | Merge a version-bump PR. |
| **`^1.0` constraints** | Select the highest matching tag. | Validated at load time; a mismatch disables the dependent with `dependency-version-unsatisfied`. |

Merging to the default branch becomes the organization-managed release gate. If
a plugin version is merged before its dependents accept it, the next sync ships
a broken dependency. The failure appears in members' `/plugin` **Errors** tabs,
not during admin sync.

For PRs that change `marketplace.json` or `plugin.json`, add a CI check that
verifies every dependent accepts the versions being merged. Continue tagging
releases for self-service resolution and the vetting audit trail.

## Organization settings and MDM

These systems are complementary:

| | Organization settings | Managed settings (MDM) |
| --- | --- | --- |
| **Purpose** | Distribution and install policy | Allowlisting and blocking sideloading |
| **Requires** | Team or Enterprise plan and GitHub App | Device management |
| **User Git access** | Not required; plugins are packaged | Required for private sources |
| **Require plugins by group** | Yes | No; only basic `enabledPlugins` support |
| **Block other marketplaces** | No | Yes, with `strictKnownMarketplaces` |

Use organization settings for distribution and policy, plus a minimal MDM
allowlist for enforcement. See
[README: Vetting public plugins](README.md#vetting-public-plugins).

## Rollout checklist

1. Push this repository to the organization's GitHub as a private or internal
   repository.
2. Install the Claude GitHub App for the repository.
3. Connect `owner/market-place-setup` in **Organization settings → Plugins**.
4. Run the bundle pilot with one group.
5. Apply the recommended policies and Enterprise group overrides.
6. Add CI validation for dependent version constraints.
7. Enable auto-sync and release through version-bump PRs.
