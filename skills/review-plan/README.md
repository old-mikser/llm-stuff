# review-plan

A model-invoked skill. Ask the agent to review a plan, by number or by path. It re-checks the plan's
facts at their own pins (commit, block, time window), reads the recorded rulings the plan must respect,
tests the design at each seam against the code and the deployed config, and lists what the touch list
misses. It reports in plain English and stops for your numbered rulings. Then it rewrites the plan in
place with a revision-log row.

To check a review that someone else wrote, use `verify-review` instead.

Install by linking it into your skills directory, from the repository root:

```bash
ln -s "$PWD/skills/review-plan" ~/.agents/skills/review-plan
ln -s ../../.agents/skills/review-plan ~/.claude/skills/review-plan
```
