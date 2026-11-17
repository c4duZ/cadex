---
name: cadex-orchestration
description: Use when this session has CADEX_DISPATCH_ID set (a task of a Cadex run) or coordinates a Cadex run, to report the task done, send signs of life, ask a question, message another task's agent or spawn a sub-task.
---

Cadex knows how your task goes only from what you report. Read the guide first:

```
cadex skills get orchestration
```

In short: `cadex run orchestration.report-done summary="<what you did>"` when the task is done,
`cadex run orchestration.report-heartbeat note="<doing what>"` every few minutes on long work,
`cadex run orchestration.ask question="<...>"` then `cadex run orchestration.inbox` for the answer.
