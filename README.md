# Claude Appshots

Codex Appshots for the Claude desktop app's Code tab. Double-tap **⌘ Command** on
any window and a short `<appshot>` block plus a screenshot of that window lands in
your open Claude Code session's message box. Claude then works in that window:
Chrome tabs through Claude in Chrome (your actual tab, not a copy), other apps
through computer use.

## Install (any Mac)

Needs macOS 14+, Apple's command line tools (`xcode-select --install`), the Claude
desktop app, and for Chrome, the Claude in Chrome extension.

```bash
git clone <your private repo URL> ~/.claude/appshots
~/.claude/appshots/install.sh
```

Then, once:

1. **Permissions.** Allow *Claude Appshots* in System Settings → Privacy & Security →
   **Accessibility** and **Screen & System Audio Recording**. It asks on first run;
   menu bar icon → Permissions… opens the right pane. If it's listed but still
   refused, remove it with –, add it back with + (⌘⇧G, `~/Applications`).
2. **Chrome bridge.** `chrome://extensions` → Developer mode on → **Load unpacked** →
   `~/.claude/appshots/chrome-extension` (⌘⇧G in the picker; `.claude` is hidden).

Update: `git -C ~/.claude/appshots pull && ~/.claude/appshots/install.sh`, then
click reload on *Claude Appshots bridge* in `chrome://extensions`.
Remove: `~/.claude/appshots/uninstall.sh`.

## Use

1. Have a Claude Code session open (its message box showing).
2. In any app or Chrome tab, double-tap ⌘ (two quick taps, nothing else).
3. Add your request and press Return. Nothing is ever sent for you.

If Claude isn't showing a Code session's message box, the Appshot is copied
instead and a notification says so: click the box and press ⌘V.
Capture several tabs, then say "control these tabs": the bridge moves every tab
captured in the last 15 minutes into Claude's group.

Claude's own Quick Entry uses double-tap Option, which is why Appshots uses ⌘.
Menu bar icon → Hotkey changes it.

## What's saved

`captures/` (readable by you only, deleted after 24 hours):

- `<App> Appshot <time>.png` — the window's screenshot (≤2048 px).
- `<App> Appshot <time>.txt` — the full Appshot in Codex's format: every element of
  the window's accessibility tree, then the selection or focused element. Password
  fields are blanked. The paste only points to it; Claude reads it when needed.

`appshots.log` records events (app, element count, paste target), never content.

## How it fits together

| Part | Job |
| --- | --- |
| `~/Applications/Claude Appshots.app` (`src/host`) | Menu bar icon; holds the two permissions; starts the agent |
| `bin/appshot-agent` (`src/agent`) | Hotkey, capture, paste into Claude, Chrome note |
| `bin/appshot-capture` (`src/capture`) | Reads a window's tree and screenshot |
| `bin/appshot-chrome-host` (`src/chrome-host`) | Native host the Chrome bridge asks "which tabs were captured?" |
| `chrome-extension/` | Chrome bridge: moves captured tabs into Claude's tab group |
| `skill/` → `~/.claude/skills/appshot` | How Claude reads and acts on an Appshot |
| `claude-md-snippet.md` → `~/.claude/CLAUDE.md` | Tells every session to load the skill |

The agent and tools inherit the app's permissions, so `./build.sh` can rebuild them
freely. Rebuilding the app itself (`./build.sh --host`) changes its signature and
macOS then asks for both permissions again; avoid it.

## Tests

```bash
tests/run.sh            # hotkey, Chrome note, bridge and host self-checks
tests/run.sh --capture  # also captures Chrome, Finder and Claude for real
```

## Troubleshooting

- **⌘⌘ does nothing:** the menu bar icon's first line says why (usually a
  permission). `appshots.log` should show `hotkey: double-tap command`.
- **No screenshot:** Screen Recording permission (see Install).
- **Copied instead of pasted:** a Code session's message box wasn't showing.
  `appshots.log` → `paste target … label=` shows what had focus.
- **Chrome tab not moved:** `appshots.log` → `chrome-bridge:` lines. No lines means
  the extension isn't loaded or needs a reload.
