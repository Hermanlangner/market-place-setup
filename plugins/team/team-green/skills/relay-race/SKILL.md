---
description: Run the relay race. Use when the user says "relay race" or "run the relay".
---

# Relay race

Spawn the race-director agent with the Agent tool and show its final report.

If the director reports it cannot spawn agents itself, spawn runner-one and
runner-two in parallel yourself, then apply the director's combination rules
and present the same report shape:

```
🏁 relay result
runner-one: <a>s
runner-two: <b>s
total: <a+b>s, fastest leg: <winner>
🏓 pong from team-green v1.0.0
```
