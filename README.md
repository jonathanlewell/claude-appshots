# Claude Appshots

A Claude desktop (Code tab) version of Codex Appshots. Double-tap **⌘ Command**
on any window and Claude Appshots pastes a short `<appshot>` block plus a
screenshot of that window into the Claude Code session you have open. Claude then
treats that window as the one to work in: Chrome tabs through Claude in Chrome,
other apps through computer use.

## Using it

1. Have a Claude Code session showing in Claude (its message box visible).
2. Go to any app or Chrome tab and double-tap ⌘ (two quick taps, nothing else).
3. The Appshot and screenshot appear in the message box. Nothing is sent: add
   your request and press Return yourself.

If Claude isn't showing a Code session's message box, the Appshot is copied
instead and a notification says so: click the box and press ⌘V.

Claude's own Quick Entry uses double-tap Option, which is why Appshots uses ⌘.
Change it from the menu bar icon → Hotkey.

### Chrome: controlling the exact tab

Claude in Chrome can only control tabs inside its own tab group. Two ways to get
your captured tab in there:

- **Automatic (Chrome bridge, recommended):** install once, below. When Claude
  starts working in Chrome, the bridge moves the tab you captured into Claude's
  group. Works for 15 minutes after each capture.
- **Manual:** when Claude asks, right-click the tab → Add tab to group → the
  Claude group.

Don't close Claude's placeholder tab in the group: Chrome then dissolves the
group.

## Install the Chrome bridge (one time)

```bash
~/.claude/appshots/install-chrome-bridge.sh
```

Then in Chrome go to `chrome://extensions`, turn on **Developer mode**, click
**Load unpacked** and choose `~/.claude/appshots/chrome-extension`. It should
show as "Claude Appshots bridge" with ID `eiomachhgadhcohiceonjfnonjkhaach`.

It asks for: tabs (to find the captured tab), tab groups (to move it) and native
messaging (to ask the Appshots app which tab you captured). It reads nothing from
pages. Remove it from `chrome://extensions` and delete
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.jonathanlewell.claude_appshots.json`.

## What's captured

- `captures/<App> Appshot <time>.png` — the window's screenshot (≤2048 px).
- `captures/<App> Appshot <time>.txt` — the full Codex-format Appshot: every
  element in the window's accessibility tree, plus the selection or focused
  element. Password fields are blanked. The paste only points to this file;
  Claude reads it when it needs detail.
- Both are deleted after 24 hours. `appshots.log` records events, never content.

## Parts

| Part | What it is | Rebuild needs new permissions? |
| --- | --- | --- |
| `~/Applications/Claude Appshots.app` | Launcher: menu bar icon, holds Accessibility and Screen Recording, starts the agent | Yes. Avoid `./build.sh --host` |
| `bin/appshot-agent` | Hotkey, capture, paste, Chrome note | No |
| `bin/appshot-capture` | Reads a window's tree and screenshot | No |
| `bin/appshot-chrome-host` | Native host the Chrome bridge talks to | No |
| `chrome-extension/` | The Chrome bridge extension | Reload it in chrome://extensions |
| `~/.claude/skills/appshot/SKILL.md` | How Claude reads and acts on an Appshot | — |
| `~/.claude/CLAUDE.md` | Tells every session to load that skill | — |

Rebuild after changing source: `./build.sh`, then `pkill -f appshot-agent`
(the app restarts it).

## Troubleshooting

- **Nothing happens on ⌘⌘:** the menu bar icon's first line says what's wrong. If
  it says it needs Accessibility, System Settings → Privacy & Security →
  Accessibility → remove Claude Appshots with –, add it back with + (⌘⇧G,
  `~/Applications`), switch it on.
- **No screenshot:** same, under Screen & System Audio Recording.
- **Pasted into the wrong box:** it only pastes into a Code session's message box;
  otherwise it copies. Check `appshots.log` for `paste target`.
- **Bridge didn't move the tab:** check `appshots.log` for `chrome-bridge:` lines.
