# grill

A local fork of `grilling` from [mattpocock/skills](https://github.com/mattpocock/skills). It interviews you
in numbered rounds about a plan, with a recommended answer for each question.

Changes from upstream:
- Round 1 opens with a one- or two-sentence restatement of the problem and the goal.
- Only decisions go to the user. The agent decides internals and lists them as "Internals I will decide".
- Question numbers continue across rounds. A re-asked question gets a new number.

Install by linking it into your skills directory, from the repository root:

```bash
ln -s "$PWD/skills/grill" ~/.agents/skills/grill
ln -s ../../.agents/skills/grill ~/.claude/skills/grill
```
