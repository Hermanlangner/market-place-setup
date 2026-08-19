# Agent anatomy

> **Supporting resource.** Every term (harness, agent, skill, tool, hook, sub
> agent, orchestration, meta-harness) located on one diagram, with what each one
> costs you. Disk layout for each term: [repository layout](repository-layout.md).

There is only one mechanism here: a loop. Everything else in the vocabulary is a
thing that attaches to that loop at a particular point. So this document draws
the loop once, numbers its five steps, and then every later section names which
step it plugs into. Nothing stands on its own.

## One loop

```text
                    you type a prompt
                            │
                            ▼
      ┌───────────────────────────────────────────┐
      │  1. CONTEXT WINDOW                        │ ◀── 2. a SKILL.md is
      │     system prompt + CLAUDE.md             │     pasted in from disk,
      │     the conversation so far               │     on demand
      │     every tool result so far              │
      └───────────────────────────────────────────┘
                            │
                            │  the model reads all of this, every pass
                            ▼
                ┌───────────────────────┐
                │  3. MODEL             │
                └───────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            │                               │
      an intent to act              nothing left to do
            │                               │
            ▼                               ▼
  ┌───────────────────┐              reply to you, done
  │  4. PERMISSION    │──── refused ──────────────┐
  └───────────────────┘                           │
            │ allowed                             │
            ▼                                     │
  ┌───────────────────┐                           │
  │  5. TOOL RUNS     │                           │
  └───────────────────┘                           │
            │                                     │
            └──────────────────┬──────────────────┘
                               ▼
              appended to the context, which is now bigger,
              then the loop runs again
```

That is an agent. Not a file, not a folder, not anything you can point at on
disk. The loop, running.

| Step | Part | What it is | Where it lives |
| --- | --- | --- | --- |
| | **Harness** | The whole diagram. It owns the loop, assembles the context, enforces permissions, runs tools | The `claude` binary, or your own build on the Agent SDK |
| 1 | Context window | Everything the model can see this pass | Memory, for the life of the session |
| 2 | Skill | Instructions pasted into the context when relevant | `<plugin>/skills/<name>/SKILL.md` |
| 3 | Model | Picks the next step. Nothing else | Anthropic's API |
| 4 | Permission | Decides whether the intent is allowed | Harness config, hooks, or you, live |
| 5 | Tool | Built-ins, your scripts and CLIs, MCP servers | Built-ins ship with the harness, scripts in `<plugin>/scripts/` |

Two facts about the shape, before anything attaches to it.

**The model reads the whole context on every pass.** Not the last message. All of
it. A session that has read thirty files resends those thirty files on every
later turn. Prompt caching makes that cheap rather than free, and does nothing
about the ceiling.

**The model never acts.** It emits an intent and the harness decides. That gap at
step 4 is where permissions, hooks, and every guardrail live. The model does not
touch your disk.

## What the loop shape costs you

The context only grows. No step in the diagram removes anything from it. Sort
every component by what it does to the context and most design questions answer
themselves.

```text
   spends context                        buys context back
   ──────────────                        ─────────────────
   a skill, for as long as it            a sub agent: reads a lot in its
     stays loaded                          own context, returns a little
                                           to yours
   a tool result, once, and
     permanently                         a script that filters before it
                                           returns (grep, don't cat)
   an MCP server's tool list,
     whether you call it or not
```

The asymmetry is the whole lesson. A tool result you did not need stays in the
context for the rest of the session. You cannot un-read a file. That is why
"just let it read the whole directory" degrades a session that was working fine
ten minutes earlier, and why the fix is usually a narrower tool rather than a
smarter prompt.

## Skills and tools: the two ways in

A skill enters at step 2. A tool is called at step 5. That one difference
explains most of the confusion around both.

```text
   step 2   skill   text, pasted into the      tells the model HOW to do
                    context                    something
                    no runtime, no exit code   costs context while loaded

   step 5   tool    code, run by the harness   lets the model DO something
                                               costs a round trip and one
                                               permission decision
```

Skills never execute. That is the single most useful fact in this document. A
skill has no runtime, no exit code, and no way to fail loudly. So when one "did
not work", there are exactly two possibilities, and they need different fixes:

```text
   it never loaded      →  the description did not match. that field is the
                           trigger, not documentation

   it loaded and lost   →  the model read it and did something else anyway
```

Find out which before you change anything. People rewrite skill bodies for hours
over what was a matching problem.

## Hooks: around the outside, not inside

Hooks are the piece missing from most people's mental model, and the diagram
shows why. They are not in it. A tool fires because the model asked. A hook fires
because an event happened, whether the model wanted it or not.

```text
   SessionStart      ──▶   before the loop starts at all
                                    │
   UserPromptSubmit  ──▶   1. context assembled
                                    │
                           3. model
                                    │
   PreToolUse        ──▶   4. permission       ◀── a hook can refuse here
                                    │
                           5. tool runs
                                    │
   PostToolUse       ──▶   result appended to the context
                                    │
   Stop              ──▶   after the reply
```

This repo's `team-blue` ships the simplest possible case, and there is a lesson
inside it:

```text
   new session
   └── SessionStart fires
         └── runs ${CLAUDE_PLUGIN_ROOT}/scripts/ping.sh
               └── output lands in the context, not in your transcript
```

The hook ran and you cannot see it, because its output went where the model
reads rather than where you do. That catches people out mid-demo, which is why
[DEMO.md](../../DEMO.md) asks Claude to quote it back.

Being deterministic gives hooks two properties. They are the right home for
anything that must not be optional, such as telemetry or a policy check. And
`PreToolUse` can refuse at step 4.

Permission modes can also stop a tool call. But those are harness configuration
and your own live decisions. A hook is the only thing a *plugin* can ship that
blocks a tool call by itself.

That is the same reason hooks run arbitrary commands on the machine at session
start, and why [plugin vetting](../objectives/plugin-vetting.md) points reviews
at hooks, MCP servers, and scripts rather than at skills.

## Sub agents: a second copy of the loop

A sub agent is not a component inside the diagram. It is the whole diagram
again, with an empty context.

```text
   your session      steps 1-5 running, context filling up
        │
        │ step 5: the Agent tool
        ▼
   sub agent         steps 1-5 running again, its own fresh context
        │              reads 40 files, burns ~90k tokens in ITS context
        │
        └── returns 12 lines ────▶ appended to YOUR context
```

Ninety thousand tokens of reading, twelve lines of cost to you. The intermediate
work stays outside your context permanently. That is the entire reason to spawn
one, and it is a good enough reason on its own.

### What a sub agent actually costs

This is the component I see reached for most often when something else was
wanted, so it is worth being blunt.

**A fresh context knows nothing.** It has not read your conversation, does not
know which file you are in, and has no idea what you already ruled out.
Everything it needs goes in the task prompt. A one-line prompt to a sub agent
usually produces a confident answer to a slightly different question.

**It cannot ask you anything.** It runs to completion and reports. Given an
ambiguous brief, it picks an interpretation and commits.

**You pay tokens twice.** Once for its work, once for the report you read. It
saves your context, not your bill.

**A verbose report defeats the point.** A sub agent that returns its transcript
has moved the cost, not removed it. Say what shape to return.

So delegate when the work is read-heavy and the conclusion is small. Keep it in
your own context when the work is conversational, when you will change your mind
halfway, or when the answer is one file away.

## Orchestration and meta-harnesses: outside one loop

Both sit outside a single run of the diagram, at different distances from it.

```text
   steps 1-5                      one loop, running        = an AGENT
   │
   ├── spawns more copies         which ones, in what order,
   │   inside one session         how results combine      = ORCHESTRATION
   │
   └── Claude Code                owns the loop            = the HARNESS
         └── Tidewave, agent      owns whole runs of it    = a META-HARNESS
             boards, session
             managers
```

**Orchestration** is a pattern, not a component. No directory, no file type. An
agent coordinating three others is an ordinary `agents/*.md`, which is exactly
what `team-green`'s race director is: one markdown file that spawns two runners.
The only structural fact worth knowing is that whichever agent coordinates holds
the plan in its own context. Delegating the work does not delegate the
bookkeeping.

**Meta-harnesses** do not implement the loop. They spawn a harness through
Claude Code headless mode or the Agent SDK, then add browser UI, parallel
sessions per worktree, and review queues. Their unit of work is a whole session,
not a tool call. Tidewave sits at both distances, since it drives Claude Code and
also serves MCP tools into those sessions.

Keep Claude Code as the inner harness and plugins, skills, hooks, and telemetry
all keep working. The `app.entrypoint` telemetry attribute separates `cli`,
`sdk`, and IDE entry points, so meta-harness use is measurable rather than
invisible. Swap the inner harness for Codex or OpenCode and only the portable
`.agents/skills` layer follows. See
[skill portability](../objectives/skill-portability.md).

## Choosing between them

| You want to | Reach for | Attaches at | It costs you |
| --- | --- | --- | --- |
| Teach the model a procedure for this session | a skill | step 2 | context, while it stays loaded |
| Let the model take an action | a tool or script | step 5 | a round trip and one permission decision |
| Read a lot, report a little | a sub agent | a second loop | a full re-brief, and it cannot ask you questions |
| Make something happen whatever the model decides | a hook | around the outside | it fires when unwanted too, and can block the session |
| Coordinate several delegates | orchestration | many loops | the coordinator holds the plan in its own context |
| Give any of the above to another team | a plugin in the marketplace | all of it | a version bump and a review |

## How each one fails

Recognizing the failure is faster than reasoning about the design.

| Symptom | Cause | Fix |
| --- | --- | --- |
| A skill burns context in sessions that never needed it | its description matches everything | narrow the description, it is the trigger |
| A skill "did not work" | it never loaded, or it loaded and lost | find out which before editing the body |
| A sub agent is confidently wrong | its prompt assumed context it never had | put the brief in the prompt, including what to ignore |
| A sub agent saves nothing | it returned a transcript, not a conclusion | specify the return shape |
| Every session starts slowly | a `SessionStart` hook doing real work | hooks sit on the critical path, keep them fast |
| The model keeps picking the wrong tool | an MCP server exposes dozens it does not need | every exposed tool sits in the context whether called or not |

## Where this repository fits

```text
   marketplace   decides who gets which folder
   └── plugin    a folder with a manifest, shipping some mix of
       │           skills (step 2), scripts (step 5), hooks,
       │           MCP config, and sub agent definitions
       └── Claude Code loads them into a session
             └── the session is one loop
                   └── which can spawn more
```

Nothing a plugin ships is a new kind of thing. Every part of it is one of the
five steps, or a hook around the outside. The marketplace adds distribution and
a review gate, and changes none of the mechanics above.
