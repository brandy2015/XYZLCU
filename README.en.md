# XYZLCU

[中文](README.md) | **English**

**XYZLCU (XYZ Local Computer Use)** is a dependency-free macOS GUI control CLI. Anything that can run shell commands, whether an AI agent (Claude Code, Codex, any shell-capable agent) or your own script, can use it to see the screen, click, type, press shortcuts, read the UI structure and press buttons. It is a single Swift source file compiled into a single binary: no Python, no Node, no Homebrew, no third-party libraries.

> Inspired by the idea behind [amontlabs/lcu](https://github.com/amontlabs/lcu), but an **independent implementation**: it shares no code and does **not** need the ChatGPT / Codex desktop app or its runtime.

## Features

- 📸 **Screenshots**: a whole display, a single window (`--window`) or a region (`--region`), optional downscaling, `--fast` for a small JPEG in one flag; prints the point/pixel mapping
- 🖱 **Mouse**: click, right-click, double-click, move, drag, scroll
- ⌨️ **Keyboard**: types Unicode text directly (Chinese, emoji; bypasses the input method), key combos like `cmd+shift+4`
- 🌳 **Accessibility tree**: dumps any app window's control tree (role, title, value, frame); `find` returns a control's frame and center by role/title, `click-el` finds and presses in one call, `wait` waits for a control to appear or disappear
- 🪟 **Apps & windows**: list, open, activate and hide apps; list windows; move and resize windows; list displays
- 🔒 **Lock-screen guard**: refuses mouse and keyboard input while the screen is locked, so nothing gets typed into the password field
- ⚡ **Resident daemon**: after `xyzlcu serve &`, commands are forwarded to it automatically, skipping process start-up and permission checks; most commands take 7–20 ms
- 🧾 **Parseable output**: JSON or a plain `ok`, plus clear exit codes

## Quick start (3 steps)

**1. Install** (pick one)

```bash
# A. Prebuilt universal binary (Apple Silicon + Intel)
mkdir -p ~/.local/bin && curl -fsSL https://github.com/brandy2015/XYZLCU/releases/latest/download/xyzlcu-macos-universal.zip -o /tmp/xyzlcu.zip \
  && unzip -o /tmp/xyzlcu.zip -d ~/.local/bin && chmod +x ~/.local/bin/xyzlcu && xattr -d com.apple.quarantine ~/.local/bin/xyzlcu 2>/dev/null; rm -f /tmp/xyzlcu.zip

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

Swift Package Manager works too: `swift build -c release`, which outputs `.build/release/xyzlcu`.

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
| `check` | Permission and lock status | `xyzlcu check` |
| `request` | Bring up the system permission prompts | `xyzlcu request` |
| `whoami` | Process chain and responsible app | `xyzlcu whoami` |
| `version` | Version | `xyzlcu version` |
| `screenshot [path] [--scale S] [--display N] [--format png\|jpg] [--quality Q]` | Screenshot (PNG by default; JPEG is faster and smaller) | `xyzlcu screenshot /tmp/s.jpg --scale 0.5` |
| `screenshot … --fast` | Fast screenshot: JPEG, quality 0.6, scale 0.5 | `xyzlcu screenshot --fast` |
| `screenshot … --window "App" [--title T]` | Capture just one app window (its frontmost window by default) | `xyzlcu screenshot /tmp/w.png --window Safari` |
| `screenshot … --region x,y,w,h` | Capture just a region (global points) | `xyzlcu screenshot /tmp/r.png --region 100,100,400,300` |
| `displays` | Displays and their coordinate ranges | `xyzlcu displays` |
| `click x y [--right] [--double]` | Click | `xyzlcu click 500 300 --double` |
| `move x y` | Move the pointer | `xyzlcu move 800 600` |
| `drag x1 y1 x2 y2` | Drag with the left button held | `xyzlcu drag 100 100 400 400` |
| `scroll dx dy` | Scroll in lines; positive dy scrolls up | `xyzlcu scroll 0 -5` |
| `cursor` | Current pointer position | `xyzlcu cursor` |
| `type "text" [--app "App"] [--via auto\|events\|ax\|paste]` | Type Unicode text. Default auto: keyboard events normally, Accessibility value writes when the keyboard is detected as blocked | `xyzlcu type "你好 Hello 😀"` |
| `insert "App" [target] "text"` | Insert text at the focus via Accessibility (sets AXSelectedText), no keyboard events; verified by reading back | `xyzlcu insert TextEdit --window Notes "hello"` |
| `settext "App" [target] "text"` | Replace a text field's whole content via Accessibility (sets AXValue); verified by reading back | `xyzlcu settext Safari --role AXTextField --title Search "XYZLCU"` |
| `value "App" [target]` | Read back an element's value (focused element by default) to check the input | `xyzlcu value TextEdit` |
| `menu "App" "Menu>Item"` | Press a menu item by path instead of a shortcut; each level accepts alternatives like `File\|文件` | `xyzlcu menu TextEdit "File>Save"` |
| `key combo… [--app "App"]` | Keys / combos, several at once | `xyzlcu key cmd+s` · `xyzlcu key cmd+c cmd+v` |
| `apps` | Running GUI apps | `xyzlcu apps` |
| `open "App"` | Open an app | `xyzlcu open "TextEdit"` |
| `activate "App"` | Bring an app to the front | `xyzlcu activate Finder` |
| `hide "App"` | Hide an app (like cmd+h) | `xyzlcu hide TextEdit` |
| `windows [--all]` | On-screen windows (owner, title, bounds) | `xyzlcu windows` |
| `movewin "App" x y [--w W --h H] [--title T]` | Move / resize a window and raise it | `xyzlcu movewin "Safari" 200 100 --w 1200 --h 800` |
| `ax ["App"] [--depth N] [--menu]` | Dump the UI control tree | `xyzlcu ax TextEdit --depth 6` |
| `find "App" [--role R] [--title T] [--contains] [--index N\|--all] [--window T] [--menu]` | Find a control; returns role, title, frame, center; stops at the first hit | `xyzlcu find TextEdit --role AXButton --title Save` |
| `click-el "App" --role R --title T [--click] [--right] [--double]` | Find a control and press it (AXPress, falling back to a center click) | `xyzlcu click-el TextEdit --role AXButton --title Save` |
| `press "App" "title"` | Find a control by title and press it (older form; prefer `click-el` in new scripts) | `xyzlcu press TextEdit "Cancel"` |
| `wait "App" --title T [--role R] [--timeout sec] [--gone]` | Wait for a control to appear (or, with `--gone`, disappear); 5 s timeout by default | `xyzlcu wait TextEdit --role AXSheet --timeout 3` |
| `wait ms` / `sleep ms` | Fixed wait | `xyzlcu sleep 300` |
| `taps` | List system event taps (diagnose stuck or dropped input) | `xyzlcu taps` |
| `run [--continue-on-error] 'cmd; cmd; …'` | Run several commands at once (split on `;` or newlines) | `xyzlcu run 'click-el TextEdit --title Save; wait TextEdit --role AXSheet; key return'` |
| `batch [--continue-on-error] [file]` | Run commands line by line from a file or stdin | `printf 'type a\nkey return\n' \| xyzlcu batch` |
| `serve [--status\|--stop]` | Start / inspect / stop the resident daemon; see [Daemon](#daemon) | `xyzlcu serve &` |

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

## When keyboard events are blocked

Sometimes another process's keyboard event tap hangs. `xyzlcu type` / `key` then return ok, but nothing shows up in the app, not even with `--app` direct delivery. The mouse usually still works.

**How to tell**: `xyzlcu check` lists the stuck taps under `keyboardBlockedBy` (active filter, interested in key events, average latency above 1 s). `xyzlcu taps` shows all the details. If the latency numbers never change, events are not being drained and old keystrokes are not being replayed either.

**Input paths that skip keyboard events** (none of them go through the keyboard event stream):

```bash
xyzlcu insert TextEdit --window "My notes" "inserted at the caret"         # sets AXSelectedText
xyzlcu settext TextEdit --role AXTextArea --window "My notes" "replace all" # sets AXValue
xyzlcu value TextEdit --window "My notes"                                   # read it back
xyzlcu type "hello"     # default --via auto switches to Accessibility writes when the keyboard is blocked
```

- Target: the app's focused element by default, or pick one with `--role` / `--subrole` / `--title` (or `--id`) / `--index`. `--window TITLE` checks which window the element is in and refuses to write if it does not match, so you cannot write into the wrong document.
- Every write reads `AXValue` back. Only `verified: true` counts as success; a mismatch exits with code 1.
- The app does not need to be frontmost, and nothing outside the target element is touched. Native Cocoa text views (TextEdit, Notes, most text fields) support it. Some web pages and custom-drawn UIs do not accept value writes and report an error.
- `--via paste`: puts the text on the clipboard, presses the "Edit>Paste" menu item, then restores your original clipboard.

**Instead of shortcuts**: press menu items with `menu`, for example `xyzlcu menu TextEdit "File>Save"`, `"文件>关闭"`, or `"Edit|编辑>Select All|全选"`. If an item is not found, every item on that level is listed.

**Limitation**: menu actions (`menu`, `press`, `--via paste`) rely on the app processing its own event queue. If the event pipeline is stuck as a whole, the app does not process them: the command reports success but nothing happens, and the action may be queued until the pipeline recovers. So when a stuck tap is detected, `menu` adds a `warning` to its output and `--via auto` does not fall back to paste. In that state only `insert` / `settext` / `type --via ax` take effect immediately. The real fix is to restart the stuck process (the one with the huge latency in `xyzlcu taps`) or to log out/reboot. XYZLCU does not kill system processes for you.

## Daemon

Every `xyzlcu` run starts a process, checks permissions and connects to the window server, about 15–50 ms. The resident daemon pays that cost once:

```bash
xyzlcu serve &          # start it from the agent's / terminal's own shell
xyzlcu serve --status   # pid, version, uptime, permissions, responsible app
xyzlcu check            # "daemon": true means commands go through the daemon
xyzlcu serve --stop     # stop it
```

- Once it's running, every command (including `run` and `batch`) is **forwarded automatically**, with identical usage and output. If the daemon can't be reached or its version differs, the command runs in-process instead.
- `XYZLCU_DAEMON=0`: never use the daemon. `XYZLCU_DAEMON=1`: require it; exits with code 5 if it can't be reached.
- The socket is `~/.xyzlcu/sock` (directory 0700, socket 0600) and only accepts connections from the **same user** (checked with `getpeereid`). No network port is opened. Override the path with `XYZLCU_SOCKET`.
- The daemon keeps the lock-screen guard and permission checks; relative paths resolve against the caller's working directory.
- **Permissions (TCC)**: the daemon runs with the permissions of **the app that started it**, so run `xyzlcu serve &` from the agent's or terminal's own shell; the responsible app is then the same as for direct commands. Check `responsibleProcess` in `xyzlcu serve --status`.
- To start it at login you can write your own LaunchAgent (`~/Library/LaunchAgents/*.plist` with `ProgramArguments` = `xyzlcu serve`). In that case the responsible process is the launchd-started xyzlcu binary itself, which then needs its own permissions in System Settings. XYZLCU never installs a LaunchAgent for you.

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

## Using with AI agents

Any agent that can run shell commands can use it, such as Claude Code, Codex CLI or your own agent. Put something like this in the system prompt or in `AGENTS.md` / `CLAUDE.md`:

```text
You can control this Mac's GUI with `xyzlcu`. Rules:
0. Run `xyzlcu serve &` once at the start of the session; every later command is faster (daemon is true in `xyzlcu check`).
1. Run `xyzlcu check` first. If screenLocked is true or a permission is missing, stop and tell the user.
2. Loop: observe → locate → act → verify.
   - Observe: prefer `xyzlcu find "App" --role AXButton --title Save` or `xyzlcu ax "App" --depth 6`; when you need pixels, use `xyzlcu screenshot --fast`, `--window "App"` for one window, `--region x,y,w,h` for one area.
   - Locate: find returns the center directly; for screenshots, convert with pixelsPerPoint and originX/originY.
   - Act: use `xyzlcu click-el "App" --role R --title T` instead of clicking coordinates when possible.
   - Wait: use `xyzlcu wait "App" --title T --timeout 5` for UI changes instead of fixed sleeps.
   - Verify: re-run find / ax or take another screenshot after each action.
3. Before every `type` or `key`, run `xyzlcu activate "TargetApp"` and confirm with `xyzlcu apps` that it is frontmost (active: true). Keyboard input goes to the frontmost app.
4. Ask the user before anything irreversible: payments, deletions, sending, submitting.
5. Never use --force to bypass the lock-screen guard.
6. Once the target is confirmed frontmost, chain several steps into one `xyzlcu run 'click-el App --title Search; type hello; key return; wait App --title Results'`; it is several times faster than separate calls.
7. If you hit a captcha, an "are you human" check or any other anti-bot check, stop and hand it to the user. Don't try to get around it.
```

## Performance

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

Run it yourself: `python3 scripts/bench.py build/xyzlcu`; `--daemon` starts the daemon first; `--gui` also opens a temporary TextEdit document to time clicks and typing, and closes it afterwards.

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
| 4 | `find` / `click-el` found no control, or `wait` timed out |
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
- Keyboard does nothing at all while the mouse works: an event tap that intercepts keyboard events is probably hung (in `xyzlcu taps` its `avgLatencyMs` is in the hundreds of thousands or millions, and its `eventsMask` covers only keyboard events). That blocks keyboard input system-wide, and `type --app "App"` may not get through either. Quit or restart that process (often Siri or Screen Sharing's RFBEventHelperd), or log out and back in.

**Daemon issues**
- `daemon` stays false in `check`: the daemon isn't running, or it's an older version (on a version mismatch commands run in-process). Run `xyzlcu serve --status`.
- Permissions are false inside the daemon: it was started from a different app. Run `xyzlcu serve --stop`, then `xyzlcu serve &` again from the authorized terminal / agent shell.
- After updating xyzlcu, run `xyzlcu serve --stop` and start it again.

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
- Don't let an agent auto-confirm payment, deletion or sending dialogs.
- XYZLCU makes no network connections, collects no data, and never modifies the system permission database. The daemon only listens on a local Unix socket and only accepts the same user.
- **No detection evasion**: XYZLCU sends ordinary synthesized mouse and keyboard events. It doesn't pretend to be a human, randomize timing, or get around captchas or websites' bot detection. When an agent hits a captcha, an "are you human" check or any other anti-bot check, it should stop and hand it to a person.

## Limitations

- macOS only, and only the logged-in user's GUI session. Nothing works while the screen is locked, and screenshots come out black.
- On macOS 13 there is no ScreenCaptureKit capture; it falls back to `/usr/sbin/screencapture` (`-l windowID` for `--window`, `-R` for `--region`).
- `press` matches the title, description, value or identifier exactly (case-insensitive) and takes the first match; use `find` / `click-el` with `--role`, `--index` and `--window` to be more precise.
- `type` bypasses the input method, so it doesn't suit cases that need IME suggestions.
- No management of windows on other Spaces (desktops).

## Uninstall

```bash
xyzlcu serve --stop 2>/dev/null
rm -f ~/.local/bin/xyzlcu ~/.local/bin/macctl
rm -rf ~/.xyzlcu
```

Then, in System Settings > Privacy & Security, turn off or remove any apps you no longer need under Accessibility and Screen & System Audio Recording.

> To keep using the old name: `ln -sf ~/.local/bin/xyzlcu ~/.local/bin/macctl`

## License

[MIT](LICENSE) © 2026 XYZTech
