# Update automation

> **Investigation.** Why Renovate rather than Dependabot, and what five large
> projects that have run vendored-copy-plus-update-bot for years converged on.
> The pipeline this feeds is
> [plugin vetting](../objectives/plugin-vetting.md).

## Renovate versus Dependabot

The short version: Dependabot cannot see our dependency, and cannot rebuild the
vendored copy inside a PR. Our dependency is a subdirectory of an arbitrary git
repository pinned by tag, which is not a package ecosystem.

| Requirement | Renovate | Dependabot |
| --- | --- | --- |
| Understand vendir-pinned git content | Native [vendir manager](https://docs.renovatebot.com/modules/manager/vendir/) | Not in the [ecosystem list](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories). The only git path is `gitsubmodule` |
| Track arbitrary git repos and tags | [git-refs](https://docs.renovatebot.com/modules/datasource/git-refs/) and [git-tags](https://docs.renovatebot.com/modules/datasource/git-tags/) datasources | No generic git support beyond submodules |
| Extend to any pinned string, such as our `marketplace.json` shas | [customManagers](https://docs.renovatebot.com/configuration-options/#custommanagers) with regex | No custom datasources, managers, or extension mechanism |
| Regenerate vendored files inside the PR | [lockFileMaintenance](https://docs.renovatebot.com/configuration-options/#lockfilemaintenance) runs `vendir sync`. Proof: [example PR #11](https://github.com/jamietanna/example-github-actions-sync-files/pull/11) | No documented mechanism to run update commands into a PR |
| Run extra commands per update, such as `build-dist.py` | [postUpgradeTasks](https://docs.renovatebot.com/configuration-options/#postupgradetasks), gated by the self-hosted [allowedCommands](https://docs.renovatebot.com/self-hosted-configuration/#allowedcommands) allowlist | No equivalent |
| Supply-chain delay before proposing an update | [minimumReleaseAge](https://docs.renovatebot.com/configuration-options/#minimumreleaseage) suppresses branch and PR creation for X days, which dodges yanked or briefly compromised releases | No equivalent |
| Fleet overview of pending updates | [Dependency Dashboard](https://docs.renovatebot.com/key-concepts/dashboard/). Renovate's own [comparison](https://docs.renovatebot.com/bot-comparison/) says Dependabot has no similar feature | None |
| Scheduling granularity | Per-dependency rules | Four preset intervals |
| Platforms | GitHub, GitLab, GHE, Bitbucket, Azure, Gitea, more | GitHub and Azure DevOps |
| Org-wide config reuse | [Shareable config presets](https://docs.renovatebot.com/config-presets/) | Per-repo YAML |

Dependabot is still the right tool somewhere. It is GitHub-native, zero-config,
and drives [security alerts from the GitHub Advisory Database](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts).
Run it alongside Renovate for classic package ecosystems inside plugins.
[Mergify](https://mergify.com/) and [Kodiak](https://kodiakhq.com/) automate
merging rather than update detection, so they sit at a different layer and are
not alternatives to either.

### The anti-recommendation

Git submodules plus Dependabot looks cheaper and breaks the marketplace.
`marketplace add` clones do not recurse submodules, and org-sync packaging
expects real files. Vendored plugins have to be actual copies, which is exactly
what vendir produces.

```text
submodule    marketplace add → clone → submodule not fetched → empty plugin dir
vendir       marketplace add → clone → real files → plugin loads
```

Two honesty notes. The submodule claim above is our own reading of Claude Code's
clone behavior, not a documented statement from Anthropic. And on the hosted
Renovate app, command execution is limited to what Mend's platform allows, so
unrestricted `postUpgradeTasks` needs self-hosting.

## Copy these setups rather than inventing one

- **[jamietanna/example-github-actions-sync-files](https://github.com/jamietanna/example-github-actions-sync-files)**
  is a minimal, complete Renovate and vendir setup syncing content from another
  repo, with a [private source variant](https://github.com/jamietanna/example-github-actions-sync-files-private).
  [PR #11](https://github.com/jamietanna/example-github-actions-sync-files/pull/11)
  shows exactly what an automated update PR looks like. The whole config is
  about 15 lines: a `vendir.yml` with git url, ref, and `includePaths`, plus a
  `renovate.json` enabling `vendir.lockFileMaintenance`.
  [Walkthrough](https://www.jvt.me/posts/2026/02/27/renovate-update-file/).
- **[zendesk/action-vendir](https://github.com/zendesk/action-vendir)**, a
  GitHub Action wrapping `vendir sync` for CI. Evidence of the pattern at
  corporate scale.
- **[Renovate vendir manager docs](https://docs.renovatebot.com/modules/manager/vendir/)**,
  the config reference.
- skill-scanner ships a
  [reusable workflow](https://github.com/cisco-ai-defense/skill-scanner) that
  writes SARIF into the Code Scanning tab. Its README is the CI example.

## Industrial-scale prior art

Projects that have run vendored copy, bot detects upstream update, PR, named
human reviewer, for years.

| Project | Mechanism | What to take |
| --- | --- | --- |
| **Firefox** | [`mach vendor`](https://firefox-source-docs.mozilla.org/mozbuild/vendor/index.html), a [`moz.yaml`](https://wiki.mozilla.org/Moz_yaml) per vendored library, and [updatebot](https://github.com/mozilla-services/updatebot) on a 6-hour cron | The closest match to our pipeline. Per-library manifest with provenance, the bot opens the patch and assigns the named maintainer as reviewer, plus an alert-only mode for upstreams too complex to auto-vendor |
| **Chromium** | [`third_party/` policy](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/adding_to_third_party.md): a `README.chromium` per dependency, mandatory security@ approval, round-robin third-party reviewers | The governance model. Security considerations recorded next to the code, a `security-critical` field, explicit escalation files |
| **conda-forge** | [autotick bot](https://conda-forge.org/blog/blog/tag/autotick-bot/) watching PyPI and GitHub releases across thousands of feedstocks, computing the dependency graph, PRing each update | Proof the pattern scales past any volume we will reach |
| **nixpkgs** | [r-ryantm / nixpkgs-update](https://nix-community.github.io/nixpkgs-update/r-ryantm/) | Multi-source update detection (Repology, GitHub releases, per-package update scripts), baseline quality checks *before* opening the PR, maintainers auto-tagged |
| **Homebrew** | [Autobump](https://docs.brew.sh/Autobump) with BrewTestBot and `brew bump-formula-pr` | Fully automated bump PRs with CI verification at registry scale |

They converge on five rules. We should adopt all five, and the table shows this
is not one project's opinion:

```text
                              Firefox  Chromium  conda  nixpkgs  Homebrew
   1  provenance manifest        ✓         ✓        ✓       ✓        ✓
      per vendored item
   2  bot proposes, never        ✓         ✓        ✓       ✓        ✓
      merges
   3  named human owner,         ✓         ✓        ✓       ✓        ·
      auto-assigned
   4  security notes beside      ·         ✓        ·       ·        ·
      the code
   5  alert-only mode for        ✓         ·        ·       ✓        ·
      un-automatable upstreams
```

Rule 3 is the one most often skipped, and the one that decides whether the
pipeline works. A PR with no named reviewer sits until someone volunteers. That
means it merges unreviewed, or it never merges.

## Claude-plugin-specific practice

Thin, but worth knowing what exists.

- [Claude Code Plugins: From Personal Setup to Org Standard](https://claudefa.st/blog/tools/mcp-extensions/plugins-distribution),
  an org-level distribution write-up.
- [Chat2AnyLLM/awesome-claude-plugins](https://github.com/Chat2AnyLLM/awesome-claude-plugins),
  a curated list. Curation by list is the low-tech ancestor of vendoring.
- [Publish a plugin to the marketplace](https://systemprompt.io/guides/publish-plugin-claude-marketplace)
  and [Anthropic's plugins announcement](https://claude.com/blog/claude-code-plugins),
  the publisher-side view.
- Directories: [claudemarketplaces.com](https://claudemarketplaces.com/) and
  [aitmpl.com/plugins](https://www.aitmpl.com/plugins/). Useful for discovering
  what exists, and not vetted.
- Anthropic's [community marketplace](https://github.com/anthropics/claude-plugins-community)
  is still the only published screened catalog.
