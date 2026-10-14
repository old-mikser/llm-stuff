# grill-docs

Runs from `/grill-docs` or from any prompt that asks to grill "with docs". It loads [`grill`](../grill/README.md) and `domain-modeling`, so the
interview also writes the glossary and ADRs as decisions settle. A local fork of `grill-with-docs` from
[mattpocock/skills](https://github.com/mattpocock/skills), pointed at `grill`.

Install by linking it into your skills directory, from the repository root:

```bash
ln -s "$PWD/skills/grill-docs" ~/.agents/skills/grill-docs
ln -s ../../.agents/skills/grill-docs ~/.claude/skills/grill-docs
```
