# Claude Appshots

Codex Appshots for the Claude desktop app's Code tab. Double-tap **⌃ Control** on
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

It makes this Mac's own signing certificate (in your login keychain), then builds
and signs the app. macOS asks for your login password to sign: click **Allow**,
not Always Allow (see Security).

Then, once:

1. **Permissions.** Allow *Claude Appshots* in System Settings → Privacy & Security →
   **Accessibility** and **Screen & System Audio Recording**. It asks on first run;
   menu bar icon → Permissions… opens the right pane. If it's listed but still
   refused, remove it with –, add it back with + (⌘⇧G, `~/Applications`).
2. **Chrome bridge.** `chrome://extensions` → Developer mode on → **Load unpacked** →
   `~/.claude/appshots/chrome-extension` (⌘⇧G in the picker; `.claude` is hidden).

Update: `git -C ~/.claude/appshots pull && ~/.claude/appshots/install.sh` (one
password prompt; permissions stay), then click reload on *Claude Appshots bridge*
in `chrome://extensions`.
Remove: `~/.claude/appshots/uninstall.sh`.

## Use

1. Have a Claude Code session open (its message box showing).
2. In any app or Chrome tab, double-tap ⌃ Control (two quick taps, nothing else).
3. Add your request and press Return. Nothing is ever sent for you.

If a message in the conversation has focus, Appshots moves focus to the message box
first. If Claude isn't showing a Code session's message box (or shows two, side by
side), the Appshot is copied instead and a notification says so: click the box and
press ⌘V.
Capture several tabs, then say "control these tabs": the bridge moves every tab
captured in the last 15 minutes into Claude's group.

Double-tap Option is Claude's Quick Entry and double-tap Command can be Siri's
shortcut, which is why Appshots uses ⌃.
Menu bar icon (a camera viewfinder, near the clock) → Hotkey changes it, Pause stops
⌃⌃ for a while, and Quit Claude Appshots (⌘Q) closes it until you open the app
again or log in. ⌘-drag the icon to move it.

## What's saved

`captures/` (readable by you only, deleted after 24 hours):

- `<App> Appshot <time>.png` — the window's screenshot (≤2048 px).
- `<App> Appshot <time>.txt` — the full Appshot in Codex's format: every element of
  the window's accessibility tree, then the selection or focused element. Password
  fields are blanked. The paste only points to it; Claude reads it when needed.

`appshots.log` records events (app, element count, paste target), never content.
Over 1 MB it's moved to `appshots.log.1`.

## Security

- Captures, the Chrome note and the log live under `~/.claude`, which only your
  account can read. Password fields are never read. The Appshot is marked so
  clipboard-history apps don't keep it, and your clipboard is put back after the
  paste unless you copied something in the meantime.
- ⌘V is sent only after checking that Claude is still in front with the message box
  focused, so switching windows mid-paste can't send it anywhere else.
- The Chrome bridge only moves tabs you captured in the last 15 minutes, only into
  Claude in Chrome's group (named "Claude …"), and its native host answers only that
  extension.
- macOS gives the two permissions to the app as signed by this Mac's certificate.
  Every helper lives inside the app and is sealed into that signature, and each
  one is checked before it runs: a swapped or re-signed file is refused, and the
  menu bar app stops with a notification. Signing needs your password every time,
  so nothing else can sign a look-alike. (Click Allow, never Always Allow: that
  would let any program sign with it silently.) Hardened runtime blocks code
  injection into all of them.
- shortcut: a helper swapped in the split second between its check and its launch
  would still run. Closing that means merging the helpers into one program.

## How it fits together

| Part | Job |
| --- | --- |
| `Claude Appshots.app` (`src/host`) | Menu bar icon; holds the two permissions; checks the signature, starts the agent |
| `…/Contents/MacOS/appshot-agent` (`src/agent`) | Hotkey, capture, paste into Claude, Chrome note |
| `…/Contents/MacOS/appshot-capture` (`src/capture`) | Reads a window's tree and screenshot |
| `…/Contents/MacOS/appshot-chrome-host` (`src/chrome-host`) | Native host the Chrome bridge asks "which tabs were captured?" |
| `src/shared/Signature.swift` | The signature check the app and agent run |
| `chrome-extension/` | Chrome bridge: moves captured tabs into Claude's tab group |
| `skill/` → `~/.claude/skills/appshot` | How Claude reads and acts on an Appshot |
| `claude-md-snippet.md` → `~/.claude/CLAUDE.md` | Tells every session to load the skill |

Rebuild with `./install.sh` after any change.

## Tests

```bash
tests/run.sh              # hotkey, Chrome note, bridge and host self-checks
tests/run.sh --installed  # also the installed app's signature check and the newest capture
```

## Troubleshooting

- **⌃⌃ does nothing:** the menu bar icon's first line says why (usually a
  permission). `appshots.log` should show `hotkey: double-tap control`.
- **No screenshot:** Screen Recording permission (see Install).
- **"Its files changed since it was built":** something altered the app. Run
  `install.sh` to rebuild it.
- **Copied instead of pasted:** a Code session's message box wasn't showing.
  `appshots.log` → `paste target … label=` shows what had focus, and
  `message box search:` how many boxes it found.
- **Chrome tab not moved:** `appshots.log` → `chrome-bridge:` lines. No lines means
  the extension isn't loaded or needs a reload.
