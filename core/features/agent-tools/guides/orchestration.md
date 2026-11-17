# Your task in a Cadex run

This session was opened by Cadex for one task of a run (an orchestration): `CADEX_DISPATCH_ID` is
set in your environment. Or you coordinate a run: then the owner asked you, in your first prompt,
to plan it. Cadex learns about your work only from what you report with `cadex run`; it never
reads your conversation. Each command answers on stdout; a refusal comes on stderr with exit 1.

## A task's agent
- When the task is done (the spec is met, the work committed if it changes files):
  `cadex run orchestration.report-done summary="<two or three sentences on what you did>"`.
  Report once; the tasks that wait for yours start after it. Leaving without it fails the task.
- While you work on something long, every few minutes:
  `cadex run orchestration.report-heartbeat note="<what you are doing>"`. With no sign of life for
  a while (the owner sets how long), the run page shows you as "stalled?" and the owner is told.
- A question you cannot settle from the spec or the code:
  `cadex run orchestration.ask question="<one question>"`. It goes to the run's coordinator, or
  to the owner. Then read the answer with `cadex run orchestration.inbox` (check again later if it
  is empty; keep working on what you can meanwhile).
- A note to another task's agent of the same run (its dispatch id is in the run's messages or in
  what the coordinator told you):
  `cadex run orchestration.send-message to=<dispatch id> text="<the note>"`.
- `cadex run orchestration.inbox` also lists the notes other agents sent you.
- A sub-task that should run in its own worktree and agent: write its spec to a file, then
  `cadex run orchestration.spawn title="<short title>" spec-file=<file>`. Optional:
  `after=<task id>,<task id>` (it waits for those) and `gate=yes` (the owner approves before it
  starts). It is dispatched on its own when ready. Sub-tasks have a depth limit and the run has a
  cap on agents and spending: a refusal says why; do the work yourself then.

## The run's coordinator
- Split the goal into tasks with `orchestration.spawn` (as above; `after=` orders them, the ids
  come back in each answer). Each is dispatched to its own agent when ready.
- `cadex run orchestration.inbox` lists the questions of the tasks' agents and what each one
  reported when it finished. Answer a question with
  `cadex run orchestration.send-message to=<dispatch id> answers=<question id> text="<answer>"`.
- A task that failed can be tried again: `cadex run orchestration.retry task=<task id>`.
- You never approve gates or stop agents: those are the owner's.

Everything you report is text kept by Cadex and shown to the owner; it is never run.
