# Changelog

## 0.7.0 — 2026-11-14

- Add `set-text` (compatible alias: `settext`): focus the element through AX before writing AXValue, verify readback, then try AXSelectedText and pid-scoped menu paste when needed. Background `type` prefers focused AX writes for text controls.
- Add `--pid` targeting and prefer window-owning processes when app names collide. Preserve existing command forms and JSON fields, adding chosen-pid and input frontmost evidence.
- Expand `press` with deep role/text/child-label substring matching, `--nth`, candidate `--list`, and `--async` (automatic for popup/menu buttons). Add `select` / MCP `select_popup_item` for native popup menu selection.
- Add `scroll-to`, AX scrollbar scrolling with `scroll --ax`, and `wait-text` for AX text appearance/disappearance. Virtualized controls use bounded scrolling and repeated tree lookup.
- Guard global HID input: locked/background input requires explicit `--allow-global`; targeted global routes also require the intended app to be frontmost. Add `--expect-front`; report `frontmostBefore` / `frontmostAfter` for input actions.
- Add click/key hold timing (`--hold`, `XYZLCU_CLICK_HOLD`): defaults are 60 ms click hold, 75 ms hover delay, 30 ms key hold.
- Preserve `check.responsibleProcess` and add `responsibleProcessInfo` with host pid/name/path/bundle id. Explain TCC host attribution in MCP errors; add `request --open [--permission …]`. Historical event-tap latency is treated as suspicion; only explicit `check --probe` sends probe events.
- Add text-only `observe`, focused AX/text/popup/scroll/wait MCP tools, shorter tool descriptions, half-scale JPEG screenshot defaults (quality 0.6) and `max_side` image limits. Compact AX/find output includes enabled/focused states.
- Add permission-free `selftest` for parsing, candidate matching and input safety policy, plus bilingual background WebView recipes and manual acceptance checks.

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
