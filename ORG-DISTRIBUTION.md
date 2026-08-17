# Org-wide distribution via claude.ai admin

Team/Enterprise alternative to MDM: an admin connects the marketplace once at
[Organization settings → Plugins](https://claude.ai/admin-settings/plugins) and
Anthropic's backend distributes it to every member — no device management, no
user git access. Members get a **Browse plugins** modal in Claude Code;
org-managed plugins can't be edited locally.

Requires: Team/Enterprise plan, Owner/Primary Owner role, Cowork + Skills enabled.
Docs: [plugin-marketplaces](https://code.claude.com/docs/en/plugin-marketplaces),
[admin guide](https://support.claude.com/en/articles/13837433).

## Connecting

| Method | How | Limits |
|---|---|---|
| **GitHub sync** | Connect a **private/internal** repo (`owner/repo`), read via the Claude GitHub App (or GHE App). Initial sync is automatic. | 500 plugins |
| **Manual upload** | ZIP per plugin. | 50 MB/ZIP, 100 plugins |

Note the inversion: self-service `marketplace add` needs a repo the *user* can
reach; the org route **refuses public marketplace repos**.

## Source rules (and why)

Sync runs server-side **without anyone's git credentials** — it can only read
what the GitHub App is installed on. Hence:

- Plugin sources: `github`, `url`, `git-subdir`, or relative paths only.
  No `npm` / `archive` / `command`.
- A source may be **private** only if it's github.com under the **same owner**
  as the marketplace repo, or on your GHE host with the App installed.
  Everything else is fetched anonymously → must be public (incl. all
  GitLab/Bitbucket sources).
- Escape hatch for private code: **relative paths inside the marketplace repo**.
  Sync packages each plugin at distribution time, so members need zero repo
  access.

This repo is already all-relative, so nothing to change. Watch out only for
future sha-pinned `vetted-external` entries (README → Vetting): upstream must be
public or same-owner, else vendor into `plugins/vendored/`. Plugin names:
lowercase-hyphenated, ≤64 chars.

## Install policy per plugin

| Level | Effect |
|---|---|
| Required | Auto-installed, can't remove |
| Installed by default | Auto-installed, can disable |
| Available for install | Self-service catalog |
| Not available | Hidden |

Enterprise: per-group overrides; a member in several groups gets the **most
permissive** level. Suggested mapping for this repo:

- `core-set` → Required (org-wide)
- `team-set` → Installed by default (that team's group)
- individual plugins → Available for install (handpick flow)
- `shared-*` → Not available (arrive as dependencies only)

## Updates

- Manual: **Update** button in admin settings.
- Auto-sync (opt-in): triggers on a **version-bump PR merging to the default
  branch** — not on direct pushes. This enforces the PR-based release flow the
  vetting audit trail wants anyway.
- Syncs validate plugins and land within ~30 min; members pick changes up next
  session / plugin refresh.

## Org route vs MDM — use both

| | Org settings | Managed settings (MDM) |
|---|---|---|
| Solves | **Distribution** + install policy | **Restriction** (allowlist, no sideloading) |
| Needs | Team/Enterprise + GitHub App | Device management |
| User git access | Never (plugins packaged) | Needed for private sources |
| Require a plugin per group | Yes | No (only crude `enabledPlugins`) |
| Block other marketplaces | **No** | **Yes** (`strictKnownMarketplaces`) |

Strongest setup: org settings for distribution/policy + thin MDM allowlist for
enforcement (README → Vetting).

## Checklist for this repo

1. Push to the org's GitHub as **private/internal**; install the Claude GitHub App.
2. Connect `owner/market-place-setup` in Organization settings → Plugins.
3. Set install levels (mapping above); add Enterprise group overrides per team.
4. Enable auto-sync; release changes via version-bump PRs.
