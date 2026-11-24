# Configuring Cadex through its files

Everything the owner can set in Cadex is a text file. You change Cadex by editing these files;
Cadex rereads them on its own. Edit only what the owner asked for, and tell them what you changed.

## The files

| File | What | Edit it? |
|---|---|---|
| `~/Library/Application Support/Cadex/settings.json` | every preference and the shortcuts | yes |
| `~/Library/Application Support/Cadex/orchestration/automations/<id>.json` | scheduled automations, one file each | yes |
| `~/Library/Application Support/Cadex/themes/<name>.json` | the owner's own themes | yes |
| `<repository>/.cadex/environment.toml` | a repository's throwaway environment for tasks | yes, in the repository |
| `projects.json`, `worktrees.json`, `history.sqlite`, `orchestration/state.sqlite`, `kit/`, `usage/`, `memory/`, `sessions/` | the app's own state and records | no: read only |

A test instance of Cadex may point elsewhere: `CADEX_SETTINGS_FILE` (settings), `CADEX_ORCHESTRATION_DIR`
(automations go in its `automations/`), `CADEX_THEMES_DIR` (themes).

## Rules for settings.json
- JSON: one object, a section per feature (`"terminal": { ... }`). Keep `"version"` as it is.
- Change only the keys you need; leave the rest. A key left out takes its default.
- Saved with Cadex open, it counts at once in every window (a few keys count when Cadex reopens:
  marked "reopen" below). No restart, no command.
- A wrong value (wrong type, not one of the choices) falls back to its default and the rest of the
  file still counts; numbers outside their range are moved to the nearest bound. Check your JSON
  parses (`python3 -m json.tool settings.json`) before you leave it.
- Write it whole and atomically when you can (write a temp file, then rename); Cadex also follows an
  edit in place.
- Paths may use `~`. Colors are `"#RRGGBB"`.

## settings.json keys
Type, default, allowed values or range, and what it does.

### general
- `general.shell` (text, `""`): the program terminals run; empty is the owner's login shell.
- `general.confirmClose` (bool, `true`): ask before closing a pane with a program running.
- `general.confirmMultilinePaste` (bool, `true`): ask before pasting several lines without bracketed paste.
- `general.openFiles` (`"beside"` | `"tab"`, `"beside"`): where files, diffs, history and previews open.
- `general.language` (`"en"` | `"pt"`, `"en"`): the interface's language. Reopen.

### terminal
- `terminal.fontFamily` (text, `"SF Mono"`): an installed monospaced font; unknown falls back to SF Mono.
- `terminal.fontSize` (number 8–32, `13`).
- `terminal.cursor` (`"bar"` | `"block"` | `"underline"`, `"bar"`).
- `terminal.cursorBlink` (bool, `false`).
- `terminal.historyLines` (number 100–100000, `10000`): scrollback; counts in new terminals.
- `terminal.optionAsMeta` (bool, `false`): left Option sends Meta.
- `terminal.copyOnSelect` (bool, `false`).
- `terminal.programNotifications` (bool, `true`): a program's notifications (OSC 9, OSC 777) as macOS ones.
- `terminal.keepSessions` (bool, `false`): terminals keep running after Cadex quits (the terminal daemon).
- `terminal.minimumContrast` (number 1–21, `1`): the contrast text keeps against its background; 1 is off.
- `terminal.lineHeight` (number 0.8–2, `1.6`): a multiple of the font's line.
- `terminal.letterSpacing` (number −1–4, `0`): points between letters.
- `terminal.fontFeatures` (list of text, `[]`): OpenType tags, `"calt"`, `"liga"`, `"ss01"`; `"-liga"` turns one off.

### appearance
- `appearance.theme` (text, `"cadex-night"`): the theme's id. Built-in ones by id (`"cadex-night"`,
  `"cadex-day"`, and the catalog's, listed in ⌘K › Choose Theme); the owner's as `"user:<file name
  without .json>"`.
- `appearance.darkTheme`, `appearance.lightTheme` (text, `""`): with `mode` `"system"`, the theme for
  each system mode; empty uses `theme`.
- `appearance.mode` (`"system"` | `"dark"` | `"light"`, `"system"`).
- `appearance.accent` (`"#RRGGBB"` or `""`, `""`): replaces the theme's accent; empty keeps it.
- `appearance.highContrast` (bool, `false`).
- `appearance.windowOpacity` (number 0.1–1, `1`): below 1 the window is glass over the desktop.
- `appearance.fullScreen` (`"auto"` | `"system"` | `"cadex"`, `"auto"`): which full screen the green
  button and ⌃⌘F give. The system's is a Space of its own over black (a translucent window shows
  black); Cadex's covers the screen over the desktop, the menu bar and the Dock at the edges.
  `"auto"`: Cadex's with `windowOpacity` below 1.
- `appearance.glass` (`"normal"` | `"strong"`, `"normal"`): `"strong"` blurs the wallpaper behind
  the whole window through a clean dark frost, makes the panes glass boxes and puts ⌘K, the menus and
  the cards in the same glass; it makes a solid window translucent.
- `appearance.paneBorder` (`"line"` | `"glow"`, `"line"`): `"glow"` draws the panes' border in the
  work color (the tab's or project's, else the accent) with a soft glow.
- `appearance.vibrancy` (bool, `false`).
- `appearance.backgroundImage` (path or `null`, `null`): an image behind the panes.
- `appearance.backgroundOpacity` (number 0–1, `0.5`), `appearance.backgroundBlur` (number 0–50, `0`).
- `appearance.uiZoom` (number 0.8–1.5, `1`). Reopen.
- `appearance.density` (`"normal"` | `"compact"`, `"normal"`). Reopen.
- `appearance.uiFont` (text, `""` the system font), `appearance.uiFontSize` (number 9–24, `13`). Reopen.

### tabs, explorer, markdown, preview
- `tabs.documentSide` (`"right"` | `"left"`, `"right"`): the side a file opened beside takes.
- `explorer.showHidden` (bool, `true`): dot files in the file tree.
- `explorer.followTerminal` (bool, `true`): the tree follows the focused terminal's folder.
- `markdown.openAs` (`"source"` | `"rendered"`, `"source"`).
- `preview.pickTarget` (`"terminal"` | `"clipboard"`, `"terminal"`): where a picked page element goes.
- `preview.pickScreenshot` (bool, `true`): a PNG of the picked element goes with it.

### power (keep the Mac awake)
- `power.mode` (`"always"` | `"running"`, `"always"`): while on, always, or only while a terminal runs a program.
- `power.onAtLaunch` (bool, `false`): turned on when Cadex opens.
- `power.keepDisplayOn` (bool, `false`).

### inspector (the right panel)
- `inspector.visible` (bool, `true`), `inspector.tab` (`"changes"` | `"files"` | `"history"` |
  `"memory"` | `"sessions"`, `"changes"`), `inspector.width` (number 240–640, `260`),
  `inspector.order` (list of those tab ids, `[]` the app's order).

### statusBar
- `statusBar.left`, `statusBar.right` (lists of item ids): the items on each side, in order; an item
  in neither is hidden; an unknown or repeated id is dropped. Ids: `project`, `folder`, `branch`,
  `agents`, `usage`, `memory`, `cadexMemory`, `ram`, `cpu`, `ports`, `ssh`, `tailscale`, `docker`,
  `terminals`, `drawer`, `keepAwake`, `update`, `environment`.

### agents (Claude Code and Codex accounts and sessions)
- `agents.sessions` (bool, `true`): read the agent sessions of every account on this Mac.
- `agents.accounts` (bool, `true`): read each account's plan usage.
- `agents.history` (bool, `true`): index every account's conversations for the history.
- `agents.attention` (bool, `true`): the bell, the feed and the board. `agents.dockBadge` (bool, `true`).
- `agents.notifyPermission`, `agents.notifyQuestion`, `agents.notifyFinished` (bool, `true`): a macOS
  notification when an agent stops for each reason.
- `agents.soundPermission` (`"Funk"`), `agents.soundQuestion` (`"Ping"`), `agents.soundFinished`
  (`"Glass"`): `"none"`, `"default"`, a macOS sound's name or a sound file's path.
- `agents.mutedMachines` (list, `[]`): machines whose agents notify nothing; `"local"` is this Mac.
- `agents.hibernateAfterMinutes` (number 0–1440, `30`): an agent done or idle and not looked at for
  this long ends and comes back when its terminal is opened; 0 is off.
- `agents.launchSkipPermissions` (bool, `false`): agents Cadex opens skip permission prompts.
- `agents.stateHooks` (bool, `true`): the hooks that tell Cadex what a session does.
- `agents.activeAccount` (text, `""`): the account folder new sessions use (`"~/.claude-work"`); empty is `~/.claude`.
- `agents.projectAccounts` (object, `{}`): a repository's own account, `{"~/code/app": "~/.claude-work"}`.
- `agents.accountNames` (object, `{}`): names for accounts by folder, `{"~/.claude-work": "Work"}`.
- `agents.hiddenAccounts` (list, `[]`): account folders left out of the lists.
- `agents.hiddenLogins` (object): kept by Cadex when an account is hidden; do not edit.

### agentTools, computerUse
- `agentTools.enabled` (bool, `true`): sessions Cadex opens get the `cadex` command, its MCP and skills.
- `agentTools.browser` (bool, `true`): agents may drive the preview.
- `agentTools.webBrowser` (`"cadex"` | `"chrome"` | `"chromeAndPlaywright"` | `"none"`, `"cadex"`): the
  browser the sessions Cadex opens are told to use: Cadex's preview beside the terminal (never
  Playwright), Claude in Chrome, Claude in Chrome or Playwright, or nothing said. Computer use is
  always Cadex's `computer_*` tools while `computerUse.enabled`. New sessions follow a change.
- `computerUse.enabled` (bool, `false`): agents may operate other Mac apps. `computerUse.allowedApps`,
  `computerUse.blockedApps` (lists of bundle ids, `[]`). Turning this on is the owner's decision.

### worktrees (tasks)
- `worktrees.root` (path, `""`): where task worktrees go; empty is `<repo>.worktrees` beside each repository.
- `worktrees.setupHooks` (object, `{}`): commands run in a new task, by repository:
  `{"~/code/app": ["pnpm install", "direnv allow"]}`.

### git, review
- `git.reviewContextLines` (number 0–50, `3`), `git.reviewWrap` (bool, `false`),
  `git.reviewShowWhitespace` (bool, `false`): the review tab.
- `review.authorship` (bool, `true`): mark the lines agents wrote.

### memory (the project memory)
- `memory.enabled` (bool, `true`), `memory.shareAcrossAccounts` (bool, `true`).
- `memory.consolidateInSession` (bool, `true`), `memory.consolidateAtContext` (number 10–95, `70`).
- `memory.backgroundAgent` (bool, `true`): the memory agent, a `claude -p` on the account.
- `memory.dailyBudgetUsd` (number 0–50, `1`), `memory.requireApproval` (bool, `false`).
- `memory.agentNoticeShown` (bool): kept by Cadex; do not edit.

### orchestration (many agents)
- `orchestration.enabled` (bool, `false`): races and runs. `orchestration.automations` (bool, `false`):
  scheduled automations (nothing runs and no LaunchAgent exists while off).
- `orchestration.maxAgents` (number 1–20, `6`), `orchestration.maxDepth` (number 0–5, `2`),
  `orchestration.heartbeatMinutes` (number 1–120, `10`), `orchestration.keepAwakeDuringRuns` (bool, `true`),
  `orchestration.defaultBudgetUsd` (number 0.1–100, `5`), `orchestration.defaultMaxMinutes` (number 1–1440, `60`).

### ssh, machines
- `ssh.ping` (bool, `true`): test each host of `~/.ssh/config` while the SSH item shows.
- `machines.tailscale` (bool, `true`): read the owner's Tailscale.
- `machines.acceptRemote` (bool, `false`): listen on the tailnet for the owner's other devices.
- `machines.users` (object, `{}`): the ssh user per MagicDNS name.

### shortcuts
An object from a key combination to a command id; `null` turns a default shortcut off.
`{"shortcuts": {"cmd+shift+t": "tab.new", "cmd+e": null}}`. Combinations: `cmd`, `shift`, `opt`,
`ctrl` joined by `+` with the key (`cmd+shift+]`, `ctrl+tab`, `cmd+opt+left`). Never `ctrl` alone with a
letter: those keys belong to programs in the terminal. Every command id, with its title and default
shortcut, is in Cadex's repository at `docs/guides/commands.md`; the owner sees them in Settings ›
Shortcuts and in ⌘K.

## Automations
One JSON file per automation in `orchestration/automations/`; the file's name (without `.json`) is
its id. They need `orchestration.automations` on. Adding, changing or deleting a file counts at once:
the Automations page refreshes and the schedule follows the enabled ones. A file that does not read
is left out (said in the log) and the others count. Every field is required except `enabledAt`:

```json
{
  "agent": { "account": "~/.claude-work", "machine": "", "model": "sonnet" },
  "allowedTools": ["Read", "Grep", "Bash(git log:*)"],
  "caps": { "budgetUsd": 1, "maxMinutes": 20 },
  "enabled": false,
  "missed": "runOnWake",
  "name": "Morning triage",
  "permissionMode": "default",
  "prompt": "Read the open issues and write a summary in TRIAGE.md.",
  "recurrence": { "weekdays": { "hour": 9, "minute": 0 } },
  "target": { "folder": { "_0": "/Users/me/code/app" } },
  "useSubscription": false
}
```

- `recurrence`, one of: `{"weekdays": {"hour": 9, "minute": 0}}` (Monday to Friday),
  `{"daily": {"hour": 9, "minute": 30}}`, `{"everyHours": {"_0": 2}}`, `{"everyMinutes": {"_0": 15}}`,
  `{"once": {"_0": "2026-12-01T09:00:00Z"}}`.
- `target`, one of: `{"folder": {"_0": "/path"}}` (runs in that folder) or
  `{"newWorktree": {"repository": "/path/to/repo"}}` (a new task worktree for each run).
- `agent.account`: the account folder, or leave the key out for the default account; `agent.model`:
  `""` for the account's default; `agent.machine`: `""` is this Mac.
- `permissionMode`: `"default"`, `"acceptEdits"`, `"plan"` or `"bypassPermissions"`.
- `missed`: `"runOnWake"` (a time missed while the Mac slept runs when it wakes) or `"skip"`.
- `useSubscription`: run on the plan instead of the account's `apiKeyHelper`; the owner's choice.
- `enabled`: a new automation should stay `false` until the owner turns it on; `enabledAt` (ISO 8601)
  is written by Cadex when it is turned on.
- Its runs' history is in `orchestration/state.sqlite`, not in the file. Deleting the file keeps the
  history out of sight; the page's Delete removes both.

## Themes
A theme is a JSON file in `themes/`; choose it with `appearance.theme` = `"user:<file name>"`:

```json
{ "name": "My theme", "dark": true,
  "interface": { "chrome": "#1E1E1E", "panel": "#161616", "panelBorder": "#2A2A2A", "tabActive": "#2E2E2E",
                 "field": "#202020", "text": "#E6E6E6", "secondaryText": "#9A9A9A", "accent": "#94E3FE" },
  "terminal": { "background": "#161616", "foreground": "#E6E6E6", "cursor": "#E6E6E6", "selection": "#33414A",
                "ansi": ["#000000", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF",
                         "#5C6370", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF"] } }
```

Every color is required and `ansi` has 16. A broken file shows on the Themes page with the field at
fault. To bring a theme from iTerm2, Ghostty or base16, the owner uses ⌘K › Import Theme.

## A repository's environment
`<repo>/.cadex/environment.toml`: the throwaway container a task of that repository runs in.

```toml
image = "ubuntu:24.04"          # or dockerfile = "Dockerfile.dev", one of them
machine = "pc"                  # where it runs; empty asks
ports = [3000, 5173]
setup = "apt-get update && apt-get install -y nodejs"
workdir = "/work"
[tailscale]
name = "ubuntu-dev"
authkey_env = "TS_AUTHKEY"      # the variable's name; never write a key here
```

## Do not
- Turn on what spends money, opens the network or acts without the owner (`computerUse.enabled`,
  `machines.acceptRemote`, `agents.launchSkipPermissions`, `orchestration.*`, an automation's
  `enabled`, `useSubscription`) unless the owner asked for it in so many words.
- Write a key, token or password in any of these files.
- Edit the app's state files (the "no" rows above).
