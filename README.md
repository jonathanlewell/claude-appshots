# Claude Appshots

Show Claude any window on your Mac with one gesture. Double-tap **⌃ Control** on
any window and a short `<appshot>` block plus a screenshot of that window lands in
the message box of your open Claude Code session (in the Claude desktop app's Code
tab), or of the chat or project thread showing in Claude. Claude then works in that
window: Chrome tabs through Claude in Chrome (your actual tab, not a copy), other
apps through computer use.

It copies the idea of Appshots in OpenAI's Codex app, where a hotkey hands the
assistant the window you're looking at. This is an independent project, not made
or supported by Anthropic or OpenAI.

## Install (any Mac)

You need:

- macOS 14 or later
- Apple's command line tools: `xcode-select --install` (gives `swiftc`, `git` and
  `python3`)
- the Claude desktop app
- for apps other than Chrome: computer use switched on in Claude
- for Chrome: Google Chrome (not Beta or Canary) with the Claude in Chrome extension

```bash
git clone https://github.com/jonathanlewell/claude-appshots.git ~/.claude/appshots
~/.claude/appshots/install.sh
```

The folder must be `~/.claude/appshots`: the installer stops if it's anywhere else.

**What the installer changes on your Mac:**

- makes a signing certificate called *Claude Appshots signing* in your login
  keychain, used only to sign this app (its private key can't be exported)
- builds `~/Applications/Claude Appshots.app` and starts it (a menu bar icon)
- links the `appshot` skill into `~/.claude/skills/appshot`
- adds a short *Appshots* section (`claude-md-snippet.md`) to the end of your
  `~/.claude/CLAUDE.md`, which tells every Claude Code session to use the skill
- registers the Chrome bridge's native host in Chrome's `NativeMessagingHosts` folder

`uninstall.sh` undoes all of these except the CLAUDE.md section and the Chrome
extension, which you remove by hand.

While it builds, macOS asks for your login password to use the certificate: click
**Allow**, not Always Allow (see Security). It asks again on every update.

Then, once:

1. **Permissions.** Allow *Claude Appshots* in System Settings → Privacy & Security →
   **Accessibility** and **Screen & System Audio Recording**. It asks on first run;
   menu bar icon → Permissions… opens the right pane. If macOS offers **Quit &
   Reopen** after Screen Recording, click it. If it's listed but still refused,
   remove it with –, add it back with + (⌘⇧G, `~/Applications`).
2. **Chrome bridge.** `chrome://extensions` → Developer mode on → **Load unpacked** →
   `~/.claude/appshots/chrome-extension` (⌘⇧G in the picker; `.claude` is hidden).
   Chrome installs extensions per profile: do this in **every profile you capture
   from**, above all the one Claude in Chrome is connected to. A capture from a
   profile without it says so in its notification and in the Appshot.

Update: `git -C ~/.claude/appshots pull && ~/.claude/appshots/install.sh` (one
password prompt; permissions stay), then click reload on *Claude Appshots bridge*
in `chrome://extensions`.
Remove: `~/.claude/appshots/uninstall.sh`.

## Use

1. Have a Claude Code session, chat or project thread open (its message box showing).
2. In any app or Chrome tab, double-tap ⌃ Control (two quick taps, nothing else).
3. Add your request and press Return. Nothing is ever sent for you.

If a message in the conversation has focus, Appshots moves focus to the message box
first. If Claude isn't showing a message box (or shows two, side by side), or the
box is Quick Entry's, the Appshot is copied instead and a notification says so:
click the box and press ⌘V.
In a chat or project thread, Claude gets the screenshot and the Appshot text, but
can't open the full Appshot file under `~/.claude`; that part needs a Code session.
Capture several tabs, then say "control these tabs": the session asks the bridge
for each of them and it moves them into that session's group.

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
- The Chrome bridge only moves tabs you captured in the last 15 minutes, only when
  a Claude session asks for that capture by its stamp (it loads
  `example.com/#appshots-handoff=<stamp>` in its own group; the part after `#`
  never leaves Chrome), never out of another session's group, and its native host
  answers only that
  extension.
- macOS gives the two permissions to the app as signed by this Mac's certificate.
  Every helper lives inside the app and is sealed into that signature, and each
  one is checked before it runs: a swapped or re-signed file is refused, and the
  menu bar app stops with a notification. Signing needs your password every time,
  so nothing else can sign a look-alike. (Click Allow, never Always Allow: that
  would let any program sign with it silently.) Hardened runtime blocks code
  injection into all of them.
- Known gap: a helper swapped in the split second between its check and its launch
  would still run. Closing that means merging the helpers into one program.

## How it fits together

| Part | Job |
| --- | --- |
| `Claude Appshots.app` (`src/host`) | Menu bar icon; holds the two permissions; checks the signature, starts the agent |
| `…/Contents/MacOS/appshot-agent` (`src/agent`) | Hotkey, capture, paste into Claude, Chrome note |
| `…/Contents/MacOS/appshot-capture` (`src/capture`) | Reads a window's tree and screenshot |
| `…/Contents/MacOS/appshot-chrome-host` (`src/chrome-host`) | Native host the Chrome bridge asks "which tabs were captured?" |
| `src/shared/Signature.swift` | The signature check the app and agent run |
| `chrome-extension/` | Chrome bridge: moves a captured tab into the asking Claude session's tab group |
| `skill/` → `~/.claude/skills/appshot` | How Claude reads and acts on an Appshot |
| `claude-md-snippet.md` → `~/.claude/CLAUDE.md` | Tells every session to load the skill |

Rebuild with `./install.sh` after any change.

## Limits

- Pasting finds Claude's message box by its English labels (`Prompt`,
  `Write your reply to Claude`). With Claude in another language, or after a
  Claude update renames them, the Appshot is copied instead of pasted: press ⌘V.
- The bridge works only in Google Chrome. Other browsers can be read from the
  screenshot and tree, but Claude can't click in them.
- Chat and project threads get the screenshot and the short block, but only a
  Code session can open the full tree file.

## Tests

Needs Node (`brew install node`) for the bridge check.

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
- **Copied instead of pasted:** no message box was showing.
  `appshots.log` → `paste target … label= window=` shows what had focus (Code's
  box is `Prompt`, a chat's `Write your reply to Claude`), and
  `message box search:` how many boxes it found.
- **Chrome tab not moved:** `appshots.log` → `chrome-bridge: v<version>` lines (the
  version shows which bridge Chrome is running; reload it after an update). No
  line after the session asked means the extension isn't loaded in that profile
  or needs a reload;
  `chrome-handoff: bridge not installed in Chrome profile dir=…` names the profile
  folder that is missing it.
