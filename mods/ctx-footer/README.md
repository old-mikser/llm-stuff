# ctx-footer

A Claude Code mod (a hooks-module plugin) that puts the current model, the
effort level and the context token count at the right end of the prompt
footer, after the mode labels:

```
12m · ⏵⏵ auto mode on                                   Opus 5.5 high · 52.8k
```

## What it shows

- **Context count.** Refreshes after every main-thread step, on each
  `session.measure`, and once a minute. Before the first response of a window
  (a fresh session, `/clear`, a compaction) it shows `/context`'s local
  estimate with a `~` prefix.
- **Cold cache.** The count turns light blue when the main thread has had no
  response within the 1h prompt-cache TTL. The last response time is kept per
  session in the mod's store. A session with no stored time takes it from its
  transcript's last assistant row, which fails above 4 MiB and reads as cold.
- **Effort.** Taken from each turn step. Until the first one in a resumed or
  cleared session, it shows the last level seen, else `effortLevel` from
  settings.
- **Resume and `/clear`.** The footer fills in on its own shortly after,
  without sending a prompt.
- **Hint line.** Starts with the time since the session's first prompt, `new`
  until one is sent; a session whose turns predate the mod counts from its
  launch. Drops the `(shift+tab to cycle)` tip and the `← N agents` pill. The
  rewritten hint is plain text, so its pills stop being clickable.

## Install

From the repository root, link it into your mods directory and name it in the
`env` block of `~/.claude/settings.json`:

```bash
mkdir -p ~/.claude/mods
ln -s "$PWD/mods/ctx-footer" ~/.claude/mods/ctx-footer
```

```json
{ "env": { "CLAUDE_CODE_PLUGIN_DIRS": "/home/<you>/.claude/mods/ctx-footer" } }
```

It loads in the next session you start or resume.

## Editing it

- Run `claude plugin validate mods/ctx-footer` after every edit. A module that
  does not load leaves the previous version running, and the footer gives no
  sign of that.
- Type-check with `npx -p typescript tsc -p mods/ctx-footer`. The editor types
  under `.claude-plugin/types/` are written by Claude Code once it has loaded
  the mod.
- A helper that takes `$` must be a top-level function, not a closure inside
  `register`.

## Why `SessionMode`

The text goes in the `SessionMode` slot on purpose: the `PromptHint` tail does
not count the agent pills, so long text there gets cut to `…`. To tint only the
count, the mod draws that slot's tree itself, the mode labels joined by ` & `
as the engine joins them.
