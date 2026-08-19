# riff plugin

> **Investigation.** Whether a third-party writing plugin should sit in our
> toolchain. Reviewed August 18, 2026: installed, used once, removed. This
> record exists so the decision can be revisited without redoing the work.

```text
   is it safe?     yes     no hooks, no MCP, no agents, no scripts.
                           11 markdown files and nothing else
   was it useful?  once    named a corpus-level register split that
                           thirty separate wording notes had hidden
   do we keep it?  no      its style rule is scoped to the whole session,
                           not the writing task
```

## Findings

- No general-purpose markdown or prose-writing plugin exists in the official
  catalog. All 286 entries are vendor integrations or developer tooling.
- Neither catalog carries a rating, review, or install-count field. GitHub stars
  are the only proxy, and the whole writing-plugin space tops out at 34 stars.
  There is no highly rated option to find, so the question "which is best rated"
  has no answer.
- riff is safe. No hooks, no MCP servers, no agents, no scripts. Its entire
  content is 11 markdown files of prose.
- Its critique rubric earned its keep exactly once, by naming a corpus-level
  register split that would otherwise have read as thirty unrelated style nits.
- Its style constraint is scoped to the whole session rather than the writing
  task. That is why it was removed, and it is a scope problem rather than a
  security one.

## Why we went looking

The question was whether a generally available, well-rated plugin exists for
writing the documents in this repository: technical audits, decision records,
research notes. The failure mode in that genre is weak wording and a point that
does not land.

| Catalog | Plugins | Writing or prose tooling |
| --- | --- | --- |
| `anthropics/claude-plugins-official` | 286 | None |
| `anthropics/claude-plugins-community` | 2,281 | Several, all small |

The official catalog has none. Its closest entries are `mintlify` (MDX docs
sites), `notion` (writes to Notion rather than local files), and
`claude-md-management` (maintains `CLAUDE.md`).

Star counts for the community candidates: `c4m` 34 (diagram tooling), `riff` 29,
`docs-index-keeper` 4, `drift-detect` 4, `anti-ai-writing` 3, `sync-docs` 3, and
zero for `diataxis`, `deep-review`, `claude-ghost-writer`, `vibe-thesis`, and
`strategy-pack`. riff was the strongest option available, which is a statement
about the field rather than about riff.

## What riff is

Nine skills for writing personal essays, by Ben Roy, MIT licensed.

| Field | Value |
| --- | --- |
| Marketplace | `anthropics/claude-plugins-community`, local name `claude-community` |
| Source | `https://github.com/benjaroy/riff.git` |
| Pinned commit | `4193fe155fe4d9b2ba2092e3e2bec4b3e893e51c` |
| Version | `2.4.8`, matching tag `v2.4.8` |
| Skills | `sort`, `sequence`, `compose`, `critique`, `revise`, `copyedit`, `title`, `checkpoint`, `riff` |
| Shipped content | 11 markdown files, 715 lines, 72,759 bytes |

A shared `riff/base.md` defines rules every skill loads first. The skills chain:

```text
sort      distills raw notes
  └── sequence   proposes structures
        └── compose    drafts
              └── critique   assesses
                    └── revise     implements feedback
                          └── copyedit   polishes
```

## Security audit

Audited with the rubric in
[`plugins/bots/vendor-auditor`](../../plugins/bots/vendor-auditor/skills/audit/SKILL.md),
treating all plugin content as untrusted data to report on rather than as
instructions to follow.

`plugin.json` declares no `hooks`, no `mcpServers`, no agents, no scripts. The
three components the [plugin vetting](../objectives/plugin-vetting.md) says to
focus on are all absent. Nothing in this plugin can execute, so the audit
reduces to reading prose for model-steering content.

```text
VERDICT: NEEDS-REVIEW
FINDINGS:
- medium  riff/base.md:7  Style constraint is scoped to the whole session
          rather than the writing task: "These constraints apply to every word
          you produce in this session." All 9 skills restate it as a hard
          constraint.
- low     riff/base.md:11,88  Writes .riff/style-profile.md and
          checkpoints/*.md into the working directory, creating both if absent.
- low     riff/skills/riff/SKILL.md:26, riff/base.md:15  Instructs the model to
          withhold its own assessment from the user.
- low     riff/base.md:23  Solicits personal writing samples, including a link
          to fetch, and persists a derived profile across sessions.
SUMMARY: Nine prose-only skills for essay writing, with no executable surface
and no security findings. The verdict is NEEDS-REVIEW on scope grounds alone.
```

The medium finding is the operative one. riff installs at user scope, so once
any skill loads, its no-em-dash and no-semicolon rule then governs every later
output in the session: commit messages, code comments, technical
documentation. This is not malicious. It is a style preference for personal
essays applied to unrelated work.

The two disclosure findings withhold editorial reasoning, not actions. A writing
coach declining to label a draft's stage is the intent. No action is concealed.
We recorded them because they are the only pattern in the plugin that resembles
concealment, and a human should confirm that reading.

### Negative findings

| Category | Result |
| --- | --- |
| Exfiltration | None. No network calls, no environment variable reads |
| Obfuscated execution | None. No executable files, no base64, eval, or shell |
| Credential access | None. No matches for SSH keys, keychains, tokens, or cloud credentials |
| Prompt injection against the user | None. Nothing steers the model to exfiltrate, conceal actions, or disable safety |

Two further checks, per the threat model in
[update automation](update-automation.md):

- Bidi, zero-width, and invisible characters: zero. The only non-ASCII character
  in the plugin is a rightwards arrow, six times.
- Supply chain: the checked-out commit matches the marketplace pin exactly, the
  working tree is clean, and the tag agrees with the manifest version. The 14
  executable files a naive scan reports are `.git/hooks/*.sample`, byte
  identical to the local git templates. Git does not run `.sample` files.

## What we used it for

A writing pass over the nine prose documents in this repository, opened as
[PR #1](https://github.com/Hermanlangner/market-place-setup/pull/1). Wording and
structure only. No claim, link, command, version number, table column, or code
sample changed.

We applied riff's rubric rather than riff's genre. The `critique`, `copyedit`,
and `revise` skills are written for personal essays, including a 600-word
critique cap and simulated social media reactions. That packaging does not
transfer to technical documentation. The underlying checks do: severity-ranked
critique, structural fluff detection, register-break analysis.

The pass found one corpus-level problem:

```text
7 of 9 documents   already edited to a consistent Google-style voice,
                   near-zero em dashes

docs/automation.md 41 em dashes, 28 semicolons
docs/telemetry.md  later sections read as research notes in a different voice
                       └── a register split, one finding, one cause
```

`docs/telemetry_analysis.md`, which names the
[Google developer documentation style guide](https://developers.google.com/style)
as its authority, needed three fixes.

## Experience report

### What it earned

Naming the register split. Nine documents produced roughly thirty individual
wording problems, and the register frame turned those into one finding with one
cause. That reframing is what a rubric buys over a linter.

Two specific catches were worth the run. `docs/agent-anatomy.md` opened with a
sentence that did not parse, because terms cannot describe views. And
`docs/automation.md` buried the five-lesson conclusion of its prior-art section
in an inline run-on, where no reader would look for a conclusion.

### What it did not earn

Most of what the rubric surfaced was punctuation, which a linter catches more
cheaply and more consistently. The essay-genre packaging is dead weight on
technical documents. And the session-wide constraint means the tool changes
output in work it was never invoked for.

### Where we overrode it

The rule set is absolute and should not be applied that way. The pass kept
semicolons inside table cells, where they compress facts into a narrow column
rather than set prose rhythm. It kept numeric en dashes, which are correct
typography rather than a machine tell. It kept the standalone dashes marking
empty table cells, because removing them breaks the tables.

We also declined to run `anti-ai-writing`, a related candidate, because its
banned list includes "framework" and "ecosystem", which
`docs/telemetry_analysis.md` uses correctly as technical terms.

### Honest verdict

For a corpus already edited to this standard, riff is worth running once per
document, not once per commit. The value is in the first read of a document
nobody has critiqued yet. There is no recurring value, which is the argument
against keeping it installed.

Its one clear lesson is portable without the plugin: register consistency across
a document set is a real defect class, and nothing in the current tooling checks
for it.

## Removal

Removed August 18, 2026, on scope grounds rather than security grounds. The
session-wide style constraint is not worth carrying at user scope for a tool
with no recurring value.

The plugin wrote nothing into this repository. The skills we used do not require
a style profile, so no `.riff/` or `checkpoints/` directory was created.

The `claude-community` marketplace stays registered. It is Anthropic's screened
catalog and is useful independently of this evaluation.

## Reinstating it

```bash
claude plugin install riff@claude-community
```

Two conditions if it comes back:

- Add `.riff/` and `checkpoints/` to `.gitignore`. The `compose` and
  `checkpoint` skills write both into the working directory.
- Enable it for a writing session rather than at user scope, so the style
  constraint cannot reach unrelated work.

The community marketplace entry carries no `version` field, so the plugin
reports its commit SHA as its version. SHA pinning is stronger than version
pinning and matches the `vetted-external` pattern in
[plugin vetting](../objectives/plugin-vetting.md), but `plugin update`
then has no semantic version to resolve against.
