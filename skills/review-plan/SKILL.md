---
name: review-plan
description: Review an implementation plan before work starts: re-check its facts at their pins, test the design against the code and the deployed config, find what the touch list misses. Use when the user asks to review a plan or a plan file.
---

Read-only until the user rules. The plan's author is not in the room: every fact, line reference and number is a **claim**.

## Steps

1. **Pin the baseline.** Find the plan in the open and the archive plan dirs. Record HEAD and the plan's baseline commit; diff the files it cites between them. Done: you can name the commit each finding holds at.
2. **Load the rulings.** Read the ADRs the plan touches, the repo's recorded operator decisions, the live-gate register, and any open plan that overlaps this one. A finding that re-argues a ruling is not a finding.
3. **Re-derive the facts** at their **pins** (commit, block, time window): the cited line, the chain at the stated block, the DB with its coverage. If the pin is unreachable, for example a pruned node, move to an archive; if none exists, mark the fact "unverified at pin". When a fact describes surprising behaviour, check whether it is a bug before the design builds on it.
4. **Test the design at its seams**: each type, channel, store, send path and config the plan plugs into. Read the deployed config, not only the options the code offers. Done: every seam has a `file:line` that shows it fits, or a finding.
5. **Walk the touch list.** Grep each symbol the plan changes for callers, tests, docs, served pages and env examples. List every miss.
6. **Check the tasks**: each has a done criterion, a valid order, and gates only for questions an agent can close on data we have. Quote value; never gate a task on it.
7. **Report**, then stop for rulings.

## Report

- Line 1: ready or not ready, the blocker count, the baseline commit.
- **What checks out:** the facts and seams you confirmed, one line each.
- **Blockers**, then **Plan-text fixes**, numbered across both. Each finding:
  - **What breaks:** one sentence a non-coder can follow: what goes wrong, when, and what it costs.
  - **Fix.**
  - **Why:** the evidence (`file:line`, block, or query).
- **Touch list misses.**
- **Rulings needed:** only the choices that are the user's.

Define each code term in plain words the first time the report uses it. End with the numbered list, so the user can reply "1 fix, 2 skip, 3 explain".

## After the rulings

Rewrite the plan in place: apply each ruling, re-check the line references at HEAD, move the baseline, and add a revision-log row. Stage the plan by its path only.
