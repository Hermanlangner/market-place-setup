# Plugin vetting

> **Objective.** Make the marketplace the single point where outside code gets
> reviewed, then lock machines to it.

A plugin can ship hooks, MCP servers, and scripts. Those execute on a
developer's machine at session start. Skills are only prompts, so they carry a
different risk: they steer the model rather than the shell. Snyk's ToxicSkills
research found prompt injection in
[36% of the skills they tested](https://snyk.io/articles/top-claude-skills-cybersecurity-hacking-vulnerability-scanning/),
so neither risk is theoretical.

That difference decides where a reviewer spends their time:

```text
   ships in a plugin        risk                          review effort
   ─────────────────        ────                          ─────────────
   hooks/hooks.json    ──▶  runs at session start,        read every line
   scripts/*.sh             on every machine, always
   MCP server config   ──▶  runs on the model's request   read every line

   skills/*/SKILL.md   ──▶  steers the model. cannot      skim for steering,
                            execute anything              not for exploits

   agents/*.md         ──▶  a prompt for a sub agent      same as a skill
```

Skills are the bulk of most plugins and the smallest part of the risk. Reviewing
them line by line while skimming `hooks.json` is the common mistake, and it is
exactly backwards.

The answer is to review once, re-list the reviewed commit here, and stop
machines from reaching anywhere else.

```text
upstream repo ──▶ pinned copy in this marketplace ──▶ engineer's machine
                        ▲                                     ▲
                  human review                    strictKnownMarketplaces
                  (the gate)                      (the fence)
```

## Pin the exact commit

Plugin sources support exact-commit pins, unlike marketplace sources:

```json
{
  "name": "some-public-tool",
  "source": {
    "source": "github",
    "repo": "someone/cool-plugin",
    "ref": "v3.2.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  },
  "category": "vetted-external"
}
```

`sha` beats `ref`, so an upstream tag that moves changes nothing here.
Re-vetting a release means a PR that updates both fields, and the PR history is
the audit trail.

Two ways to go further. Vendor the code under `plugins/vendored/` for a relative
path and full control. Or set `strict: false` to expose only approved components,
such as skills but not hooks. Cross-marketplace dependencies stay
blocked unless `allowCrossMarketplaceDependenciesOn` names the other
marketplace.

## Automate the update, keep the human gate

The three tools below already exist. Write glue, not a scanner.

| Job | Tool | Why this one |
| --- | --- | --- |
| Vendor and pin | [vendir](https://carvel.dev/vendir/) | Declarative `vendir.yml` with git URL, pinned ref, `includePaths` for a subdirectory, plus a lockfile |
| Detect updates and open the PR | [Renovate](https://docs.renovatebot.com/) | Native vendir manager: watches upstream tags, bumps the pin, runs `vendir sync`, opens a PR whose diff *is* the upstream change |
| Scan for malicious content | [skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) | Built for `SKILL.md`, our exact format. YAML, YARA, and Python rules, dependency intel, an adjudicating LLM analyzer, dataflow analysis. Ships SARIF, a reusable Action, and a pre-commit hook |
| Watch installed machines | [cc-plugin-audit](https://github.com/STRML/cc-plugin-audit) | Runs as a plugin on engineers' machines, hashes what is installed, flags marketplace auto-updates at session start |

The pipeline:

```text
Renovate (cron)
  └── new upstream tag
        └── bump vendir.yml + vendir sync
              └── open PR
                    ├── vendir sync --check
                    ├── claude plugin validate
                    ├── skill-scanner → SARIF → Code Scanning tab
                    └── human review  ◀── the gate
                          └── merge
                                └── marketplace entry serves the vendored copy
```

The merge is the vetted state. The PR body and diff are the record. Vendoring
also keeps [org distribution](org-distribution.md) working, because
relative paths need no external fetch at install time.

An optional Claude audit prompt on top is fine. Treat any LLM verdict on
untrusted content as advisory input to the human gate, never as the gate.

## What Anthropic supplies, and what it does not

- The [community marketplace](https://github.com/anthropics/claude-plugins-community)
  is screened by an internal pipeline: automated scan, human review, nightly
  catalog sync, SHA-pinned entries. None of it is reusable, but it confirms the
  shape: pin, scan, human gate.
- [claude-code-security-review](https://github.com/anthropics/claude-code-security-review)
  reviews PR diffs with Claude, and is explicitly *not* hardened against prompt
  injection. It is documented for trusted PRs. Vendored third-party code is
  untrusted by definition, so this is the wrong AI layer for this job.
- `claude plugin validate` checks structure and schema. It runs no security
  scan at all.

Build-versus-buy outcome: the hand-rolled `tools/vendor.py` and
`tools/scan-plugin.sh` in this repo are superseded by vendir, Renovate, and
skill-scanner. The `plugins/bots/vendor-auditor` skill survives as the codified
rubric a human reviewer applies on the PR. That rubric was exercised for real
in the [riff plugin](../investigations/riff-plugin.md).

The reasoning behind Renovate rather than Dependabot, and the prior art the
pipeline copies, live in [update automation](../investigations/update-automation.md). Costs
and alternatives live in the
[security tooling](../resources/security-tooling.md).

## Fence the machines with managed settings

IT deploys an MDM policy through Jamf, Intune, or Kandji to
`/Library/Application Support/ClaudeCode/managed-settings.json`:

```json
{
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "your-org/market-place-setup" }
  ],
  "extraKnownMarketplaces": {
    "acme": { "source": { "source": "github", "repo": "your-org/market-place-setup" } }
  },
  "disableSideloadFlags": true,
  "disableCommandPluginSources": true
}
```

- `strictKnownMarketplaces` is a hard allowlist checked on every add, install,
  and update. Marketplaces that already exist and do not match stop working
  too. An empty list, `[]`, is a total lockdown. Owner wildcards such as
  `"your-org/*"` need v2.1.223+.
- `extraKnownMarketplaces` registers `acme` for the user, so nobody runs `add`.
- Both `disable*` flags matter. The allowlist checks where a marketplace comes
  from, not what it contains, so sideloading and command-sourced plugin entries
  need blocking separately.
- The allowlist breaks local `./` marketplaces. Maintainers need a `pathPattern`
  entry such as `"^/Users/[^/]+/Projects/"`, or exclusion from the MDM group.

### Test the lockdown locally

> [!WARNING]
> This needs sudo and affects every session on the machine. Remove the policy
> when you are done.

```bash
sudo mkdir -p "/Library/Application Support/ClaudeCode"
sudo tee "/Library/Application Support/ClaudeCode/managed-settings.json" > /dev/null <<'JSON'
{ "strictKnownMarketplaces": [ { "source": "pathPattern", "pathPattern": "^/Users/" } ] }
JSON

claude plugin marketplace add ./                                 # allowed
claude plugin marketplace add anthropics/claude-plugins-official # refused

sudo rm "/Library/Application Support/ClaudeCode/managed-settings.json"
```

The same file carries the telemetry environment block. See
[telemetry configuration](../resources/telemetry-configuration.md).
