# Org-wide distribution via claude.ai admin

Team/Enterprise alternative to MDM (Mobile Device Management — Jamf/Intune-style
device policy): an admin connects the marketplace once at
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

## Documented gaps — verify before relying on this route

Two behaviors of our setup change meaning on the org route, and the docs don't
fully specify either. Both have cheap pilots.

### 1. Bundles × admin install levels

**What's documented**: client-side dependency mechanics (auto-install at the
same scope, transitive enable, disable blocked while a dependent is enabled);
that dependencies resolve within the same marketplace; that org-managed plugins
appear to users as managed and can't be edited locally.

**What isn't**: whether an admin-driven install ("Required" / "Installed by
default") triggers dependency resolution the same way `plugin install` does,
and what wins when levels conflict with the graph — e.g. a Required `team-set`
whose member is marked "Not available", or a member trying to disable `core-b`
that a Required bundle needs.

**Pilot** (one group, ~15 min):

1. Set `team-set` → "Installed by default" for a pilot group; members "Available".
2. In a member session: `claude plugin list` — expect team-a/b/c **and** core-b
   installed and enabled.
3. `claude plugin disable core-b@acme` — expect refusal naming team-a.
4. Flip `team-b` → "Not available" while it's in `team-set` — note which wins.

**Decision tree**: if bundles behave → keep them, use levels only for the
Required `core-set`. If not → on the org route, per-group "Installed by
default" on individual plugins is the native equivalent of a bundle; keep
bundles only for self-service users.

### 2. Version semantics shift from tags to merge-to-main

| | Self-service route | Org route |
|---|---|---|
| What users get | Resolved on their machine against `{plugin}--v{version}` git tags | Whatever the default branch held at sync time (packaged server-side) |
| Release act | Pushing a tag | Merging a version-bump PR (auto-sync keys on exactly this) |
| Role of `^1.0` constraints | Resolver — picks the highest matching tag | Safety net only — checked at load time; violation disables the dependent (`dependency-version-unsatisfied`) |

Consequences:

- **Merge-to-main becomes the release gate.** A plugin bump merged before its
  dependents' constraints allow it ships broken on the next sync — and the
  breakage surfaces in *members'* `/plugin` Errors tabs, not at admin sync time.
  Add a CI check on `marketplace.json`/`plugin.json` PRs that verifies every
  dependent's range still matches the bumped versions.
- **Keep tagging anyway**: maintainers and any self-service installs still
  resolve via tags, and tags mark the reviewed commits for the audit trail.
- The version-bump-PR discipline auto-sync enforces is the same discipline the
  vetting audit trail wants, so the two reinforce each other.

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
3. Run the bundle pilot (gap #1 above) with one group before broad rollout.
4. Set install levels (mapping above); add Enterprise group overrides per team.
5. Enable auto-sync; release via version-bump PRs, with a CI constraint check (gap #2).
