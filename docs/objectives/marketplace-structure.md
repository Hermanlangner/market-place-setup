# Marketplace structure

> **Objective.** Serve every team from a single catalog that a user adds once.
> Behavior verified on Claude Code v2.1.233.

## The constraint that shapes everything

Claude Code reads a Git-hosted catalog from exactly one path,
`.claude-plugin/marketplace.json` at the repository root. One repo cannot host
two marketplaces. Every grouping idea has to work inside that single file.

Groups are therefore folders plus metadata, not separate catalogs:

```text
market-place-setup/
├── .claude-plugin/marketplace.json   one catalog, every entry
└── plugins/
    ├── shared/     shared-kit        building blocks other plugins depend on
    ├── core/       core-basics       everyone gets this
    ├── team/       team-blue, team-green
    ├── agents/     scout             one sub agent, alone in its plugin
    ├── vendored/   party-parrot      reviewed third party, copied in
    └── bundles/    core-set, blue-set, green-set
```

Folders carry ownership. Point CODEOWNERS at `plugins/team/team-blue/` and that
team owns its plugin without touching anyone else's. Catalog entries carry
`category` and `tags`, which is what `/plugin` filters on when a user browses.

## Dependencies do the installing

Each plugin names what it needs in the `dependencies` array of its own
`plugin.json`. Names resolve inside this marketplace.

```text
shared-kit
└── core-basics
    ├── team-blue    (^1.0)
    └── team-green   (^1.0)

core-set  → core-basics    (shared-kit follows)
blue-set  → team-blue      (core-basics and shared-kit follow)
green-set → team-green     (core-basics and shared-kit follow)
```

Installing `blue-set` pulls two more plugins with no further commands. That is
the point of the whole layout: one install, and the user has the set their team
agreed on.

## Bundles are the managed unit

A bundle plugin is a manifest and nothing else: `name`, `version`,
`description`, `dependencies`. Adding a plugin to a team's set is a one-line PR
and a version bump.

```diff
 {
   "name": "blue-set",
-  "version": "1.0.0",
+  "version": "1.1.0",
   "dependencies": [
-    "team-blue"
+    "team-blue",
+    "party-parrot"
   ]
 }
```

```text
   author   one line in blue-set/plugin.json, plus a version bump
      │     git tag blue-set--v1.1.0
      ▼
   user     claude plugin marketplace update acme    catalog refreshed
            claude plugin update blue-set@acme       bundle now 1.1.0
                                                     ✗ "failed to load"
            claude plugin install party-parrot@acme   ✓ resolved
```

That middle state is real, not theoretical. The bundle sits broken between the
second and third command.

Delivering that change takes two commands, not one. Verified on v2.1.233,
`plugin update` moves the bundle version but leaves a newly added dependency
uninstalled, and the bundle reports "failed to load" until it arrives:

```bash
claude plugin update blue-set@acme       # bundle goes to 1.1.0
claude plugin install party-parrot@acme  # the new member needs this explicitly
```

No hands-off auto-update fires. Plan the rollout announcement around that,
because a version bump alone leaves users with a broken bundle.

Treat the bundle as the thing people install and stop them toggling members
individually. If a team can switch off half its own set, the set stops meaning
anything.

## Versions stay independent inside one repo

Constraints resolve against Git tags named `{plugin}--v{version}`, such as
`core-basics--v1.0.0`. Every plugin gets its own version line without needing
its own repository.

When no tag matches, Claude Code installs the working copy and checks the
constraint at load time. That slack is deliberate. You can iterate untagged and
still get a real dependency error when you break one.

## Guardrails that come for free

Claude Code refuses to disable a plugin another enabled plugin needs, and it
prints the chained command that would work instead. `uninstall --prune` and
`plugin prune` clear dependencies nothing needs any more.

## Verify it end to end

From the repository root:

```bash
claude plugin validate .              # passes; author warnings are fine
claude plugin marketplace add ./      # "." is rejected, "./" works
claude plugin install blue-set@acme   # + 3 deps: team-blue, core-basics, shared-kit
```

Every non-bundle plugin ends its output with `🏓 pong from <name> v<version>`.
That marker is the test. If you see it, that exact version loaded.

`team-blue` v1.0.0 carries one of every component type, so it doubles as the
coverage check:

| Say this | Expect |
| --- | --- |
| `standup` | a banner and four lines ending `🏓 pong from team-blue v1.0.0` |
| `use the blue-reporter agent` | the Agent tool spawns it and returns `🏓 pong from team-blue sub agent v1.0.0` |
| start a *new* session | the SessionStart hook runs `scripts/ping.sh` and its `🏓 pong from team-blue script` line appears |
| `hello acme` | proves the transitive dependency `core-basics` loaded, not just installed |

`claude plugin details team-blue@acme` should report 1 skill, 1 agent, and 1
SessionStart hook.

> [!WARNING]
> Hooks run arbitrary commands on the user's machine. That is why
> [plugin vetting](plugin-vetting.md) exists.

Then push on the guardrails:

```bash
claude plugin disable core-basics@acme          # refused: team-blue still needs it
claude plugin install green-set@acme            # reuses the installed core-basics
claude plugin uninstall green-set@acme --prune  # drops team-green, keeps core-basics
```

Tag resolution needs a real commit:

```bash
git tag core-basics--v1.0.0
claude plugin install team-blue@acme   # resolves core-basics via ^1.0 against tags
# change team-blue's constraint to ^2.0 and reinstall → no-matching-tag error
```

`tools/ship.sh` runs the central-management case. It adds `party-parrot` to
`blue-set`, bumps the bundle to 1.1.0, commits, and tags. Then:

```bash
claude plugin marketplace update acme
claude plugin update blue-set@acme       # bumps the bundle to 1.1.0
claude plugin install party-parrot@acme  # the new member, explicitly
```

The third command is the one people forget. `tools/timewarp.sh <version>` moves
between released bundle versions afterwards. Clean up with
`claude plugin marketplace remove acme`, which also uninstalls its plugins.

## Version floors and known quirks

- v2.1.143+ for dependency auto-enable and disable.
- v2.1.196+ for local-folder tag resolution.
- `metadata.pluginRoot` is documented, but `validate` rejects it. Use explicit
  `./plugins/...` source paths.
- `claude plugin marketplace add .` is rejected. `add ./` works.

## Before this reaches the org

- Push to GitHub. Teammates run `claude plugin marketplace add <owner>/<repo>`.
  Private repos work through normal Git credentials.
- Tag releases with `claude plugin tag --push` so constraints resolve.
- Set CODEOWNERS per `plugins/<group>/`. The platform team owns the catalog and
  `shared/`.
- For mandatory sets, either list the bundle in `enabledPlugins` in managed
  settings, or take the [org distribution](org-distribution.md)
  for per-group install policy.
