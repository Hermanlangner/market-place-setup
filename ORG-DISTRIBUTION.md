# Organization-managed plugin distribution (claude.ai admin route)

Companion to the [README](README.md). That document covers the marketplace
itself and the MDM-based lockdown; this one covers the **parallel admin route**:
distributing the marketplace org-wide through **claude.ai → Organization
settings → Plugins**, with no device management involved.

Sources: [Create and distribute a plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
(the "Organization settings > Plugins" notes) and the admin guide
[Manage plugins for your organization](https://support.claude.com/en/articles/13837433).

---

## What it is

On **Team and Enterprise plans**, Owners and Primary Owners get an admin page at
[Organization settings → Plugins](https://claude.ai/admin-settings/plugins)
(Cowork and Skills must be enabled for the org). Instead of every engineer
running `/plugin marketplace add` — or IT pushing `managed-settings.json` to
laptops — an admin connects the marketplace once and Anthropic's backend
distributes it to every member.

Members see the plugins in a **Browse plugins** modal inside Claude Code.
Org-managed plugins can't be edited locally, so shared tools can't drift on
individual machines.

## Connecting a marketplace

Two methods, which can coexist:

| Method | How | Limits | Best for |
|---|---|---|---|
| **GitHub sync** | Connect a **private or internal** repo as `owner/repo`. Read through the **Claude GitHub App** (or your GitHub Enterprise App) — no user git credentials involved. A personal token is used once to verify the connecting admin has access to the repo. Initial sync runs automatically. | 500 plugins | The normal path; this repo |
| **Manual upload** | Upload per-plugin ZIP files. | 50 MB per ZIP, 100 plugins | Quick iteration, non-developer teams |

Note the inversion from the self-service route: `/plugin marketplace add`
requires a repo the *user* can reach (public, or private via their own git
credentials), while the org route requires the marketplace repo to be
**private or internal** — it refuses public marketplace repos.

## Why the source rules are stricter

Organization sync runs **server-side with no access to anyone's git
credentials**. The only private content it can read is what the GitHub App is
installed on. Consequences for `marketplace.json`:

- Plugin sources must be `github`, `url`, `git-subdir`, or **relative paths**.
  `npm`, `archive`, and `command` sources are not supported on this route.
- A plugin source may be **private** in exactly two cases:
  1. a github.com repo **under the same owner** as the marketplace repo, or
  2. a repo on your GitHub Enterprise host with the GHE App installed on it.
- Every other source is fetched **anonymously**, so github.com repos under a
  different owner, and anything on GitLab/Bitbucket/other hosts, must be
  **public**.
- The escape hatch for private code: keep plugin folders **inside the
  marketplace repo as relative paths**. Sync *packages* each plugin during
  distribution, so members never need access to any repository at all — no git
  credentials, SSH keys, or repo permissions on their machines.

**This repo is already the ideal shape**: every plugin is a relative path in
one repo. The entries needing care are sha-pinned `vetted-external` ones (see
the README's vetting section) — those work only if the upstream repo is public
or shares this org's GitHub owner. Otherwise, vendor the reviewed code into
`plugins/vendored/<name>` and reference it by relative path.

Plugin names must be lowercase-hyphenated, max 64 characters (this repo's
already are).

## Distribution control per plugin

Admins assign each plugin an installation level:

| Level | Effect on members |
|---|---|
| **Required** | Auto-installed; member can't remove it |
| **Installed by default** | Auto-installed; member can disable it |
| **Available for install** | Listed in the catalog for self-service |
| **Not available** | Hidden |

**Enterprise group overrides**: admins can override the org-wide level per
group. A member in multiple groups gets the **most permissive** setting
(Required > Installed by default > Available for install > Not available).

This maps directly onto this repo's structure:

- `core-set` → **Required** org-wide
- `team-set` → **Installed by default** for that team's group
- individual plugins (`core-a`, `diagnose`, …) → **Available for install**
  (the handpick flow)
- `shared-*` → **Not available** (they arrive as dependencies; nobody should
  install them directly)

## How updates propagate

- **Manual sync**: an admin clicks **Update** in the admin settings page.
- **Auto-sync** (optional, per marketplace): triggers when a **pull request
  containing a version bump merges to the default branch** — direct pushes do
  *not* trigger it. This quietly enforces a PR-based release flow, which is
  exactly what the vetting audit trail wants anyway.
- Syncs complete within ~30 minutes; the latest commit is compared and plugins
  are validated before replacement.
- Members pick up changes on their **next session or plugin refresh**.

## Org route vs managed settings (MDM) — combine them

The two routes solve different halves of governance:

| | Org settings (this doc) | Managed settings / MDM (README) |
|---|---|---|
| Solves | **Distribution**: push the catalog to everyone, per-plugin/per-group install policy | **Restriction**: block all other marketplaces and side-loading |
| Needs | Team/Enterprise plan, GitHub App | Device management (MDM) |
| User git access | Never needed (plugins are packaged) | Needed for private sources |
| Can require a plugin | Yes (Required / per group) | Only crudely (`enabledPlugins`) |
| Stops users adding random public marketplaces | **No** | **Yes** (`strictKnownMarketplaces`) |

Strongest setup for centrally vetted plugins: **org settings for distribution
and install policy, plus a thin MDM allowlist for enforcement** on managed
machines.

## Checklist to move this repo onto the org route

1. Push the repo to the org's GitHub and make it **private or internal**.
2. Install the **Claude GitHub App** on the repo.
3. Confirm every plugin source is a relative path or a public/same-owner git
   source (all-relative today, so nothing to do until vetted-external entries
   are added).
4. In [Organization settings → Plugins](https://claude.ai/admin-settings/plugins),
   connect `owner/market-place-setup`; initial sync runs automatically.
5. Set installation levels per plugin (suggested mapping above); on Enterprise,
   add group overrides per team.
6. Enable auto-sync and adopt the release convention: changes land via PR with
   a version bump.

## Limitations to keep in mind

- Team/Enterprise plans only; Owners/Primary Owners manage it.
- GitHub only for sync (github.com or GHE) — no GitLab/Bitbucket-hosted
  marketplace on this route.
- 500-plugin cap for synced marketplaces (100 for manual uploads).
- No `npm` / `archive` / `command` plugin sources.
- It distributes but doesn't restrict: pair with `strictKnownMarketplaces` if
  users must not add other marketplaces (see README → Vetting section).
