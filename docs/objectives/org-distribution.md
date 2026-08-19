# Org distribution

> **Objective.** Put the right plugins on every member's machine without asking
> anyone to run a command or hold repository access.

Team and Enterprise admins can distribute this marketplace through
[Organization settings → Plugins](https://claude.ai/admin-settings/plugins).
Connect it once and Anthropic pushes the plugins to members. Members need no
repository access, browse permitted plugins in Claude Code, and cannot edit
organization-managed plugins locally.

You need a Team or Enterprise plan, an Owner or Primary Owner role, and Cowork
plus Skills enabled. Reference:
[plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) and
the [admin guide](https://support.claude.com/en/articles/13837433).

## Two routes, two jobs

Organization settings and MDM solve different problems. Run both.

```text
Organization settings  ──▶ who gets which plugins, and whether they can opt out
Managed settings (MDM) ──▶ which marketplaces are allowed to exist at all
```

| | Organization settings | Managed settings (MDM) |
| --- | --- | --- |
| Purpose | Distribution and install policy | Allowlisting and blocking sideloading |
| Requires | Team or Enterprise plan, GitHub App | Device management |
| User Git access | Not required; plugins arrive packaged | Required for private sources |
| Require plugins by group | Yes | No, only basic `enabledPlugins` |
| Block other marketplaces | No | Yes, with `strictKnownMarketplaces` |

Use organization settings for distribution and policy, and a minimal MDM
allowlist for enforcement. The MDM half is written up under
[plugin vetting](plugin-vetting.md).

## Connect the marketplace

| Method | Process | Limits |
| --- | --- | --- |
| GitHub sync | Connect a private or internal `owner/repo` through the Claude GitHub App or GHE App. Initial sync runs automatically. | 500 plugins |
| Manual upload | Upload one ZIP per plugin. | 50 MB per ZIP, 100 plugins |

```text
   your private repo
        │   the Claude GitHub App reads it
        ▼
   Anthropic packages the default branch      validate + sync, about 30 min
        │
        ▼
   the member's Claude Code                   no repo access, no git creds
        │                                     cannot edit org-managed plugins
        └── the install policy decides what actually lands
```

Packaging is the whole trick. Because Anthropic ships files rather than a clone
instruction, a member needs no credentials and no access to your repository.

Self-service `marketplace add` requires every user to reach the repository.
Organization settings work the opposite way: they reject public marketplace
repositories outright.

## Meet the source requirements

Organization sync runs without user Git credentials. It can only reach
repositories exposed to the installed GitHub App.

```text
allowed    github · url · git-subdir · relative paths
disallowed npm · archive · command

private sources  must be on github.com under the same owner as the
                 marketplace, or a GHE host where the App is installed
everything else  must be public, including GitLab and Bitbucket, which
                 are fetched anonymously
```

For private code, use relative paths inside the marketplace repository. Sync
packages the plugins, so members still need no repository access. This
repository already uses relative paths.

Plugin names must be lowercase, hyphenated, and 64 characters or fewer.

## Install policies

| Level | Behavior |
| --- | --- |
| Required | Auto-installed, cannot be removed |
| Installed by default | Auto-installed, can be disabled |
| Available for install | Listed for self-service |
| Not available | Hidden |

Enterprise plans support group overrides. A member in several groups gets the
most permissive policy.

Recommended mapping:

```text
core-set     Required               org-wide
blue-set     Installed by default   the blue team's group
green-set    Installed by default   the green team's group
scout        Available for install  handpicked
shared-kit   Not available          it arrives as a dependency
party-parrot Available for install  while testing handpicking, then move it
                                    to Not available once a bundle carries it
```

The mapping above assumes bundle dependencies survive the admin path. That is
not yet proven, which is the subject of
[org sync unknowns](../investigations/org-sync-unknowns.md). Run that pilot before
committing to it.

## Updates

- Manual: select **Update** in organization settings.
- Automatic, opt-in: merge a version-bump PR into the default branch. Direct
  pushes do not trigger auto-sync.
- Validation and sync finish in about 30 minutes. Members see changes in their
  next session, or after refreshing plugins.

Merging to the default branch becomes the release gate for this route, which is
a real change in behavior worth stating plainly:

```diff
 self-service release
   push a tag                    → user machines resolve {plugin}--v{version}

 organization-managed release
-  push a tag
+  merge a version-bump PR       → the server packages the default branch
```

## Rollout checklist

1. Push this repository to the organization's GitHub as private or internal.
2. Install the Claude GitHub App for the repository.
3. Connect `owner/market-place-setup` in **Organization settings → Plugins**.
4. Run the [bundle pilot](../investigations/org-sync-unknowns.md) with one group.
5. Apply the policies above, plus Enterprise group overrides.
6. Add CI validation for dependent version constraints.
7. Enable auto-sync and release through version-bump PRs.
