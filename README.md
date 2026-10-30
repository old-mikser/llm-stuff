# llm-stuff

Personal Claude Code configuration I reuse across machines: hooks, skills and
a mod. Each has its own README with install steps.

| Kind | Where | What |
|------|-------|------|
| Hooks | [`.claude/hooks/`](.claude/hooks/README.md) | Six shell hooks: completion and attention chimes, comment-policy enforcement and its commit-time layer, and a `--no-verify` guard. |
| Skill | [`skills/orchestrate/`](skills/orchestrate/README.md) | `/orchestrate <plan paths>`: runs a plan's tasks through subagents, verifies once, reviews, closes the plan. |
| Skill | [`skills/grill/`](skills/grill/README.md) | Interviews you in numbered rounds about a plan; Matt Pocock's `grilling`, slightly updated. |
| Skill | [`skills/grill-docs/`](skills/grill-docs/README.md) | "Grill with docs" or `/grill-docs`: `grill` plus `domain-modeling`, Matt Pocock's `grill-with-docs`, slightly updated. |
| Skill | [`skills/verify-review/`](skills/verify-review/README.md) | Paste a review and ask to verify it: re-derives each claim at the review's own pin, grades fact and fix apart, reports in plain English. |
| Mod | [`mods/ctx-footer/`](mods/ctx-footer/README.md) | Model, effort and context size in the prompt footer, tinted when the prompt cache is cold. |
