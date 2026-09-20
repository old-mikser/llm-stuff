#!/usr/bin/env bash
# Global git hook entry point, installed under every hook name in ~/.git-hooks/
# and pointed at by core.hooksPath. Setting core.hooksPath replaces a repo's own
# .git/hooks entirely — it does not add to it — so this dispatcher runs the global
# check and then chains to the repo's own hook of the same name if one exists.
# Without the chain, a repo-local secret scanner or post-commit would go quiet.
set -uo pipefail

name="$(basename "$0")"
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if [ "$name" = "pre-commit" ] && [ -x "$here/no-comment-metadata-precommit.sh" ]; then
    python3 "$here/no-comment-metadata-precommit.sh" || exit $?
fi

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
local_hook="$git_dir/hooks/$name"
if [ -x "$local_hook" ] && [ "$(readlink -f "$local_hook")" != "$(readlink -f "$0")" ]; then
    exec "$local_hook" "$@"
fi
exit 0
