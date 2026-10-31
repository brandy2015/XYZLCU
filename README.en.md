# XYZLCU

[中文](README.md) | **English**

**XYZLCU (XYZ Local Computer Use)** is a dependency-free macOS GUI control CLI. Anything that can run shell commands, whether an AI agent (Claude Code, Codex, any shell-capable agent) or your own script, can use it to see the screen, click, type, press shortcuts, read the UI structure and press buttons. It is a single Swift source file compiled into a single binary: no Python, no Node, no Homebrew, no third-party libraries.

> Inspired by the idea behind [amontlabs/lcu](https://github.com/amontlabs/lcu), but an **independent implementation**: it shares no code and does **not** need the ChatGPT / Codex desktop app or its runtime.

## Features

- 📸 **Screenshots**: main display or a chosen display, optional downscaling, prints the point/pixel mapping
- 🖱 **Mouse**: click, right-click, double-click, move, drag, scroll
- ⌨️ **Keyboard**: types Unicode text directly (Chinese, emoji; bypasses the input method), key combos like `cmd+shift+4`
- 🌳 **Accessibility tree**: dumps any app window's control tree (role, title, value, frame) so targets can be found without screenshots; `press` controls by title
- 🪟 **Apps & windows**: list, open, activate and hide apps; list windows; move and resize windows; list displays
- 🔒 **Lock-screen guard**: refuses mouse and keyboard input while the screen is locked, so nothing gets typed into the password field
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
| `displays` | Displays and their coordinate ranges | `xyzlcu displays` |
| `click x y [--right] [--double]` | Click | `xyzlcu click 500 300 --double` |
| `move x y` | Move the pointer | `xyzlcu move 800 600` |
| `drag x1 y1 x2 y2` | Drag with the left button held | `xyzlcu drag 100 100 400 400` |
| `scroll dx dy` | Scroll in lines; positive dy scrolls up | `xyzlcu scroll 0 -5` |
| `cursor` | Current pointer position | `xyzlcu cursor` |
| `type "text"` | Type Unicode text | `xyzlcu type "你好 Hello 😀"` |
| `key combo…` | Keys / combos, several at once | `xyzlcu key cmd+s` · `xyzlcu key cmd+c cmd+v` |
| `apps` | Running GUI apps | `xyzlcu apps` |
| `open "App"` | Open an app | `xyzlcu open "TextEdit"` |
| `activate "App"` | Bring an app to the front | `xyzlcu activate Finder` |
| `hide "App"` | Hide an app (like cmd+h) | `xyzlcu hide TextEdit` |
| `windows [--all]` | On-screen windows (owner, title, bounds) | `xyzlcu windows` |
| `movewin "App" x y [--w W --h H] [--title T]` | Move / resize a window and raise it | `xyzlcu movewin "Safari" 200 100 --w 1200 --h 800` |
| `ax ["App"] [--depth N] [--menu]` | Dump the UI control tree | `xyzlcu ax TextEdit --depth 6` |
| `press "App" "title"` | Find a control by title and press it | `xyzlcu press TextEdit "Cancel"` |
| `wait ms` | Wait | `xyzlcu wait 500` |
| `taps` | List system event taps (diagnose stuck or dropped input) | `xyzlcu taps` |
| `run 'cmd; cmd; …'` | Run several commands in one launch (split on `;` or newlines) | `xyzlcu run 'click 500 300; type hello; key return'` |
| `batch [file]` | Run commands line by line from a file or stdin | `printf 'type a\nkey return\n' \| xyzlcu batch` |

Notes:

- **App names** can be the localized name, the English bundle name (`Finder`) or the bundle ID (`com.apple.finder`).
- **Key names**: `a–z`, `0–9`, common symbols, `return`/`enter`, `tab`, `space`, `delete`/`backspace`, `forwarddelete`, `esc`, `up`/`down`/`left`/`right`, `home`/`end`/`pageup`/`pagedown`, `f1–f12`. Modifiers: `cmd`, `shift`, `opt`/`alt`, `ctrl`, `fn`.
- **`ax` output format**: `Role(Subrole) title="…" desc="…" value="…" id="…" [x,y WxH]`. The brackets hold point coordinates; the center is `(x + W/2, y + H/2)`.
- **`press`** tries AXPress first and clicks the control's center if that fails.
- **`run` / `batch`**: quoting works like the shell (`"…"`, `'…'`, `\` escapes); lines starting with `#` are comments. Execution stops at the first failing command, with that command's exit code.
- **`--delay N`**: gap between synthesized mouse/keyboard events in ms (default 2). Raise it if a slow app drops input, e.g. `xyzlcu --delay 20 type …` or `XYZLCU_DELAY=20`.
- **Screenshots**: on macOS 14+ capture goes through ScreenCaptureKit (in-process, rendered directly at the `--scale` size); otherwise, or with `--cli`, it falls back to the system `screencapture`. The `method` field in the output tells you which path ran.

## Worked example: write Chinese text in TextEdit and save it

```bash
# 0. Create an empty file and open it, so the typing is sure to land there
: > ~/Documents/xyzlcu-demo.txt
open -a TextEdit ~/Documents/xyzlcu-demo.txt
xyzlcu wait 1500
xyzlcu activate TextEdit

# 1. Find the text area
xyzlcu ax TextEdit --depth 3 | grep AXTextArea
#   AXTextArea id="First Text View" [234,135 656x384]

# 2. Click into it (center = 234+656/2, 135+384/2)
xyzlcu click 562 327

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
1. Run `xyzlcu check` first. If screenLocked is true or a permission is missing, stop and tell the user.
2. Loop: observe → locate → act → verify.
   - Observe: prefer `xyzlcu ax "App" --depth 6`; when you need pixels, use `xyzlcu screenshot /tmp/s.png --scale 0.5`.
   - Locate: compute the center from the ax [x,y WxH]; for screenshots, convert with pixelsPerPoint and originX/originY.
   - Act: use `xyzlcu press "App" "title"` when possible instead of click.
   - Verify: re-read ax or take another screenshot after each action.
3. Before every `type` or `key`, run `xyzlcu activate "TargetApp"` and confirm with `xyzlcu apps` that it is frontmost (active: true). Keyboard input goes to the frontmost app.
4. Ask the user before anything irreversible: payments, deletions, sending, submitting.
5. Never use --force to bypass the lock-screen guard.
6. Once the target is confirmed frontmost, chain several steps into one `xyzlcu run 'click 500 300; type hello; key return'`; it is several times faster than separate calls.
```

## Performance

v0.2.0 removes the fixed 15–60 ms sleeps (replaced by `--delay`, default 2 ms), reuses one event source, types in 20-unit UTF-16 chunks, captures screenshots with ScreenCaptureKit directly at the scaled size, adds JPEG output, builds with `-wmo`, and adds `run`/`batch` so multi-step actions pay the process start-up cost once.

Medians from `scripts/bench.py` on an Apple Silicon Mac (macOS 26+):

| Command | v0.1.0 | v0.2.0 | Speed-up |
|---|---:|---:|---:|
| `screenshot --scale 0.5` (PNG) | 750 ms | 251 ms | 3.0× |
| `screenshot --scale 0.5 --format jpg` | — | 197 ms | 3.8× (vs v0.1.0 PNG) |
| `screenshot` (full 4112×2658 PNG) | 555 ms | 501 ms | 1.1× |
| `type` (128 chars, mixed Chinese/English) | 222 ms | 73 ms | 3.0× |
| `type` (5 chars) | 84 ms | 58 ms | 1.4× |
| `key right` | 102 ms | 68 ms | 1.5× |
| `click` | 85 ms | 58 ms | 1.5× |
| `move` | 60 ms | 51 ms | 1.2× |
| 5 actions (alternating type/key) | ~310 ms (5 launches) | 76 ms (one `batch`) | 4× |
| `check` / `apps` / `windows` / `cursor` / `ax` | 15–50 ms | 15–55 ms | unchanged (mostly process start-up) |

Run it yourself: `python3 scripts/bench.py build/xyzlcu` (`--gui` also opens a temporary TextEdit document to time clicks and typing, and closes it afterwards).

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
- XYZLCU makes no network connections, collects no data, and never modifies the system permission database.

## Limitations

- macOS only, and only the logged-in user's GUI session. Nothing works while the screen is locked, and screenshots come out black.
- Screenshots use the system's `/usr/sbin/screencapture`.
- `press` matches the title, description, value or identifier exactly (case-insensitive) and takes the first match.
- `type` bypasses the input method, so it doesn't suit cases that need IME suggestions.
- No management of windows on other Spaces (desktops).

## Uninstall

```bash
rm -f ~/.local/bin/xyzlcu ~/.local/bin/macctl
```

Then, in System Settings > Privacy & Security, turn off or remove any apps you no longer need under Accessibility and Screen & System Audio Recording.

> To keep using the old name: `ln -sf ~/.local/bin/xyzlcu ~/.local/bin/macctl`

## License

[MIT](LICENSE) © 2026 XYZTech
