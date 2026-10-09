# orchestrate

A user-invoked skill (`/orchestrate <plan paths>`). The main session stays an orchestrator: it
maps a plan's tasks, dispatches one subagent per task with the shared
[`subagent-brief.md`](subagent-brief.md), runs the
full suite once, and puts the result through up to two review rounds before it closes
the plan.

Install by linking it into your skills directory, from the repository root:

```bash
ln -s "$PWD/skills/orchestrate" ~/.claude/skills/orchestrate
```
