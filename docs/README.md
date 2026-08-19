# docs/

Every document from this repository, recut so that one folder is one kind and
one file is one topic.

```text
docs/
├── objectives/       what we are trying to achieve, and the decisions made
├── investigations/   what was tested, what it showed, what is still unknown
└── resources/        reference material the other two point at
```

Each file opens with a banner naming its kind and what it covers.

## objectives/

| Topic | What it decides |
| --- | --- |
| [marketplace-structure](objectives/marketplace-structure.md) | One catalog, folder-based groups, dependencies, bundles, independent versions, and the commands that prove all of it |
| [org-distribution](objectives/org-distribution.md) | Getting plugins onto machines through claude.ai admin, install policies per group, and how that route differs from MDM |
| [plugin-vetting](objectives/plugin-vetting.md) | SHA pinning, vendoring, the Renovate and scanner pipeline, and locking machines to this marketplace |
| [bot-runtimes](objectives/bot-runtimes.md) | Shipping automated agent behavior through the same catalog as human tooling |
| [skill-portability](objectives/skill-portability.md) | Reaching OpenCode and Codex with one generated skill tree |
| [adoption-measurement](objectives/adoption-measurement.md) | The posture, the funnel definitions, the rollout, and what telemetry will never prove |

## investigations/

| Topic | What it found |
| --- | --- |
| [org-sync-unknowns](investigations/org-sync-unknowns.md) | Two undocumented admin-sync behaviors, with the pilot that settles them |
| [skill-name-redaction](investigations/skill-name-redaction.md) | Custom skill names survive on plugin events and beta spans, and are redacted on cost metrics |
| [cross-harness-telemetry](investigations/cross-harness-telemetry.md) | What Claude Code, Codex, and OpenCode each expose, at three evidence levels |
| [update-automation](investigations/update-automation.md) | Why Renovate beats Dependabot here, and the five rules five large projects converged on |
| [riff-plugin](investigations/riff-plugin.md) | A writing plugin audited, used once, and removed on scope grounds |

## resources/

| Topic | What it holds |
| --- | --- |
| [agent-anatomy](resources/agent-anatomy.md) | Harness, agent, skill, sub agent, orchestration, meta-harness, in three figures |
| [repository-layout](resources/repository-layout.md) | Every concept mapped to a path, the three scopes, and how to choose |
| [telemetry-configuration](resources/telemetry-configuration.md) | Postures A, B, C, the env and collector blocks, and the privacy controls |
| [telemetry-pipeline](resources/telemetry-pipeline.md) | Schemas, alias manifest, and label rules for one adoption model across three clients |
| [security-tooling](resources/security-tooling.md) | Every tool considered, what each costs, and the cheapest path that works |

## How they connect

```text
objectives/marketplace-structure
├── objectives/org-distribution ──── investigations/org-sync-unknowns
├── objectives/plugin-vetting
│   ├── investigations/update-automation
│   ├── investigations/riff-plugin        (the vetting rubric, used for real)
│   └── resources/security-tooling
├── objectives/bot-runtimes
├── objectives/skill-portability
└── objectives/adoption-measurement
    ├── investigations/skill-name-redaction
    ├── investigations/cross-harness-telemetry
    │     └── resources/telemetry-pipeline
    └── resources/telemetry-configuration

resources/agent-anatomy ──▶ resources/repository-layout
      vocabulary for everything above
```

## Conventions

Everything here follows the same three rules, so a new file has a shape to copy.

- **One visual language.** Plain text diagrams only, under 80 columns. No
  mermaid: it renders differently in every viewer, and its edges are the first
  thing to disappear in a dark theme.
- **A spine, not a pile.** Each file names its one mechanism up front, then every
  later section says which part of it they attach to.
- **State the cost.** A component or a decision gets a "what it costs you" line.
  A finding gets what it does not prove.
