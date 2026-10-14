# grill-docs

**Credit:** This is Matt Pocock's [`grill-with-docs`](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs)
skill from [mattpocock/skills](https://github.com/mattpocock/skills), with a few small changes.

It loads [`grill`](../grill/README.md) and `domain-modeling`, so the interview also writes the glossary and
ADRs as decisions settle.

Changes from the original:
- It loads `grill` (the updated copy) instead of `grilling`.
- It runs from any prompt that asks to grill "with docs", as well as from `/grill-docs`. The original runs from
  the slash command only.

Install by linking it into your skills directory, from the repository root:

```bash
ln -s "$PWD/skills/grill-docs" ~/.agents/skills/grill-docs
ln -s ../../.agents/skills/grill-docs ~/.claude/skills/grill-docs
```
