# Automation: vendored-plugin updates and marketplace-powered bots

Two automation questions, answered from ecosystem research (August 2026)
rather than from scratch. Compose existing tools; keep only thin glue.

## 1. Vendoring third-party plugins with automated updates and scanning

### What people actually use

| Concern | Tool | Why it fits |
| --- | --- | --- |
| Vendor + pin | [vendir](https://carvel.dev/vendir/) | Declarative `vendir.yml` (git URL, pinned ref, `includePaths` subdir) with a lockfile — a standardized `vendor.json` |
| Detect updates + PR | [Renovate](https://docs.renovatebot.com/) | **Native vendir manager**: watches upstream tags, bumps the pin, runs `vendir sync`, opens a PR whose diff is the upstream change. Battle-tested scheduling/grouping/PR lifecycle. [Worked example](https://www.jvt.me/posts/2026/02/27/renovate-update-file/) |
| Scan for malicious content | [cisco-ai-defense/skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) | Purpose-built for Agent Skills / `SKILL.md` (our exact format). Pattern rules (YAML+YARA+Python), dependency intel, **LLM analysis with adjudication**, dataflow analysis. CI-ready: SARIF for GitHub Code Scanning, reusable Action, pre-commit hook. `pip install cisco-ai-skill-scanner` |
| Client-side defense | [cc-plugin-audit](https://github.com/STRML/cc-plugin-audit) | Runs on engineers' machines as a plugin: hashes installed plugins, flags marketplace auto-updates at session start, surfaces security diffs. Not CI — a complementary layer |

Threat justification: Snyk's ToxicSkills research found prompt injection in
[36% of skills tested](https://snyk.io/articles/top-claude-skills-cybersecurity-hacking-vulnerability-scanning/)
across the ecosystem.

### What Anthropic provides (and doesn't)

- The [community marketplace](https://github.com/anthropics/claude-plugins-community)
  is screened by an **internal, proprietary pipeline** (automated scan + human
  review, nightly catalog sync, SHA-pinned entries). Nothing reusable — but it
  confirms the pattern: pin + scan + human gate.
- [claude-code-security-review](https://github.com/anthropics/claude-code-security-review)
  (official Action) reviews PR diffs with Claude — but it is **explicitly not
  hardened against prompt injection** and is documented for *trusted* PRs
  only. Vendored third-party code is untrusted by definition, so it is the
  wrong AI layer here; skill-scanner's adjudicating LLM analyzer is designed
  for adversarial skill content.
- `claude plugin validate` checks structure/schema only — no security scan.

### Recommended pipeline

```
Renovate (cron) ──new upstream tag──▶ bump vendir.yml + vendir sync ──▶ PR
                                                                        │
CI on the PR: vendir sync --check · claude plugin validate ·           ▼
skill-scanner (SARIF → Code Scanning) · human review = vetting gate ──▶ merge
                                                                        │
                    marketplace entry serves the vendored copy ◀────────┘
```

- The PR body/diff is the audit trail; `vetted` state is the merge itself.
- The vendored copy keeps [org-distribution](../ORG-DISTRIBUTION.md)
  compatibility (relative paths, no external fetch at install time).
- Our own AI second opinion (a Claude audit prompt) is optional on top;
  treat any LLM verdict on untrusted content as advisory input to the human
  gate, never as the gate.

**Build-vs-buy outcome**: the earlier hand-rolled scaffolding in this repo
(`tools/vendor.py`, `tools/scan-plugin.sh`) is superseded by vendir + Renovate
+ skill-scanner. The `plugins/bots/vendor-auditor` skill remains useful as the
codified audit rubric a human reviewer (or optional Claude pass) applies on
the PR.

## 2. Using the marketplace for managed agents and automated bots

A bot is a Claude session without a human — and in three of the four official
runtimes, it can load plugins from this marketplace, so **bot behavior ships,
versions, and gets vetted exactly like human tooling**:

| Runtime | Plugin support | How the marketplace plugs in |
| --- | --- | --- |
| [claude-code-action](https://code.claude.com/docs/en/github-actions.md) (GitHub CI) | **Native**: `plugin_marketplaces` + `plugins` inputs | `plugin_marketplaces: <this repo git URL>`, `plugins: review-bot@acme` — the bot's behavior is a plugin entry |
| Headless CLI (`claude -p` on cron/own infra) | Full | `claude plugin marketplace add` in provisioning, or [CLAUDE_CODE_PLUGIN_SEED_DIR](https://code.claude.com/docs/en/plugin-marketplaces#pre-populate-plugins-for-containers) to pre-bake plugins into container images |
| [Agent SDK](https://code.claude.com/docs/en/agent-sdk/plugins.md) (self-hosted bots) | **Local paths only** | Check out this repo in the bot image and point `plugins: [{type: "local", path: "plugins/team/team-a"}]` at it — the monorepo layout is exactly what the SDK wants |
| [Cloud routines](https://code.claude.com/docs/en/scheduled-tasks.md) (`/schedule`) | **None** — MCP connectors only | The one gap: scheduled cloud runs can't load plugins; keep scheduled bots on CI cron or self-hosted, or express the capability as an MCP server |
| [Managed Agents](https://claude.com/blog/claude-managed-agents) (Anthropic-hosted, ~Apr 2026) | **Skills (≤20) + MCP**, not full plugins | Feed it from `dist/agents/skills/` — the [multi-harness projection](multi-harness.md) doubles as the Managed Agents skill source |

Patterns this enables:

- **Bot behavior as a `bots/` category**: a PR-review bot, a triage bot, the
  vendor-audit rubric — each a plugin entry. Updating a bot = a version-bump
  PR; rollback = pin the old version; vetting/telemetry identical to human
  plugins.
- **Reproducibility**: pin bot plugins by `version` (or install from a tagged
  ref) so a bot's behavior is deterministic per deploy, unlike a prompt
  pasted into a workflow file.
- **Identity & telemetry**: run bots on service accounts with
  `user.slug=bot-<name>`; the `app.entrypoint` attribute separates
  cli/sdk/action traffic, so bot cost and usage report through the same
  [telemetry pipeline](telemetry.md) as humans.
- **Governance carries over**: `strictKnownMarketplaces` on bot infrastructure
  pins bots to this marketplace the same way it pins laptops.

## Reference examples

Look at these instead of building from scratch:

- **[jamietanna/example-github-actions-sync-files](https://github.com/jamietanna/example-github-actions-sync-files)** —
  minimal, complete Renovate + vendir setup syncing content from another repo
  (private source: […-private](https://github.com/jamietanna/example-github-actions-sync-files-private)).
  [PR #11](https://github.com/jamietanna/example-github-actions-sync-files/pull/11)
  shows exactly what an automated update PR looks like. The entire config is
  ~15 lines: a `vendir.yml` (git url + ref + `includePaths`) and a
  `renovate.json` enabling `vendir.lockFileMaintenance`.
  Walkthrough: [jvt.me post](https://www.jvt.me/posts/2026/02/27/renovate-update-file/).
- **[zendesk/action-vendir](https://github.com/zendesk/action-vendir)** —
  Zendesk's GitHub Action wrapping `vendir sync` for CI, evidence of the
  pattern at corporate scale.
- **[Renovate vendir manager docs](https://docs.renovatebot.com/modules/manager/vendir/)** —
  the manager's own config reference.
- Scanner-in-CI reference: skill-scanner ships a
  [reusable GitHub Actions workflow](https://github.com/cisco-ai-defense/skill-scanner)
  (SARIF → Code Scanning tab) — its README is the CI example.

## Why Renovate — especially over Dependabot

Every claim linked to its source. The short version: Dependabot cannot see our
"dependency" (a subdirectory of an arbitrary git repo, pinned by tag) and
cannot rebuild the vendored copy inside a PR; Renovate does both natively.

| Requirement | Renovate | Dependabot |
| --- | --- | --- |
| Understand vendir-pinned git content | Native [vendir manager](https://docs.renovatebot.com/modules/manager/vendir/) | Not in the [fixed ecosystem list](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories); the only git path is `gitsubmodule` |
| Track arbitrary git repos/tags | [git-refs](https://docs.renovatebot.com/modules/datasource/git-refs/) / [git-tags](https://docs.renovatebot.com/modules/datasource/git-tags/) datasources | No generic git support beyond submodules ([ecosystems doc](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories)) |
| Extensible to *any* pinned string (e.g. our `marketplace.json` shas) | [customManagers (regex)](https://docs.renovatebot.com/configuration-options/#custommanagers) | No custom datasources, managers, or extension mechanism ([ecosystems doc](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories)) |
| Regenerate vendored files inside the PR | [lockFileMaintenance](https://docs.renovatebot.com/configuration-options/#lockfilemaintenance) runs `vendir sync`; proof: [example PR #11](https://github.com/jamietanna/example-github-actions-sync-files/pull/11) | No documented mechanism to run update commands into a PR |
| Run extra commands per update (e.g. `build-dist.py`) | [postUpgradeTasks](https://docs.renovatebot.com/configuration-options/#postupgradetasks), gated by the self-hosted [allowedCommands](https://docs.renovatebot.com/self-hosted-configuration/#allowedcommands) allowlist | No equivalent |
| Supply-chain delay before proposing updates | [minimumReleaseAge](https://docs.renovatebot.com/configuration-options/#minimumreleaseage) — "suppress branch/PR creation for X days", dodging yanked/briefly-compromised releases | No equivalent |
| Fleet overview of pending updates | [Dependency Dashboard](https://docs.renovatebot.com/key-concepts/dashboard/); Renovate's [official comparison](https://docs.renovatebot.com/bot-comparison/): "Dependabot does not have a similar feature" | — |
| Scheduling granularity | Per-dependency rules ([bot comparison](https://docs.renovatebot.com/bot-comparison/)) | Four preset intervals ([bot comparison](https://docs.renovatebot.com/bot-comparison/)) |
| Platforms | GitHub, GitLab, GHE, Bitbucket, Azure, Gitea and more ([platforms](https://docs.renovatebot.com/modules/platform/)) | GitHub and Azure DevOps ([bot comparison](https://docs.renovatebot.com/bot-comparison/)) |
| Org-wide config reuse | [Shareable config presets](https://docs.renovatebot.com/config-presets/) | Per-repo YAML |

Where Dependabot **is** the right tool: it's GitHub-native, zero-config, and
drives [security alerts from the GitHub Advisory Database](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts)
— worth running *alongside* Renovate for classic package ecosystems inside
plugins. And bots like [Mergify](https://mergify.com/) or
[Kodiak](https://kodiakhq.com/) automate *merging*, not update detection — a
different layer, not an alternative.

Two honesty notes: the submodules-break-the-marketplace point above is our own
analysis of Claude Code's clone behavior, not a documented statement; and on
the hosted Renovate app, command execution is limited to what Mend's platform
allows — unrestricted `postUpgradeTasks` requires self-hosting.

## Further research: public vendoring practice

### Industrial-scale prior art (vendored third-party + update bots)

The strongest references are projects that have run "vendored copy + bot
detects upstream updates + PR + named human reviewer" for years:

| Project | Mechanism | What to steal |
| --- | --- | --- |
| **Firefox** | [`mach vendor`](https://firefox-source-docs.mozilla.org/mozbuild/vendor/index.html) + a [`moz.yaml`](https://wiki.mozilla.org/Moz_yaml) per vendored library + [updatebot](https://github.com/mozilla-services/updatebot) (cron every 6h) | Closest architectural match to our pipeline: per-library manifest with provenance, bot opens the patch and **assigns the named maintainer as reviewer**; an *alert-only* mode for upstreams too hairy to auto-vendor |
| **Chromium** | [`third_party/` policy](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/adding_to_third_party.md): `README.chromium` metadata per dependency, mandatory security@ approval, round-robin third-party reviewers | The **governance** model: security considerations recorded next to the code, a `security-critical` field, explicit escalation files (`README.SECURITY.URGENTLY`) |
| **conda-forge** | [autotick bot](https://conda-forge.org/blog/blog/tag/autotick-bot/) ([how it works](https://conda-forge.org/docs/maintainer/updating_pkgs.html)) | Watches PyPI/GitHub releases across thousands of feedstocks, computes the dependency graph, PRs each update — proof the pattern scales |
| **nixpkgs** | [r-ryantm bot / nixpkgs-update](https://nix-community.github.io/nixpkgs-update/r-ryantm/) ([wiki](https://wiki.nixos.org/wiki/Nixpkgs/Automatic_Updates), [example PR](https://github.com/NixOS/nixpkgs/pull/360281)) | Multi-source update detection (Repology + GitHub releases + per-package update scripts), **baseline quality checks before opening the PR**, maintainers auto-tagged |
| **Homebrew** | [Autobump](https://docs.brew.sh/Autobump) (BrewTestBot + `brew bump-formula-pr`) | Fully automated bump PRs with CI verification at registry scale |

The distilled lessons these converge on: (1) a provenance manifest per
vendored item; (2) a bot that detects and proposes, never merges; (3) a named
human owner per item, auto-assigned; (4) security notes recorded beside the
code; (5) an alert-only mode for un-automatable upstreams.

### Claude-plugin-specific practice (young, thinner)

- [Claude Code Plugins: From Personal Setup to Org Standard](https://claudefa.st/blog/tools/mcp-extensions/plugins-distribution) — org-level distribution practices write-up
- [Chat2AnyLLM/awesome-claude-plugins](https://github.com/Chat2AnyLLM/awesome-claude-plugins) — curated list of marketplaces/plugins (curation-by-list, the low-tech ancestor of vendoring)
- [Publish a plugin to the marketplace](https://systemprompt.io/guides/publish-plugin-claude-marketplace) (systemprompt.io) and [Anthropic's plugins announcement](https://claude.com/blog/claude-code-plugins) — publisher-side view
- Directories: [claudemarketplaces.com](https://claudemarketplaces.com/), [aitmpl.com/plugins](https://www.aitmpl.com/plugins/) — useful for discovering what exists, not vetted
- Anthropic's own [community marketplace](https://github.com/anthropics/claude-plugins-community) (see above) remains the only published *screened* catalog

## Cost breakdown

Monthly, assuming a private GitHub repo and a handful of vendored-plugin
update PRs per month:

| Component | License cost | Run cost |
| --- | --- | --- |
| vendir | $0 (OSS binary) | seconds of CI |
| Renovate — hosted [Mend GitHub App](https://github.com/apps/renovate) | $0 (free tier covers private repos; Mend sells enterprise tiers) | $0 (runs on Mend's infra) |
| skill-scanner, static layers (YARA/patterns) | $0 | seconds of CI |
| skill-scanner, LLM analyzer | $0 | LLM tokens per update PR — single-digit $/mo at our PR volume |
| Optional Claude second-opinion audit | — | measured in our lab at ~$0.06–0.27 per small run; PR-sized ≈ $0.5–2 → a few $/mo |
| GitHub Actions minutes | — | a few min/week, inside included minutes |
| Heeler | **$0 incremental** (already licensed) | — |
| The real cost | — | **human review per update PR** (~15–30 min each) — the vetting gate is irreducible |

## Lowest-cost path (non-OSS-managed, Heeler in place)

Zero new vendors, zero new licenses:

1. **Heeler does the scanning** — its GitHub integration + Agent Skills
   inventory/scoring replaces self-run skill-scanner *and* the client-side
   layer (cc-plugin-audit). Already paid for.
2. **Hosted Renovate app does detection + PRs** — free, operated by Mend, so
   nothing to run or maintain; the only self-owned piece is the ~15-line
   vendir/renovate config from the reference repo above.
3. **GitHub does the rest** — Actions for `vendir sync` verification and
   branch protection for the human gate.

Incremental spend ≈ Actions minutes + optional Claude audit tokens.

Anti-recommendation: git **submodules + Dependabot** looks even cheaper but
breaks the marketplace — `marketplace add` clones don't recurse submodules and
org-sync packaging expects real files, so vendored plugins must be actual
copies (which is what vendir produces).

## Vendor directory

Everything mentioned above plus the evaluated alternatives, in one place.

### Open source

| Tool | Role | Lookup |
| --- | --- | --- |
| vendir (Carvel/Broadcom) | Declarative vendoring with lockfile | [carvel.dev/vendir](https://carvel.dev/vendir/) · [GitHub](https://github.com/carvel-dev/vendir) |
| Renovate (Mend) | Update detection + automated PRs (native vendir manager) | [docs.renovatebot.com](https://docs.renovatebot.com/) · [vendir manager](https://docs.renovatebot.com/modules/manager/vendir/) |
| skill-scanner (Cisco AI Defense) | SKILL.md security scan: YARA + patterns + adjudicating LLM + dataflow; SARIF/Action/pre-commit | [GitHub](https://github.com/cisco-ai-defense/skill-scanner) · [docs](https://cisco-ai-defense.github.io/docs/skill-scanner) · [critique](https://repello.ai/blog/cisco-skill-scanner-alternatives) |
| ai-skill-scanner | Alternative scanner: LLM + static rules + taint tracking, CI/PR integration | [GitHub](https://github.com/suchithnarayan/ai-skill-scanner) |
| vexscan | Scanner plugin for Claude Code (plugins/skills/MCPs/hooks) | [GitHub](https://github.com/edimuj/vexscan-claude-code) |
| Safe Skill Install | Deterministic wrapper around Cisco's scanner for install-time checks | [mcpmarket listing](https://mcpmarket.com/tools/skills/safe-skill-install) |
| cc-plugin-audit | Client-side: detects marketplace auto-updates on engineers' machines, surfaces security diffs | [GitHub](https://github.com/STRML/cc-plugin-audit) |
| claude-code-security-review (Anthropic) | AI PR review — trusted PRs only, not injection-hardened; not for vendored third-party code | [GitHub](https://github.com/anthropics/claude-code-security-review) |

### Commercial

| Vendor | Role | Lookup |
| --- | --- | --- |
| **Heeler** ("Agentic Development Security Platform") | The buy-side option closest to this whole doc: **Agent Skills Security** — "instructions, skills, subagents, hooks and MCP configs inventoried across every assistant and scored 0–100" — plus agent execution audit trails, MCP-embedded guardrails in Claude Code/Cursor/VS Code, and classic SCA/SAST/secrets with auto-remediation PRs. Continuous inventory+scoring across all machines, vs our pipeline's PR-time gate; overlaps Renovate (SCA PRs) and skill-scanner (skill scanning) in one platform. SOC 2 Type II; pricing not public | [heeler.com](https://www.heeler.com/) · [funding/background](https://www.securityweek.com/application-security-startup-heeler-raises-8-5-million-in-seed-funding/) |
| Snyk | ToxicSkills research; classic SCA; agent-security content | [ToxicSkills](https://snyk.io/articles/top-claude-skills-cybersecurity-hacking-vulnerability-scanning/) |

**Build/buy read**: the OSS pipeline (vendir + Renovate + skill-scanner) gates
*what enters the marketplace*; Heeler-class tooling additionally watches *what
is actually installed and executing* across every engineer's machine and
assistant — different control points. If the org adopts an ASPM platform with
agent-skills coverage, the PR-time gate stays (defense in depth), and the
client-side layer (cc-plugin-audit) becomes redundant.

### Sources

[claude-plugins-community](https://github.com/anthropics/claude-plugins-community) ·
[claude-code-security-review](https://github.com/anthropics/claude-code-security-review) ·
[GitHub Actions docs](https://code.claude.com/docs/en/github-actions.md) ·
[Scheduled tasks docs](https://code.claude.com/docs/en/scheduled-tasks.md) ·
[SDK plugins docs](https://code.claude.com/docs/en/agent-sdk/plugins.md) ·
[skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) ([independent critique](https://repello.ai/blog/cisco-skill-scanner-alternatives)) ·
[cc-plugin-audit](https://github.com/STRML/cc-plugin-audit) ·
[Renovate vendir/git-refs](https://docs.renovatebot.com/modules/datasource/git-refs/) ·
[Renovate+vendir walkthrough](https://www.jvt.me/posts/2026/02/27/renovate-update-file/) ·
[Snyk ToxicSkills](https://snyk.io/articles/top-claude-skills-cybersecurity-hacking-vulnerability-scanning/)
