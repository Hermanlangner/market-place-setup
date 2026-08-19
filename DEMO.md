# Demo runbook

One marketplace serves a whole org: one install delivers a team's stack,
one bundle edit ships to everyone, and the guardrails catch the mistakes.
Eight acts, about ten minutes.

Two block types throughout: `bash` blocks paste into a shell, plain-text
blocks are typed into a Claude session. Never paste a prompt into a shell.

Prerequisites: claude v2.1.233 or newer, this repo cloned, every command
run from the repo root.

The cast, for narration:

```text
blue-set ───▶ team-blue ───▶ core-basics ───▶ shared-kit
green-set ──▶ team-green ──▶ core-basics         (the same one, reused)
core-set ───▶ core-basics
scout            no bundle: handpicked from /plugin
party-parrot     offstage until act 6
```

## Act 1: one install, a whole stack

The point: a developer types one command and receives their team's plugin,
the org core, and the shared scripts, resolved as dependencies.

```bash
claude plugin marketplace add ./
claude plugin install blue-set@acme
```

Look for: `+ 3 dependencies: team-blue, core-basics, shared-kit`.

Quirks: a bare `.` is rejected, `./` works. If acme is already registered,
run `claude plugin marketplace update acme` instead of `add`.

Say: "Nobody copied a file. The bundle asked, the catalog answered."

## Act 2: trust, but verify

The point: every component type answers with a versioned marker, so the
audience sees what loaded, not what we claim.

In a Claude session:

```text
standup
```

Look for: the STANDUP banner, then `yesterday: shipped pixels`,
`today: shipping more pixels`, `blockers: none`, and
`🏓 pong from team-blue v1.0.0`. The banner box comes from shared-kit's
script; blue only asked for it.

The SessionStart hook fires on every new session, but its output lands in
the session context, not the visible transcript. Start a new session and
ask:

```text
Quote verbatim any SessionStart hook output present in your context.
```

Look for: `🏓 pong from team-blue script v1.0.0 (plugin root: <root>)`.

Then the sub agent:

```text
use the blue-reporter agent
```

Look for: `all blue systems nominal` and
`🏓 pong from team-blue sub agent v1.0.0`.

Back in the shell, the manifest view:

```bash
claude plugin details team-blue@acme
```

Look for: 1 skill, 1 agent, 1 SessionStart hook.

Say: "Skill, hook, agent, script. One plugin, four proofs."

## Act 3: the catalog is the org chart

The point: categories and tags make one catalog browsable per team, and a
plugin can be as small as a single agent.

In a session, open the browser and filter by category and tags:

```text
/plugin
```

Then handpick the independent agent:

```bash
claude plugin install scout@acme
```

```text
ask the scout to report
```

Look for: one `- <name> v<version>` line per installed acme plugin,
`scout counted <n> acme plugins`, and `🏓 pong from scout v1.0.0`.

Say: "scout is a plugin that is one file. The floor is low on purpose."

## Act 4: orchestration is behavior, not a file type

The point: team green's director is an ordinary `agents/*.md` that fans
out to two runners; coordination needs no new machinery.

```bash
claude plugin install green-set@acme
```

Look for: `+ 1 dependency: team-green`. core-basics is already installed,
so nothing duplicates.

```text
run the relay
```

Look for: the `🏁 relay result` block ending in
`🏓 pong from team-green v1.0.0`. Leg times are rolled, so the totals
differ every run.

Say: "Two teams now share one core, zero copies. And the race is never
rigged the same way twice."

## Act 5: the repo is not the marketplace

The point: the repo carries its own tooling that the catalog never
distributes.

```bash
tools/acme catalog
```

Look for: the PLUGIN, VERSION, CATEGORY, TAGS, BUNDLE table. The CLI that
printed it is absent from it: repo file, not catalog entry.

Say: "Install everything in the catalog and this tool still never lands on
your machine."

## Act 6: ship it, live

The point: one bundle edit is the whole release process, and the demo
shows exactly which commands make it land, including the one that
surprised us.

```bash
tools/ship.sh
```

Look for: commit `ship: blue-set 1.1.0 adds party-parrot` and tag
`blue-set--v1.1.0`.

First, the honest beat: what does NOT happen. Open a fresh session, say
`celebrate`, then check:

```bash
claude plugin list
```

party-parrot is not installed. There is no hands-off auto-update, verified
on v2.1.233. Beware the false positive: run from the repo root, Claude can
read the skill file straight off disk and produce the parrot with no
plugin loaded, so `plugin list` is the referee, never the output.

The real sequence is three commands:

```bash
claude plugin marketplace update acme
claude plugin update blue-set@acme
claude plugin install party-parrot@acme
```

The last one matters: `plugin update` bumps blue-set to 1.1.0 but does not
install its newly added dependency, and blue-set reports "failed to load"
until party-parrot arrives.

New session:

```text
celebrate
```

Look for: the parrot block ending in `🏓 pong from party-parrot v1.0.0`.

Now toggle releases while talking:

```bash
tools/timewarp.sh 1.0.0
claude plugin list
tools/timewarp.sh 1.1.0
```

Look for: the blue-set version flipping 1.1.0 to 1.0.0 and back, plus
`new sessions load this version`.

Aside, for the governance beat: party-parrot is vendored here, under our
control. Pointed at the real upstream, its catalog entry would be
SHA-pinned:

```json
{
  "name": "party-parrot",
  "source": {
    "source": "github",
    "repo": "someone/party-parrot",
    "ref": "v1.0.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  },
  "category": "vendored"
}
```

The `sha` wins over `ref`, so a moved upstream tag changes nothing.

Say: "One line in a bundle, one script, and every blue machine gets the
parrot. Where the CLI has sharp edges, the demo shows them instead of
hiding them."

## Act 7: the guardrails push back

The point: the dependency graph protects itself; you cannot quietly break
a teammate.

```bash
claude plugin disable core-basics@acme
claude plugin uninstall green-set@acme --prune
```

Look for: the disable refused, naming team-blue and team-green as
dependents and printing the correct chained command. The uninstall drops
green-set and flags team-green as orphaned; confirm the prompt (in a
script, `claude plugin prune -y`). core-basics survives, because team-blue
still needs it.

Say: "The graph knows who needs what."

## Act 8: same skills, another harness

The point: skills are the portable layer, so the layout is not married to
one vendor.

```bash
mise run dist:build
opencode run "banner hello"
```

Look for: OpenCode loading `shared-kit-banner`. Expect the skill, not the
script marker: banner reaches its script through `${CLAUDE_PLUGIN_ROOT}`,
which only Claude Code resolves, and the dist build ships skill folders
without plugin scripts. docs/multi-harness.md draws this boundary.

Say: "The knowledge travels. The Claude-specific plumbing stays put, by
design."

## Cleanup

```bash
claude plugin uninstall blue-set@acme --prune
```

`claude plugin marketplace remove acme` drops everything, plugins
included. timewarp leaves the working tree at whichever release you last
warped to; `git status` shows it, reset when done.
