# Your task in Cadex

A Cadex task is a git worktree with its own branch and agent, made by the owner with New Task. Cadex
shows each task's status and a short comment in its Tasks page and in the Agents page.

- When you start working: `cadex worktree status doing` and `cadex worktree comment "<what>"`.
- When you change what you are doing, update the comment (a few words, present tense).
- When the work is ready for the owner to look at: `cadex worktree status review`, then
  `cadex notify "<one sentence on what is ready>"`.
- Never set `done` yourself unless the owner asked: done is the owner's call after review.
- `cadex diff` opens the task's whole diff beside your terminal, for the owner or for you.
