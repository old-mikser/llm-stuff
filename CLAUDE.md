# Working in this repo

This repo is the **source of truth** for the Claude Code hooks in `.claude/hooks/`.
Edit them here. Committed state is deployed state — never hand-edit `~/.claude/`
to make a change, and never copy files between the two by hand.

## Every time you change a hook

1. Edit the file under `.claude/hooks/` and test it (see below).
2. If the `hooks` block your settings need has changed, update
   `.claude/settings.example.json` to match.
3. Update the matching `README.md` section.
4. Commit and push to `main` directly — no PR.

Because the committed state is what runs, a change is not finished until it is
committed: an uncommitted edit is not live, no matter how well it tests.

## Testing a hook

Hooks read their JSON payload on stdin, so they can be driven directly:

```bash
echo '{"tool_input":{"file_path":"/tmp/t.rs","old_string":"a","new_string":"// note\na"}}' \
  | python3 .claude/hooks/no-comment-metadata.sh; echo "exit=$?"
```

Exit 2 means deny (stderr goes back to Claude); exit 0 with
`permissionDecision: "ask"` JSON on stdout means the user is prompted.

Keep a hook's test cases in the repo rather than only in a chat transcript —
they are the only thing that catches a regression in the next change.
