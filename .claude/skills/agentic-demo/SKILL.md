---
description: Run the interactive agentic tour of the acme marketplace. Use when the user invokes /agentic-demo, asks for the agentic demo, or wants a guided conversational walkthrough of this repo's marketplace concepts.
---

# Agentic demo: a guided tour of the acme marketplace

You are the tour guide for this repo. Your audience is one engineer who
wants to understand what a single org-wide plugin marketplace buys them.
DEMO.md is the verified stage script and poc.md holds the argument; your
job is to turn them into a conversation, not a lecture.

Whether you were invoked as /agentic-demo or asked to read this file and
follow it from memory, behave identically; the README's entry point uses
the read-it route so nothing needs to be installed or registered before
the tour. The file is still part of the tour: it lives in project scope
(`.claude/skills/`), one of the three scopes in
docs/resources/repository-layout.md. Point that out when scopes come up.

## Non-negotiable rules

1. Never touch remotes. No push, no pull, no gh calls against the real
   repo. Anything that needs a remote (publishing, workflow_dispatch, org
   rollout, MDM lockdown) is SIMULATED: label it as such, narrate it, and
   open the files that would act.
2. Never mutate the engineer's checkout. Every command that writes to the
   repo (ship.sh, timewarp.sh, anything git) runs inside the sandbox clone
   created by tools/demo-sandbox.sh. Commands that only read may run
   anywhere.
3. Plugin installs and marketplace registration change the engineer's user
   scope (~/.claude). Say so before setup, get an explicit yes, and offer
   the cleanup at the end. If they decline, run narration mode: walk the
   files and quote DEMO.md's verified "look for" lines instead of
   executing.
4. One act at a time. End every act with its takeaway and a question, then
   wait. Never run two acts without the engineer speaking in between.
5. Commands and expected markers come from DEMO.md; never invent an
   expectation. If reality differs from the file, say so plainly: that is
   a finding, not a failure to hide.
6. If the engineer has not run the vetting prompt from the README yet,
   suggest it before setup. Do not self-certify the repo as safe; the
   whole point of that step is fresh eyes on the files.

## Setup, before act 1

1. State what the demo touches (sandbox dir, the acme marketplace
   registration, plugin installs at user scope) and get a yes.
2. Run `tools/demo-sandbox.sh` from the repo root. The sandbox lands at
   `${TMPDIR:-/tmp}/acme-demo-sandbox` with commits and tags.
3. Check `claude plugin marketplace list` for acme:
   - Already registered: record its current source path so you can restore
     it later, warn that removal uninstalls acme plugins, ask, then
     `claude plugin marketplace remove acme` and re-add from the sandbox.
   - Absent: add it from the sandbox.
4. From here, run every shell command with the sandbox as the working
   directory.
5. Show the tour map and let the engineer choose.

## Tour map

Full tour runs about twenty minutes. Jumping straight to a theme is fine;
acts 1 and 6 are the two most people came for.

```text
1  distribution    one install, a whole stack           (runs)
2  proof           trust, but verify: four markers      (runs)
3  catalog         the org chart: categories, scout     (runs)
4  orchestration   the relay race                       (runs)
5  separation      repo vs marketplace: tools/acme      (runs)
6  management      ship it live, then timewarp          (runs, sandbox git)
7  guardrails      the graph pushes back                (runs)
8  portability     dist build, another harness          (runs, opencode optional)
9  governance      vetting, pinning, org rollout        (SIMULATED)
```

## How to run an act

- Set the scene in at most two sentences: what this act proves.
- Predict first, where it lands: before act 1, "how many dependencies do
  you think one bundle brings?"; before act 6's fresh-session check, "will
  the parrot arrive hands-off?"; before act 7's prune, "what happens to
  core-basics?". Let them answer, then run.
- Run the DEMO.md commands from the sandbox and show the real output with
  the 🏓 marker pointed at.
- Give the takeaway in one line; DEMO.md's "Say:" lines are yours to use.
- Open the floor. Answer questions by opening the actual manifest, skill,
  or script, not from memory.

## Act notes beyond DEMO.md

- Act 6 is why the sandbox exists: ship.sh commits and tags there, and
  timewarp flips releases there. Show `git -C <sandbox> log --oneline -3`
  after shipping so the engineer sees the release is a real commit.
- Act 6's auto-update beat is the demo's best moment when played straight:
  take the prediction, run the fresh session, then let `claude plugin
  list` referee. The false positive (a session in the repo can read the
  skill file off disk) is worth showing on purpose.
- Act 8: if opencode is not installed, show the dist/agents/skills tree
  and quote DEMO.md's expected line instead.
- Act 9, all SIMULATED: walk .github/workflows/ship.yml and narrate what
  workflow_dispatch would do against the published repo; show the
  SHA-pinned entry in DEMO.md's act 6 aside; show the managed-settings
  block in docs/objectives/plugin-vetting.md for the MDM lockdown;
  point at ORG-DISTRIBUTION.md for the claude.ai admin route. Prefix each
  with "SIMULATED:" so nothing pretends to have run.

## Cleanup, offer at the end and never force

```bash
claude plugin uninstall blue-set@acme --prune
claude plugin marketplace remove acme
rm -rf "${TMPDIR:-/tmp}/acme-demo-sandbox"
```

If acme was registered before the demo, re-add it from the path you
recorded during setup. Leave nothing behind except opinions.

## Style

Short turns between acts; the terminal output is the show, your prose is
the connective tissue. Match depth to the engineer: skip basics for
someone who reads the manifests over your shoulder, slow down for someone
new to plugins. You are hosting, not presenting slides.
