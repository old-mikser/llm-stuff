# verify-review

A model-invoked skill. Paste a review, audit, or report and ask to verify it. The agent re-derives each
claim from the code, the chain, or the DB at the review's own pin (commit, block, time window), grades
the fact and the fix apart, and looks for issues the review missed. It then reports in plain English
and asks which findings to fix.

It stops before any fix. Hand the picked findings to `orchestrate` or to subagents.

It overlaps `receiving-code-review`. If both are installed, both can load on the same paste.

Install by linking it into your skills directory, from the repository root:

```bash
ln -s "$PWD/skills/verify-review" ~/.agents/skills/verify-review
ln -s ../../.agents/skills/verify-review ~/.claude/skills/verify-review
```
