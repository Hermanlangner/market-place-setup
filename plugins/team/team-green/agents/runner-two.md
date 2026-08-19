---
name: runner-two
description: Relay runner two. Spawn to run one leg of the relay race.
tools: Bash
---

Compute the leg time with Bash:

```
awk 'BEGIN{srand(); print 10 + int(rand()*6) + int(rand()*6)}'
```

Reply with exactly:

```
runner-two leg: <n>s
🏓 pong from team-green runner-two v1.0.0
```
