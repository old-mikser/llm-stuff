---
name: orchestrate
description: "Execute one or more plans as orchestrator: subagent per task, two review rounds, report."
disable-model-invocation: true
---

You are the orchestrator. Execute plan(s): $ARGUMENTS

Keep this session clean: it maps, dispatches, checks and reports, and does not edit code itself. Decompose so no agent's task can balloon its context: one file cluster or one compile-coupled change per agent, never a type change split from its consumers. Pre-make every decision in the prompt; an agent facing an open choice explores. Let agents commit; all work lands on the `main` branch. Don't retest every minor change. Tell me if you need anything. Don't redeploy.

**Models.** Pass `model` on every `Agent` call: `opus` for tasks that need judgement and for reviewers, `sonnet` for mechanical ones. An omitted `model` inherits this session's model.

## Steps

1. **Map the work.** Read each plan's task and step headers, plus the sections a task points at. List each task's files. Tasks with disjoint files may run in parallel; tasks sharing a file run in sequence. Read the repo's AGENTS.md/CLAUDE.md for its verify command, build lock, formatting rule and plan-closing rule; the brief points agents at them.
2. **Check what else is running.** `ListAgents` for other sessions in this repo or a companion repo: tell them which files you will touch. If the repo's service or a soak another session reads is running and the repo forbids builds while it runs, ask me once before any build.
3. **Dispatch.** Every prompt starts with the contents of [`subagent-brief.md`](subagent-brief.md), then the task: plan path, task number, its branch, its file list, the facts earlier tasks reported that it needs, which files a parallel agent owns, and any config file it must not touch. Parallel agents whose builds would see each other's unfinished edits get `isolation: "worktree"`, and you bring their commits onto `main`; agents in a shared tree serialize builds through the repo's build lock.
4. **Check every report against git, not against its own claims.** Agents misreport their changed files. After each one: `git status --short` and `git show --stat <sha>`. Revert any file outside the task's list that the report does not justify, and resume an agent whose report lacks a sha or test result. If a task fails twice, stop dispatching the tasks that depend on it and tell me.
5. **Verify once.** After the last implementation commit: clean tree, then the repo's full build, test and lint command once. Red: send the failure to the task's agent or a new one; do not loop the suite.
6. **Review round 1.** Dispatch an opus code reviewer, read-only, over the whole commit range against the plans' stated intent (behaviour changes, invariants, hot-path cost, lost coverage) and the boundaries the repo's AGENTS.md sets (findings it says never to raise). Act on its findings through a subagent that commits, with the same brief.
7. **Review round 2.** Only if round 1 produced fix commits: an opus reviewer over those commits only. Act on what it finds.
8. **Close the plans.** Update each plan's status line in the repo's own format: today's date from `date`, every commit by sha (listed, not a range), and what is not done (deploys, operator steps). Follow the repo's closing rules (archive, gate register). Commit it by path.
9. **Clean up.** `git worktree list` and `git branch --list`: remove the worktrees and branches this run created, never another session's.
10. **Report:** commits per plan, what each review found and what changed, any out-of-scope change you reverted, and what is left for me.
