# Security tooling

> **Supporting resource.** Every tool considered for the vendoring and scanning
> pipeline, what each costs, and the cheapest path that still works. The
> pipeline itself is in [plugin vetting](../objectives/plugin-vetting.md).

## Open source

| Tool | Role | Lookup |
| --- | --- | --- |
| vendir (Carvel, Broadcom) | Declarative vendoring with a lockfile | [carvel.dev/vendir](https://carvel.dev/vendir/) · [GitHub](https://github.com/carvel-dev/vendir) |
| Renovate (Mend) | Update detection and automated PRs, with a native vendir manager | [docs.renovatebot.com](https://docs.renovatebot.com/) · [vendir manager](https://docs.renovatebot.com/modules/manager/vendir/) |
| skill-scanner (Cisco AI Defense) | `SKILL.md` security scan: YARA, patterns, an adjudicating LLM, dataflow. Ships SARIF, an Action, and a pre-commit hook | [GitHub](https://github.com/cisco-ai-defense/skill-scanner) · [docs](https://cisco-ai-defense.github.io/docs/skill-scanner) · [critique](https://repello.ai/blog/cisco-skill-scanner-alternatives) |
| ai-skill-scanner | Alternative scanner: LLM, static rules, taint tracking, CI and PR integration | [GitHub](https://github.com/suchithnarayan/ai-skill-scanner) |
| vexscan | Scanner plugin for Claude Code covering plugins, skills, MCPs, and hooks | [GitHub](https://github.com/edimuj/vexscan-claude-code) |
| Safe Skill Install | Deterministic wrapper around Cisco's scanner for install-time checks | [mcpmarket listing](https://mcpmarket.com/tools/skills/safe-skill-install) |
| cc-plugin-audit | Client side: detects marketplace auto-updates on engineers' machines, surfaces security diffs | [GitHub](https://github.com/STRML/cc-plugin-audit) |
| claude-code-security-review (Anthropic) | AI PR review for *trusted* PRs only. Not injection-hardened, so not for vendored third-party code | [GitHub](https://github.com/anthropics/claude-code-security-review) |

## Commercial

| Vendor | Role | Lookup |
| --- | --- | --- |
| **Heeler** | The buy-side option closest to this whole design. Agent Skills Security inventories and scores instructions, skills, subagents, hooks, and MCP configs 0 to 100 across every assistant, plus agent execution audit trails, MCP-embedded guardrails in Claude Code, Cursor, and VS Code, and classic SCA, SAST, and secrets with auto-remediation PRs. Continuous inventory across all machines, against our pipeline's PR-time gate. Overlaps Renovate and skill-scanner in one platform. SOC 2 Type II, pricing not public | [heeler.com](https://www.heeler.com/) · [background](https://www.securityweek.com/application-security-startup-heeler-raises-8-5-million-in-seed-funding/) |
| Snyk | ToxicSkills research, classic SCA, agent-security content | [ToxicSkills](https://snyk.io/articles/top-claude-skills-cybersecurity-hacking-vulnerability-scanning/) |

## Cost

Monthly, assuming a private GitHub repo and a handful of vendored-plugin update
PRs.

| Component | License | Run cost |
| --- | --- | --- |
| vendir | $0, OSS binary | seconds of CI |
| Renovate, hosted through the [Mend GitHub App](https://github.com/apps/renovate) | $0; the free tier covers private repos | $0, runs on Mend's infrastructure |
| skill-scanner, static layers (YARA and patterns) | $0 | seconds of CI |
| skill-scanner, LLM analyzer | $0 | LLM tokens per update PR, single-digit dollars a month at our volume |
| Optional Claude second-opinion audit | n/a | measured in our lab at roughly $0.06 to $0.27 per small run. A PR-sized run is about $0.50 to $2, so a few dollars a month |
| GitHub Actions minutes | n/a | a few minutes a week, inside included minutes |
| Heeler | $0 incremental, already licensed | n/a |
| **The real cost** | n/a | **human review per update PR, 15 to 30 minutes each** |

The last row is the only one that matters:

```text
   vendir           │ $0
   Renovate         │ $0
   skill-scanner    │ $0 + a few $ of LLM tokens
   Heeler           │ $0 incremental, already licensed
   Actions minutes  │ inside the included allowance
   ─────────────────┼──────────────────────────────────────────────────
   human review     │███████████████████████  15-30 min per update PR
```

Every tool is close to free. The gate is a person reading a diff, and that cost
is irreducible. Any plan that claims to remove it has moved the risk instead.

## Lowest-cost path

Zero new vendors, zero new licenses, given Heeler is already in place.

```text
1. Heeler scans.        Its GitHub integration and Agent Skills inventory and
                        scoring replace self-run skill-scanner AND the
                        client-side layer (cc-plugin-audit). Already paid for.

2. Hosted Renovate      Free, operated by Mend, nothing to run or maintain.
   detects and PRs.     The only self-owned piece is the ~15-line vendir and
                        renovate config from the reference repo.

3. GitHub does          Actions for vendir sync verification, branch
   the rest.            protection for the human gate.

incremental spend = Actions minutes + optional Claude audit tokens
```

## Build or buy

The OSS pipeline (vendir, Renovate, skill-scanner) gates *what enters the
marketplace*. Heeler-class tooling also watches *what is installed and
executing* across every engineer's machine and assistant. Those are different
control points, not competing products.

```text
                  PR-time gate                  runtime inventory
                  ─────────────                 ─────────────────
what it sees      code entering the catalog     what is installed everywhere
when              before merge                  continuously
our tools         vendir + Renovate + scanner   Heeler
```

If the org adopts an ASPM platform with agent-skills coverage, keep the PR-time
gate as defense in depth. The client-side layer, cc-plugin-audit, becomes
redundant at that point.
