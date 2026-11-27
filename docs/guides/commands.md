# Os comandos do Cadex

Gerado por `tools/gen_commands.py` a partir do código (não edite à mão; `make manifests` confere).
Toda ação do Cadex é um destes comandos (`../adr/0005-every-action-is-a-command.md`). Use o id
para mudar um atalho na seção `shortcuts` do `settings.json` (`settings.md`, Atalhos): a combinação
aponta para o id, ou `null` para tirar um atalho padrão. O título é o que o ⌘K mostra em inglês.
Um `\(n)` num atalho é um número (os de ⌘1 a ⌘9). Alguns comandos têm o id montado na hora (um por
tema, por conta, por item da barra de status) e não estão aqui: o ⌘K os mostra.

| id | título | atalho padrão |
|---|---|---|
| `agent-tools.notify` | Agents' Notes |  |
| `agent-tools.open-diff` | Open a Diff for the Agent |  |
| `agent-tools.open-file` | Open a File for the Agent |  |
| `agent-tools.show-sessions` | Show Sessions Using Cadex… |  |
| `agent-tools.toggle` | Turn Agent Tools On or Off |  |
| `agents.add-account` | Add Agent Account |  |
| `agents.answer` | Answer an Agent's Question… |  |
| `agents.approve` | Allow an Agent's Request… |  |
| `agents.continue-in-account` | Continue Agent Conversation in Another Account… |  |
| `agents.continue-in-agent` | Continue in… |  |
| `agents.copy-resume-command` | Copy Agent Conversation's Resume Command… |  |
| `agents.customize-accounts` | Customize Accounts |  |
| `agents.deny` | Deny an Agent's Request… |  |
| `agents.follow-default-config` | Follow the Default Account Again… |  |
| `agents.go-to-request` | Go to the Agent That Waits for You |  |
| `agents.hibernate` | Hibernate This Agent |  |
| `agents.mark-unread` | Mark an Agent as Unread… |  |
| `agents.mute-machine` | Mute or Unmute a Machine's Agents… |  |
| `agents.open-account` | Open an Account's Agent | `cmd+shift+a` |
| `agents.refresh-usage` | Refresh Agent Usage |  |
| `agents.remove-account` | Remove Agent Account… |  |
| `agents.rename-account` | Rename an Agent Account… |  |
| `agents.restart` | Restart This Agent |  |
| `agents.resume-session` | Resume Agent Conversation… |  |
| `agents.reveal-session-log` | Reveal Agent Conversation's Log… |  |
| `agents.set-active-account` | Set Active Agent Account |  |
| `agents.set-project-account` | Set This Project's Agent Account |  |
| `agents.share-account-config` | Share the Default Account's Config… |  |
| `agents.show-accounts` | Show Agent Accounts | `cmd+shift+u` |
| `agents.show-attention` | Show What Needs You |  |
| `agents.show-feed` | Show Agents' Feed |  |
| `agents.show-history` | Show All Sessions (Archive) |  |
| `agents.switch-account` | Switch Account… |  |
| `agents.sync-account-config` | Sync Agent Accounts' Config |  |
| `agents.test-notifications` | Send Test Notifications |  |
| `agents.use-own-copy` | Use an Account's Own Copy… |  |
| `app.check-for-updates` | Check for Updates… |  |
| `app.hide` | Hide Cadex | `cmd+h` |
| `app.install-update` | Install Update and Reopen |  |
| `app.quit` | Quit Cadex | `cmd+q` |
| `app.skip-update` | Don't Remind Me About This Update |  |
| `computer-use.agent` | Computer Use Settings |  |
| `computer-use.open-permissions` | Open Computer Use Permissions |  |
| `computer-use.revoke-apps` | Forget Apps Allowed to Agents |  |
| `computer-use.stop` | Stop the Agent in Other Apps |  |
| `computer-use.toggle` | Turn Computer Use On or Off |  |
| `drawer.move-to-project` | Move the Drawer's Terminal to the Project | `cmd+return` |
| `drawer.toggle` | Show or Hide the Terminal Drawer | `cmd+opt+`` |
| `edit.copy` | Copy | `cmd+c` |
| `edit.cut` | Cut | `cmd+x` |
| `edit.find` | Find | `cmd+f` |
| `edit.paste` | Paste | `cmd+v` |
| `edit.redo` | Redo | `cmd+shift+z` |
| `edit.select-all` | Select All | `cmd+a` |
| `edit.undo` | Undo | `cmd+z` |
| `editor.fold-all` | Fold All Blocks |  |
| `editor.save` | Save File | `cmd+s` |
| `editor.unfold-all` | Unfold All Blocks |  |
| `explorer.collapse-all` | Collapse All Folders |  |
| `explorer.copy-files` | Copy Files |  |
| `explorer.copy-path` | Copy Path |  |
| `explorer.copy-relative-path` | Copy Relative Path |  |
| `explorer.focus` | Show Files | `cmd+shift+e` |
| `explorer.new-file` | New File |  |
| `explorer.new-folder` | New Folder |  |
| `explorer.open` | Open File |  |
| `explorer.open-beside` | Open to the Side |  |
| `explorer.open-in-finder` | Open in Finder |  |
| `explorer.open-in-tab` | Open in New Tab |  |
| `explorer.open-in-terminal` | Open in Terminal |  |
| `explorer.paste-files` | Paste Files |  |
| `explorer.refresh` | Reload Files |  |
| `explorer.rename` | Rename |  |
| `explorer.reveal` | Reveal in Finder |  |
| `explorer.toggle-hidden` | Show or Hide Hidden Files | `cmd+shift+.` |
| `explorer.trash` | Move to Trash |  |
| `git.accept-both` | Keep Both in Conflict |  |
| `git.accept-ours` | Keep Ours in Conflict |  |
| `git.accept-theirs` | Keep Theirs in Conflict |  |
| `git.changes-last-turn` | Changes: Last Turn |  |
| `git.changes-task` | Changes: Task |  |
| `git.changes-uncommitted` | Changes: Uncommitted |  |
| `git.commit` | Commit… |  |
| `git.discard` | Discard File Changes |  |
| `git.fetch` | Git Fetch |  |
| `git.history` | Open Git History |  |
| `git.history-in-tab` | Open Git History in New Tab |  |
| `git.mark-resolved` | Mark Conflict Resolved |  |
| `git.open-diff` | Open File Diff |  |
| `git.open-diff-beside` | Open Diff Beside |  |
| `git.open-diff-in-tab` | Open Diff in New Tab |  |
| `git.open-file` | Open Changed File |  |
| `git.open-file-beside` | Open File Beside |  |
| `git.open-file-in-tab` | Open File in New Tab |  |
| `git.open-pr` | Open Pull Request |  |
| `git.pull` | Git Pull (Fast-Forward Only) |  |
| `git.push` | Git Push |  |
| `git.refresh` | Refresh Git Status |  |
| `git.reveal` | Reveal Changed File in Finder |  |
| `git.review-compare-worktrees` | Compare Two Worktrees |  |
| `git.review-image-mode` | Next Image Comparison Mode |  |
| `git.review-next-file` | Next File in Review |  |
| `git.review-next-hunk` | Next Change in Review |  |
| `git.review-open` | Review Changes |  |
| `git.review-prev-file` | Previous File in Review |  |
| `git.review-prev-hunk` | Previous Change in Review |  |
| `git.review-set-base` | Set Review Base |  |
| `git.review-stage-hunk` | Stage Change |  |
| `git.review-stage-lines` | Stage Marked Lines |  |
| `git.review-toggle-collapse` | Show or Fold Unchanged Lines |  |
| `git.review-toggle-whitespace` | Show Whitespace in Review |  |
| `git.review-toggle-wrap` | Toggle Line Wrap in Review |  |
| `git.review-unstage-hunk` | Unstage Change |  |
| `git.review-unstage-lines` | Unstage Marked Lines |  |
| `git.show` | Show Git | `cmd+shift+g` |
| `git.show-history` | Show Git History | `cmd+shift+l` |
| `git.stage` | Stage File |  |
| `git.stage-all` | Stage All Changes |  |
| `git.switch-branch` | Switch Branch |  |
| `git.unstage` | Unstage File |  |
| `git.unstage-all` | Unstage All |  |
| `history.copy-sha` | Copy Commit SHA |  |
| `history.current-branch` | Toggle Current Branch Only in History |  |
| `history.open-remote` | Open Commit on Remote |  |
| `history.refresh` | Refresh History |  |
| `history.search` | Search History |  |
| `history.show-in-tab` | Show Commit Details in a Tab |  |
| `home.show` | Show the Home Screen |  |
| `machines.connect` | Connect to a Tailnet Machine |  |
| `machines.copy-address` | Copy a Tailnet Machine's Address |  |
| `machines.docker-context` | Use a Machine's Docker in This Tab… |  |
| `machines.docker-ps` | Show a Machine's Containers… |  |
| `machines.ping` | Ping a Tailnet Machine |  |
| `machines.refresh` | Refresh Tailnet Machines |  |
| `machines.share-port` | Share This Preview on Your Tailnet |  |
| `machines.share-public` | Share This Preview on the Internet… |  |
| `machines.stop-sharing` | Stop Sharing a Preview… |  |
| `markdown.backlinks` | Show Backlinks |  |
| `markdown.open-link` | Open Link Under Cursor |  |
| `markdown.toggle-preview` | Toggle Rendered Markdown | `cmd+shift+v` |
| `media.zoom-actual` | Actual Size | `cmd+opt+0` |
| `media.zoom-fit` | Zoom to Fit | `cmd+0` |
| `media.zoom-in` | Zoom In | `cmd+=` |
| `media.zoom-out` | Zoom Out | `cmd+-` |
| `memory.approve` | Approve Memory Proposal… |  |
| `memory.bootstrap` | Organize History with AI… |  |
| `memory.configure-project` | Configure This Project's Memory |  |
| `memory.consolidate-now` | Consolidate Memory Now |  |
| `memory.discard-message-edit` | Discard an Agent Message's Edit |  |
| `memory.edit-message` | Edit a Queued Agent Message |  |
| `memory.enable` | Turn On Project Memory (All Projects) |  |
| `memory.fix-health` | Fix Memory Health… |  |
| `memory.new-session-without` | New Session without Memory |  |
| `memory.open-guide` | Open an ai-memory Guide |  |
| `memory.open-in-cadex` | Open the Memory Project in Cadex |  |
| `memory.panel-back` | Memory Panel: Back |  |
| `memory.panel-forward` | Memory Panel: Forward |  |
| `memory.pause-agent` | Pause or Resume the Memory Agent |  |
| `memory.pause-session` | Pause Memory in This Session |  |
| `memory.refresh` | Refresh Memory Page |  |
| `memory.reindex` | Reindex Project Memory |  |
| `memory.reject` | Reject Memory Proposal… |  |
| `memory.resume-session` | Resume Memory in This Session |  |
| `memory.run-dream` | Reorganize Memory Now (Dream) |  |
| `memory.save-message` | Save an Edited Agent Message |  |
| `memory.search` | Search Project Memory… |  |
| `memory.send-message` | Send a Message to an Agent |  |
| `memory.show` | Show Project Memory |  |
| `memory.show-briefing` | What the Next Agent Will Get |  |
| `memory.show-history` | Show Memory History |  |
| `memory.show-panel` | Show the Memory Panel |  |
| `memory.toggle-project` | Turn Memory On or Off in This Project |  |
| `orchestration.new-automation` | New Automation: a Prompt on a Schedule |  |
| `orchestration.new-run` | New Run: Tasks for Several Agents |  |
| `orchestration.show-automations` | Show Automations |  |
| `orchestration.toggle` | Turn Races and Runs On or Off |  |
| `orchestration.toggle-automations` | Turn Automations On or Off |  |
| `palette.open` | Open Command Palette | `cmd+k` |
| `pane.close` | Close Pane | `cmd+w` |
| `pane.next` | Next Pane | `cmd+]` |
| `pane.previous` | Previous Pane | `cmd+[` |
| `pane.split-down` | Split Down | `cmd+shift+d` |
| `pane.split-right` | Split Right | `cmd+d` |
| `pane.zoom` | Maximize or Restore Pane | `cmd+shift+return` |
| `place.go` | Go to a Place (the Project's Own or a Task) |  |
| `ports.stop` | Stop a Listening Port |  |
| `power.allow-sleep` | Let the Computer Sleep |  |
| `power.keep-awake` | Keep the Computer Awake |  |
| `power.keep-awake-hour` | Keep the Computer Awake for 1 Hour |  |
| `power.keep-awake-while-running` | Keep Awake While a Program Runs |  |
| `power.toggle` | Toggle Keep Awake |  |
| `preview.add-note` | Add a Note to the Page |  |
| `preview.agent` | Show the Agent's Preview |  |
| `preview.back` | Go Back in Preview |  |
| `preview.clear-notes` | Clear the Page's Notes |  |
| `preview.forward` | Go Forward in Preview |  |
| `preview.open` | Open Web Preview | `cmd+shift+h` |
| `preview.open-in-tab` | Open Web Preview in New Tab |  |
| `preview.pick-element` | Pick Element in Preview | `cmd+shift+c` |
| `preview.reload` | Reload Preview | `cmd+r` |
| `preview.send-notes` | Send the Page's Notes to the Agent |  |
| `preview.stop-agent` | Stop the Agent on This Preview |  |
| `preview.stop-picking` | Stop Picking | `escape` |
| `project.close` | Close Project |  |
| `project.close-terminals` | Close the Project's Terminals |  |
| `project.copy-path` | Copy the Project's Path |  |
| `project.create` | New Project… |  |
| `project.edit` | Edit Project (Name, Image, Color)… |  |
| `project.go` | Go to a Project |  |
| `project.move-terminal` | Move Terminal to Its Folder's Project |  |
| `project.new` | Open Project… | `ctrl+cmd+n` |
| `project.new-claude` | New Claude in the Project |  |
| `project.new-terminal` | New Terminal in the Project |  |
| `project.next` | Next Project | `ctrl+cmd+right` |
| `project.pin` | Pin or Unpin the Project |  |
| `project.previous` | Previous Project | `ctrl+cmd+left` |
| `project.remove` | Remove the Project from the Sidebar |  |
| `project.rename` | Rename Project |  |
| `project.reveal` | Show the Project in Finder |  |
| `project.set-color` | Set Project Color |  |
| `project.show-all` | Show Projects |  |
| `project.show-memory` | Show the Project's Memory |  |
| `project.show-overview` | Show the Project's Page |  |
| `project.show-sessions` | Show the Project's Sessions |  |
| `project.show-settings` | Show the Project's Settings |  |
| `project.show-terminals` | Show the Project's Own Terminals |  |
| `project.switch` | Switch Project | `cmd+shift+s` |
| `remote.show` | Connect to a Remote Machine… |  |
| `review.add-comment` | Comment on Lines | `c` |
| `review.clear-comments` | Clear Comments |  |
| `review.delete-comment` | Delete Comment |  |
| `review.edit-comment` | Edit Comment |  |
| `review.export-authorship` | Export Line Authorship… |  |
| `review.send-comments` | Send Comments to Agent |  |
| `review.show-sent` | Show Sent Comments |  |
| `review.toggle-authorship` | Show or Hide Who Wrote Each Line |  |
| `search.content` | Find Text in Files | `cmd+shift+f` |
| `search.files` | Find File by Name | `cmd+p` |
| `search.toggle-case` | Match Case in Text Search | `cmd+opt+c` |
| `search.toggle-regex` | Use Regular Expression in Text Search | `cmd+opt+r` |
| `settings.open` | Open settings | `cmd+,` |
| `settings.open-agents` | Open Agent and Account Settings |  |
| `settings.open-terminal` | Open Terminal Settings |  |
| `settings.open-themes` | Open Theme Settings |  |
| `sidebar.find` | Find a Project, Task or Terminal… |  |
| `sidebar.show` | Show the Sidebar | `cmd+shift+j` |
| `sidebar.show-files` | Show Files in the Sidebar | `cmd+shift+2` |
| `sidebar.show-work` | Show Work in the Sidebar | `cmd+shift+1` |
| `sidebar.switch-view` | Switch Between Work and Files | `cmd+e` |
| `ssh.connect` | Connect with SSH |  |
| `ssh.test-again` | Test SSH Hosts Again |  |
| `statusBar.activity-monitor` | Open Activity Monitor |  |
| `statusBar.customize` | Customize Status Bar |  |
| `statusBar.toggle-item` | Show or Hide a Status Bar Item |  |
| `tab.least-recently-used` | Go to Least Recently Used Tab | `ctrl+shift+tab` |
| `tab.new` | New Tab | `cmd+t` |
| `tab.next` | Next Tab | `cmd+shift+]` |
| `tab.previous` | Previous Tab | `cmd+shift+[` |
| `tab.previous-used` | Back to Previous Tab | `ctrl+tab` |
| `tab.rename` | Rename Tab |  |
| `tab.set-color` | Set Tab Color |  |
| `terminal.clear` | Clear Terminal | `cmd+l` |
| `terminal.open-pasted-image-beside` | Open Last Pasted Image Beside |  |
| `terminal.open-pasted-image-in-tab` | Open Last Pasted Image in New Tab |  |
| `terminal.scroll-bottom` | Scroll to Bottom | `cmd+down` |
| `terminal.scroll-top` | Scroll to Top | `cmd+up` |
| `terminal.toggle-ligatures` | Turn Ligatures On or Off |  |
| `theme.accent` | Choose Accent Color |  |
| `theme.accent-reset` | Use the Theme's Accent Color |  |
| `theme.choose` | Choose Theme |  |
| `theme.choose-dark` | Choose Theme for Dark Mode |  |
| `theme.choose-light` | Choose Theme for Light Mode |  |
| `theme.import` | Import Theme… |  |
| `theme.open-folder` | Open Themes Folder |  |
| `theme.toggle-high-contrast` | Turn High Contrast On or Off |  |
| `theme.toggle-pane-glow` | Glowing or Plain Pane Borders |  |
| `theme.toggle-translucent` | Make the Window Translucent or Solid |  |
| `theme.toggle-vibrancy` | Turn Vibrancy On or Off |  |
| `view.board` | Show the Board |  |
| `view.jump` | Jump to a Task… | `cmd+j` |
| `view.toggle-sidebar` | Show or Hide the Sidebar | `cmd+b` |
| `window.new` | New Window | `cmd+shift+n` |
| `window.toggle-full-screen` | Enter or Leave Full Screen | `ctrl+cmd+f` |
| `workspace.open-folder` | Open Folder… | `cmd+o` |
| `workspace.use-terminal-folder` | Use the Terminal's Folder |  |
| `worktrees.edit-setup-hooks` | Edit Task Setup Hooks… |  |
| `worktrees.new-race` | New Race: the Same Task in Several Agents |  |
| `worktrees.new-task` | New Task | `cmd+n` |
| `worktrees.new-task-on` | New Task on Another Machine… |  |
| `worktrees.open` | Open Task… |  |
| `worktrees.open-remote-shell` | Open a Remote Task's Shell… |  |
| `worktrees.remove` | Remove Task… |  |
| `worktrees.set-comment` | Comment on a Task… |  |
| `worktrees.set-status` | Set Task Status… |  |
