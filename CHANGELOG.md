# Changelog

## 0.8.1 — 2026-11-15

- Add an explicit owner-selected `screenshot --assurance practical --request-fd N --output-dir DIR --json` route on macOS 14.2+. Strict remains the default with unchanged v0.8.0 refusals; AX, input/actions, open-app, daemon/batch/MCP capture and consumer admission remain unavailable.
- Compare the complete caller lock binding before and after fresh exact-window SCK capture, including PID/start time, signing/cdhash/executable hash, bundle ID, window ID/owner/layer/frame/on-screen state. Retain protected-app denial and fail closed without publishing pixels on mismatch.
- Publish schema-versioned practical proof with nonce, pre/post observations, timing, encoded-byte SHA-256, normalized raw-pixel SHA-256 and a private output path. Require an existing real 0700 directory with no extended ACL, no-follow path traversal, and an exclusive 0600 ACL-free output file.
- Document the residual millisecond-scale same-process window-reuse risk, embedded sensitive-content/family attribution gaps, lack of authenticated/replay-protected consumer authority and caller-owned lock/consent/nonce lifecycle in [the practical contract](docs/IDENTITY_PROOF_PRACTICAL.md).
- Add deterministic mismatch/policy/hash/strict-separation tests and extend the owned background fixture for practical capture with explicit TCC SKIP behavior. Install versioned 0.8.1 and historical 0.7.1 pairs side by side while preserving unversioned 0.8.0 binaries; no Actions/CI.

## 0.8.0 — 2026-11-15

- Add strict identity protocol/schema, duplicate-key rejecting bounded JSON parser, canonical hashing, injectable guarded coordinator, single-use request nonce ledger, and atomic host pending-response consumption. Real Swift tests cover process/signature/window/AX replacement, policy, publication, nonce and schema failures with zero-dispatch assertions.
- Add native execution-time process observation and complete expected-process revalidation, including kernel seconds/microseconds, boot, executable file/digest, runtime/static signing and nonce echo. Diagnostic process observations remain separate from content Success proofs.
- Add fixed-path user-only protected policy loading with descriptor-relative no-follow opens, owner/mode/link/size checks and explicit overlay continuity. Built-in protected seeds remain denied when publisher pins are unverified.
- Add bounded owner window catalog with redacted protected entries and explicit thumbnail unavailability. Implement one-shot exact-window SCK and no-argument background NSWorkspace dispatch services behind unavailable reviewed-provider gates.
- Intentionally refuse legacy input, AX content, capture, activation, unsafe/PID/global routes and aliases across CLI, daemon, batches and MCP. Disable legacy display prewarm; no global flag bypass exists. Proof descriptors are never relayed to protocol 2 or an overridden core.
- Generic window/element/surface continuity, authenticated consumer bootstrap/transport, launch trust/exact launch and positive thumbnail/content/launch acceptance remain deferred. XYZStudio operations stay disabled; this release is not consumer acceptance.
- Add only-owned-background-fixture integration with named TCC/provider SKIPs, replace the old TextEdit recipe, verify local ad-hoc signatures, and release built binaries without Actions/CI.

## 0.7.1 — 2026-11-14

- Add an unlocked global input safety gate across CLI, daemon and MCP: HID/session keyboard events, HID mouse click/move/drag/scroll, and activation (including implicit/open-to-front) require explicit `--allow-global` or an intended `--app` / `--pid` already frontmost. Recheck immediately before each event batch and stop if the frontmost target changes. Refuse before creating a global CGEvent with non-zero status, `ok:false`, `GLOBAL_INPUT_REFUSED`, and the actual frontmost app. AX-only and `postToPid` routes are unchanged; auto routing cannot bypass the gate.
- Never accept `XYZLCU_ALLOW_GLOBAL=1` as authorization. MCP tools that can emit global input expose `allowGlobal` (boolean, default `false`) and use the same gate.
- A failed `lock`, including bad/empty window IDs, unknown options or missing targets, writes a persistent `lock-failed` tombstone and updates daemon state. Subsequent input fails with `LOCK_FAILED` until explicit `unlock` or a successful `lock`. Empty/missing option values are hard argument errors and never consume the next option.
- Keep health/check/probe diagnostics passive: they never emit global keyboard/mouse input.
- Extend permission-free selftests with CLI/C-client/MCP refusal paths, failed-lock chaining, option validation and rejected environment bypass. Tests never emit global input or activate apps. Keep background AX/pid routes intact; GUI acceptance remains a separate check.

## 0.7.0 — 2026-11-14

- Make **Single-window background control** the headline feature. `lock` / MCP `lock` default to strict process+window scope: AX/pid only, no activation/raise, pointer warp, global HID, clipboard fallback, broad app menus or silent foreground fallback. Reject conflicting target selectors and unsafe `--no-lock` bypasses; corrupt/unreadable lock state fails closed, and an exited target retains its lock until explicit recovery. Errors include `error: "refused: would use global input"` and an actionable `hint`.
- Add command-local `--allow-foreground` / `--allow-global` (MCP `allow_foreground` / `allow_global`) and persistent `lock --unsafe` / MCP `unsafe`. Global HID still checks the intended frontmost target. Strict menus allow only scoped edit commands; app-wide/unknown menus, `check --probe`, permission requests, open/activate/hide/movewin/replay/move/drag are refused unless explicitly relaxed. Both READMEs contain the side-effect audit.
- Use ScreenCaptureKit `SCContentFilter(desktopIndependentWindow:)` exclusively for every targeted/locked window screenshot, including pid/window-id targeting. Covered and partly off-screen windows use the OS backing surface. Window screenshots/diffs report window-relative coordinates and a separate global window frame. No desktop crop, full-display or CLI capture fallback. Window capture supports macOS 13 through a one-frame SCStream and macOS 14+ through SCScreenshotManager/live streams; `--cli` with a window target is refused. Minimized/other-Space capture remains OS-dependent.
- Harden public `CGEvent.postToPid` mouse/Unicode/key/scroll routes: confirm the target AX key window, convert window points to event global locations, tag window-number fields, hold down/up events, and avoid shared HID event state. No private SLEvent posting symbols. Report `route`, `verified` and a reason when delivery/effect cannot be verified; bounded AX state change does not prove the semantic outcome of a command.
- Add `set-text` (alias `settext`): AX-focus within the target app, AXValue write/readback, then AXSelectedText or pid Unicode where supported; background `type` uses the same focus-first routes. Stop on an ambiguous accepted AX write instead of risking duplicate fallback. Pid replacement requires readable text and verified full selection. Explicit paste is globally guarded before touching the clipboard.
- Add `frontmostBefore`, `frontmostAfter` and `contention` snapshots to JSON objects. `--assert-no-contention` / MCP `assert_no_contention` fails on observed pointer/frontmost changes. Snapshots do not prove continuous isolation or prevent an app from activating itself; async worker completion and later app effects/contending input are outside the parent response's observation interval; list/plain/binary formats keep their existing shape.
- Add isolated manual `scripts/bg_selftest.sh`: `open -g` a temporary TextEdit document, strict lock, AX text, pid Unicode, AX range selection/readback, window capture and value/frontmost/pointer assertions with a PASS/FAIL/SKIP table. Disabled inactive-app menus are an expected SKIP. Poll a unique document title, handle a blocking Open panel, and close only the disposable AX window without quitting TextEdit. It never sends global input, does not overwrite an existing lock and retains artifacts. Run only with real GUI/TCC permissions.
- Fix pid-only screenshot selector conflicts; rank app owners and windows by usable on-screen layer-0 windows, title and area, excluding transparent/tiny/off-screen helpers. Retain explicit window-ID targeting and report chosen ID/title/frame. Add synthetic ranking and conflict regressions.
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
