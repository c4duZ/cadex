---
name: cadex-settings
description: Use when the owner asks to change how Cadex itself works or looks (a preference, the theme, the terminal's font, a shortcut, the status bar, notifications, accounts, the memory, an automation, a repository's task environment). Cadex is configured by editing its text files.
---

Cadex keeps every setting in text files and rereads them on its own. Read the full reference first:

```
cadex skills get settings
```

In short: preferences and shortcuts are in `~/Library/Application Support/Cadex/settings.json`
(change only the keys asked for; it counts at once), automations are one JSON each in
`~/Library/Application Support/Cadex/orchestration/automations/`, the owner's themes are in
`~/Library/Application Support/Cadex/themes/`. Never turn on what spends money, opens the network or
acts without the owner unless they asked for it in so many words.
