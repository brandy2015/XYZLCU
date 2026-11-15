# XYZLCU 0.8.0 identity verification

Phase L3, 2026-11-15. Implements a conservative, bounded portion of the revised [design](IDENTITY_PROOF_DESIGN.md) and [review](IDENTITY_PROOF_REVIEW.md). This report does **not** accept XYZStudio computer tools. All consumer operation admission remains unavailable.

## Implemented and deferred

| Area | Built behavior | Remaining gate |
| --- | --- | --- |
| Execution-time process identity | Native complete PROC_PIDTBSDINFO start seconds/microseconds, boot UUID, effective UID, canonical executable, device/inode/SHA-256, validated dynamic/static code, executing architecture and signature observations; fresh pre/post full comparison; expected-process FD check | Non-atomic multi-provider observation; no audit-token attestation or authenticated consumer admission |
| Structured protocol | Closed design schema, duplicate-key/UTF-8/depth/size rejection, semantic operation checks, canonical hashes, nonce/sequence/capacity ledger, payload withholding and stable failure envelope | No negotiated HMAC or authenticated consumer transport; integrity requests refuse |
| Window/AX proof coordinator | Injectable providers; two pre-observations and postcheck; window/element/context/signature/display mismatch and known generation replacement fail; unprovable required assurance refuses before primitive | No public generic window/control incarnation or reviewed AX mapping/surface provider; production reads/actions unavailable |
| Authority/publication | Independent revoke/dispatch mutex, local deadline transition, once-only pending-response ledger with full expected identity; tests of revoke/duplicate/capacity behavior | Helpers are not integrated into XYZStudio's authenticated live origin/lock/owner/TCC authority or all publication sinks; host acceptance remains separate |
| Protected apps | Conservative built-in seed denials, suspicious signer handling, exact/final-component-glob owner additions, strict schema, trusted account-home/no-follow FD traversal, mode/owner/link/size checks, exact overlay revision/digest continuity | Third-party publisher artifacts and family/helper/host attribution not reviewed; consumer Unknown unavailable. External trusted owner high-water/session admission not implemented |
| SCK | Compiled fresh unique CG+SC exact-window object service; owner/bundle/layer/frame checks, one-shot private image, child exclusion on 14.2+, pre/post guard, no desktop crop or CLI/cache fallback | No production admission/provider; no actual pixel capture or thumbnail positive acceptance. macOS 13/14.0 new capture refuses unsupported composition |
| Picker | Bounded metadata catalog, fresh discovery tokens, protected redaction, nonselectable candidates and explicit thumbnail reasons; no capture to classify a surface | No authenticated owner role/catalog binding, selectable target or image thumbnails |
| Safe launch | Validated bundle-ID CLI shape and unavailable response; compiled NSWorkspace no-args/no-URL/no-documents/no-activation/no-substitution/no-prompt dispatcher | Path/publisher allowlist, reviewed current OS launch trust, exact checked-code submission and complete callback proof unavailable; CLI performs zero AppKit launches |
| Compatibility | All legacy content/input/action/permission-request/activation/lock-create paths refuse before dispatch; aliases, batches and MCP covered; no display prewarm/live/diff producer admission | Intentional compatibility break; old scripts are not usable as computer-control tools |

No flag enables unavailable capabilities. An unsigned/ad-hoc fixture or matching endpoint descriptors cannot create a publisher grant or prove arbitrary-app continuity. Native service implementation is distinct from reachable CLI support.

## Verification environment and commands

Run locally on the user's Mac using the installed Xcode SDK, with no Actions/CI. Build output is universal arm64 + x86_64, ad-hoc signed with identifiers `com.xyztech.xyzlcu` (core) and `com.xyztech.xyzlcu.client` (C client). Ad-hoc validation is not Developer ID distribution trust or notarization. Intel slices are built and signature-verified; runtime tests execute the native Apple Silicon slice only. macOS 13/14 capture behavior is not runtime-accepted.

Commands run:

```sh
./build.sh
swift test
./scripts/unit_test.sh
./scripts/selftest.sh
./scripts/identity_integration_test.sh
./scripts/bg_selftest.sh
./build.sh --install
xyzlcu --version
```

Final counts and installed checks are recorded below. Build/test logs and machine-readable integration results are retained under ignored `build/`; they are evidence, not release capability claims.

## Test interpretation

XCTest uses injectable process/signature/window/AX/policy/clock/primitive providers. It asserts zero dispatch for precheck refusals and absence of result/proof for postcheck failures. Coverage includes real isolated policy files (0600/0700, symlink, hardlink, FIFO, oversized file, missing overlay/continuity, non-directory FD and noncanonical revision), every builtin protected seed, PID reuse, executable/signature mismatch, cooperative window reuse, indistinguishable ABA refusal, AX element replacement/context, frame tolerance and cumulative drift, display scale, protected refusal, canonical nonce echo, replay/sequence/capacity, schema and Unicode distinctions, stale capture timestamps, cancellation, dispatch ordering and host duplicate-consumption races.

The integration suite builds an ad-hoc fixture bundle in a private temporary directory and a passive AppKit test host. It opens only this fixture with background NSWorkspace configuration, two nonce-bearing windows, and no input events. Private run-ID authenticated files ask the fixture itself to recreate a window/control and quit; this is fixture lifecycle coverage, not proof that XYZLCU performed AX actions or detected real OS ABA reuse. Native process checks target only that fixture, including a stale expected start and changed expected executable digest. An isolated owned daemon tests its actual executor PID, metadata, refusal on consumer admission, empty capture buffers and clean socket shutdown. The fixture monitors whether it ever became active at 50 ms intervals; frontmost/pointer snapshots and this monitor are observations, not continuous OS isolation proof.

Positive AX content/actions, window/control incarnation and SCK pixel/thumbnail checks are named SKIPs when the shipping provider cannot meet requirements. Missing TCC is separately detected and reported as SKIP, never requested. Launch integration uses the fixture host, not the unavailable production open-app route. The CLI route is checked for refusal and zero dispatch.

The current test-launching context reports Accessibility and Screen Recording granted. Those grants did not waive the missing identity/surface providers. No global keystrokes, mouse events, activation of another application, TCC grants/dialog interaction, firewall changes or hosted CI were performed.

## TCC and installed executors

Permissions belong to the actual process and responsible launching host. Installation keeps stable ad-hoc signing identifiers but changes content hashes; macOS may require a new grant for a replacement core/client or a different responsible host (for example XYZStudio launching a daemon). Do not infer transfer from Terminal, a previous build, or an old XYZStudio toggle. No permission was requested or re-granted during this work. Final passive preflight observations and resident executor handling are recorded with the final counts.

MCP stdio servers already running from an old mapped executable cannot be replaced in place through their unrelated host's private pipes. Their hosts must reconnect/restart the MCP session to load 0.8.0. This does not require restarting or acting on the host application through UI automation. Socket `serve` daemons are independently inspected and cleanly restarted if present.

## XYZStudio contract

1. Query `capabilities --json`; `consumer_available:false` and empty `consumer_transports` are authoritative. Do not enable computer tools.
2. `identity-observe` and `identity-check` produce `kind:process-observation`, diagnostic metadata only, explicitly separate from `urn:xyzlcu:identity-proof:1` content Success. The FD request is closed `{schema_version:1,nonce,expected}`; expected is the complete prior `observed_pre` process object. Canonical nonce is 32 bytes unpadded base64url (43 characters). Successful checks compare the full frozen object twice and echo the nonce.
3. Full process start time preserves decimal-string seconds plus integer microseconds. Executor start time is an exact combined decimal microsecond string. Continuous nanosecond counters are decimal strings. Signing identifiers and bundle IDs are distinct; ad-hoc diagnostics cannot grant permanent app/T4 authority.
4. Failure JSON is closed and versioned: stable code, numeric exit, nonce/null, phase, dispatch_state, side_effects_possible, retryable:false, mismatch_fields, bounded message, mac:null. No content/result/proof appears. Unauthenticated consumer requests refuse before request/key FD read or protocol-2 relay; a nonce inside such an unread envelope is intentionally not echoed.
5. Catalog tokens are discovery-only, all current candidates nonselectable with null thumbnails. Catalog absence of images is not a capture success. Metadata-only first-use can show the builtin diagnostic policy; production policy loading requires explicit owner initialization. No CLI can write policy, bootstrap owner authority, reset the high-water state, supply a policy path or bypass consumer denials.
6. The host still needs an authenticated executor/controller session, reviewed stronger providers, owner self/helper exclusions, immutable policy/revision checks, live dispatch permit, deadline/kill/lock/TCC supervision and once-only response publication. None can be reconstructed from chat logs, a version, caller-supplied Allowed string or a matching proof.

## Final artifact results

- `./build.sh`: exit 0, both binaries universal x86_64 + arm64; strict ad-hoc signature verification passed.
- `swift test` and `./scripts/unit_test.sh`: each ran 62 XCTest cases, 0 failures. These are the same suite, not 124 distinct tests.
- `./scripts/selftest.sh`: 239 assertions passed, including core/client consumer lifecycle refusal, unread request FD, retired executable override in daemon=0/1, disabled aliases, MCP and batch; created/posted global event counters remained zero.
- Final `./scripts/identity_integration_test.sh`: 21 PASS, 5 SKIP, 0 FAIL, macOS 27.2.1 (26B131), arm64. Four skips are missing reviewed window/control/surface providers; the fifth is an externally moved pointer between passive snapshots. The fixture sent no pointer events. AX and Screen Recording preflight were both true.
- `./scripts/bg_selftest.sh`: the unchanged wrapper also ran the fixture suite successfully on the preceding universal build: 22 PASS, 4 provider SKIP, 0 FAIL. It is duplicate fixture coverage, not an additional independent suite. Final identity suite above covers the final helper/diagnostic changes.
- Machine-readable closed core schema is published in `docs/schemas/identity-proof.v1.schema.json` (entry points Request/Success). Error and owner-policy schemas are adjacent. Unreviewed attribution/composition/system-trust/context-provider evidence and transport-3/handshake schemas remain unfrozen and unsupported. The embedded core schema and published JSON were compared for equality.

- `./build.sh --install`: exit 0; `xyzlcu --version` resolved `/Users/zhangzihao/.local/bin/xyzlcu` and printed `xyzlcu 0.8.0`. Installed and build binary SHA-256 hashes match exactly; the final fixture report identifies the same core hash.
- Installed core SHA-256: `f8314a7156228a7a66cc565ff4a432730122102386a535718ab847f62a4cc6d2`.
- Installed C client SHA-256: `d9f0632217e3df1ba2de08aa76c44629ed4b20493f7dabb77e36654efd1296fa`.
- Passive installed invocation via `xyzlcu` reported Accessibility=true and Screen Recording=true. Its actual executable was `~/.local/bin/xyzlcu-core`; the responsible host was `Grok Bot` (`com.anysphere.sand`, `/Applications/Grok Bot.app/Contents/MacOS/Grok Bot`). No re-grant was needed or attempted for this tested context. This does not establish XYZStudio-launched daemon or a future host's TCC state. The relay itself performs no AX/SCK operation.
- `check` reported `computerOperationsAvailable:false`, `consumerAvailable:false`, every route `available:false`, and empty type/key route orders despite granted TCC.
- The default socket daemon was not running before or after installation, so no pre-existing `serve` daemon needed restart. Owned integration daemons were cleanly stopped through their isolated sockets. Five pre-install stdio MCP sessions remained under unrelated owning hosts; those hosts need to reconnect the sessions to load the new executable. They were not killed or replaced through guessed stdin/stdout pipes.
- `git diff --check` passed. No workflow was added or run; release packaging is local and publication uses git/gh only.
