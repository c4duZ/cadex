"""The weight budget of `make perf` (tools/perf/run.py): each limit with what
was measured beside it. A limit only goes up with the reason written.
"""

LIMITS = {
    # 43 MB universal (2026-10-20); 50.3 MB after plan 21 (the review tab, image diffs, conflicts,
    # comments, line authorship: 2026-11-15), raised from 50 then, room for plans 22 to 24.
    "app_mb": 55,
    "idle_mb": 100,               # ~78 MB with one terminal in a project
    "idle_cpu": 2.0,              # ~0 %
    "flood_peak_mb": 200,         # ~147 MB while `yes` floods
    "flood_after_mb": 130,        # ~100 MB once it stops (10 000 history lines kept)
    "tui_peak_mb": 200,           # ~147 MB redrawing the whole screen
    "home_idle_mb": 110,          # 79 MB with the home folder as the workspace
    "home_idle_cpu": 3.0,         # ~0 %: the indexes wait for a query
    "files_home_s": 15,           # 3.1 s for 100 000 files near the focus
    "files_home_mb": 60,          # +22 MB
    "notes_home_s": 30,           # 7.7 s
    "notes_home_mb": 60,          # +22 MB
    "files_repo_s": 2,            # 0.2 s for this repository
    "agent_cpu": 10.0,            # 2-4 % while a file is saved every 0.1 s
    "theme_switch_mb": 6,         # 0 MB over 300 switches after 150 to warm up (90 -> 90, 2026-10-20)
    "reading_flood_peak_mb": 200, # flood with minimum contrast 7 and ligatures on
    "terminal_tab_mb": 6,         # 0-1 MB each hidden tab (its canvas goes); 22 with the canvas kept, 43 before the shared atlas (2026-10-21)
    "all_on_over_idle_pct": 10,   # plan 17: everything on, at most 10% over idle_mb
    "all_on_cpu": 2.0,            # the same as idle_cpu
    "subagent_first_mb": 20,      # +6 to +9 MB: a 34 MB log's first opening, the text system included (2026-10-21)
    "subagent_open_mb": 8,        # 0 to +2 MB each opening after (TextKit 1 had kept +20 and jumped 70)
    "subagent_closed_mb": 5,      # +1 to +3 MB once its tab is closed again
    "history_open_over_idle_pct": 10,   # plan 18: 3 accounts (one managed), 200 transcripts, History open
    "history_open_cpu": 2.0,            # the same as idle_cpu once the first reading is done
    "history_closed_over_idle_pct": 10, # History closed: nothing indexed or watched
    "history_closed_cpu": 2.0,
    "history_open_index_wrong": 0,      # open, the index file is made: the page did show
    "history_closed_index_wrong": 0,    # closed, the index file is not even made
    # Plan 19 (tools/perf/plan19.py). Measured 2026-11-15 on this Mac, in swap.
    "daemon_off_running": 0,      # terminal.keepSessions off: no daemon at all
    "kept_tab_mb": 6,             # the same as terminal_tab_mb: a tab kept by the daemon weighs no more
    "daemon_window_mb": 6,        # 1.6 MB with ten idle shells and the app attached
    "daemon_window_cpu": 1.0,     # ~0 %: nothing moves, nothing wakes it
    "daemon_alone_mb": 6,         # 1.4 MB with the app killed
    "daemon_alone_cpu": 1.0,      # ~0 %
    "daemon_lost_shells": 0,      # killing the app ends none of the ten shells
    "daemon_stays_empty": 0,      # the ten closed, the daemon leaves the `ps` (ADR 0022)
    "hooks_cpu": 3.0,             # 1.2 % with 5 sessions hooking every second (idle 0.3 %)
    "hooks_mb": 5,                # 0 MB grown over 20 s of hooks
    "hooks_refused": 0,           # every hook with a session's token is answered
    # Plan 20 (tools/perf/plan20.py). Measured 2026-11-15 on this Mac.
    "tools_off_accepted": 0,      # agentTools off: a command request with a token is refused
    "tools_off_over_idle_mb": 5,  # off weighs what the idle app weighs (94 MB against 91-93 idle)
    "browser_agent_mb": 40,       # 26 MB: the preview tab the first goto opens, then 100 snapshots and clicks
                                  # (the app only; WebKit's page process is its own)
    "browser_agent_cpu": 10.0,    # 2.5 %, 201 requests one after another in 32 s
    "browser_agent_failed": 0,    # every goto, snapshot and click answered
    "browser_agent_after_cpu": 1.0,  # 0.6 %: the agent stopped, nothing left running
    # Plan 21 (tools/perf/plan21.py): 50 files, 5 000 changed lines. Measured 2026-11-15, the Mac in swap.
    "review_open_s": 3.0,         # 0.75 s from the command to the review read and laid out
    "review_mb": 30,              # 15 MB kept once it settles, 20 comments and 200 edits' marks in
    "review_peak_mb": 120,        # 82 MB while jumping 30 changes a second: freed, macOS takes it back
    "review_cpu": 40.0,           # 18.5 %, a full redraw at each of those jumps
    "review_after_cpu": 1.0,      # 0.0 % once it stops
    "review_edits_refused": 0,    # every one of the 200 edits answered
    "review_off_over_idle_mb": 5,  # authorship off: the idle app's weight
}
