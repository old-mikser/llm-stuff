# Working in this repo

This repo is a **mirror** of the live Claude Code hooks in `~/.claude/hooks/`.
The live copy is the one that actually runs; the repo copy is the published one.

## Every time you change a hook

Edit the live file in `~/.claude/hooks/` first, test it there, then:

1. `cp ~/.claude/hooks/<file> .claude/hooks/<file>` — the two must be byte-identical.
2. If the `hooks` block in `~/.claude/settings.json` changed, mirror it into
   `.claude/settings.example.json`.
3. Update the matching `README.md` section.
4. Commit and push to `main` directly — no PR.

**Before any push, verify the sync in both directions:**

```bash
diff -r ~/.claude/hooks .claude/hooks --exclude='*.log'
```

A push with the repo and `~/.claude/` out of step is a broken push — the README
would then describe a hook that isn't what's running.

## Testing a hook

Hooks read their JSON payload on stdin, so they can be driven directly:

```bash
echo '{"tool_input":{"file_path":"/tmp/t.rs","old_string":"a","new_string":"// note\na"}}' \
  | python3 ~/.claude/hooks/no-comment-metadata.sh; echo "exit=$?"
```

Exit 2 means deny (stderr goes back to Claude); exit 0 with
`permissionDecision: "ask"` JSON on stdout means the user is prompted.
