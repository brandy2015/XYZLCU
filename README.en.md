# XYZLCU

[中文](README.md) | **English**

[![License: MIT](https://img.shields.io/github/license/brandy2015/XYZLCU)](LICENSE) [![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](#requirements) [![Universal: Apple Silicon + Intel](https://img.shields.io/badge/arch-Apple%20Silicon%20%2B%20Intel-blue)](#requirements) [![Release](https://img.shields.io/github/v/release/brandy2015/XYZLCU)](https://github.com/brandy2015/XYZLCU/releases/latest)

**XYZLCU (XYZ Local Computer Use)** is a dependency-free macOS GUI control CLI. Anything that can run shell commands, whether an AI agent (Claude Code, Codex, any shell-capable agent) or your own script, can use it to see the screen, click, type, press shortcuts, read the UI structure and press buttons. It is one Swift source file (built as `xyzlcu-core`) plus a tiny C client (`xyzlcu`): no Python, no Node, no Homebrew, no third-party libraries.

> **General-purpose, not tied to any agent.** XYZLCU is a plain command-line program: any agent that can run shell commands and read JSON output can use it directly (Grok Bot, Claude Code, Codex CLI, Cursor, Gemini CLI, Cline / Roo, Aider, OpenClaw, OpenCode, Trae, …), with no plugin or adapter layer. MCP-only clients can use the built-in `xyzlcu mcp`. It works without an agent too: shell scripts, Shortcuts, cron / launchd. See [Supported agents](#supported-agents).

> Inspired by and borrows ideas from [LCU (Local Computer Use)](https://github.com/amontlabs/lcu) by Amont Labs, with thanks (see [Acknowledgements](#acknowledgements)). XYZLCU is an **independent implementation**: it copies no LCU code and does **not** need the ChatGPT / Codex desktop app or its runtime. For a speed and usability comparison with LCU, see [Benchmark](#benchmark-vs-lcu).

## Why XYZLCU (highlights)

All numbers are medians measured on the same Apple Silicon Mac (macOS 26+); see [Benchmark](#benchmark-vs-lcu) for the method and full data. The LCU numbers come from the 0.4.2 round on the same machine (LCU 0.13.4). LCU does some things better than XYZLCU too, and those are listed in [Benchmark](#benchmark-vs-lcu) as well.

- ⚡ **Fast**: with the daemon running, `xyzlcu` is a tiny C program, about **3 ms** per call.

  | Operation | XYZLCU | LCU |
  |---|---:|---:|
  | Click | **6 ms** | 140 ms |
  | Type `abc` | **5 ms** | 43 ms |
  | Type Chinese `你好abc` | **7 ms** | ~9 s |
  | Key press | **4 ms** | 14 ms |
  | Window screenshot | **6 ms** (first one ~25 ms) | 51 ms |
  | List apps | **3 ms** | 17 ms |

- 🧠 **In-memory and diff screenshots**: `--base64` / `--stdout` produce the image in memory, with no file written, and a `--fast` half-size JPEG takes about **9 ms**. `--diff` returns only the region that changed; if nothing changed you get a short JSON reply (3–4 ms, no image), which suits agents that keep taking a quick look.
- 🛣 **Typing works even when the keyboard is stuck**: the event stream is probed for real every time. If it is stuck, typing falls back automatically: AX value write → posting to the process → paste via the menu. Shortcuts first look for the matching menu-bar item. Every path is **read back and verified**, and the next path is tried only if nothing landed. If the field cannot be read back, it stays on the current path, so **the same text is never typed twice**. The output says which path was actually used.
- 🔌 **Works with any agent**: anything that runs shell commands can use it, and MCP-only clients get the built-in `xyzlcu mcp`. Tested: Grok Bot, Codex CLI, OpenCode, an MCP client (full handshake), Python / Node programs, and shell scripts. See [Supported agents](#supported-agents).
- 🪙 **Saves tokens**: `ax --compact` lists only actionable controls, one per line with a number and a center point; `click-el --ref N` then presses by number. Finder's control tree with the menu bar goes from **13.7 KB to 0.4 KB**, and a TextEdit window from 740 to 243 bytes.
- 🧰 **Full feature set**: mouse position and movement, drag, scroll, full-screen / window / region screenshots, the window list, moving and resizing windows, the display list, pressing menus in the background, the control tree and pressing controls, waiting for a control to appear, and record / replay. LCU on the Mac has no mouse position or movement, no full-screen screenshots and no window list.
- 🔒 **Safety**:
  - Mouse and keyboard actions are refused while the screen is locked, so nothing gets typed into the lock-screen password field.
  - The recorder only listens and never intercepts input; it skips keystrokes while Secure Input (password fields) is on or the screen is locked.
  - No anti-detection: it does not pretend to be a human and does not get around CAPTCHAs or bot detection.
- 🏠 **Privacy**: local only, with **no network access and no telemetry**. The only socket in the code is the daemon's local Unix socket, and the only programs it runs are the system's own `screencapture` (the macOS 13 fallback) and `open` (to launch apps). Recordings are saved locally with permissions 0600.
- 📦 **No dependencies**: two files (`xyzlcu` + `xyzlcu-core`), universal binaries for Apple Silicon and Intel, macOS 13+. No ChatGPT desktop app, Python, Node, Homebrew or third-party libraries needed.
- 📖 **Open source**: MIT licensed, with Chinese and English docs and the benchmark scripts in `scripts/`, so you can reproduce the results.

## Features

- 📸 **Screenshots**: a whole display, a single window (`--window`) or a region (`--region`), optional downscaling, `--fast` for a small JPEG in one flag; prints the point/pixel mapping
- 🧠 **In-memory screenshots** (v0.4.2): `--base64` / `--stdout` produce the image in memory without writing a file; the daemon keeps capture streams on demand, so repeated captures of the same window take about 20 ms
- 🚀 **Faster in v0.5.0**: a tiny C client (~3 ms per call), the main display stream pre-opened at daemon start (`--fast` ~9 ms), parallel PNG encoding (full-size PNG 171 → 31 ms), JPEG / HEIC, `--diff` returns only what changed, and an MCP `batch` tool
- ⚡ **v0.6.0**: the daemon keeps its own app table (`apps` 10 → 3 ms, `ax` 27 → 5 ms, `find` 21 → 8 ms), uncovered windows are cropped straight from the display stream (first window shot 114 → 25 ms), `ax --compact` + `click-el --ref` to save tokens, and a stale daemon restarts itself after an upgrade
- 🖱 **Mouse**: click, right-click, double-click, move, drag, scroll
- ⌨️ **Keyboard**: types Unicode text directly (Chinese, emoji; bypasses the input method), key combos like `cmd+shift+4`
- 🌳 **Accessibility tree**: dumps any app window's control tree (role, title, value, frame); `find` returns a control's frame and center by role/title, `click-el` finds and presses in one call, `wait` waits for a control to appear or disappear
- 🪟 **Apps & windows**: list, open, activate and hide apps; list windows; move and resize windows; list displays
- 🛣 **Multiple input paths** (v0.4.0): probes whether the event stream is stuck, then picks a working path among Accessibility writes, keyboard events, direct-to-process delivery and menu paste, and reports which one it used
- ⏺ **Record / replay**: listen-only recording of keyboard and mouse (never intercepts input; no keys recorded in password fields or while locked), replayed with the original timing
- 🔒 **Lock-screen guard**: refuses mouse and keyboard input while the screen is locked, so nothing gets typed into the password field
- 📊 **Measured**: a per-operation speed comparison with LCU is in [Benchmark](#benchmark-vs-lcu), with a reproducible script
- ⚡ **Resident daemon**: after `xyzlcu serve --background`, commands are forwarded to it automatically, skipping process start-up and permission checks; most commands take 2–10 ms
- 🔌 **MCP server** (v0.4.2): `xyzlcu mcp` over stdio for MCP-only clients (such as Claude Desktop); screenshots come back as images
- 🧾 **Parseable output**: JSON or a plain `ok`, plus clear exit codes

## Quick start (3 steps)

**1. Install** (pick one)

```bash
# A. Prebuilt universal binary (Apple Silicon + Intel)
mkdir -p ~/.local/bin && curl -fsSL https://github.com/brandy2015/XYZLCU/releases/latest/download/xyzlcu-macos-universal.zip -o /tmp/xyzlcu.zip \
  && unzip -o /tmp/xyzlcu.zip -d ~/.local/bin && chmod +x ~/.local/bin/xyzlcu ~/.local/bin/xyzlcu-core \
  && xattr -d com.apple.quarantine ~/.local/bin/xyzlcu ~/.local/bin/xyzlcu-core 2>/dev/null; rm -f /tmp/xyzlcu.zip

# B. Build from source (needs Xcode or the Command Line Tools)
git clone https://github.com/brandy2015/XYZLCU.git && cd XYZLCU && ./build.sh --install
```

Add `~/.local/bin` to your PATH (zsh):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**2. Grant permissions**: in System Settings > Privacy & Security, turn on Accessibility and Screen & System Audio Recording for **the app that launches the command**. See [Permissions](#permissions).

**3. Check**

```bash
xyzlcu check
# {"accessibility": true, "screenRecording": true, "screenLocked": false, "responsibleProcess": "...", ...}
```

Once both are `true`, you're ready.

Swift Package Manager works too: `swift build -c release`, which outputs into `.build/release/` (keep `xyzlcu-core` and `xyzlcu` in the same directory).

> **Two files** (since v0.5.0): `xyzlcu` is a tiny C client that forwards the command straight to the daemon when one is running (~3 ms). With no daemon, or for `mcp` / `serve` / `record` / `replay` / help, it `exec`s `xyzlcu-core` from the same directory (the Swift program that does the work; override with `XYZLCU_CORE`). Put both in `~/.local/bin`. The `macctl` symlink still points at `xyzlcu`.

## Requirements

- macOS 13 Ventura or later (built for `macos13`; tested on macOS 27)
- Apple Silicon or Intel (`build.sh` and the release produce a universal binary)
- Building from source needs Xcode or the Command Line Tools (`xcode-select --install`)

## Permissions

macOS privacy permissions (TCC) are **not granted to xyzlcu itself**. They go to the *responsible app* that launched it. If you run it from Terminal, Terminal needs the permissions. If an AI agent runs commands through some app, that app needs them.

**Find out which app needs them:**

```bash
xyzlcu whoami
```

This prints the parent process chain and `responsiblePath`. The `.app` that `responsiblePath` points to is the one to enable.

| How you run it | App that usually needs the permissions |
|---|---|
| Terminal | Terminal |
| iTerm2 | iTerm |
| VS Code / Cursor terminal | Visual Studio Code / Cursor |
| Claude Code, Codex CLI | The terminal app hosting it |
| Desktop AI assistant running remote commands | That assistant's app (check `whoami`) |

**Turn the switches on:**

1. System Settings > Privacy & Security > **Accessibility**: enable that app. Needed for clicking, typing, keys, AX tree reads, `press` and `movewin`.
2. System Settings > Privacy & Security > **Screen & System Audio Recording** (called "Screen Recording" on older macOS): enable the same app. Needed for screenshots.
3. If the app isn't in the list, click "+" and add it from Applications.
4. **Quit and reopen that app**, then run `xyzlcu check`.

`xyzlcu request` brings up both system permission prompts. XYZLCU never edits the TCC database and never tries to bypass permissions.

## Commands

| Command | Description | Example |
|---|---|---|
| `check [--probe]` | Permissions, lock status, and which input paths work (see [Multiple input paths](#multiple-input-paths-when-keyboard-events-are-blocked)) | `xyzlcu check` |
| `request` | Bring up the system permission prompts | `xyzlcu request` |
| `whoami` | Process chain and responsible app | `xyzlcu whoami` |
| `version` | Version | `xyzlcu version` |
| `screenshot [path] [--scale S] [--display N] [--format png\|jpg\|heic] [--quality Q]` | Screenshot. Format: `--format`, else the file extension, else PNG (JPEG for `--fast` and in-memory output) | `xyzlcu screenshot /tmp/s.jpg --scale 0.5` |
| `screenshot … --fast` | Fast screenshot: JPEG, quality 0.6, scale 0.5 | `xyzlcu screenshot --fast` |
| `screenshot … --window "App" [--title T]` | Capture just one app window (its frontmost window by default) | `xyzlcu screenshot /tmp/w.png --window Safari` |
| `screenshot … --window-id N` | Capture a window by the id from `windows` | `xyzlcu screenshot /tmp/w.png --window-id 1234` |
| `screenshot … --region x,y,w,h` | Capture just a region (global points) | `xyzlcu screenshot /tmp/r.png --region 100,100,400,300` |
| `screenshot … --base64` | No file: the image is base64 in the JSON `base64` field (JPEG by default when no path is given) | `xyzlcu screenshot --fast --base64` |
| `screenshot … --stdout` | No file: raw image bytes on stdout, metadata JSON on stderr | `xyzlcu screenshot --window Safari --stdout > w.jpg` |
| `screenshot … --diff` | Return only what changed since the previous capture of the same target and scale: `diff.rects` (global points) and `changedPercent`, with the image cropped to the changed area; no image when nothing changed. Daemon / MCP only | `xyzlcu screenshot --fast --diff --base64` |
| `screenshot … --out path` / `--timing` | `--out` also writes a file; `--timing` adds per-stage `timingMs` | `xyzlcu screenshot --fast --base64 --timing` |
| `displays` | Displays and their coordinate ranges | `xyzlcu displays` |
| `click x y [--right] [--double]` | Click | `xyzlcu click 500 300 --double` |
| `move x y` | Move the pointer | `xyzlcu move 800 600` |
| `drag x1 y1 x2 y2` | Drag with the left button held | `xyzlcu drag 100 100 400 400` |
| `scroll dx dy` | Scroll in lines; positive dy scrolls up | `xyzlcu scroll 0 -5` |
| `cursor` | Current pointer position | `xyzlcu cursor` |
| `type "text" [--app "App"] [--window title] [--via auto\|ax\|events\|pid\|paste]` | Type Unicode text; JSON output (`path` = path actually used, `verified` = read back and checked). Default auto picks the path | `xyzlcu type --app TextEdit --window Notes "你好 😀"` |
| `insert "App" [target] "text"` | Insert text at the focus via Accessibility (sets AXSelectedText), no keyboard events; verified by reading back | `xyzlcu insert TextEdit --window Notes "hello"` |
| `settext "App" [target] "text"` | Replace a text field's whole content via Accessibility (sets AXValue); verified by reading back | `xyzlcu settext Safari --role AXTextField --title Search "XYZLCU"` |
| `value "App" [target]` | Read back an element's value (focused element by default) to check the input | `xyzlcu value TextEdit` |
| `menu "App" "Menu>Item" [--window title] [--activate]` | Press a menu item by path (AXPress, does not activate the app by default) instead of a shortcut; each level accepts alternatives like `File\|文件` | `xyzlcu menu TextEdit "File>New"` |
| `key combo… [--app "App"] [--via auto\|events\|menu\|pid]` | Keys / combos, several at once; JSON output with the path used per key. Presses the matching menu item when the event stream is blocked | `xyzlcu key cmd+s` · `xyzlcu key --app TextEdit cmd+a` |
| `apps` | Running GUI apps | `xyzlcu apps` |
| `open "App"` | Open an app | `xyzlcu open "TextEdit"` |
| `activate "App"` | Bring an app to the front | `xyzlcu activate Finder` |
| `hide "App"` | Hide an app (like cmd+h) | `xyzlcu hide TextEdit` |
| `windows [--all]` | On-screen windows (owner, title, bounds) | `xyzlcu windows` |
| `movewin "App" x y [--w W --h H] [--title T]` | Move / resize a window and raise it | `xyzlcu movewin "Safari" 200 100 --w 1200 --h 800` |
| `ax ["App"] [--depth N] [--menu]` | Dump the UI control tree | `xyzlcu ax TextEdit --depth 6` |
| `ax ["App"] --compact [--menu] [--text] [--max 300]` | Only actionable controls: `[N] Role "title" ="value" @centerX,centerY`, for agents, few tokens | `xyzlcu ax TextEdit --compact` |
| `find "App" [--role R] [--title T] [--contains] [--index N\|--all] [--window T] [--menu]` | Find a control; returns role, title, frame, center; stops at the first hit | `xyzlcu find TextEdit --role AXButton --title Save` |
| `click-el "App" --role R --title T [--click] [--right] [--double]` | Find a control and press it (AXPress, falling back to a center click) | `xyzlcu click-el TextEdit --role AXButton --title Save` |
| `click-el --ref N ["App"]` | Press control number N from the last `ax --compact` (needs the daemon) | `xyzlcu click-el --ref 3` |
| `press "App" "title"` | Find a control by title and press it (older form; prefer `click-el` in new scripts) | `xyzlcu press TextEdit "Cancel"` |
| `wait "App" --title T [--role R] [--timeout sec] [--gone]` | Wait for a control to appear (or, with `--gone`, disappear); 5 s timeout by default | `xyzlcu wait TextEdit --role AXSheet --timeout 3` |
| `wait ms` / `sleep ms` | Fixed wait | `xyzlcu sleep 300` |
| `taps` | List system event taps (diagnose stuck or dropped input); `blocking` marks suspicious ones | `xyzlcu taps` |
| `record [--out f.jsonl] [--duration s] [--no-moves]` | Listen-only recording of keyboard and mouse, see [Record and replay](#record-and-replay) | `xyzlcu record --duration 30` |
| `replay f.jsonl [--speed N] [--no-keys] [--force]` | Replay a recording | `xyzlcu replay rec.jsonl --no-keys` |
| `run [--continue-on-error] 'cmd; cmd; …'` | Run several commands at once (split on `;` or newlines) | `xyzlcu run 'click-el TextEdit --title Save; wait TextEdit --role AXSheet; key return'` |
| `batch [--continue-on-error] [file]` | Run commands line by line from a file or stdin | `printf 'type a\nkey return\n' \| xyzlcu batch` |
| `serve [--background\|--status\|--stop]` | Start / start in background / inspect / stop the resident daemon; see [Daemon](#daemon) | `xyzlcu serve --background` |
| `mcp` | Run as a stdio MCP server; see [MCP server](#mcp-server) | `xyzlcu mcp` |

Notes:

- **App names** can be the localized name, the English bundle name (`Finder`) or the bundle ID (`com.apple.finder`).
- **Key names**: `a–z`, `0–9`, common symbols, `return`/`enter`, `tab`, `space`, `delete`/`backspace`, `forwarddelete`, `esc`, `up`/`down`/`left`/`right`, `home`/`end`/`pageup`/`pagedown`, `f1–f12`. Modifiers: `cmd`, `shift`, `opt`/`alt`, `ctrl`, `fn`.
- **`ax` output format**: `Role(Subrole) title="…" desc="…" value="…" id="…" [x,y WxH]`. The brackets hold point coordinates; the center is `(x + W/2, y + H/2)`.
- **`find` / `click-el` / `wait`**: `--title` can also be given as the second argument (`xyzlcu find TextEdit Save`). Titles match title, description, value and identifier exactly (case-insensitive); `--contains` switches to substring matching. The focused window is searched first, then the other windows; the menu bar only with `--menu`. The search stops as soon as the `--index`-th match (default 1) is found instead of walking the whole tree. Not found exits with code 4.
- **`click-el` / `press`** try AXPress first and click the control's center if that fails; `--click` (or `--right`, `--double`) forces a mouse click on the center.
- **`wait "App" …`** first checks after 20 ms and backs off to 250 ms between checks; a timeout exits with code 4.
- **`type` / `key --app "App"`**: posts the keyboard events straight to that app's process (`CGEventPostToPid`) instead of the system input stream. Text can't land in another app if focus is stolen, but you still need to confirm that app's focused window is the one you want.
- **`run` / `batch`**: quoting works like the shell (`"…"`, `'…'`, `\` escapes); lines starting with `#` are comments. By default execution stops at the first failing command, with that command's exit code, and the error names the step number; with `--continue-on-error` the remaining steps still run and the exit code is that of the last failing step (0 if all succeed). `find`, `click-el`, `wait` and `sleep` can be mixed in.
- **`--delay N`**: gap between synthesized mouse/keyboard events in ms (default 2). Raise it if a slow app drops input, e.g. `xyzlcu --delay 20 type …` or `XYZLCU_DELAY=20`.
- **Screenshots**: on macOS 14+ capture goes through ScreenCaptureKit (in-process, rendered directly at the `--scale` size; `--window` captures only that window, even when covered; `--region` only that area); otherwise, or with `--cli`, it falls back to the system `screencapture`. The `method` field tells you which path ran, and `originX/originY` is the image's top-left in global points.

## Multiple input paths (when keyboard events are blocked)

Sometimes a process's keyboard event tap hangs: keyboard events are posted but take ages to reach the app, or queue up and burst out much later, while the mouse still works. Since v0.4.0, `type` and `key` check event-stream health first, pick a path that works, and report the path actually used in the `path` field of their JSON output.

**Health check**

- Reads the system tap list (`CGGetEventTapList`): an active (not listen-only) tap with average latency above 1000 ms (`XYZLCU_TAP_THRESHOLD_MS`) is suspicious.
- Those stats are historical: a freshly hung tap still shows low numbers, while one that recovered long ago can keep showing high numbers. So the keyboard is **actively probed** every time: a tagged "right Shift up" event (no effect on any app) is posted and timed by a listen-only tap at the end of the chain; it is healthy if it gets through the whole stream within 400 ms (normally 1–30 ms). The mouse is probed only when its stats look suspicious (an in-place mouseMoved). Taps with high stats but a passing probe are listed as `staleTapStats` in `check` and treated as healthy.
- The daemon caches the result for 1.5 s; `check` always re-checks, and `check --probe` probes the mouse too. `XYZLCU_PROBE=0` disables probing (stats only).
- `XYZLCU_EVENTS_HEALTH=bad` / `good` forces blocked / healthy, for testing the fallback paths (works with the daemon too; the client forwards these variables with each request).

**The paths**

| `path` | How | Passes HID-stream taps? | App must be frontmost? | Verification |
|---|---|---|---|---|
| `ax-selected-text` | Accessibility write of the focused element's `AXSelectedText` (inserts at the caret) | No | No | Reads back `AXValue` |
| `events-hid` | CGEvents posted to the system HID stream (`type` / `key` without `--app`) | Yes | Yes | Read back within 300 ms |
| `events-pid` | `CGEventPostToPid`, delivered straight to the app process (`--app`, or `--via pid`) | No | No | Read back within 600 ms |
| `paste-menu` | Puts the text on the clipboard, AXPresses the app's Edit>Paste item, restores the clipboard after verifying | No | No | Read back |
| `menu` | `key` only: finds the menu item with the same shortcut and AXPresses it (e.g. `cmd+a` → Edit>Select All) | No | see below | — |
| `ax-menu` | The `menu` command: AXPress by menu path | No | see below | — |

**`type --via auto` (default)**

- Healthy stream: `ax` when focus is a standard text control (`AXTextField` / `AXTextArea` / `AXComboBox` / `AXSearchField`), otherwise `events`.
- Blocked stream: tries `ax` → `pid` → `paste`, verifying each by reading back and moving on only if it had no effect. It **never** uses `events-hid` while blocked, because those keystrokes would queue and burst out once the stream recovers.
- If the field can't be read back (no way to verify), it stops at the current path instead of trying another, so the same text is never entered twice.
- If no path worked: exit code 4, with each path's result in `tried`.
- If `paste` could not be verified, the clipboard is **not** restored (`clipboardRestored: false`), so a queued paste won't paste the old contents.
- `--via ax|events|pid|paste` forces one path; `XYZLCU_TYPE_VIA` changes the default.
- `--window title`: refuses (exit code 4) unless the focused element is in a window whose title contains this text, so you never type into another document.

**`key --via auto` (default)**

- Healthy stream: `events` (`events-pid` with `--app`).
- Blocked stream: first looks for a menu item with the same shortcut (matching `AXMenuItemCmdChar` / `AXMenuItemCmdModifiers` / `AXMenuItemCmdGlyph`, enabled items first) and presses it; keys with no menu item (arrows, return, …) go through `CGEventPostToPid`.
- If nothing works: exit code 4, suggesting `menu` with an explicit item. `--via events|menu|pid` forces a path; `XYZLCU_KEY_VIA` changes the default.
- Output `keys[]`: the `path` used for each combo, plus `menuItem` when a menu item was pressed.

**Menus in the background**

`menu "App" "Menu>Item" [--window title]` reads the menu bar by pid and AXPresses the item **without bringing the app to the front** (output `activated: false`, `appWasActive`). `--window` first makes that window the main window. Tested with TextEdit:

- App-level items (File>New, File>Open…) work while the app is in the background;
- Items that act on the document or the focused control (Select All, Bold, Prevent Editing, …) are disabled by Cocoa while the app is not frontmost, so pressing them does nothing and the output carries a `note`. Add `--activate` (activate first, then press), or use `insert` / `settext` / `type --via ax` instead.

**Other commands that bypass keyboard events**

```bash
xyzlcu insert TextEdit --window "My notes" "insert at the caret"           # writes AXSelectedText
xyzlcu settext TextEdit --role AXTextArea --window "My notes" "replace all"  # writes AXValue
xyzlcu value TextEdit --window "My notes"                                  # read back to verify
```

- Target: the app's focused element by default, or pick one with `--role` / `--subrole` / `--title` (or `--id`) / `--index`. `--window title` checks the element's window and refuses to write if it doesn't match.
- Every write is read back from `AXValue`; only `verified: true` counts as success, otherwise the exit code is 1.
- Native Cocoa text controls (TextEdit, Notes, most input fields) support this; some web pages and custom-drawn UIs don't, and then only `pid` / `paste` remain.

**`check` output**: `paths` lists whether events / mouse / ax / menu / pid / paste / record are usable (events and mouse include the measured `probeMs`); `typeOrder` / `keyOrder` show the order auto would try right now; `keyboardBlockedBy` lists the hung taps.

**Limits**: `events-pid`, `menu` and `paste` bypass taps on the HID stream; if the app's own main thread is stuck, no path helps. To really fix it, restart the hung process (the one with `blocking: true` in `xyzlcu taps`) or log out / reboot. XYZLCU never kills processes for you.

## Record and replay

```bash
xyzlcu record --duration 30                        # saved to ~/.xyzlcu/recordings/rec-<timestamp>.jsonl by default
xyzlcu record --out /tmp/demo.jsonl --no-moves     # skip mouse moves
xyzlcu replay /tmp/demo.jsonl --speed 2 --no-keys  # 2x speed, mouse only
```

- `record` uses a **listen-only** event tap at the end of the chain: it never intercepts, modifies or delays input, and can't block the keyboard even if it stalls. Needs Input Monitoring permission (`inputMonitoring` in `check`). Stops on Ctrl-C or after `--duration` seconds (default 60) and prints a summary.
- Records key down / up / modifier changes (with characters), mouse buttons, drags and scrolls; mouse moves at most one per 15 ms (`--no-moves` skips them). The first line is a header (version, start time, display layout).
- **Privacy**: the file is mode 0600 and stays on this Mac. Keys are **not** recorded while Secure Input (password fields) is on or the screen is locked (counted as `skippedSecureKeys`); recording stops when the screen locks. Recordings may contain what you typed, so delete them when done.
- `replay` posts the events to the HID stream with the recorded timing; `--speed` speeds it up, `--no-keys` replays only the mouse. It refuses while the event stream is blocked (replayed events would queue) unless `--force`; it stops immediately if the screen locks (exit code 3). Check the frontmost window before replaying.
- Replay posts ordinary synthetic events with the recorded timing: no random jitter, no "humanizing", and no anti-detection of any kind.

## Daemon

Every `xyzlcu` run starts a process, checks permissions and connects to the window server, about 15–50 ms. The resident daemon pays that cost once:

```bash
xyzlcu serve --background   # start it from the agent's / terminal's own shell (log: ~/.xyzlcu/serve.log)
xyzlcu serve &              # or keep it in the foreground like this
xyzlcu serve --status       # pid, version, uptime, permissions, responsible app, capture streams
xyzlcu check            # "daemon": true means commands go through the daemon
xyzlcu serve --stop     # stop it
```

- Once it's running, every command (including `run` and `batch`) is **forwarded automatically**, with identical usage and output. If the daemon can't be reached or its version differs, the command runs in-process instead.
- `XYZLCU_DAEMON=0`: never use the daemon. `XYZLCU_DAEMON=1`: require it; exits with code 5 if it can't be reached.
- **Only one daemon** (v0.5.0): `serve` first takes a file lock on `~/.xyzlcu/sock.lock`. If a daemon is already running it says so and exits 0, so running it again is harmless; a stale socket left by `kill -9` is detected and replaced. While a daemon is starting but not yet accepting, clients wait up to 3 s (`XYZLCU_CONNECT_WAIT_MS`) instead of concluding there is no daemon.
- **Protocol** (v0.5.0): images travel between client and daemon as raw length-prefixed bytes, not base64. The `--base64` JSON output and MCP still use base64. A client of a different version falls back to running in-process; `serve --stop` can stop an older daemon.
- **Stale daemon auto-restart** (v0.6.0): after an upgrade, a client that finds an older daemon stops it, restarts it in the background with the new version, and runs the command (once, about 1 s). Concurrent clients queue on a file lock at `~/.xyzlcu/sock.restart`. The new daemon inherits permissions from the process that starts it, so the restart only happens when the current process has both Accessibility and Screen Recording; otherwise you get a hint to restart it from a terminal that has them. Disable with `XYZLCU_AUTO_RESTART=0`. A client older than the daemon leaves the daemon alone and runs in-process.
- The socket is `~/.xyzlcu/sock` (directory 0700, socket 0600) and only accepts connections from the **same user** (checked with `getpeereid`). No network port is opened. Override the path with `XYZLCU_SOCKET`.
- The daemon keeps the lock-screen guard and permission checks; relative paths resolve against the caller's working directory.
- **Permissions (TCC)**: the daemon runs with the permissions of **the app that started it**, so run `xyzlcu serve --background` from the agent's or terminal's own shell; the responsible app is then the same as for direct commands. Check `responsibleProcess` in `xyzlcu serve --status`.
- **Capture streams (v0.4.2)**: the first time the daemon captures a window / display / region, it opens a ScreenCaptureKit stream for it in the background; later screenshots take the latest frame (`method: "screencapturekit-stream"`) instead of capturing again. Since v0.5.0 each scale has its own stream, scaled on the GPU (until a new scale's stream has a frame, an existing stream's frame is scaled on the CPU once). At most 4 streams at a time; a stream unused for 20 s is stopped (`XYZLCU_STREAM_IDLE=seconds`). A screenshot right after a click or typing waits for a newer frame (up to 0.12 s), so it never returns the pre-action picture. While a stream is open, macOS shows its screen-recording indicator in the menu bar; that is expected. `XYZLCU_STREAM=0` disables streams. `liveStreams` in `xyzlcu serve --status` lists the open streams.
- **Prewarm the main display (v0.5.0)**: at start-up the daemon opens full-size and half-size streams for the main display (`XYZLCU_PREWARM_SCALES=1,0.5`), so even the first screenshot takes 25–35 ms instead of 170–210 ms. **Trade-off**: while the daemon runs, the menu bar shows the screen-recording indicator; the two streams use about 45 MB of memory and the GPU does a little scaling whenever the screen changes. Prewarmed streams close after 600 s unused (`XYZLCU_PREWARM_IDLE=seconds`) and reopen on demand. To opt out: `XYZLCU_PREWARM=0 xyzlcu serve --background`.
- **PNG encoding (v0.5.0)**: a built-in multi-threaded PNG encoder (zlib level 1, bands compressed in parallel) keeps the capture's color space and embeds its ICC profile. Pixels are identical to ImageIO's output; files are somewhat larger. `XYZLCU_PNG=imageio` switches back to the system encoder, `XYZLCU_PNG_LEVEL=0-9` sets the compression level.
- **Window shots cropped from the display stream (v0.6.0)**: when a window is not covered by other windows, lies inside one display, and that display's stream is running, `--window` crops it from the stream's latest frame (`method: "display-stream-crop"`), so even the first shot of a window takes about 25 ms. The area outside the rounded corners is desktop, not transparent. Disable with `XYZLCU_WINDOW_CROP=0`.
- **App table (v0.6.0)**: the daemon keeps its own list of running apps (updated from launch / terminate / activate / hide notifications, fully refreshed at most every 10 s), so `apps` and app lookups no longer query LaunchServices process by process.
- To start it at login you can write your own LaunchAgent (`~/Library/LaunchAgents/*.plist` with `ProgramArguments` = `xyzlcu serve`). In that case the responsible process is the launchd-started xyzlcu binary itself, which then needs its own permissions in System Settings: grant them to the `xyzlcu-core` binary (and put `xyzlcu-core serve` in `ProgramArguments`). XYZLCU never installs a LaunchAgent for you.

## Worked example: write Chinese text in TextEdit and save it

```bash
# 0. Create an empty file and open it, so the typing is sure to land there
: > ~/Documents/xyzlcu-demo.txt
open -a TextEdit ~/Documents/xyzlcu-demo.txt
xyzlcu wait 1500
xyzlcu activate TextEdit

# 1. Confirm the frontmost, focused window is this file (not another document)
xyzlcu wait TextEdit --role AXWindow --title xyzlcu-demo.txt --timeout 5
xyzlcu ax TextEdit --depth 0          # the first window line should have title xyzlcu-demo.txt

# 2. Find the text area and click into it (one step)
xyzlcu click-el TextEdit --role AXTextArea --window xyzlcu-demo.txt --click

# 3. Type Chinese, a newline, then a second line
xyzlcu type "你好，这是 XYZLCU 的电脑操控测试 123"
xyzlcu key return
xyzlcu type "Second line: Unicode 😀"

# 4. Save and check the file
xyzlcu key cmd+s
cat ~/Documents/xyzlcu-demo.txt

# 5. Close the document
xyzlcu key cmd+w
```

## Supported agents

XYZLCU is **general-purpose**: it depends on no agent framework and needs no plugin. Any agent that can (1) run a shell command and (2) read its output (JSON or `ok`) and exit code can drive this Mac with XYZLCU. Clients that only speak MCP can use `xyzlcu mcp`.

| Agent / tool | How it connects | Status |
|---|---|---|
| Grok Bot | shell tool runs `xyzlcu …` | ✅ tested |
| Codex CLI | shell tool; or MCP (`~/.codex/config.toml`) | ✅ tested (0.163.0, shell), needs full access, see note below |
| OpenCode | bash tool | ✅ tested (2.0.32) |
| Your own Python / Node program | `subprocess` / `child_process`, see examples below | ✅ tested |
| Any MCP client | `xyzlcu mcp` (stdio) | ✅ tested (scripted full handshake: initialize, tools/list, tools/call, screenshot returned as an image) |
| Claude Code | Bash tool; or `claude mcp add` | should work (shell tool), not tested |
| Claude Desktop | MCP (`claude_desktop_config.json`) | should work (MCP), not tested |
| Cursor | the agent's terminal; or `.cursor/mcp.json` | should work (shell tool), not tested |
| Gemini CLI | `run_shell_command`; or `mcpServers` in `~/.gemini/settings.json` | should work (shell tool), not tested (sign-in unavailable on the test machine) |
| Cline / Roo Code | `execute_command`; or the extension's MCP settings | should work (shell tool), not tested |
| Aider | `/run xyzlcu …` | should work (shell tool), not tested |
| OpenClaw | exec / shell tool | should work (shell tool), not tested |
| Trae | terminal; or MCP settings | should work (shell tool), not tested |
| No agent at all | shell scripts, Shortcuts "Run Shell Script", cron / launchd | ✅ tested (shell scripts) |

"Tested" means the agent actually ran `xyzlcu` on the test machine (at least `check`, `cursor`, `apps` and a screenshot) and the results were checked. "Should work" means it has a shell tool, and XYZLCU behaves no differently for it than for any other caller, but it was not run here.

**Notes**

- **Permissions follow the responsible app**: Accessibility and Screen & System Audio Recording must be granted to the app that launches `xyzlcu` (Terminal, Cursor, Claude.app, …). Check with `xyzlcu whoami`. Run `xyzlcu serve --background` once in the agent's own shell; later commands and `xyzlcu mcp` are forwarded to that daemon and use its permissions.
- **Codex CLI sandbox**: in the default sandbox, commands cannot reach the window server (`xyzlcu cursor` returns `0,0`, screenshots fail). Use full access (`--sandbox danger-full-access`), or allow the command to run outside the sandbox when asked. The same applies to other sandboxed agents.
- XYZLCU cannot work when the agent runs in a sandbox or remote container that has no access to the local GUI session.

### Paste into AGENTS.md / CLAUDE.md / .cursor/rules

Copy this into your project's `AGENTS.md` (Codex, OpenCode, Gemini CLI, …), `CLAUDE.md` (Claude Code), `.cursor/rules/xyzlcu.mdc` (Cursor), `.clinerules` (Cline) or a system prompt:

```markdown
## Controlling the Mac GUI: xyzlcu

You can use the `xyzlcu` CLI to see the screen, click, type, press keys and read the UI tree.

Start
- Once per session run `xyzlcu serve --background` (makes later commands faster; running it twice is fine), then `xyzlcu check`.
- If `screenLocked` is true or a permission is missing: stop and tell the user.

Common commands (output is JSON or `ok`)
- Look: `xyzlcu find "App" --role AXButton --title Save` (returns center), `xyzlcu ax "App" --depth 6`
- Screenshot: `xyzlcu screenshot --fast --base64` (whole screen, image in the JSON `base64` field, no file),
  `xyzlcu screenshot --window "App" --base64`, `xyzlcu screenshot /tmp/s.jpg --region x,y,w,h`
- Press a control: `xyzlcu click-el "App" --role AXButton --title Save`
- Token-cheap look: `xyzlcu ax "App" --compact` lists only actionable controls (`[3] Button "Save" @612,340`), then `xyzlcu click-el --ref 3` presses by number
- Click a point: `xyzlcu click x y` (global points; convert screenshot pixels with pixelsPerPoint and originX/originY)
- Type: `xyzlcu type --app "App" --window "Window title" "text"` (check `path` and `verified` in the output)
- Keys: `xyzlcu key --app "App" cmd+s`
- Apps: `xyzlcu apps`, `xyzlcu activate "App"`
- Wait: `xyzlcu wait "App" --title T --timeout 5` (no fixed sleeps)
- Several steps: `xyzlcu run 'click-el App --title Search; type hello; key return'`
- Only what changed: `xyzlcu screenshot --fast --diff --base64` (no image when nothing changed)

Exit codes
- 0 ok; 1 bad arguments or app/element not found; 2 missing permission; 3 screen locked, action refused;
  4 control not found, wait timed out, input had no effect or --window mismatch; 5 daemon required but unreachable.

Safety rules
- Before every `type` / `key`, make sure the target app and window are frontmost (`active: true` in `xyzlcu apps`), or scope them with `--app` / `--window`.
- Loop: observe → locate → act → verify. Re-run find / screenshot after acting to confirm the result.
- Ask the user before irreversible actions such as paying, deleting, sending or submitting.
- Never use `--force` to get around the lock-screen guard.
- On a CAPTCHA, "prove you are human" or any other anti-bot check, stop and hand over to the user; do not try to get around it.
```

### Calling it from your own code

Python:

```python
import base64, json, subprocess

def xyz(*args):
    r = subprocess.run(["xyzlcu", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"xyzlcu {args[0]} failed (exit {r.returncode}): {r.stderr.strip()}")
    out = r.stdout.strip()
    return json.loads(out) if out.startswith(("{", "[")) else out

print(xyz("cursor"))                                   # {"x": …, "y": …}
shot = xyz("screenshot", "--fast", "--base64")         # no file written
jpeg = base64.b64decode(shot["base64"])
```

Node:

```js
import { execFileSync } from "node:child_process";
const xyz = (...args) => JSON.parse(execFileSync("xyzlcu", args, { encoding: "utf8" }));
console.log(xyz("cursor"));
const jpeg = execFileSync("xyzlcu", ["screenshot", "--fast", "--stdout"]); // Buffer of raw JPEG bytes; metadata JSON goes to stderr
```

### MCP server

`xyzlcu mcp` runs an MCP server over stdio (JSON-RPC 2.0, one message per line) for clients that only speak MCP and cannot run commands. Tools:

- Read-only: `check`, `screenshot` (returns the image directly, JPEG by default), `apps`, `windows`, `cursor`, `ax`, `find`
- Actions: `click_element`, `click`, `type_text`, `key`, `activate`
- Batch: `batch` (`steps` is an array of command strings, e.g. `["click-el TextEdit --title Save", "wait TextEdit --role AXSheet", "screenshot --diff"]`; one call runs them in order and returns each step's output and images; `continue_on_error` keeps going after a failure). Saves round trips and model turns; screenshot steps default to half-size JPEG
- `screenshot` accepts `diff: true` to return only the changed area
- Generic: `xyzlcu` (an `args` array, runs any subcommand except `mcp`, `serve`, `record`, `replay`, `batch` and `--stdout`)

When a daemon is running, every tool call is forwarded to it; otherwise `xyzlcu mcp` itself is the long-lived process (it keeps capture streams too), so no new process is started per call.

Replace `/Users/you/.local/bin/xyzlcu` below with the output of `which xyzlcu` (many clients do not expand `~`).

Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`), Cursor (`.cursor/mcp.json` in a project or `~/.cursor/mcp.json`) and Gemini CLI (`~/.gemini/settings.json`) all use this format:

```json
{
  "mcpServers": {
    "xyzlcu": {
      "command": "/Users/you/.local/bin/xyzlcu",
      "args": ["mcp"]
    }
  }
}
```

Claude Code:

```bash
claude mcp add xyzlcu -- "$(which xyzlcu)" mcp
```

Codex CLI (`~/.codex/config.toml`):

```toml
[mcp_servers.xyzlcu]
command = "/Users/you/.local/bin/xyzlcu"
args = ["mcp"]
```

Try the handshake yourself:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | xyzlcu mcp
```

- The MCP server is launched by the client app, so the system permissions must be granted to **that app** (e.g. Claude.app, Cursor). Or run `xyzlcu serve --background` first in an authorized terminal; MCP calls are then forwarded to it and use its permissions.
- When the client asks whether to allow a tool, decide by how much you trust it; the action tools (`click`, `type_text`, `key`, …) really operate your computer.

## Benchmark (vs LCU)

**Where LCU still has the edge** (up front):

- **Background operation**: LCU clicks and types without moving the real mouse or bringing the app to the front, so you can keep using the computer. XYZLCU's `click` / `type` really move the mouse and need the app in front. XYZLCU's paths that leave the foreground alone are `click-el` (AXPress), `type --app`, `menu` and `insert` / `settext`, but not every app supports them.
- **Working with the model**: LCU sits on ChatGPT's CUA runtime, organizes actions per app, and is more tightly integrated with ChatGPT / Codex. The tables below compare single-operation latency only, not the ability to finish a whole task.

### 0.6.0 vs 0.5.0

Same machine, with a 0.5.0 daemon and a 0.6.0 daemon running at the same time on different sockets and called **alternately**, 21 runs each, **median / p90** in ms. Alternating removes system-load drift (two rounds of the same version can differ by 20%).

| Operation | 0.5.0 | **0.6.0** |
|---|---:|---:|
| List apps (`apps`) | 9.5 / 9.9 | **3.2 / 3.5** |
| List windows (`windows`) | 3.4 / 7.0 | 3.3 / 4.4 |
| Control tree (`ax TextEdit`, focused window) | 26.9 / 28.1 | **5.3 / 7.5** |
| Control tree with menus (`ax Finder --menu`) | 52.1 / 53.7 | **23.0 / 23.9** |
| `find` hits the text area | 20.6 / 23.3 | **7.9 / 11.0** |
| `find` miss (searches the whole tree) | 26.9 / 30.9 | **12.9 / 14.9** |
| Window shot (covered window, stream open) | 14.7 / 16.0 | **6.2 / 6.8** |
| Window shot (frontmost window, stream open) | 17.2 / 38.6 | **6.4 / 19.9** |
| Full screen `--fast` | 8.9 / 25.8 | 8.9 / 18.5 |
| **First** shot of a window (not covered, main display prewarmed; 8 runs) | 113.6 / 128.1 | **25.3 / 31.2** |
| **First** shot of a window (covered; 8 runs) | 98.3 / 120.6 | 82.1 / 88.6 |

Size of `ax --compact` output (same windows):

| | `ax` | `ax --compact` |
|---|---:|---:|
| TextEdit window | 740 bytes / 11 lines | **243 bytes / 4 lines** |
| TextEdit window + menu bar (`--menu`) | 9209 bytes / 153 lines | **513 bytes / 12 lines** |
| Finder + menu bar (`--menu`) | 13680 bytes / 224 lines | **401 bytes / 11 lines** |

**Where the time went and what changed (honestly)**

- **The biggest bottleneck was NSRunningApplication**: sampling the daemon showed `apps` spending almost all of its time in synchronous `_LSCopyApplicationInformation` XPCs. `NSWorkspace.runningApplications` returns fresh objects every time, and the first property read on each one (even `processIdentifier`) asks LaunchServices, about 8–15 ms for 140 processes. A per-pid cache does not help (reading the pid is the slow part), so the daemon now keeps its own app table. `find`, `ax` and window screenshots all look up the app first, so they all got faster.
- **Control tree**: 6–8 IPCs per control became one `AXUIElementCopyMultipleAttributeValues`.
- **First window capture**: it used to take an `SCScreenshotManager` grab (~55 ms) and then open a window stream. Now, if the window is not covered, lies inside one display, and that display's stream is running (the daemon prewarms the main display by default), the window is cropped from the latest display frame. Covered windows keep the old path (~80 ms), since a crop would include whatever is in front. The coverage check ignores non-normal-layer windows that fill a whole display (the Dock, full-screen transparent overlays); otherwise every window would count as covered.
- **Not changed**:
  - The ~13 ms fixed cost of an in-process call (no daemon) is loading the Swift runtime and AppKit and friends; code cannot remove it. The answer is the daemon + C client (3 ms).
  - `--fast` already gets small frames straight from the GPU, ~9 ms, mostly encoding and transfer.
  - Prewarmed streams stay at 60 fps: idle, the daemon uses about 1.9% of one core and 9.6 MB (only for 10 minutes after the last screenshot). A lower frame rate would make post-click screenshots wait longer; not worth it.
  - Multiple `--stdout` images in one `run` are not returned together (stdout can carry only one binary blob); this is now a clear error. Use `-o` files or MCP `batch` for several images.

### 0.5.0 vs 0.4.2 and LCU
**Setup**: Apple Silicon Mac (macOS 26+). XYZLCU 0.5.0 vs 0.4.2 and [LCU](https://github.com/amontlabs/lcu) 0.13.4 (the CUA runtime 0.0.35 shipped with ChatGPT). 15 runs per operation; the table shows **median / p90** in milliseconds. The LCU column comes from the 0.4.2 round on the same machine (LCU was not reinstalled this time).

| Operation | 0.5.0 in-process | **0.5.0 daemon** | 0.4.2 daemon | LCU (MCP `js` call) |
|---|---:|---:|---:|---:|
| Version (`version`, ~empty call) | 8 / 11 | **3 / 3** | 8 / 9 | — |
| List apps (`apps` / `cua.listApps`) | 18 / 19 | **10 / 10** | 15 / 18 | 17 / 18 |
| List windows (`windows`) | 57 / 68 | **3 / 3** | 7 / 11 | — (not on Mac) |
| Pointer position (`cursor`) | 28 / 32 | **2 / 2** | 6 / 6 | — (not on Mac) |
| Move pointer (`move`) | 68 / 75 | **2 / 4** | 7 / 10 | — (not on Mac) |
| Full screenshot (full-size PNG, to file) | 223 / 248 | **31 / 34** | 171 / 180 | — (not on Mac) |
| Full screenshot (full-size JPEG, to file) | 214 / 226 | **30 / 33** | 48 / 50 | — (not on Mac) |
| Full screenshot (full-size HEIC, to file) | — | 98 / 103 | — | — (not on Mac) |
| Full screenshot (half-size PNG, to file) | 199 / 212 | **12 / 15** | 50 / 52 | — (not on Mac) |
| Full screenshot (`--fast`, half-size JPEG, to file) | 202 / 212 | **9 / 10** | 13 / 72 | — (not on Mac) |
| Full screenshot (`--fast --base64`, in memory) | 192 / 199 | **10 / 10** | 20 / 24 | — (not on Mac) |
| Full screenshot (`--fast --stdout`, in memory) | 194 / 206 | **9 / 9** | 18 / 20 | — (not on Mac) |
| Full screenshot (`--fast --diff --base64`) | — | **9 / 15** | — | — (not on Mac) |
| Window screenshot (TextEdit window, PNG to file) | 202 / 228 | **17 / 103** | 26 / 86 | 51 / 53 |
| Window screenshot (`--window … --base64`, in memory) | 203 / 220 | **18 / 24** | 24 / 32 | 51 / 53 |
| UI tree (`ax --depth 3` / `getAXState`) | 64 / 76 | **20 / 22** | 32 / 47 | 55 / 76 |
| Click (`click`) | 59 / 69 | **6 / 9** | 11 / 16 | 140 / 166 |
| Type ASCII `abc` | 85 / 113 | **5 / 9** | 10 / 14 | 43 / 48 |
| Type Chinese `你好abc` | 109 / 121 | **7 / 10** | 10 / 14 | 9057 / 10541 |
| Key (`cmd+right` / `super+Right`) | 71 / 87 | **4 / 11** | 10 / 14 | 14 / 19 |
| 3 separate calls (`cursor`, `--fast` screenshot, `windows`) | 271 / 283 | 17 / 20 | 41 / 44 | — |
| The same 3 steps in one `run` | 195 / 207 | **12 / 15** | 25 / 26 | — |

**Other measurements** (0.5.0, daemon)

| Item | 0.4.2 | 0.5.0 |
|---|---:|---:|
| First `--fast` screenshot 1.5 s after a daemon restart | 190–220 | **24–37** (prewarmed); 173–213 with `XYZLCU_PREWARM=0` |
| One forwarded call (`cursor`, median of 30) | 6 (Swift client) | **3.1** (C client; `/usr/bin/true` alone is 1.6) |
| MCP: `cursor` + `screenshot` + `windows` as 3 tool calls vs one `batch` | — | 16.1 vs 15.8 |
| MCP `screenshot` (half-size JPEG, returned as an image) | — | 11–12 |
| MCP `screenshot` with `diff: true`, screen unchanged | — | 3–4 (no image) |

**Method**

- **XYZLCU**: each sample is a full CLI invocation (process start → run → JSON output), which is what an agent actually pays when calling it from a shell. "In-process" = `XYZLCU_DAEMON=0`; "daemon" = after `xyzlcu serve`. In-process runs first, then the daemon is started (see the screenshot item under [Troubleshooting](#troubleshooting)).
- **LCU**: installed into a temp directory (no system changes, no agent config changes) and driven through LCU's own `adapters/client.mjs` over stdio MCP. Each sample is one `js` tool call such as `await app.click([x, y])` or `await app.typeText("abc")`, timed as a round trip **on an already-connected client**. Connecting (~270 ms), the first call (~520 ms) and `getApp` (~70 ms) are excluded, as is the agent's own time to produce a tool call.
- "3 separate calls" are three CLI invocations; "one `run`" is `xyzlcu run 'cursor; screenshot --fast; windows'`.
- **GUI operations** all target a temporary TextEdit document. Before every input the script checks that TextEdit is frontmost and the document is its front window; at the end it reads the document back (both tools typed the right text), then closes and deletes it. LCU asks for approval the first time it touches TextEdit; the benchmark only answers "this session".

**Reading the numbers (honestly)**

- **Forwarding overhead is down to 2–3 ms**: with a daemon running, `xyzlcu` is a tiny C program that connects to the socket, sends the request, writes the reply out and exits, without loading the Swift runtime and system frameworks. Queries, clicks, typing and keys are roughly twice as fast as 0.4.2.
- **Full-size PNG 171 → 31 ms**: the cost was encoding, not capturing. 0.4.2 used ImageIO, single-threaded and with a color-space conversion first; 0.5.0 compresses in parallel, keeps the original color space and embeds the ICC profile. Pixels are identical to ImageIO's; files are somewhat larger.
- **`--fast` is ~9 ms, even the first time**: every scale gets its own ScreenCaptureKit stream scaled on the GPU, and the daemon pre-opens the main display at full and half size. Scaling a full-size frame on the CPU did not help: just reading a 4112×2658 IOSurface (44 MB) takes ~11 ms, so the GPU now produces the small image directly.
- **HEIC is slower than JPEG** (98 vs 30 ms full size) but smaller. Use HEIC to save bandwidth / tokens, JPEG for speed.
- **Window screenshot p90 is high (103 ms)**: the first capture of a window in each round sets up a stream; after that it is 17–18 ms.
- **`run` / MCP `batch` save round trips**: on the CLI, 3 calls take 17 ms and one `run` 12 ms. MCP is already connected to the daemon, so 3 tool calls and one `batch` cost about the same (16.1 vs 15.8 ms). What MCP `batch` really saves is the model's turns between tool calls (typically hundreds of ms to seconds each), which this table does not include.
- **`--diff`**: when nothing changed the reply is a small JSON (3–4 ms, no image); otherwise only the changed area is returned. That saves the most tokens for agents that keep "taking a look".
- In-process (no daemon) is about the same as 0.4.2; the time goes to process start-up and connecting to the window server. It is 1–2 ms slower than 0.4.2 because the C client `exec`s `xyzlcu-core`.
- **LCU's click is slower (140 ms) but it is background delivery**: it does not move the real pointer or bring the app to the front, so the user can keep working. XYZLCU's `click` really moves the pointer. For background work XYZLCU has `click-el` (AXPress), `type --app`, `menu`, and `insert` / `settext`.
- **LCU types Chinese very slowly**: `你好abc` has a ~9 s median, while plain ASCII takes 43 ms. XYZLCU sends Unicode directly or writes via Accessibility, so both are equally fast.
- **"—" in the LCU column means LCU has no such capability on Mac** (no pointer position/move, no full-screen screenshot, no window list; it works per app). It does not mean the test was skipped.
- This compares single-operation latency only, not the ability to finish whole tasks. LCU sits on ChatGPT's CUA runtime and has strengths in model integration and background operation.

**Usability differences**

| | XYZLCU | LCU |
|---|---|---|
| Needs | One binary, macOS 13+, Apple Silicon or Intel | The ChatGPT desktop app installed (it uses its CUA runtime), Apple Silicon; bundles Node |
| Integration | Anything that can run shell commands; or `xyzlcu mcp` | MCP server (`lcu setup --agent …` writes agent configs) |
| Approval | System Accessibility and Screen & System Audio Recording for the responsible app | On top of system permissions, each app needs approval the first time (this session / always) |
| Interaction model | Global coordinates + real input events, plus Accessibility, direct-to-process and menu paths that avoid keyboard events | Per app; coordinates are pixels in the window screenshot; background delivery |
| Output | JSON; screenshots to files, or in memory with `--base64` / `--stdout`; images directly over MCP | Tool results carry the image |

**Reproduce**

```bash
python3 scripts/bench.py ~/.local/bin/xyzlcu --runs 15            # XYZLCU only (in-process + daemon)
python3 scripts/bench.py ~/.local/bin/xyzlcu --runs 15 --gui      # plus click/type/key (opens a temporary TextEdit doc)
python3 scripts/bench.py ~/.local/bin/xyzlcu --runs 15 --gui \
    --lcu /path/to/lcu --lcu-allow-session --json bench.json       # also LCU (needs LCU and the ChatGPT desktop app)
```

`--mode inproc|daemon` runs one mode only. Without `--lcu-allow-session`, the script declines LCU approval requests, so operations that need approval report no numbers; the script never chooses "always". For clean in-process screenshot numbers, run `xyzlcu serve --stop` first.

<details>
<summary>v0.4.2 comparison</summary>

**Setup**: Apple Silicon Mac (macOS 26+). XYZLCU 0.4.2 vs [LCU](https://github.com/amontlabs/lcu) 0.13.4 (the CUA runtime 0.0.35 shipped with ChatGPT). 15 runs per operation; the table shows **median / p90** in milliseconds; the last column is the 0.4.1 daemon median on the same machine.

| Operation | XYZLCU in-process | XYZLCU daemon | LCU (MCP `js` call) | 0.4.1 daemon |
|---|---:|---:|---:|---:|
| Version (`version`, ~empty call) | 6 / 7 | 7 / 12 | — | 10 |
| List apps (`apps` / `cua.listApps`) | 15 / 19 | **13 / 13** | 17 / 18 | 17 |
| List windows (`windows`) | 44 / 52 | **9 / 18** | — (not on Mac) | 7 |
| Pointer position (`cursor`) | 26 / 32 | **8 / 11** | — (not on Mac) | 6 |
| Move pointer (`move`) | 55 / 73 | **9 / 19** | — (not on Mac) | 7 |
| Full screenshot (full-size PNG, to file) | 352 / 361 | 180 / 200 | — (not on Mac) | 233 |
| Full screenshot (`--fast`, half-size JPEG, to file) | 184 / 200 | **13 / 75** | — (not on Mac) | 60 |
| Full screenshot (`--fast --base64`, in memory) | 192 / 208 | **21 / 23** | — (not on Mac) | — |
| Window screenshot (TextEdit window, PNG to file) | 199 / 207 | **35 / 72** | 51 / 53 | 68 |
| Window screenshot (`--window … --base64`, in memory) | 185 / 199 | **23 / 27** | 51 / 53 | — |
| UI tree (`ax --depth 3` / `getAXState`) | 66 / 69 | **26 / 29** | 55 / 76 | 28 |
| Click (`click`) | 56 / 74 | **12 / 19** | 140 / 166 | 12 |
| Type ASCII `abc` | 82 / 93 | **13 / 17** | 43 / 48 | 12 |
| Type Chinese `你好abc` | 82 / 116 | **13 / 18** | 9057 / 10541 | 14 |
| Key (`cmd+right` / `super+Right`) | 78 / 98 | **10 / 13** | 14 / 19 | 8 |

</details>

<details>
<summary>v0.4.1 comparison</summary>

**Setup**: Apple Silicon Mac (macOS 26+). XYZLCU 0.4.1 vs [LCU](https://github.com/amontlabs/lcu) 0.13.4 (the CUA runtime 0.0.35 shipped with ChatGPT). 15 runs per operation; the table shows **median / p90** in milliseconds.

| Operation | XYZLCU in-process | XYZLCU daemon | LCU (MCP `js` call) |
|---|---:|---:|---:|
| Version (`version`, ~empty call) | 5 / 6 | 10 / 18 | — |
| List apps (`apps` / `cua.listApps`) | 14 / 16 | 17 / 18 | 14 / 16 |
| List windows (`windows`) | 52 / 63 | **7 / 8** | — (not on Mac) |
| Pointer position (`cursor`) | 27 / 35 | **6 / 6** | — (not on Mac) |
| Move pointer (`move`) | 54 / 65 | **7 / 10** | — (not on Mac) |
| Full-screen screenshot (full-size PNG) | 354 / 367 | 233 / 250 | — (not on Mac) |
| Full-screen screenshot (`--fast`, half-size JPEG) | 190 / 196 | 60 / 68 | — (not on Mac) |
| Window screenshot (TextEdit window) | 198 / 210 | 68 / 78 | **47 / 51** |
| UI tree (`ax --depth 3` / `getAXState`) | 66 / 71 | **28 / 47** | 49 / 70 |
| Click (`click`) | 54 / 63 | **12 / 14** | 135 / 175 |
| Type `abc` | 87 / 118 | **12 / 14** | 41 / 45 |
| Type `你好abc` (Chinese) | 87 / 115 | **14 / 16** | 9060 / 10560 |
| Key (`cmd+right` / `super+Right`) | 73 / 96 | **8 / 14** | 14 / 24 |

In 0.4.1 every screenshot was captured from scratch, encoded as PNG and written to a file, so window capture was slower than LCU (68 vs 47 ms).

</details>

<details>
<summary>Earlier versions (v0.2.0 → v0.3.0)</summary>

v0.3.0 adds the resident daemon (`serve`), window and region screenshots, `--fast`, `find` / `click-el` / `wait` (an early-exit control search that fetches several attributes per IPC call), and `run --continue-on-error`.

Medians of 15 runs per command from `scripts/bench.py` on an Apple Silicon Mac (macOS 26+):

| Command | v0.2.0 | v0.3.0 | v0.3.0 + daemon |
|---|---:|---:|---:|
| `check` | 31 ms | 29 ms | 22 ms |
| `apps` | 17 ms | 16 ms | 14 ms |
| `windows` | 50 ms | 52 ms | **9 ms** |
| `cursor` | 29 ms | 28 ms | **7 ms** |
| `move` | 63 ms | 60 ms | **9 ms** |
| `ax Finder --depth 3` | 48 ms | 49 ms | **16 ms** |
| `find Finder --role AXMenuBarItem --menu --index 2` | — | 47 ms | **12 ms** |
| `screenshot` (full 4112×2658 PNG) | 503 ms | 499 ms | 382 ms |
| `screenshot --scale 0.5` (PNG) | 250 ms | 266 ms | 136 ms |
| `screenshot --scale 0.5 --format jpg` | 190 ms | 194 ms | 71 ms |
| `screenshot --fast` | — | 202 ms | **67 ms** |
| `screenshot --region 100,100,400,300` | — | 184 ms | **60 ms** |
| `screenshot --window` (960×660 pt window, `--scale 0.5`) | — | 212 ms | **80 ms** |

Without the daemon, v0.3.0 is on par with v0.2.0 (within measurement noise); most of the time is process start-up. With the daemon running, query commands drop to 7–22 ms and screenshots get 1.3–3× faster (ScreenCaptureKit is already initialized, and the display/window lists are cached). The v0.2.0 gains over v0.1.0 (`type` of 128 chars 222 → 73 ms, screenshots 750 → 251 ms, and so on) are listed in the v0.2.0 release notes.

</details>

## Coordinate system

- All coordinates are **global points**, with the origin at the **top-left of the main display**; x grows to the right and y grows downward.
- **Points vs pixels**: on Retina displays 1 point = 2 pixels. Screenshots are in pixels, while `click` takes points. `screenshot` prints `pixelsPerPoint`, so `point = pixel / pixelsPerPoint`.
- **`--scale`**: on a 2x display, `--scale 0.5` makes image pixels equal points. It's the simplest option and gives smaller images.
- **Multiple displays**: `xyzlcu displays` lists each display's `x, y, w, h` (a secondary display can have negative x or y). `screenshot --display 2` captures display 2, and the output's `originX/originY` is that display's top-left in global coordinates: `global x = originX + pixelX / pixelsPerPoint`.
- To bring a window back from another display: `xyzlcu movewin "App" 200 100`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Bad arguments, or app / element / display not found |
| 2 | Missing permission (Accessibility or Screen Recording) |
| 3 | Screen is locked; mouse/keyboard input refused |
| 4 | `find` / `click-el` found no control, `wait` timed out, `type` / `key` found no working input path, or the `--window` guard refused |
| 5 | `XYZLCU_DAEMON=1` is set but the daemon can't be reached |

## Troubleshooting

**Screenshot is black, or shows only the desktop with no windows?**
- Black: the screen is probably locked. Check `screenLocked` in `xyzlcu check`.
- Only the desktop and menu bar: the responsible app lacks Screen & System Audio Recording.
- Some windows are missing: they may be on another Space or another display; try `--display 2`.

**Clicks or typing do nothing?**
- Accessibility isn't granted to the right app. Run `xyzlcu whoami`, enable the app shown in `responsiblePath`, then restart that app.
- After changing permissions or updating the app, you may need to toggle the switch off and on again.
- Input shows up late or characters go missing: run `xyzlcu taps`. A process with `listenOnly: false` and a large `avgLatencyMs` (hundreds of ms or more) is holding up input events; common culprits are Screen Sharing (RFBEventHelperd), voice assistants or other computer-use tools. Quit or restart it and try again.
- If an app can't keep up with fast input, widen the gap: `xyzlcu --delay 20 type …`.
- Keyboard does nothing at all while the mouse works: an event tap that intercepts keyboard events is probably hung (`xyzlcu check` shows `paths.events.healthy: false`, and `xyzlcu taps` marks it `blocking: true`). `type` / `key` automatically switch to Accessibility, direct-to-process or menu paths (see [Multiple input paths](#multiple-input-paths-when-keyboard-events-are-blocked)). To fully recover, quit or restart that process (often Siri or Screen Sharing's RFBEventHelperd), or log out and back in.

**Daemon issues**
- `daemon` stays false in `check`: the daemon isn't running, or it's an older version (on a version mismatch commands run in-process). Run `xyzlcu serve --status`.
- Permissions are false inside the daemon: it was started from a different app. Run `xyzlcu serve --stop`, then `xyzlcu serve --background` again from the authorized terminal / agent shell.
- After updating xyzlcu, run `xyzlcu serve --stop` and start it again. (a version mismatch falls back to in-process automatically).
- An in-process screenshot (`XYZLCU_DAEMON=0`) takes ~2 s and has a `warning`: while a daemon of the same xyzlcu binary is running, macOS does not deliver in-process ScreenCaptureKit callbacks, so XYZLCU waits 1.5 s and falls back to `screencapture`. Drop `XYZLCU_DAEMON=0` and go through the daemon (9–31 ms).
- When replacing the binary yourself, write to a temp file and `mv` it into place (`build.sh --install` does this); overwriting a signed binary that is in use with `cp` can get new processes killed by the system (exit code 137).

**Does a Chinese input method get in the way?**
- `type` sends Unicode characters directly and bypasses the input method, so the right text comes out even with a Chinese IME active.
- `key` sends physical keystrokes, though: a bare letter with the IME in Chinese mode opens the candidate window. Shortcuts (`cmd+…`) are unaffected.

**`ax` prints nothing or is slow?**
- Some apps (games, some Electron apps) have poor accessibility support. Lower `--depth`, or locate targets with screenshots instead.
- Each app request times out after 3 seconds, and output is capped at 3000 nodes.

**Keys went to the wrong window?**
- Keyboard events go to the frontmost app. `activate` first, then confirm with `apps`.

## Safety

- With Accessibility permission, anything can be clicked or typed. Use it only where you trust the setup, and turn the switch off when you don't need it.
- **Always confirm the frontmost app before `type` / `key`.** Otherwise text can land in another document, and a shortcut can close another window.
- **Lock-screen guard**: while the screen is locked, `click / move / drag / scroll / type / key` refuse to run and exit with code 3. `--force` overrides this but isn't recommended.
- **Recordings may contain what you typed**: they stay on this Mac (mode 0600), and no keys are recorded in password fields or while locked; delete them when done and don't share them. Check the frontmost window before `replay`, `type` or `key`.
- Don't let an agent auto-confirm payment, deletion or sending dialogs.
- XYZLCU makes no network connections, collects no data, and never modifies the system permission database. The daemon only listens on a local Unix socket and only accepts the same user.
- **No detection evasion**: XYZLCU sends ordinary synthesized mouse and keyboard events. It doesn't pretend to be a human, randomize timing, or get around captchas or websites' bot detection. When an agent hits a captcha, an "are you human" check or any other anti-bot check, it should stop and hand it to a person.

## Limitations

- macOS only, and only the logged-in user's GUI session. Nothing works while the screen is locked, and screenshots come out black.
- On macOS 13 there is no ScreenCaptureKit capture; it falls back to `/usr/sbin/screencapture` (`-l windowID` for `--window`, `-R` for `--region`).
- `press` matches the title, description, value or identifier exactly (case-insensitive) and takes the first match; use `find` / `click-el` with `--role`, `--index` and `--window` to be more precise.
- `type` bypasses the input method, so it doesn't suit cases that need IME suggestions.
- No management of windows on other Spaces (desktops).
- The daemon's app table is refreshed at most every 10 s: a background process that becomes a regular app without being activated can take up to 10 s to show up in `apps` (looking an app up by name rescans immediately on a miss, so that is not affected).
- A window shot cropped from the display stream shows the desktop outside the rounded corners instead of transparency. Covered windows, windows spanning displays, or displays without a running stream fall back to capturing the window on its own.

## Uninstall

```bash
xyzlcu serve --stop 2>/dev/null
rm -f ~/.local/bin/xyzlcu ~/.local/bin/xyzlcu-core ~/.local/bin/macctl
rm -rf ~/.xyzlcu
```

Then, in System Settings > Privacy & Security, turn off or remove any apps you no longer need under Accessibility and Screen & System Audio Recording.

> To keep using the old name: `ln -sf ~/.local/bin/xyzlcu ~/.local/bin/macctl`

## Changelog

- **0.6.0**: faster daemon queries and a far smaller control listing for agents.
  - **App table**: the daemon keeps its own table of running apps (updated from launch / terminate / activate / hide notifications, fully refreshed at most every 10 s) instead of asking LaunchServices about every process on every call. `apps` 9.5 → 3.2 ms; `ax` / `find` / `click-el` / `press` / window screenshots each save 6–10 ms.
  - **Batched AX reads**: `ax` fetches all attributes of a control in one IPC (TextEdit window 27 → 5 ms, `ax Finder --menu` 52 → 23 ms).
  - **`ax --compact`**: lists only actionable controls, one line each with a number and center point; `click-el --ref N` presses by number (needs the daemon). `ax Finder --menu` 13.7 KB → 0.4 KB. The MCP `ax` tool gains `compact` / `menu` / `text` / `max`, and `click_element` gains `ref`.
  - **Window shots cropped from the display stream**: when the window is not covered, crop it from the latest frame of the always-on display stream; first capture of a window 114 → 25 ms (`method: "display-stream-crop"`, disable with `XYZLCU_WINDOW_CROP=0`). New `--window-id N` (MCP `window_id`).
  - **Stale daemon auto-restart**: after an upgrade, a client that finds an older daemon stops it and restarts it with the new version (only when the current process has both Accessibility and Screen Recording; `XYZLCU_AUTO_RESTART=0` disables). The first call takes about 1 s longer.
  - Fixes: when a version mismatch fell back to in-process execution, a `batch` script read from stdin was lost; in `run` / `batch`, a second `--stdout` image silently overwrote the first, now it is a clear error.
- **0.5.0**: a speed overhaul.
  - **Tiny C client**: `xyzlcu` is now a small C program that forwards straight to the daemon (empty call 8 → 3 ms) and otherwise `exec`s `xyzlcu-core` from the same directory. Permission attribution is unchanged (still the app that launched it). Installs now have one more file, `xyzlcu-core`.
  - **Screenshot encoding**: parallel PNG encoding (full size 171 → 31 ms, ICC profile kept), new `--format heic`; format is `--format` > file extension > default (JPEG for `--fast` / in-memory, PNG otherwise).
  - **Prewarm**: the daemon pre-opens full- and half-size streams of the main display at start-up (first screenshot 190–220 → 24–37 ms); `XYZLCU_PREWARM=0` turns it off, `XYZLCU_PREWARM_SCALES` / `XYZLCU_PREWARM_IDLE` tune it. One stream per scale, scaled on the GPU.
  - **Binary protocol**: images travel between client and daemon as raw length-prefixed bytes instead of base64; the external JSON / MCP output is unchanged.
  - **Batching**: new MCP `batch` tool; a 3-step `run` went 25 → 12 ms.
  - **`--diff`**: return only the changed area (CLI and MCP; needs the daemon or MCP).
  - **Daemon start-up**: a file lock guarantees a single daemon, a repeated `serve` exits 0, a stale socket left by `kill -9` is handled, new `serve --background`; `serve --stop` can stop older versions.
  - Fix: an unknown `--option` is no longer taken as the screenshot file name.
- **0.4.2**: faster screenshots that can stay in memory: `--base64` / `--stdout` / `--out` / `--timing`; the daemon keeps ScreenCaptureKit capture streams on demand (window capture 68 → 23–35 ms, faster than LCU's 51 ms), caches the screen-recording permission check and the window content list, and input read-back polls every 5 ms. New `xyzlcu mcp` (stdio MCP server, 13 tools, screenshots returned as images). New [Supported agents](#supported-agents) section. Fix: the daemon no longer exits with SIGPIPE when a client connects and disconnects without sending a request (e.g. a liveness probe).
- **0.4.1**: in-process screenshots pump the main run loop while waiting for ScreenCaptureKit; a callback timeout is waited out once (1.5 s), then it falls back to `screencapture` with a `warning` instead of stalling for 10+ s. `apps` in the daemon no longer waits a fixed 20 ms (42 → 17 ms). New LCU comparison benchmark (`scripts/bench.py --lcu`, `scripts/bench_lcu.mjs`).
- **0.4.0**: multiple input paths (Accessibility writes, direct-to-process, menus, paste), event-stream health checks, `insert` / `settext` / `value` / `menu` / `taps`, listen-only record and replay.
- Older versions: see [Releases](https://github.com/brandy2015/XYZLCU/releases).

## Acknowledgements

XYZLCU is inspired by and borrows ideas from **[LCU (Local Computer Use)](https://github.com/amontlabs/lcu)** by Amont Labs: letting any local agent see the screen, click and type, locating things with screenshots plus the accessibility tree, and the "Local Computer Use" name itself. Many thanks to Amont Labs for open-sourcing LCU.

XYZLCU is an independent implementation and contains no LCU code. LCU is released under the MIT License, Copyright (c) 2026 Amont Labs.

## License

[MIT](LICENSE) © 2026 XYZTech
