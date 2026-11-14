# Changelog

## 0.7.0 — 2026-11-14

- Make **Single-window background control** the headline feature. `lock` / MCP `lock` default to strict process+window scope: AX/pid only, no activation/raise, pointer warp, global HID, clipboard fallback, broad app menus or silent foreground fallback. Reject conflicting target selectors and unsafe `--no-lock` bypasses; corrupt/unreadable lock state fails closed, and an exited target retains its lock until explicit recovery. Errors include `error: "refused: would use global input"` and an actionable `hint`.
- Add command-local `--allow-foreground` / `--allow-global` (MCP `allow_foreground` / `allow_global`) and persistent `lock --unsafe` / MCP `unsafe`. Global HID still checks the intended frontmost target. Strict menus allow only scoped edit commands; app-wide/unknown menus, `check --probe`, permission requests, open/activate/hide/movewin/replay/move/drag are refused unless explicitly relaxed. Both READMEs contain the side-effect audit.
- Use ScreenCaptureKit `SCContentFilter(desktopIndependentWindow:)` exclusively for every targeted/locked window screenshot, including pid/window-id targeting. Covered and partly off-screen windows use the OS backing surface. Window screenshots/diffs report window-relative coordinates and a separate global window frame. No desktop crop, full-display or CLI capture fallback. Window capture supports macOS 13 through a one-frame SCStream and macOS 14+ through SCScreenshotManager/live streams; `--cli` with a window target is refused. Minimized/other-Space capture remains OS-dependent.
- Harden public `CGEvent.postToPid` mouse/Unicode/key/scroll routes: confirm the target AX key window, convert window points to event global locations, tag window-number fields, hold down/up events, and avoid shared HID event state. No private SLEvent posting symbols. Report `route`, `verified` and a reason when delivery/effect cannot be verified; bounded AX state change does not prove the semantic outcome of a command.
- Add `set-text` (alias `settext`): AX-focus within the target app, AXValue write/readback, then AXSelectedText or pid Unicode where supported; background `type` uses the same focus-first routes. Stop on an ambiguous accepted AX write instead of risking duplicate fallback. Pid replacement requires readable text and verified full selection. Explicit paste is globally guarded before touching the clipboard.
- Add `frontmostBefore`, `frontmostAfter` and `contention` snapshots to JSON objects. `--assert-no-contention` / MCP `assert_no_contention` fails on observed pointer/frontmost changes. Snapshots do not prove continuous isolation or prevent an app from activating itself; async worker completion and later app effects/contending input are outside the parent response's observation interval; list/plain/binary formats keep their existing shape.
- Add isolated manual `scripts/bg_selftest.sh`: `open -g` a temporary TextEdit document, strict lock, AX text, pid Unicode, safe AX menu, window capture and value/frontmost/pointer assertions with a PASS/FAIL table. It never sends global input, does not overwrite an existing lock and retains artifacts. Run only with real GUI/TCC permissions.
- Add `--pid` targeting; deep `press --nth/--list/--async`, native popup `select`, `scroll-to` / `scroll --ax`, `wait-text` and text-only `observe`; preserve old command forms and JSON fields where safety permits.
- Add click/key holds (60 ms click, 75 ms hover, 30 ms key by default), structured responsible-process TCC diagnostics, `request --open`, focused compact AX output, half-scale JPEG MCP screenshots and `max_side`.
- Add permission-free CLI/C-client/MCP selftests for parsing, targeting and safety policy. GUI behavior remains a separate acceptance gate.

Build and pure-logic tests are separate from real-app acceptance. GUI behavior and timing need verification on a Mac with the appropriate AX/TCC permissions; historical benchmark tables are not v0.7.0 measurements.

## Earlier versions

Summarized from this repository's release commits (`git log`):

| Version | Commit | Summary |
|---|---|---|
| 0.6.1 | `762d836` | Window-locked background mode, MCP lock, screenshot `-o`, remote-panel routing and content-first compact AX. |
| 0.6.0 | `d53290e` | Cached app table, batched AX reads, compact numbered refs, display-stream window crops and stale-daemon restart. |
| 0.5.0 | `4e5aecc` | Tiny C forwarding client, parallel PNG/JPEG/HEIC, prewarmed capture streams, binary daemon protocol, MCP batch and image diffs. |
| 0.4.2 | `33a59a1` | In-memory screenshots, persistent capture streams and stdio MCP server. |
| 0.4.1 | `74ffd69` | In-process screenshot callback fix and LCU benchmark scripts. |
| 0.4.0 | `be6487e` | AX/pid/menu/paste input routes, active event-stream diagnosis, window guards and listen-only record/replay. |
| 0.3.1 | `2db65bb` | AX insert/settext/value, menu command, typing route selection and blocked-keyboard detection. |
| 0.3.0 | `3f06122` | Resident daemon, window/region/fast capture, find/click-el/wait, batch error handling and app-targeted keys. |
| 0.2.0 | `132c092` | Faster input/capture, run/batch and tap diagnostics. |
| 0.1.0 | `e3a20ff` | Initial dependency-free macOS GUI control CLI. |
