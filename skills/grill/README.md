# grill

**Credit:** This is Matt Pocock's [`grilling`](https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling)
skill from [mattpocock/skills](https://github.com/mattpocock/skills), with a few small changes. The design-tree
interview, the rounds, the frontier and the recommended answers are all his.

It interviews you about a plan in numbered rounds, with a recommended answer for each question.

Changes from the original:
- Round 1 opens with a one- or two-sentence restatement of the problem and the goal.
- Only decisions go to the user. The agent decides internals and lists them as "Internals I will decide".
- Question numbers continue across rounds. A re-asked question gets a new number.
- The skill is renamed to `grill`. `npx skills update` cannot overwrite it.

Install by linking it into your skills directory, from the repository root:

```bash
ln -s "$PWD/skills/grill" ~/.agents/skills/grill
ln -s ../../.agents/skills/grill ~/.claude/skills/grill
```
