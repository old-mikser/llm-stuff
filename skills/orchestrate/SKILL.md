---
name: orchestrate
description: "Execute one or more plans as orchestrator: subagent per task, two review rounds, report."
disable-model-invocation: true
---

You are the orchestrator. Execute plan(s): $ARGUMENTS

If no plan is named above, ask which one and stop.

Keep the main session clean: it maps, dispatches, checks and reports, and does not edit code itself. Run each task as a separate subagent (for some tasks, separate subagents even for subtasks): `opus` for tasks that need judgement and for reviewers, `sonnet` for mechanical ones, passed as `model` on every `Agent` call. Don't let them interfere with each other when running in parallel, and don't let them balloon context: one file cluster or one compile-coupled change per agent, never a type change split from its consumers. Let agents commit. Don't retest every minor change. Tell me if you need anything. Do all the work in `main`, in this one tree: no branches, no worktrees. Don't redeploy.

## Steps

1. **Map the work.** An unmet prerequisite blocks the plan: ask the busy sessions which one is landing it and wait for it, or tell me if none is. Then read each plan's task and step headers, plus the sections a task points at. List each task's files. Tasks with disjoint files may run in parallel; tasks sharing a file run in sequence. Read the repo's AGENTS.md/CLAUDE.md once for its verify command and its rules on building, formatting and closing plans. Check `ListAgents` for other sessions working in this repo or a companion repo and message them which files you will touch.
2. **Dispatch.** One subagent per task (or subtask). Every prompt starts with the contents of [`subagent-brief.md`](subagent-brief.md), then the task: plan path, task number, its file list, the facts earlier tasks reported that it needs, and which files a parallel agent owns. Pre-make every decision in the prompt; an agent facing an open choice explores.
3. **Check each report against git, not against its own claims:** `git status --short` and `git show --stat <sha>`. Revert any file outside the task's list that the report does not justify; resume an agent whose report lacks a sha or test result. If a task fails twice, stop dispatching the tasks that depend on it and tell me.
4. **Verify once.** After the last implementation commit: clean tree, then the repo's full build, test and lint command once. Red: send the failure to one agent; do not loop the suite.
5. **Review round 1.** Dispatch an opus code reviewer, read-only, over the whole commit range against the plans' stated intent (behaviour changes, invariants, hot-path cost, lost coverage), within any review boundaries the repo's AGENTS.md sets. Act on its findings through a subagent that commits, with the same brief.
6. **Review round 2.** Only if round 1 produced fix commits: an opus reviewer over those commits only. Act on what it finds.
7. **Close the plans.** Update each plan's status line in the repo's own format: today's date from `date`, every commit by sha (listed, not a range), and what is not done (deploys, operator steps). Follow the repo's closing rules. Commit it by path.
8. **Report:** commits per plan, what each review found and what changed, any out-of-scope change you reverted, and what is left for me.
