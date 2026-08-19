# Org sync unknowns

> **Investigation.** Two behaviors on the claude.ai admin distribution path are
> undocumented, and both would change the recommended install-policy mapping.
> Test them before rollout.

## Question 1: do bundles work under admin policy?

Client-side dependency behavior is documented and predictable:

```text
dependencies install at the same scope
dependencies enable transitively
dependencies resolve within the same marketplace
a dependency cannot be disabled while an enabled plugin needs it
```

The docs say nothing about admin-driven installs. Two things are unknown: does
the admin path reproduce that behavior, and which side wins when an install
policy contradicts the dependency graph.

### The pilot

Run this against one group.

```text
1. set blue-set             → Installed by default
   set its member plugins   → Available for install

2. claude plugin list
   expect: team-blue, core-basics, shared-kit installed and enabled

3. claude plugin disable core-basics@acme
   expect: refusal naming team-blue as the dependent

4. set team-blue → Not available, while blue-set still depends on it
   record: which side wins
```

### What each outcome means

| Result | Do this |
| --- | --- |
| Bundles behave as they do client-side | Keep the bundle-based mapping. Require `core-set`, apply each team policy to the bundle rather than its members. |
| They do not | Mark individual plugins **Installed by default** per group, and keep bundles for self-service users only. |

## Question 2: how does version resolution differ?

The two distribution routes resolve versions differently, and only one of them
is a Git operation.

| | Self-service | Organization-managed |
| --- | --- | --- |
| Distributed version | User machines resolve `{plugin}--v{version}` Git tags | The server packages the default branch at sync time |
| Release trigger | Push a tag | Merge a version-bump PR |
| `^1.0` constraints | Highest matching tag wins | Validated at load time; a mismatch disables the dependent with `dependency-version-unsatisfied` |

The failure this creates is specific and quiet. Merge a plugin version before
its dependents accept it, and the next sync ships a broken dependency. The
error surfaces in members' `/plugin` **Errors** tab, not during admin sync, so
nobody who caused it sees it.

```text
merge core-basics v2.0.0     (team-blue still says ^1.0)
  └── sync packages default branch
        └── member session loads plugins
              └── team-blue disabled: dependency-version-unsatisfied
                    └── visible only in that member's /plugin Errors tab
```

### The fix

Add a CI check on any PR touching `marketplace.json` or `plugin.json` that
verifies every dependent accepts the versions being merged. Keep tagging
releases as well, both for self-service resolution and for the vetting audit
trail.
