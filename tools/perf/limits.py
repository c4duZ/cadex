"""The weight budget of `make perf` (tools/perf/run.py): each limit with what
was measured beside it. A limit only goes up with the reason written.
"""

LIMITS = {
    # 43 MB universal (2026-10-20); 50.3 MB after plan 21 (the review tab, image diffs, conflicts,
    # comments, line authorship: 2026-11-15), raised from 50 then. 85 since plan 22 (the owner,
    # 2026-11-15): the memory engine cadex-memory, Rust, ~24 MB universal (10.4 arm64 + 13.2 x86_64,
    # docs/adr/0028-project-memory.md); room for plans 23 and 24.
    "app_mb": 85,
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
    "subagent_closed_mb": 5,      # +1 to +3 MB once its tab is closed again, read 16-22 s after the close
                                  # (read 4-7 s after, a loaded Mac caught the close's 1-2 s peak: +44, 2026-11-16)
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
    # Plan 22 (tools/perf/plan22.py): cadex-memory from the release bundle. Measured 2026-11-16 on this Mac.
    "memory_engine_running": 0,   # the idle app with no agent session: no cadex-memory in the `ps`
    "memory_idle_mb": 25,         # 13 MB with a session open and no model (12 in the proof)
    "memory_idle_cpu": 1.0,       # 0.00 %: nothing by the clock while a session is open
    "memory_model_peak_mb": 400,  # 304-378 MB writing 500 pages and searching (366 in the proof)
    "memory_model_after_mb": 25,  # 13 MB: unloaded after --embed-idle-secs and re-executed (68 without it)
    "memory_tool_hook_ms": 2.0,   # 0.66-0.81 ms a PostToolUse over the socket, with 2 000 pages (0.15 in the proof's leaner router)
    "memory_briefing_ms": 8.0,    # 2.5-3.7 ms with 2 000 pages; 1.3 ms with none (0.9 in the proof, 54 pages)
    "memory_whole_hook_ms": 10.0,  # 4.0-4.9 ms the whole `cadex memory-hook PostToolUse`, process start included
    "memory_whole_start_ms": 30.0, # 6-18 ms the whole SessionStart with its briefing
    # Plan 23 (tools/perf/plan23.py): a fake daemon with 20 machines. Measured 2026-11-16.
    "machines_first_open_mb": 15,        # +9-14 MB once: the first card content's text system and the dots'
                                         # layers (the SSH card's hosts pay it on a first hover too; the test
                                         # app never hovers); a second opening adds 0 (2026-11-16)
    "machines_open_over_idle_pct": 3,    # the plan's limit, each opening after the first: 0 % measured
    "machines_after_cpu": 1.0,           # the idle CPU once the group closes
    "machines_requests_after_close": 0,  # closed: nothing read, the watch stream ended
    "machines_off_requests": 0,          # machines.tailscale off: not one request to Tailscale
    # Plan 24 (tools/perf/plan24.py): races, runs and automations. Measured 2026-11-16 on this Mac.
    "orch_off_over_idle_mb": 5,   # off: -1 MB (88 against 89), the app as it was
    "orch_off_files": 0,          # off: no state.sqlite and no LaunchAgent written
    "orch_off_launchd_jobs": 0,   # off: no job of Cadex in launchd
    "orch_on_mb": 220,            # 141-160 MB: a race of 3 and a run of 5, 9 terminal tabs, the board and the page open
    "orch_on_cpu": 5.0,           # 1.45-2.86 %: 6 fake agents sending a heartbeat every 20 s, hooks, the watch's 15 s
    "orch_agents_missing": 0,     # every fake agent started (the 3 contenders and the 5 dispatches)
    "orch_run_missing": 0,        # the chain of 2 done, the 3 long ones dispatched
    "orch_network": 0,            # not one network connection of the app (lsof -i)
    "orch_keychain": 0,           # no Keychain file open (fs_usage needs root; lsof)
    # Plan 27 (tools/perf/plan27.py): the work's tree with 8 projects of 6 tasks each.
    "tree_over_idle_pct": 10,     # the plan's limit before the first measure
}
