# XYZLCU v0.8.0 identity proof design

Status: **Phase L2 — security critique incorporated; design only**, 2026-11-15. This document proposes a protocol and release gates; it does not implement them, enable XYZStudio tools, or assert runtime acceptance. Baseline: XYZLCU `cdcae18`, advertised version 0.7.1; Swift executor `Sources/xyzlcu/main.swift`, C relay `Sources/client/xyzlcu.c`, `Package.swift`, and `build.sh`. No version bump is part of L1/L2. Findings and evidence are in [IDENTITY_PROOF_REVIEW.md](IDENTITY_PROOF_REVIEW.md); see §14 for review changes.

Consumer requirements were read in XYZStudio's [permission design](../../../../Projects/XYZStudio/docs/PERMISSIONS_DESIGN.md) §§2, 4.1, 5–10, [security review](../../../../Projects/XYZStudio/docs/PERMISSIONS_DESIGN_REVIEW.md) F01/F02/F05/F08/F10–F12, and [verification report](../../../../Projects/XYZStudio/docs/PERMISSIONS_VERIFICATION.md), especially its opening and remaining platform gates. These relative links describe the current sibling workspace layout, not files distributed in this repository. Consumer document paths are `~/Projects/XYZStudio/docs/{PERMISSIONS_DESIGN,PERMISSIONS_DESIGN_REVIEW,PERMISSIONS_VERIFICATION}.md`.

**Release meaning:** v0.8.0 may provide evidence of observed identity around an operation. A version string, matching descriptors, payload digest, or HMAC is not an atomic OS target guarantee. Where a caller requires an instance guarantee the provider cannot establish, the operation is unavailable and fails closed. XYZStudio currently keeps **all** computer operations unavailable, including T1 reads and app launch; this proposal alone does not change that.

## 1. Scope and invariants

The user chooses a target in trusted XYZStudio owner UI. Its backend retains an expected binding and sends that binding with each authorized request. The model cannot create, weaken, or replace the binding, pick a window, supply policy facts, request TCC, or obtain the owner session/key. XYZLCU validates **inside the process performing the primitive**, immediately before each screenshot, AX read, or action, and validates again after capture/read/action before releasing a result.

Normative terms MUST, MUST NOT and SHOULD describe the proposed v0.8.0 contract.

1. A PID, window number, app name, title, AX selector, or successful event post alone MUST NOT authorize execution.
2. A bound operation MUST use the expected process instance, signed executable/application, window owner and geometry, and, where applicable, exact AX target and observation context. Any required field that is unavailable is a refusal, not a wildcard.
3. Detectable mismatches, PID reuse, window reuse, owner changes, geometry/display changes beyond the frozen tolerance, and element replacement invalidate the binding. Never search for a replacement with the same name or title.
4. If required window/control instance continuity cannot be proved, fail `IDENTITY_UNPROVABLE` or the more specific AX/mapping error. Matching pre/post descriptors do not prove the absence of an intervening replacement.
5. Sensitive output stays in private executor memory until post-checks succeed. Post-check failure discards pixels/AX payloads, including partial output, temporary results and caches. There is no success proof on a failed request.
6. After an action was dispatched, a failed post-check cannot undo it. Report possible effects and never automatically retry.
7. Consumer mode prohibits global input, activation, pasteboard changes and foreground fallbacks. There is **no consumer `--allow-global` usage path**, even for an already-frontmost target.
8. The default protected-app policy applies before capture, AX access, actions and launch, including owner-picker thumbnails. A picker exception permits discovery metadata, not protected content.
9. Identity proof is evidence, not a permission grant. XYZStudio still owns tier, desktop-chat origin, single-use approval, lock/revisions, deadlines, kill, parent supervision, audit and output-publication gates.

### 1.1 What already exists in 0.7.1

Current targeted-window screenshots already use ScreenCaptureKit: `shareableContent` / `grab` / `captureWindowStream` / `captureSCK` in `main.swift` (approximately lines 1573–1860). There is no `CGWindowListCreateImage` call in the current Swift source. macOS 14+ uses `SCScreenshotManager` and live streams; macOS 13 has a one-frame `SCStream` route. Targeted capture rejects `--cli` and does not crop a full-display screenshot. v0.8.0 preserves and hardens these paths; adding modern picker thumbnails is still new work. Any deprecated window-image API in downstream picker code is replaced with this SCK service, not a desktop crop.

The existing `windows` command (around 3670) emits an array of CG metadata, with no signing/start-time proof or thumbnails. Its `--all` only relaxes layer filtering within an onscreen enumeration. Existing locks hold PID/bundle/window/title but no start time/signature pin. `bgTarget` caches a command target and checks PID existence and CG owner; these are insufficient for this protocol.

Current AX/window mapping uses private `_AXUIElementGetWindow` with a frame/title fallback (around 2135). Neither is a reviewed public exact-mapping capability. Existing numeric AX refs, role/label checks, bounded-tree-change `verified:true`, and asynchronous AX workers are not instance proofs. Consumer mode MUST NOT inherit those claims.

## 2. Threat model and assurance levels

The intended boundary covers model mistakes, prompt injection in app content, stale selection/approval, accidental misrouting, ordinary process/window lifecycle changes, stale caches, transport mixups, and replay. It assumes a trusted OS, XYZStudio backend, executor binaries, policy loader and supported target/provider. A signed app can itself expose misleading AX data or perform arbitrary behavior after receiving a valid action; a signature identifies code, not safe semantics.

An arbitrary malicious process running as the same UID may replace user files/binaries, connect to a 0600 socket, inspect accessible process state, steal a session secret, or invoke GUI APIs independently. POSIX permissions, JSON proofs, HMAC and a denylist do not sandbox that attacker. Root, compromised OS, compromised signed target, and a model with unrestricted same-UID shell/file-write capability are outside the claimed isolation boundary. §7 explains the necessary model-tool restriction.

Assurance is explicit and operation-specific:

| Capability | Evidence | Limitation / refusal rule |
| --- | --- | --- |
| `process-instance` | Boot identity + PID + exact kernel start time; dynamic code validation and path identity, sandwiched around observations | No atomic multi-provider snapshot; exec-in-place and executable changes must also be checked |
| `window-observed` | Fresh CG and SC window/owner/layer/frame/display observations, bound to that process | No public CG/SC window creation generation; same-process ABA reuse may be indistinguishable |
| `window-instance` | Provider-specific, reviewed evidence maintaining the same window incarnation through dispatch/capture | Generic public metadata alone cannot advertise this; unavailable provider means refusal |
| `element-observed` | Retained AX handle within an executor session, path/fingerprint, owner/window checks, context and invalidation observations | AX descriptors and `CFEqual` are not universal immutable incarnation identifiers |
| `element-instance` | Reviewed provider/target protocol establishing control instance and relevant context through the primitive | Generic role/title/nth/path matching cannot advertise this; unsupported means refusal |
| `surface-continuity` | Reviewed provider establishes Allowed app/window/current composed surface and its attribution/context throughout the primitive | Endpoint classification, app signature, AX URL/title or screenshot inspection cannot establish this universally; unavailable means refusal in consumer mode |
| `launch-observed` | Checked static app, exact-URL submission, callback process/start/signature revalidation | AppKit does not expose an atomic checked-inode-to-launch transaction |
| `launch-exact` | Provider can prove dispatch used the approved code/path without substitution | If this cannot be established, refuse before submission; post-launch validation is insufficient |

The proof lists only capabilities actually achieved. Caller-required capabilities MUST be a subset; the executor may not silently downgrade. Ordinary CLI diagnostics can request observed evidence without claiming it satisfies XYZStudio. XYZStudio's current strict gates require stronger window/control binding, protected-surface classification and exact launch behavior. Its support stays unavailable where these cannot be established. A self-built cooperative fixture can test stronger provider behavior without establishing support for arbitrary apps.

## 3. Expected binding and identity providers

Conceptual seams are `ProcessProvider`, `SigningProvider`, `WindowProvider`, `AXProvider`, `CaptureProvider`, `LaunchProvider`, `PolicyProvider` and `ClockProvider`. All are injectable for tests. A central guarded-operation coordinator performs policy and identity checks; individual legacy helpers cannot bypass it in proof/consumer mode. This is an implementation direction, not a source refactor in L1.

### 3.1 Process and signed application identity

Observe all of the following, before and after each primitive:

- Boot session UUID (`kern.bootsessionuuid` or an equivalently reviewed boot identifier), PID, effective UID, kernel process start time as exact seconds plus microseconds. Use `proc_pidinfo(PROC_PIDTBSDINFO)` and `pbi_start_tvsec/pbi_start_tvusec`; require a complete struct result. A reviewed `sysctl(KERN_PROC_PID)` / `kinfo_proc.kp_proc.p_starttime` fallback must produce the same precision. Wall-clock `NSRunningApplication.launchDate`, PID existence, command name, or a synthetic timestamp is not a fallback. Inconsistent/unreadable results fail closed. Start time is an incarnation discriminator, not a signing identity.
- Canonical executable path from the process (`proc_pidpath`), containing canonical app bundle path where applicable, and filesystem identity (device/inode and executable content digest). Resolve symlinks with component-aware ancestry. Match these against the selected application, not against a similarly named file. A process exec may preserve PID/start time; executable and runtime code checks must catch it.
- A running `SecCode` obtained by `SecCodeCopyGuestWithAttributes` using the observed PID (and OS audit token where genuinely available). Perform `SecCodeCheckValidity`/`WithErrors` against the pinned requirement. Validate the corresponding static app/executable as well and verify they correspond. Bracket PID-based Security lookups with fresh start-time observations. Do not claim PID lookup is an atomic audit-token binding.
- From valid code, capture Team ID, signing identifier, cdhash plus hash algorithm and executing architecture, designated requirement text and its digest, validity/signing kind, and any required dynamic status. `SecCodeCopySigningInformation` by itself principally reads disk signature information; it is not runtime validation. Signature API errors or a missing required field are errors. Record all relevant CodeDirectory hashes where needed to reconcile universal executables; never compare an arm64 hash to an x86_64 hash accidentally.
- Bundle ID from OS running-app information cross-checked against signed bundle metadata and validated executable membership. `CFBundleIdentifier` and signing identifier are separate fields; do not equate them. Missing/disagreeing identities refuse. UI names/icons are display data only.

Team ID is nullable only under an explicit signing-kind rule. Apple platform code may have no ordinary Team ID: use a validated Apple anchor/designated requirement, not a made-up Apple team. Developer ID/App Store code requires its reviewed publisher requirement as well as Team ID. Unsigned code is unsupported in consumer mode. Ad-hoc code is supported only in an isolated, owner-selected test/development session pinned to executable digest; it cannot establish a publisher or a permanent app grant/T4. No model flag enables this exception.

Signing kind MUST be established by validated anchor/certificate policy and code flags, never by self-asserted Team/identifier strings or validity against only the target's own designated requirement. Self-signed certificates do not become Developer ID/App Store identities by embedding familiar names/IDs. Compile trusted publisher requirements from the reviewed catalog/owner trust policy independently of target-provided requirements, and validate sealed bundle metadata/nested code membership needed by that policy. Renaming a signed app does not change its signing identity. A running translocated copy is its actual observed location/instance, never silently mapped back to an installed approved path; unsupported location/provider scope refuses, and §9 rejects translocated launch candidates outright.

Within a lock, **all pinned observed fields match exactly**, including cdhash, requirement digest, executable digest/path and start time. An update needs a new lock. Across sessions a consumer may recognize an update satisfying the old designated requirement, bundle ID, signing identifier and canonical path after owner policy checks; that does not permit changing code under a pending call. A Team ID match alone is never sufficient.

### 3.2 Window identity, geometry and screen binding

Use fresh `CGWindowListCopyWindowInfo` records and fresh `SCShareableContent` / `SCWindow` records for the expected numeric window ID. Require exactly one matching record in each provider; missing/duplicate/zero IDs refuse. `SCWindow.windowID` is the Core Graphics window identifier, not a separate incarnation certificate. Verify `kCGWindowOwnerPID`, SC `owningApplication.processID`, bundle mapping, layer, frame and visibility. CG and SC must agree within the frozen tolerance. Missing owner or disagreement is an error, not a best-effort match. Capture with that exact validated `SCWindow` object via `SCContentFilter(desktopIndependentWindow:)`; pass it through the coordinator rather than resolving `.first(windowID == id)` again after the guard. Never resolve by app name/frontmost window after validation. A new CG/SC enumeration requires the complete guard again; it cannot cure missing instance continuity.

Bind:

- Window number, owner process binding, layer, frame in global desktop points with top-left convention, and explicit coordinate-space version.
- Intersecting display IDs **and UUIDs**, each display's bounds, backing scale and rotation, plus the window-to-pixel transform and capture content rect. Multi-display windows use a deterministic documented mapping. Unknown mapping, a disconnected display or ambiguous transform refuses coordinate actions/capture.
- Window incarnation evidence/token and its provider/assurance. An executor-generated random token identifies a session record; it is not an OS window creation generation.
- AX-window correspondence when AX is needed. Public exact mapping is not available universally. Matching bounds/title, guessing focused/main window, or using private `_AXUIElementGetWindow` is not sufficient in consumer mode. Ambiguous/unsupported mapping returns `AX_WINDOW_UNPROVABLE`.

Default frame tolerance is **0.5 pt per x/y/width/height component**, frozen by the owner backend, with a protocol ceiling of 1 pt. Tolerance covers measurement rounding, not movement permission. Negative/non-finite tolerance refuses. Display ID/UUID/topology, scale and rotation changes have zero tolerance. For coordinate actions the consumer may require zero tolerance; it cannot widen an approved call after a change. Any layout/content-transform change invalidates that observation even when outer frame movement falls within rounding tolerance. Report actual deltas.

Titles may legitimately change and are never window incarnation keys. A title change does not pick another window. If title is part of approved observation context, it invalidates that call. A window closing, being recreated, changing owner, or becoming unavailable terminates the binding. A new window in the same process does not inherit it. Monitor lifecycle signals during a retained session, but missing or delayed notifications cannot be called proof of continuity.

**ABA limitation:** CG/SC expose no universal public creation timestamp/nonce. Reusing the same window ID in the same process with identical descriptors can defeat metadata comparisons. Without a reviewed instance provider, `window-instance` is unsupported and a caller requiring it receives `IDENTITY_UNPROVABLE` before reading/acting. This refusal is how the contract handles unprovable window reuse; it must not claim every reuse is detectable from a number and frame.

### 3.3 AX element and observation binding

Resolve only inside the bound AX window. Store a bounded root-to-element path, each segment's child index and role/subrole/identifier, final role/subrole/identifier, title hash, supported action set, bounds/coordinate transform, relevant state digest, and document/page context digest. Titles and optional identifiers use explicit `null` for absent; absence is not a wildcard. Hash exact UTF-8, without locale folding or lossy truncation; domain-separate absent, empty and present strings. A SHA-256 title hash can still reveal low-entropy text by guessing; it is not anonymization.

The owner observation produces an opaque session-bound element token, retained handle and observation ID/revision. The caller passes the expected fingerprint/token; a model-supplied role/title/nth may only propose a query to the trusted preparation layer and is never an execution binding. Direct invocations cannot deserialize a retained AX handle from a previous process. They must return `AX_INSTANCE_UNPROVABLE` when continuity is required, or use a compatible retained executor session.

Immediately before every AX attribute fetch, subtree step, hit test, set-value, focus or AX action, verify process/window binding and current expected element/context. Keep that exact retained object for dispatch; do not rerun a loose selector after approval. Bound traversal by nodes/depth/bytes/time. Read identity attributes under the process/window guard first; if the element fingerprint/context cannot be established, do not read or write its content. Recheck after each primitive and before releasing the combined payload. Events/notifications are hints triggering invalidation, not a substitute for these checks.

Use `AXUIElementGetPid`, window/parent ancestry, retained-object comparison and lifecycle invalidation where available. A disappeared handle, changed path/fingerprint, duplicate match, replacement notification, changed document/navigation/context, supported-action change, modal overlay, changed semantic state or coordinate hit on another element invalidates the observation. Never refind the “same” label automatically. Source URLs/AX labels are app-provided data; do not trust them as security classification.

**Replacement limitation:** path + role + subrole + identifier + title hash can all be reproduced by a newly created control. AX has no universal public immutable element incarnation ID. A retained reference/`CFEqual` and notifications improve detection but do not certify every replacement or action semantic change. If the caller requires `element-instance` and the provider cannot establish it, fail `AX_INSTANCE_UNPROVABLE` before access. Do not issue strong proofs from structural matching. A fixture adapter may expose its own generation token; generic apps do not inherit that capability.

Freeze observation freshness/context with approval. XYZStudio currently specifies at most 5 seconds from observation to preparation, at most 120 seconds pending approval with continuity maintained, and a final observation at most 1 second before dispatch. These are consumer maxima, not TOCTOU protection. Tokens expire on deadline, lock/session/policy revision change, daemon restart, target change, lost observer continuity, sleep/lock or cancellation; never persist them as reusable authority.

## 4. Guarded execution and result publication

The following sequence runs in the actual executor, including a daemon or any worker that would perform a primitive:

1. Strictly parse a size/depth-bounded request before value deserialization can hide duplicate keys. Reject unknown fields/versions, invalid nonce, selectors contradicting the binding, unsupported required assurance, expired/mismatched boot/session/lock/policy revisions, and prohibited routes. Verify optional request MAC before performing discovery beyond public capability metadata.
2. Acquire the session operation lock and register a cancellable operation. Check live cancellation/parent channel, deadline, lock generation, policy digest and TCC without prompting. Reserve the nonce once; repeats cannot dispatch. No request can consult another session's lock or refs.
3. Resolve and validate process/static/runtime signatures, then window/AX association/context as needed. Apply protected policy **before content access**, including thumbnails. A legacy `kill(pid,0)` check is insufficient. No cached identity counts as the final observation.
4. Prepare the bound API object and capture geometry. Immediately at the primitive boundary, re-read start identity and all required observed identities, evaluate mismatch and policy again, and record the pre-check interval. Provider reads are themselves non-atomic: sandwich them with start/runtime/path checks and refuse inconsistencies. Then enter the dispatch barrier defined below: check the complete live permit state, not identity/policy alone.
5. Execute exactly one permitted primitive using that bound object. For a compound AX traversal, `set-text` focus/write/readback, multi-event sequence or screenshot+AX observation, repeat steps 3–6, including the complete dispatch barrier, at **each** primitive. Unsupported async or global fallbacks refuse. A single initial guard never licenses an entire batch.
6. Immediately after capture/read/dispatch, re-observe process/signing/window/geometry/element/context and policy. Record the post-check interval. Capture/read output stays private until the check succeeds. A write whose expected post-state legitimately changes has an explicit precondition/postcondition; it cannot redefine identity or silently accept unrelated context changes. If relevant title/state changes are not declared by that operation, invalidate rather than relax checks.
7. Ensure stream/worker cleanup, nonce finalization, deadline/cancellation and policy/lock revision still permit release. Compute payload and request digests, build proof from actual observations, optionally MAC it, and emit one bounded response. For a multi-part response there is no early binary/stdout streaming. No post-failure cached pixel or partial AX tree is released.

A success attests the observed checks and specific route, not that arbitrary target application semantics succeeded. Keep identity and effect results separate: `identity_check: "matched"` versus `effect_verification: "verified" | "unverified" | "not_applicable"`. An AX setter returning success or a posted event is not proof of an intended semantic outcome.

**Dispatch barrier (L2-01):** after every slow lookup/await and immediately before each content read, capture submission, AX focus/write/action or launch, the coordinator MUST serialize a complete permit check and the transition to `dispatching` with revocation. Check authenticated controller liveness, independent cancellation token/epoch, current origin/toolsEnabled/owner gate, session/lock/policy/allowlist revisions, continuous-clock deadlines, sleep/lock state and current required TCC. Host-owned facts arrive through the authenticated live control session; unknown or stale facts refuse. Revocation ordered first means zero later primitives; dispatch ordered first may have effects, but cancellation prevents every subsequent primitive and publication. Recheck the clock at this transition. This orders local authority; it does not make the OS target transaction atomic or guarantee recall after admission to an OS call.

The operation queue/session lock MUST NOT block out-of-band revocation. Hold only a short state/dispatch mutex; do not hold the cancellation mutex through Security, AX, SCK or AppKit calls. Slow/non-cancellable calls remain registered and their output private until completion/cleanup. A cancellation acknowledgement from a relay is not proof that the daemon is quiescent. The actual executor must acknowledge stopped future dispatch and complete/unknown cleanup; otherwise the host remains unavailable for rearming. A resident daemon needs a live authenticated controller lifeline independent of a request's EOF: the existing C `shutdown(SHUT_WR)` is normal request completion. Relay exit, daemon PPID, a released socket or a reused PID cannot substitute for controller-death supervision.

Public APIs do not provide an atomic transaction across kernel process info, Security, WindowServer, AX and SCK. A transient change and change-back can escape observations; a pre/post capture sandwich cannot prove the pixels' historical origin against a malicious target. Record the real interval and limitations. Do not describe `identity_check:matched` as `atomic:true` or remote attestation. Calls requiring an unachievable guarantee fail before dispatch.

On post-dispatch failure, the response is `ok:false`, `phase:"postcheck"`, `dispatch_state:"dispatched"` (or `"unknown"` if uncertain), `side_effects_possible:true` for an action/launch, and `retryable:false`. Reads have no action effects but their data is discarded. A transport loss after submission means outcome unknown; do not resend an action merely because its proof was lost. A nonce-status query may return non-sensitive status and digests, never re-execute the operation or recover sensitive content after revocation.

XYZStudio verifies the response independently before model delivery, image persistence, tool records or UI publication: trusted executor/channel, protocol/schema, request/nonce/digests, required assurance, full observed binding, policy/revisions, deadline and current origin/kill/lock/lease. Its final publication gate is serialized with revocation. Proof success cannot bypass a later kill or make an old screenshot publishable. Audit should store bounded codes/digests/identity references, not screenshots, AX text, titles, nonce secrets or raw OS error text by default.

**Response replay (L2-06):** the host retains a pending-request record created before submission, binding controller/executor/session/boot, sequence, nonce and request digest. Verification and the transition from pending to published/discarded are atomic with the final publication gate. At most one response can publish to any sink; a duplicate or a response with no live pending record cannot restore authority, publish a tool record twice, or trigger another action. Terminal records remain until session expiry, with bounded capacity that refuses new work rather than evicts live replay protection. Executor nonce consumption prevents repeat execution; it does not replace this host-side proof-consumption rule. Restart/restore cannot recreate pending requests from chat logs or recorded proofs.

## 5. CLI and wire surface

All names below are proposed. Protocol version and feature capability are separate from binary version.

| Surface | Contract |
| --- | --- |
| `xyzlcu capabilities --json` | Non-content metadata: executor build/content identity, supported proof schemas/transports, macOS API availability and per-route assurance/limitations. TCC status is current observation, not a grant. No proof of target identity from a version string. |
| `xyzlcu windows --thumbnails --json [--show-all]` | Owner-only picker catalog, versioned JSON with fresh identity observations and optional SCK thumbnails (§8). Existing `windows` output stays an array without these flags. |
| `xyzlcu bind-window --request-fd N` | Owner session consumes a fresh catalog token/revision, revalidates it and creates an expiring binding/token. No guessed PID/window authorization. This is unavailable to the model. |
| `xyzlcu <screenshot\|ax\|press\|set-text\|click> --consumer xyzstudio --proof-protocol 1 --request-fd N [--hmac-key-fd K]` | The complete structured envelope (§6), including expected binding, nonce, operation and typed arguments, is read from a private FD. CLI verb must match envelope operation. No additional selectors/positional action data. |
| `xyzlcu open-app --bundle-id X --consumer xyzstudio --proof-protocol 1 --request-fd N [--hmac-key-fd K]` | X must equal the frozen expected app binding. Background launch only in v1; no URLs, documents or arguments (§9). |

`--request-fd` includes expected binding and nonce so they are not exposed in argv/process listings. An equivalent owner API may construct this envelope without a CLI. Do not add a model-facing `--expected-json`, arbitrary proof downgrade, policy path, shell/argv execution or key-selection mechanism. File output paths, where enabled outside the consumer, must use a private owner-controlled destination; consumer image transfer is inline bounded base64 in the post-validated envelope (or a future reviewed FD transport).

Consumer mode is an executor-enforced typed profile. It MUST reject `--allow-global`, `allowGlobal`, `--allow-foreground`, `--unsafe`, `--no-lock`, global environment switches, `--via events/paste/pid`, `--cli`, screen/display/region capture, activation, arbitrary CLI/MCP forwarding, batching, replay, menus, asynchronous popup workers and unsupported command aliases. Reject even conflicting options which would otherwise be ignored. A named already-frontmost app does not permit global input.

Initial action support, if its assurance gates pass, is synchronous window-local AXPress on a pinned ordinary button, AX value writes with explicit pre/postconditions, and coordinate click only when a guarded hit test identifies the approved element and dispatch uses its supported AX action. No generic PID mouse/key route qualifies as control delivery proof. `postToPid` targets a process and window fields are hints; it cannot prove which control consumed an event. Unsupported controls remain unavailable. T4 is not an XYZLCU flag or bypass.

### 5.1 Daemon, direct execution, MCP and workers

Today the C client forwards most argv to the Unix daemon with `proto:2`; absent daemon or version mismatch can lead to direct `execv` of the adjacent Swift core. `XYZLCU_CORE`, socket/environment overrides, MCP fallback and worker routes exist. A parent/client must never manufacture a proof for a child/daemon operation.

Proposed consumer transport is a separately negotiated **daemon protocol 3**, supporting bounded structured envelopes and FD passing (`SCM_RIGHTS`) or an equivalent reviewed private-session setup. It checks directory 0700, socket 0600, owner/type/link constraints, same-UID peer credentials and session/key binding. Same UID alone does not authenticate XYZStudio. Bind executor boot/start/build identity, session ID, controller instance, policy revision, lock revision and request sequence to the authenticated channel. Reject shared mutable cwd/environment overlays affecting another session.

An FD number in client argv is process-local: forwarding `3` to a resident daemon does not transfer the binding/key. The C relay must transfer the actual descriptor safely, or read a bounded envelope and pass bytes with explicit sensitive handling. The daemon creates its proof/HMAC using **its own** observed state after performing the operation. Close received FDs, bound counts/lengths, prevent FD leakage to target apps/children, never place secret bytes in argv/logs, and isolate concurrent sessions. An old daemon cannot emit this new protocol's errors: the new relay maps failed negotiation, legacy-only replies or legacy version-mismatch code 98 to local `PROOF_PROTOCOL_UNSUPPORTED`, without submitting a primitive. Only a negotiated protocol-3 executor emits the new execution envelopes.

Direct execution may use the same protocol/coordinator, with `execution_mode:"direct"` and its own executor identity. FD inheritance must be intentional. Consumer direct mode inherits an initially empty private bootstrap channel through client-to-core exec, authenticates the actual executed core/channel, then delivers key/request bytes; inherited FD availability does not authorize prefilling secrets before admission. Any key/request FD is closed before launching anything else. Direct mode cannot reuse daemon AX handles or pretend to retain continuity across invocations. An owner may choose direct execution **before** submitting a request if its required capabilities are supported. There is no legacy version-mismatch restart/fallback or retry after a proof request might have reached an executor.

Consumer startup pins canonical client/core paths and verified distributed signatures or exact trusted content hashes. It ignores/rejects untrusted `XYZLCU_CORE`, socket/cwd/environment redirection. A daemon is verified as well, not merely its relay. The existing `build.sh` ad-hoc signatures and ignored signing failures are not trusted publisher distribution; release requirements appear in §12.

**Bootstrap order (L2-05):** authenticate the actual connected executor before sending a key FD, expected binding, action text or other sensitive request. A reviewed OS-bound peer mechanism must bind the connection to its boot/PID/exact kernel start/runtime code/build pin; bracket PID-based lookups and refuse ambiguous/reused peers. A socket filename, UID, self-reported `executor` JSON, or an HMAC using a key just handed to that endpoint is insufficient. The executor independently authenticates the controller and its backend-assigned role; `profile:"xyzstudio"`/owner strings cannot grant admission. Bind a fresh connection challenge and the complete controller/executor identities, negotiated profile/protocol/integrity and policy into the authenticated handshake transcript; both endpoints verify it before accepting operation traffic. Reconnect/restart requires fresh admission and invalidates old pending work. A C relay must transport this authenticated channel without gaining authority to invent another executor's proof. If the supported OS/transport cannot establish these bindings, consumer daemon mode is unavailable. Direct mode must likewise verify the launched core and exclusively inherited private channel before credential delivery. The exact wire handshake/FD ownership and OS mechanism remain implementation release gates, not an assertion that current protocol 2 provides authentication.

A consumer MCP wrapper must use the same structured coordinator, with session credentials held in trusted host code, not model arguments. Generic MCP `xyzlcu` passthrough and escape flags are unavailable in this profile. If a worker is ever supported, it performs its own checks and produces the final authenticated proof; the parent waits for completion and validates it. v0.8.0 initially refuses existing `__ax-press` asynchronous workers. A “worker accepted” response cannot be a completed action proof.

## 6. JSON protocol, digests and errors

### 6.1 Encoding and schemas

Schema URI family is `urn:xyzlcu:identity-proof:1`. All JSON is UTF-8, finite numbers only, duplicate keys rejected **before** construction of a generic JSON value, unknown fields rejected and integer range checked. Normal requests are at most 256 KiB / depth 24; AX content and image results have separately negotiated hard limits (initial 4 MiB AX JSON, 32 MiB encoded image, 64 MiB complete response). Fail rather than truncate a hashed payload invisibly. Catalog pagination has a separate 8 MiB page limit. A schema change affecting identity, hashing or semantics requires negotiation; an unknown major version fails. Minor additive extensions are accepted only in a negotiated, explicitly typed extension, not as arbitrary ignored fields.

The following JSON Schema 2020-12 is the proposed **closed core schema**, not implemented validation code. Select `#/$defs/Request`, `Binding` or `Success` as an entry point. Semantic rules below remain mandatory, especially operation/argument matching, signing kinds, array uniqueness/order, canonical paths and assurance. Example IDs/digests are not shipped trust pins.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "urn:xyzlcu:identity-proof:1",
  "$ref": "#/$defs/Request",
  "$defs": {
    "Digest": {"type":"string","pattern":"^[0-9a-f]{64}$"},
    "Token": {"type":"string","minLength":22,"maxLength":128,"pattern":"^[A-Za-z0-9_-]+$"},
    "Counter": {"type":"string","pattern":"^(0|[1-9][0-9]{0,19})$"},
    "Frame": {
      "type":"object","additionalProperties":false,
      "required":["x","y","width","height"],
      "properties":{"x":{"type":"number"},"y":{"type":"number"},"width":{"type":"number","exclusiveMinimum":0},"height":{"type":"number","exclusiveMinimum":0}}
    },
    "FileIdentity": {
      "type":"object","additionalProperties":false,"required":["device","inode","sha256"],
      "properties":{"device":{"$ref":"#/$defs/Counter"},"inode":{"$ref":"#/$defs/Counter"},"sha256":{"$ref":"#/$defs/Digest"}}
    },
    "Signing": {
      "type":"object","additionalProperties":false,
      "required":["kind","valid","team_id","signing_identifier","cdhash","cdhash_algorithm","architecture","designated_requirement","requirement_sha256"],
      "properties":{
        "kind":{"enum":["developer_id","app_store","apple_platform","adhoc_fixture"]},
        "valid":{"const":true},"team_id":{"type":["string","null"],"minLength":1,"maxLength":128},
        "signing_identifier":{"type":"string","minLength":1,"maxLength":512},
        "cdhash":{"type":"string","pattern":"^[0-9a-f]{40,64}$"},
        "cdhash_algorithm":{"enum":["sha1","sha256","sha256_truncated"]},
        "architecture":{"enum":["arm64","arm64e","x86_64"]},
        "designated_requirement":{"type":"string","minLength":1,"maxLength":8192},
        "requirement_sha256":{"$ref":"#/$defs/Digest"}
      }
    },
    "App": {
      "type":"object","additionalProperties":false,
      "required":["bundle_id","bundle_path","executable_path","executable_file","signing"],
      "properties":{
        "bundle_id":{"type":"string","minLength":3,"maxLength":255},
        "bundle_path":{"type":"string","minLength":1,"maxLength":4096},
        "executable_path":{"type":"string","minLength":1,"maxLength":4096},
        "executable_file":{"$ref":"#/$defs/FileIdentity"},"signing":{"$ref":"#/$defs/Signing"}
      }
    },
    "Process": {
      "type":"object","additionalProperties":false,
      "required":["boot_id","pid","uid","start_time","app"],
      "properties":{
        "boot_id":{"type":"string","format":"uuid"},"pid":{"type":"integer","minimum":1,"maximum":2147483647},
        "uid":{"type":"integer","minimum":0},
        "start_time":{
          "type":"object","additionalProperties":false,"required":["seconds","microseconds"],
          "properties":{"seconds":{"$ref":"#/$defs/Counter"},"microseconds":{"type":"integer","minimum":0,"maximum":999999}}
        },
        "app":{"$ref":"#/$defs/App"}
      }
    },
    "Display": {
      "type":"object","additionalProperties":false,"required":["id","uuid","frame","scale","rotation"],
      "properties":{"id":{"type":"integer","minimum":1},"uuid":{"type":"string","format":"uuid"},"frame":{"$ref":"#/$defs/Frame"},"scale":{"type":"number","exclusiveMinimum":0},"rotation":{"type":"number"}}
    },
    "Window": {
      "type":"object","additionalProperties":false,
      "required":["id","owner_pid","layer","frame","onscreen","displays","coordinate_space","content_transform_sha256","instance_token","instance_provider"],
      "properties":{
        "id":{"type":"integer","minimum":1,"maximum":4294967295},"owner_pid":{"type":"integer","minimum":1},"layer":{"type":"integer"},
        "frame":{"$ref":"#/$defs/Frame"},"onscreen":{"type":"boolean"},
        "displays":{"type":"array","minItems":1,"maxItems":32,"items":{"$ref":"#/$defs/Display"}},
        "coordinate_space":{"const":"desktop-top-left-points-v1"},
        "content_transform_sha256":{"$ref":"#/$defs/Digest"},
        "instance_token":{"type":["string","null"],"maxLength":128},"instance_provider":{"type":["string","null"],"maxLength":256}
      }
    },
    "AXSegment": {
      "type":"object","additionalProperties":false,"required":["child_index","role","subrole","identifier"],
      "properties":{"child_index":{"type":"integer","minimum":0},"role":{"type":"string","minLength":1,"maxLength":256},"subrole":{"type":["string","null"],"maxLength":256},"identifier":{"type":["string","null"],"maxLength":4096}}
    },
    "Element": {
      "type":"object","additionalProperties":false,
      "required":["token","path","role","subrole","identifier","title_sha256","frame","actions","state_sha256","context_sha256","observation_id","observation_revision","instance_provider"],
      "properties":{
        "token":{"$ref":"#/$defs/Token"},"path":{"type":"array","minItems":1,"maxItems":64,"items":{"$ref":"#/$defs/AXSegment"}},
        "role":{"type":"string","minLength":1,"maxLength":256},"subrole":{"type":["string","null"],"maxLength":256},"identifier":{"type":["string","null"],"maxLength":4096},
        "title_sha256":{"$ref":"#/$defs/Digest"},"frame":{"$ref":"#/$defs/Frame"},
        "actions":{"type":"array","maxItems":32,"uniqueItems":true,"items":{"type":"string","maxLength":256}},
        "state_sha256":{"$ref":"#/$defs/Digest"},"context_sha256":{"$ref":"#/$defs/Digest"},
        "observation_id":{"$ref":"#/$defs/Token"},"observation_revision":{"$ref":"#/$defs/Counter"},
        "instance_provider":{"type":["string","null"],"maxLength":256}
      }
    },
    "Binding": {
      "type":"object","additionalProperties":false,
      "required":["binding_token","process","window","element","context_sha256"],
      "properties":{"binding_token":{"$ref":"#/$defs/Token"},"process":{"$ref":"#/$defs/Process"},"window":{"$ref":"#/$defs/Window"},"element":{"oneOf":[{"$ref":"#/$defs/Element"},{"type":"null"}]},"context_sha256":{"$ref":"#/$defs/Digest"}}
    },
    "LaunchBinding": {
      "type":"object","additionalProperties":false,"required":["app","existing_process","allowlist_revision"],
      "properties":{"app":{"$ref":"#/$defs/App"},"existing_process":{"oneOf":[{"$ref":"#/$defs/Process"},{"type":"null"}]},"allowlist_revision":{"$ref":"#/$defs/Counter"}}
    },
    "Assurance": {"enum":["process-instance","window-observed","window-instance","element-observed","element-instance","surface-continuity","launch-observed","launch-exact"]},
    "MAC": {
      "oneOf":[{"type":"null"},{"type":"object","additionalProperties":false,"required":["algorithm","key_id","tag"],"properties":{"algorithm":{"const":"hmac-sha256"},"key_id":{"$ref":"#/$defs/Token"},"tag":{"$ref":"#/$defs/Digest"}}}]
    },
    "Request": {
      "type":"object","additionalProperties":false,
      "required":["schema_version","profile","session_id","controller_id","lock_revision","policy_sha256","nonce","sequence","deadline","operation","expected","required_assurance","frame_tolerance_pt","catalog_context","arguments","mac"],
      "properties":{
        "schema_version":{"const":1},"profile":{"enum":["xyzstudio","owner_diagnostic"]},
        "session_id":{"$ref":"#/$defs/Token"},"controller_id":{"$ref":"#/$defs/Token"},
        "lock_revision":{"$ref":"#/$defs/Counter"},"policy_sha256":{"$ref":"#/$defs/Digest"},
        "nonce":{"type":"string","pattern":"^[A-Za-z0-9_-]{43}$"},"sequence":{"$ref":"#/$defs/Counter"},
        "deadline":{"type":"object","additionalProperties":false,"required":["boot_id","continuous_ns"],"properties":{"boot_id":{"type":"string","format":"uuid"},"continuous_ns":{"$ref":"#/$defs/Counter"}}},
        "operation":{"enum":["screenshot","ax","press","set-text","click","open-app"]},
        "expected":{"oneOf":[{"$ref":"#/$defs/Binding"},{"$ref":"#/$defs/LaunchBinding"}]},
        "required_assurance":{"type":"array","minItems":1,"uniqueItems":true,"items":{"$ref":"#/$defs/Assurance"}},
        "frame_tolerance_pt":{"type":"number","minimum":0,"maximum":1},
        "catalog_context":{"oneOf":[{"type":"null"},{"type":"object","additionalProperties":false,"required":["catalog_revision","target_id"],"properties":{"catalog_revision":{"$ref":"#/$defs/Token"},"target_id":{"$ref":"#/$defs/Token"}}}]},
        "arguments":{
          "oneOf":[
            {"type":"object","additionalProperties":false,"required":["format","max_pixel_edge"],"properties":{"format":{"enum":["png","jpeg"]},"max_pixel_edge":{"type":"integer","minimum":1,"maximum":8192}}},
            {"type":"object","additionalProperties":false,"required":["max_depth","max_nodes"],"properties":{"max_depth":{"type":"integer","minimum":1,"maximum":64},"max_nodes":{"type":"integer","minimum":1,"maximum":10000}}},
            {"type":"object","additionalProperties":false,"required":["action"],"properties":{"action":{"const":"AXPress"}}},
            {"type":"object","additionalProperties":false,"required":["text","precondition_sha256","postcondition_sha256"],"properties":{"text":{"type":"string","maxLength":65536},"precondition_sha256":{"$ref":"#/$defs/Digest"},"postcondition_sha256":{"$ref":"#/$defs/Digest"}}},
            {"type":"object","additionalProperties":false,"required":["x","y","action"],"properties":{"x":{"type":"number"},"y":{"type":"number"},"action":{"const":"AXPress"}}},
            {"type":"object","additionalProperties":false,"required":["bundle_id","activates"],"properties":{"bundle_id":{"type":"string","minLength":3,"maxLength":255},"activates":{"const":false}}}
          ]
        },
        "mac":{"$ref":"#/$defs/MAC"}
      }
    },
    "Instant": {
      "type":"object","additionalProperties":false,"required":["continuous_ns","wall_utc"],
      "properties":{"continuous_ns":{"$ref":"#/$defs/Counter"},"wall_utc":{"type":"string","format":"date-time"}}
    },
    "Interval": {
      "type":"object","additionalProperties":false,"required":["start","end"],
      "properties":{"start":{"$ref":"#/$defs/Instant"},"end":{"$ref":"#/$defs/Instant"}}
    },
    "Payload": {
      "type":"object","additionalProperties":false,
      "required":["kind","sha256","byte_length","media_type","pixel_sha256","pixel_width","pixel_height"],
      "properties":{
        "kind":{"enum":["image","ax_json","action_receipt","launch_receipt"]},"sha256":{"$ref":"#/$defs/Digest"},"byte_length":{"type":"integer","minimum":0},
        "media_type":{"enum":["image/png","image/jpeg","application/json"]},"pixel_sha256":{"oneOf":[{"$ref":"#/$defs/Digest"},{"type":"null"}]},
        "pixel_width":{"type":["integer","null"],"minimum":1},"pixel_height":{"type":["integer","null"],"minimum":1}
      }
    },
    "Policy": {
      "type":"object","additionalProperties":false,"required":["sha256","catalog_revision","classification","decision","matched_rule_ids","surface_classification","surface_evidence"],
      "properties":{"sha256":{"$ref":"#/$defs/Digest"},"catalog_revision":{"type":"string","maxLength":128},"classification":{"enum":["known_unprotected","unknown"]},"decision":{"const":"allow"},"matched_rule_ids":{"type":"array","maxItems":64,"items":{"type":"string","maxLength":128}},"surface_classification":{"enum":["allowed","unknown"]},"surface_evidence":{"oneOf":[{"type":"null"},{"$ref":"#/$defs/SurfaceEvidence"}]}}
    },
    "SurfaceEvidence": {
      "type":"object","additionalProperties":false,"required":["provider","provider_version","evidence_revision","subject_binding_sha256","context_sha256","attribution_sha256","composition_sha256","continuity_token","observed_at","evidence_sha256"],
      "properties":{"provider":{"type":"string","minLength":1,"maxLength":256},"provider_version":{"type":"string","minLength":1,"maxLength":128},"evidence_revision":{"$ref":"#/$defs/Counter"},"subject_binding_sha256":{"$ref":"#/$defs/Digest"},"context_sha256":{"$ref":"#/$defs/Digest"},"attribution_sha256":{"$ref":"#/$defs/Digest"},"composition_sha256":{"$ref":"#/$defs/Digest"},"continuity_token":{"$ref":"#/$defs/Token"},"observed_at":{"$ref":"#/$defs/Instant"},"evidence_sha256":{"$ref":"#/$defs/Digest"}}
    },
    "Proof": {
      "type":"object","additionalProperties":false,
      "required":["schema_version","session_id","controller_id","lock_revision","nonce","sequence","operation","request_sha256","expected_binding_sha256","executor","observed_pre","observed_post","timing","assurance","identity_check","effect_verification","policy","payload","route","limitations","mac"],
      "properties":{
        "schema_version":{"const":1},"session_id":{"$ref":"#/$defs/Token"},"controller_id":{"$ref":"#/$defs/Token"},"lock_revision":{"$ref":"#/$defs/Counter"},
        "nonce":{"type":"string","pattern":"^[A-Za-z0-9_-]{43}$"},"sequence":{"$ref":"#/$defs/Counter"},"operation":{"enum":["screenshot","ax","press","set-text","click","open-app"]},
        "request_sha256":{"$ref":"#/$defs/Digest"},"expected_binding_sha256":{"$ref":"#/$defs/Digest"},
        "executor":{"type":"object","additionalProperties":false,"required":["pid","start_time","boot_id","build_sha256","execution_mode","client_build_sha256"],"properties":{"pid":{"type":"integer","minimum":1},"start_time":{"$ref":"#/$defs/Counter"},"boot_id":{"type":"string","format":"uuid"},"build_sha256":{"$ref":"#/$defs/Digest"},"execution_mode":{"enum":["daemon","direct","mcp_core","worker"]},"client_build_sha256":{"oneOf":[{"$ref":"#/$defs/Digest"},{"type":"null"}]}}},
        "observed_pre":{"oneOf":[{"$ref":"#/$defs/Binding"},{"$ref":"#/$defs/LaunchBinding"}]},
        "observed_post":{"oneOf":[{"$ref":"#/$defs/Binding"},{"$ref":"#/$defs/Process"}]},
        "timing":{"type":"object","additionalProperties":false,"required":["precheck","operation","postcheck","release","source_frame_continuous_ns"],"properties":{"precheck":{"$ref":"#/$defs/Interval"},"operation":{"$ref":"#/$defs/Interval"},"postcheck":{"$ref":"#/$defs/Interval"},"release":{"$ref":"#/$defs/Instant"},"source_frame_continuous_ns":{"oneOf":[{"$ref":"#/$defs/Counter"},{"type":"null"}]}}},
        "assurance":{"type":"array","minItems":1,"uniqueItems":true,"items":{"$ref":"#/$defs/Assurance"}},
        "identity_check":{"const":"matched"},"effect_verification":{"enum":["verified","unverified","not_applicable"]},
        "policy":{"$ref":"#/$defs/Policy"},"payload":{"$ref":"#/$defs/Payload"},
        "route":{"enum":["sck-window-screenshot","sck-window-stream-once","ax-read","ax-press","ax-set-value","appkit-background-launch"]},
        "limitations":{"type":"array","maxItems":32,"items":{"type":"string","maxLength":128}},"mac":{"$ref":"#/$defs/MAC"}
      }
    },
    "Success": {
      "type":"object","additionalProperties":false,"required":["ok","proof","result"],
      "properties":{"ok":{"const":true},"proof":{"$ref":"#/$defs/Proof"},"result":{"type":"object","additionalProperties":false,"required":["encoding","data"],"properties":{"encoding":{"enum":["base64","jcs-json"]},"data":{"type":"string"}}}}
    }
  }
}
```

Mandatory semantic validation supplements the schema:

- `screenshot` accepts only image arguments, a window binding, and `element:null`; `ax` accepts only depth/node arguments and a binding rooted at the approved window/subtree. `press`, `set-text` and `click` require a non-null element and their corresponding argument shape. `open-app` requires launch binding and launch arguments, no window. No cross-operation shape is accepted just because it matches another `oneOf` branch.
- Consumer defaults require `process-instance`, `window-instance` and `surface-continuity` for every window operation, including owner thumbnails. AX reads additionally require a reviewed AX-window/source mapping and context continuity for the root and every returned element; the complete read must establish `element-instance`, or refuse. Actions require `element-instance` for the approved target/context, including the coordinate hit-test target. `element-observed` alone never satisfies these minima. The caller cannot remove profile-required assurance. `open-app` in XYZStudio requires `launch-exact` and reviewed launch-surface support. Diagnostic observed-only requests never satisfy those gates.
- `catalog_context` is non-null only for an owner-authorized thumbnail `screenshot` request, binding the exact candidate token/revision into the request digest/MAC; it is mandatory there and must be null for ordinary locked-window/launch requests. Session admission determines the owner role; a Request profile string cannot grant it. Picker access is not a model tool.
- `surface_classification:allowed` requires fresh `SurfaceEvidence` from a reviewed executor provider, bound to the exact expected subject/context and evidence revision. Unknown uses null. Provider/version, binding/context/evidence digests and observation time are rechecked at dispatch/release; a string enum or caller-supplied classifier result is insufficient. Attribution/composition digests refer to retained, versioned provider records of the verified family/host graph and all included surfaces (§7.1/§8.1); their closed schemas and supported OS/app scope must be frozen before enabling that provider. `continuity_token` refers to provider-established continuity throughout the primitive, not an executor-created assertion of safety. Matching pre/post classifications cannot alone satisfy `surface-continuity`. Loss of this capability refuses before access, or discards a result if lost in flight. For launch, subject evidence binds the approved App/LaunchBinding and its supported safety scope rather than inventing a window; the token proves the relevant admission-to-submit scope only and grants no later content access.
- `observed_pre/post` have the same operation-specific subject type, except launch: pre is LaunchBinding and post is Process. The new process must match the pinned App; if an existing process was frozen it must be the same instance. For intentional AX value changes, only frozen operation postconditions permit state changes; identity fields never change.
- Time counters encode unsigned 64-bit nanoseconds as decimal strings, avoiding JSON/JavaScript precision loss. Executor `start_time` is kernel seconds * 1,000,000 + microseconds, encoded as a decimal string; target Process retains both components. `continuous_ns` is `mach_continuous_time` converted with checked integer arithmetic and a boot-scoped common epoch. It includes sleep. Deadlines are never derived from wall time; enforce ordering and same boot. Wall UTC is RFC 3339 observation metadata and may move backwards; report clock discontinuity rather than using it for expiry.
- Nonces are 32 OS-random bytes, base64url without padding (43 characters with canonical final bits). Sequence is strictly increasing per session. Sessions retain a bounded consumed-nonce ledger until expiry and never evict live replay protection to accept more work. Requests outside capacity refuse. Restart invalidates sessions/keys/tokens. A nonce echo is correlation, not authentication.
- Arrays representing display sets, action sets and matched rule IDs have deterministic ordering and uniqueness. Display identity is not only an integer. Required `format` validation and path/bundle-ID validation must actually run; JSON Schema annotations alone are insufficient.
- Title hashing uses SHA-256 over `XYZLCU/TITLE/1\0` plus a presence byte (0 for absent; 1 followed by exact UTF-8 for present). Context/state/transform digest inputs have separately versioned closed schemas agreed during negotiation; if their provider cannot define/verify the relevant context, it cannot advertise strong assurance. A digest of app-supplied data alone is not context authenticity.
- `result.encoding:base64` is for encoded image bytes. `jcs-json` contains the exact canonical JSON payload as a UTF-8 string for AX/action/launch receipts; parse it strictly again before use. Limits apply before and after decoding. Success payload metadata must match actual bytes/dimensions; image width/height are decoded by the consumer.

### 6.2 Payload binding and optional integrity

Use SHA-256 with explicit domain/version prefixes. Canonical JSON is RFC 8785 JCS, with unsupported numbers rejected. Do not hash arbitrary pretty-printed JSON or an implementation's dictionary ordering.

| Digest | Exact input |
| --- | --- |
| `expected_binding_sha256` | `XYZLCU/BINDING/1\0` + JCS of complete `expected` |
| `request_sha256` | `XYZLCU/REQUEST/1\0` + JCS of the entire Request with `mac:null`; includes operation/arguments, nonce, deadline, profile, policy and epochs |
| `payload.sha256` | `XYZLCU/PAYLOAD/1\0` + exact decoded image file bytes or exact JCS UTF-8 receipt/AX bytes |
| `pixel_sha256` | `XYZLCU/PIXELS/1\0` + uint32 big-endian width + uint32 big-endian height + canonical captured pixels: top-down, sRGB, RGBA8, straight alpha, no row padding; non-images use null |
| Policy digest | `XYZLCU/POLICY/1\0` + JCS of effective built-in catalog, accepted overlay/revision, mandatory session self/helper exclusions, reviewed attribution/surface provider versions and their versions/revisions; per-operation graph/composition digests are additionally bound by SurfaceEvidence |

Pixels mean the final captured/cropped/scaled raster before PNG/JPEG encoding. Record pixel dimensions and the complete content transform in the binding/context. JPEG is lossy: its decoded pixels cannot reproduce the pre-encoding pixel digest. XYZStudio can always verify encoded-file `payload.sha256`; use PNG for reproducible pixel-digest validation, or treat the JPEG pixel hash as executor evidence only. Do not claim a JPEG decoder verifies the original raster. No proof-enabled `--diff` or previous-frame substitution in the initial release.

Without a MAC, JSON+digests detect accidental corruption and bind returned bytes to the stated observation; an attacker can forge both. Even MACed output is a local trusted-executor statement, not an Apple certificate of pixel provenance or independent attestation. XYZStudio pins the executor separately and compares observed values to its own lock, never just `identity_check`.

Optional integrity uses a fresh 256-bit per-session key generated by XYZStudio, passed via a private FD after authenticated bootstrap (§5.1). Only direct `owner_diagnostic` controlled launches may accept `XYZLCU_PROOF_KEY_B64` as an explicit weaker environment alternative; it is forbidden for XYZStudio consumer sessions because it delivers a secret before live-core admission. Clear it immediately after diagnostic loading, exclude it from forwarded environment/logs/crash diagnostics as far as possible, never pass it to apps/children, and disclose its weaker exposure. A resident daemon cannot read a new client's environment automatically; it needs authenticated session establishment/FD transfer. Never serialize the key into the legacy argv/env protocol.

Request MAC = HMAC-SHA256(key, `XYZLCU/REQUEST-MAC/1\0` + JCS(Request with `mac:null`)). Proof MAC = HMAC-SHA256(key, `XYZLCU/PROOF-MAC/1\0` + JCS(Proof with `mac:null`)). The proof covers request digest, nonce, executor, pre/post observations/timing, policy, route, assurance and payload digest. Key IDs are opaque and never key material. Compare tags in constant time; wrong key/session/MAC refuses before dispatch or consumer publication. Sessions negotiate integrity mode once; `mac:null` cannot downgrade a MAC-required session. Authenticate admitted-session refusal envelopes too in MAC mode. Pre-admission parsing/negotiation errors without an identifiable trusted session/key are unauthenticated, contain no sensitive details, cannot report successful execution and never authorize a retry. Rotation/daemon death ends the session; keys are not persisted and are cleared on expiry/close.

A stolen same-UID key or compromised executor can forge an HMAC. FD delivery and private permissions reduce accidental disclosure; they do not repair an unrestricted same-UID execution threat. Stronger isolation would require a separately protected service/sandbox and authenticated OS IPC, with its own design.

### 6.3 Failure schema and stable error taxonomy

The proposed failure envelope is also closed and versioned. `proof` and `result` MUST NOT appear. It intentionally does not echo sensitive observed titles, AX text, pixels or full paths; detailed diagnostics are owner-only and sanitized.

```json
{
  "$schema":"https://json-schema.org/draft/2020-12/schema",
  "$id":"urn:xyzlcu:identity-error:1",
  "type":"object","additionalProperties":false,
  "required":["schema_version","ok","code","exit_code","nonce","phase","dispatch_state","side_effects_possible","retryable","mismatch_fields","message","mac"],
  "properties":{
    "schema_version":{"const":1},"ok":{"const":false},
    "code":{"type":"string","pattern":"^[A-Z][A-Z0-9_]+$"},"exit_code":{"type":"integer","minimum":1,"maximum":255},
    "nonce":{"type":["string","null"],"maxLength":43},
    "phase":{"enum":["parse","negotiate","precheck","operation","postcheck","release"]},
    "dispatch_state":{"enum":["not_dispatched","dispatched","unknown"]},
    "side_effects_possible":{"type":"boolean"},"retryable":{"const":false},
    "mismatch_fields":{"type":"array","maxItems":32,"items":{"type":"string","maxLength":128}},
    "message":{"type":"string","maxLength":256},
    "mac":{"oneOf":[{"type":"null"},{"type":"object","additionalProperties":false,"required":["algorithm","key_id","tag"],"properties":{"algorithm":{"const":"hmac-sha256"},"key_id":{"type":"string","maxLength":128},"tag":{"type":"string","pattern":"^[0-9a-f]{64}$"}}}]}
  }
}
```

Error MAC uses `XYZLCU/ERROR-MAC/1\0` + JCS(envelope with `mac:null`). Only echo a nonce after canonical syntax validation; otherwise use null. Unknown fields and malformed input never trigger an operation. `mismatch_fields` contains schema paths/codes, not raw values. Error codes are stable strings; `exit_code` is separately numeric. For multiple failures choose policy/invalid identity over descriptive details; do not expose protected-content diagnostics.

| Proposed code | Condition | Exit |
| --- | --- | --- |
| `INVALID_REQUEST`, `DUPLICATE_JSON_KEY`, `REQUEST_TOO_LARGE` | Parsing/shape/limits, conflicting flags or wrong operation arguments | 2 |
| `PROOF_PROTOCOL_UNSUPPORTED`, `PROOF_CAPABILITY_UNSUPPORTED` | Old transport/schema or unsupported route/assurance | 3 |
| `GLOBAL_INPUT_FORBIDDEN`, `CONSUMER_ROUTE_FORBIDDEN` | Global/foreground/pasteboard/pid-event escape or disallowed command | 4 |
| `SESSION_INVALID`, `BINDING_REQUIRED`, `BINDING_STALE`, `REQUEST_REPLAYED`, `REQUEST_EXPIRED`, `BOOT_MISMATCH` | Session/lock/nonce/deadline/boot mismatch | 4 |
| `PROCESS_NOT_FOUND`, `PROCESS_IDENTITY_UNAVAILABLE`, `PROCESS_UID_MISMATCH` | Missing process, unavailable start time, incorrect owner | 4 |
| `PID_REUSED`, `PROCESS_START_MISMATCH` | PID now has a different start incarnation; alternate start evidence disagrees | 4 |
| `SIGNATURE_INVALID`, `SIGNING_IDENTITY_MISMATCH`, `BUNDLE_ID_MISMATCH`, `EXECUTABLE_IDENTITY_MISMATCH` | Invalid code or changed team/signing ID/cdhash/requirement/bundle/path/content/file identity | 4 |
| `WINDOW_NOT_FOUND`, `WINDOW_ID_REUSED`, `WINDOW_OWNER_MISMATCH`, `WINDOW_LAYER_MISMATCH` | Closed/reused/changed window or owner/layer mismatch | 4 |
| `WINDOW_FRAME_MISMATCH`, `DISPLAY_BINDING_MISMATCH`, `COORDINATE_MAPPING_UNPROVABLE` | Frame exceeds tolerance, screen/topology/scale/rotation changed, unknown transform | 4 |
| `AX_WINDOW_UNPROVABLE`, `AX_TARGET_MISMATCH`, `AX_ELEMENT_REPLACED`, `AX_TARGET_AMBIGUOUS`, `AX_CONTEXT_MISMATCH`, `AX_INSTANCE_UNPROVABLE` | Mapping/fingerprint/retained handle/context/instance continuity failure | 4 |
| `IDENTITY_UNPROVABLE` | Required identity/continuity is fundamentally unavailable, including indistinguishable window ABA | 4 |
| `PROTECTED_APP_REFUSED`, `PROTECTED_IDENTITY_SUSPICIOUS`, `SURFACE_CLASSIFICATION_UNPROVABLE` | Denylist match, protected ID with wrong signer, or consumer unknown/forbidden surface | 4 |
| `POLICY_INVALID`, `POLICY_CHANGED`, `POLICY_PERMISSION_INVALID` | Corrupt/untrusted/changed policy or unsafe file permissions/links | 4 |
| `TCC_SCREEN_RECORDING_REQUIRED`, `TCC_ACCESSIBILITY_REQUIRED`, `SESSION_LOCKED` | Missing/revoked permission or locked/sleeping desktop | 5 |
| `CAPTURE_UNAVAILABLE`, `CAPTURE_TIMEOUT`, `CAPTURE_FRAME_STALE`, `CAPTURE_SOURCE_UNPROVABLE`, `CAPTURE_CLEANUP_FAILED` | SCK unavailable/timeout/stale/unknown source or stream cannot be safely stopped | 5 |
| `AX_READ_FAILED`, `AX_ACTION_FAILED`, `EFFECT_UNVERIFIED` | Primitive failure or required effect verification unavailable | 5 |
| `APP_NOT_FOUND`, `APP_PATH_REFUSED`, `APP_RESOLUTION_AMBIGUOUS`, `APP_IDENTITY_CHANGED`, `LAUNCH_BINDING_UNPROVABLE`, `LAUNCH_FAILED`, `LAUNCH_OUTCOME_UNKNOWN` | Safe launch validation/submission/result failures | 5 |
| `APP_TRUST_UNPROVABLE`, `APP_TRUST_REFUSED` | Unsupported/unknown system launch assessment or blocked/approval-needed quarantine/trust state | 5 |
| `PROOF_MAC_INVALID`, `PAYLOAD_DIGEST_MISMATCH`, `EXECUTOR_UNTRUSTED` | Request/channel/executor or consumer response verification fails | 4 |
| `CANCELLED`, `PARENT_CHANNEL_LOST`, `DEADLINE_EXCEEDED`, `OUTCOME_UNKNOWN` | Revocation, supervision loss, timeout or uncertain dispatch | 6 |
| `INTERNAL_ERROR` | Sanitized internal failure; never a success fallback | 1 |

Specific mismatch code is preserved if discovered in postcheck; the `phase` and `side_effects_possible` fields describe timing rather than replacing every failure with a generic postcheck code. If no authoritative reuse evidence exists, use `IDENTITY_UNPROVABLE`, not a fabricated `WINDOW_ID_REUSED`. Permission codes do not automatically open Settings or prompt. Errors never suggest consumer escape flags.

Example: no payload is returned after a detected window move during an action:

```json
{"schema_version":1,"ok":false,"code":"WINDOW_FRAME_MISMATCH","exit_code":4,"nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","phase":"postcheck","dispatch_state":"dispatched","side_effects_possible":true,"retryable":false,"mismatch_fields":["window.frame.x"],"message":"Target changed; choose the window and prepare again.","mac":null}
```

The all-zero nonce above is documentation data; production nonces must be random. A consumer verification error such as payload mismatch is a local rejection, even if the executor sent `ok:true`.

## 7. Protected applications and owner policy

### 7.1 Default catalog and matching

Ship a versioned built-in catalog embedded in the trusted executor distribution. Matching uses the **verified bundle ID plus validated signing Team ID/publisher requirement**, with signing identifier/Apple anchor as appropriate. Names, localized names, process basenames, window titles and fuzzy app-name matching never determine a deny decision. A Team ID is not guessed or derived from a bundle prefix. Apple rules may use `team_id:null` with a verified Apple anchor. A known protected bundle ID whose signature/team differs or is missing is `PROTECTED_IDENTITY_SUSPICIOUS`, not an unknown allowed app. A known protected publisher/signing-ID alias is handled similarly.

The release catalog MUST cover these families and verified release variants/helpers. The IDs below are catalog seeds, not a complete trusted signer database. Except where noted, third-party team/requirement pins must be collected from validated vendor release artifacts before shipping. A missing signer pin leaves that protected seed conservatively refused as unverified; it must not silently drop the rule. Product renames, channels and new bundle IDs require catalog maintenance.

**Protected-family attribution (L2-02):** flat bundle rules are only leaves of policy evaluation. Before any content access/action/launch, a reviewed attribution provider MUST evaluate the actual window/AX owner and the verified enclosing application, nested XPC/login helper, extension/plug-in and hosting application relationships relevant to that surface. Validate each code identity and signed package membership or an OS-authenticated host/extension association; cache only within a verified process incarnation. PPID ancestry, pathname containment, common Team ID, display name and app-reported relationship/URL alone do not establish this graph. A protected node dominates an otherwise ordinary host/owner verdict. A renamed/moved `.app` retaining protected signed identity stays protected; changed IDs/signatures do not erase a verified family relationship. A completely repackaged unknown app cannot be recognized universally: Studio denies Unknown rather than claiming a denylist catches every clone.

System Settings extensions and shared security/authentication hosts must be attributed beyond `com.apple.systempreferences`. Browser/web-view/Electron password managers, bank pages, terminal/devtools/extension-management and local administration surfaces require reviewed current-surface/host support; the browser or Electron publisher signature does not classify hosted content. Unknown relevant relationships/surfaces are unavailable in Studio. Do not refuse every app sharing a publisher as a substitute for verified attribution. Bind the attribution-provider/version and graph digest into surface evidence/effective policy; changes invalidate observations and pending calls. User overlay rules add denials, never create trusted host edges or Allowed surface evidence. Until the graph/context providers and closed evidence schemas are reviewed, advertise these targets as unsupported.

| Category | Required product coverage | Bundle-ID seeds / validation notes |
| --- | --- | --- |
| Password managers | 1Password | `com.1password.1password`, older `com.agilebits.onepassword7`; verify supported release variants and vendor Team/requirement |
| Password managers | Bitwarden | `com.bitwarden.desktop`; validate macOS distribution variants rather than using a Linux app ID as evidence |
| Password managers | LastPass | `com.lastpass.LastPass`; release artifact verification required |
| Password managers | Dashlane | `com.dashlane.Dashlane`; release artifact verification required |
| Password managers | KeePassXC | `org.keepassxc.keepassxc`; include owner-installed/ad-hoc variants as suspicious/unverified protected seeds |
| Apple secrets | Passwords; Keychain Access | `com.apple.Passwords`, `com.apple.keychainaccess`; validate Apple anchor, including OS-version path variants |
| System/security management | System Settings / System Preferences | `com.apple.systempreferences`; whole-app refusal, including Privacy & Security/TCC |
| Code execution hosts | Terminal; iTerm2 | `com.apple.Terminal`, `com.googlecode.iterm2` |
| Code execution hosts | Warp; Ghostty | `dev.warp.Warp-Stable` and reviewed channel IDs; `com.mitchellh.ghostty` |
| Code execution hosts | Alacritty; kitty; WezTerm | `org.alacritty`, `net.kovidgoyal.kitty`, `com.github.wez.wezterm`; verify supported channels/signers |
| Payment-capable clients | WeChat for Mac | `com.tencent.xinWeChat`, observed locally with Team `5A4RE8SF68`; this is a seed requiring validity/requirement verification on supported release artifacts, not a blanket trust pin |
| Banking/payment compatibility apps | PayPal; Alipay where installable | Known mobile-family seeds `com.yourcompany.PPClient` (PayPal), `com.alipay.iphoneclient` (Alipay); verify current official app metadata, macOS availability, team and requirement before shipping verified publisher pins; do not claim every iOS app runs on macOS |

Banking/payment coverage is necessarily incomplete across regions and distribution channels. Owner additions support exact verified bundle/team pairs and restricted, anchored bundle-ID glob patterns under specified verified publishers, e.g. a bank's verified namespace `com.examplebank.*` with that bank's pinned publisher. `com.examplebank.*` is illustrative, not a known bank. Matching is on IDs, never `*Bank*` app names or window text. No unrestricted regex, script or model-supplied pattern is executed. Built-in known payment IDs plus configurable verified-ID patterns are defense in depth, not detection of bank websites inside browsers.

Whole-app System Settings refusal is deliberate: pane navigation is dynamic, AX titles/localization are unreliable, and a supposedly harmless pane can transition to Privacy & Security, accounts or authentication before dispatch. No pane-only classifier currently proves isolation. Thus refusing the entire app is more reliable than pretending title/pane checks isolate TCC. Terminals are refused because their ordinary function is arbitrary command execution, even if the visible text appears harmless.

Catalog results distinguish `protected`, `known_unprotected`, `unknown` and `suspicious_identity`. In XYZLCU's base denylist policy, a valid signed app not recognized by the catalog is **unknown → allowed but explicitly reported** (`classification:"unknown", decision:"allow"`). Unknown identity/signature is never allowed. This is separate from subinterface safety: a browser may be an ordinary app while displaying a password manager, payment site, developer tools or local administration UI.

**XYZStudio remains stricter:** its app/window/current-surface classifier uses `Allowed / Protected / Unknown`; Unknown is denied for reads and actions. Consumer profile enforces `SURFACE_CLASSIFICATION_UNPROVABLE` unless a reviewed provider supplies allowed surface evidence. A caller cannot simply set `surface_classification:"allowed"`. LCU's unknown→allowed base behavior does not satisfy this gate. XYZStudio session admission MUST receive backend-verified exclusion pins for every XYZStudio instance, its owner panel and permission helpers, including publisher/helper relationships; missing or unverifiable exclusions refuse session admission. Bind these immutable exclusions into the effective policy/session digest and recheck them at each operation. No model flag, tier, owner removal or app relaunch can bypass them.

### 7.2 User-only configuration

Proposed fixed file: `~/Library/Application Support/XYZLCU/protected-apps.v1.json`; directory 0700, file 0600, owned by the effective user. Discover the user home from the trusted account context, not a model-controlled `HOME`. There is no consumer `--policy-file` or environment override. Owner-only development tests may inject an in-memory policy provider rather than point production at arbitrary files.

XYZLCU reads this file; XYZStudio edits it **only from the isolated owner UI/backend**, never model tools, general Settings imports, chat text, MCP or arbitrary CLI. Before read/write verify every relevant path component, regular-file type, UID, mode, no symlink, file link count exactly one, bounded size (256 KiB), strict schema and revision. Open from verified directory descriptors with no-follow semantics and verify the opened descriptor; compare metadata to avoid component/path races. Invalid/missing-required policy or unsafe existing permissions fail closed, without silently substituting an empty denylist. An absent optional overlay means the immutable built-in catalog only on explicitly initialized first use, subject to the high-water rule below. Write atomically through a private 0600 temp file in the same 0700 directory, fsync file and directory, and increment revision; in-flight operations with the old digest are invalidated.

**Policy continuity (L2-07):** the trusted owner/controller persists whether an overlay has been accepted/required and its latest revision/digest before authorizing sessions. Once accepted, file disappearance, lower revision, same revision with different bytes/effective digest, or missing/unreadable continuity state is `POLICY_INVALID`, never an implicit reset to built-ins. An authorized owner reset writes a new higher-revision explicit empty overlay and revokes sessions; deleting the file is not a reset operation. The consumer passes its expected policy digest/high-water identity on session admission and every operation; a new direct process or restarted daemon cannot silently bootstrap weaker defaults. Reconcile policy file and durable owner state under one policy-update coordinator before granting authority; interrupted updates block until explicit owner recovery. Bound the accepted content as well as revision, and invalidate on any change even if a watcher misses it. These checks detect rollback/loss within the stated trust boundary, not a malicious same-UID actor able to rewrite both file and trusted state.

The closed overlay shape is:

```json
{
  "schema_version": 1,
  "revision": "1",
  "additions": [],
  "allow_builtin_removals": false,
  "removed_builtin_rule_ids": []
}
```

Each addition is a closed rule `{rule_id, category, bundle_id_pattern, team_id, designated_requirement, signing_identifiers}` with bounded strings/arrays; exact IDs or the restricted final-component glob grammar only. Apple entries require an Apple anchor; third-party patterns require an exact reviewed Team/publisher requirement. Rule IDs are unique. Categories and pattern grammar are schema-versioned, never free executable predicates. Default union is built-ins plus additions. User deletion of an addition is still an explicit owner policy change and invalidates pending calls.

Proposed policy JSON Schema (publisher validation, glob grammar and immutable consumer rules also require semantic checks):

```json
{
  "$schema":"https://json-schema.org/draft/2020-12/schema",
  "$id":"urn:xyzlcu:protected-policy:1",
  "type":"object","additionalProperties":false,
  "required":["schema_version","revision","additions","allow_builtin_removals","removed_builtin_rule_ids"],
  "properties":{
    "schema_version":{"const":1},"revision":{"type":"string","pattern":"^[1-9][0-9]{0,19}$"},
    "additions":{"type":"array","maxItems":256,"items":{"$ref":"#/$defs/Rule"}},
    "allow_builtin_removals":{"type":"boolean"},
    "removed_builtin_rule_ids":{"type":"array","maxItems":256,"uniqueItems":true,"items":{"type":"string","minLength":1,"maxLength":128}}
  },
  "allOf":[{"if":{"properties":{"allow_builtin_removals":{"const":false}}},"then":{"properties":{"removed_builtin_rule_ids":{"maxItems":0}}}}],
  "$defs":{
    "Rule":{
      "type":"object","additionalProperties":false,
      "required":["rule_id","category","bundle_id_pattern","team_id","designated_requirement","signing_identifiers"],
      "properties":{
        "rule_id":{"type":"string","minLength":1,"maxLength":128},
        "category":{"enum":["password_manager","apple_secrets","system_security","terminal","banking_payment","owner_addition"]},
        "bundle_id_pattern":{"type":"string","minLength":3,"maxLength":255},
        "team_id":{"type":["string","null"],"minLength":1,"maxLength":128},
        "designated_requirement":{"type":"string","minLength":1,"maxLength":8192},
        "signing_identifiers":{"type":"array","minItems":1,"maxItems":32,"uniqueItems":true,"items":{"type":"string","minLength":1,"maxLength":512}}
      }
    }
  }
}
```

Additions are permitted through owner UI without weakening defaults. Removing built-ins requires both a nonempty explicit rule-ID list and the user-only **`allow_builtin_removals:true` flag**, written after a separate owner confirmation showing exact rules. The default false flag plus an attempted removal is `POLICY_INVALID`. There is no action/request `--allow-protected` escape and no model-facing switch to set this flag. XYZStudio MUST reject removals for its immutable protected categories/self/helpers even if another LCU owner application uses that base-policy feature; higher tiers/approvals never override them. Report effective policy digest/revision and removed-rule state to owner diagnostics.

“Not writable by the model” means XYZStudio's broker does not offer any tool/capability able to edit the policy, key, executor or owner UI, including indirect shell/terminal/filesystem writes. 0600 does **not** distinguish the owner UI from another process under the same UID. If a deployment grants unrestricted same-UID shell/file write to the model, it cannot make this claim; it needs an external sandbox/helper privilege boundary or keeps these consumer capabilities disabled. An HMAC on the overlay can detect accidental/uncredentialed changes within the session trust boundary but cannot solve arbitrary same-UID key theft.

## 8. ScreenCaptureKit capture and picker thumbnails

### 8.1 One-window capture

Use fresh `SCShareableContent` to get the exact validated `SCWindow`. Build `SCContentFilter(desktopIndependentWindow:)`; use `SCScreenshotManager.captureImage` on macOS 14+ and a one-frame `SCStream` on macOS 13. API availability is runtime checked. No `CGWindowListCreateImage`, display capture, private WindowServer image API, `/usr/sbin/screencapture`, activation, unminimize, Space switch, or desktop crop is an alternative route.

**Capture composition (L2-03):** freeze the complete inclusion/compositing scope, not only the main window ID. Where available (macOS 14.2+), explicitly set `includeChildWindows=false`; verify actual API/OS behavior in acceptance rather than relying on a default. This option is not proof that an app's own surface contains no embedded protected content. Attached authentication sheets, extension-hosted panels, web views and any included child/composited surfaces require the attribution and Allowed surface-continuity checks too. On older OS versions or unsupported composition providers, if the required exclusion/continuity cannot be established, refuse before capture. Never capture first and inspect pixels/AX content to decide whether capture was permitted.

The proof route bypasses the existing 30-second shareable-content cache and streams keyed only by `w<windowID>`. For v0.8.0 start with a fresh one-shot capture/stream per operation; no prewarm display stream and no frame from before the request. Future caches must be keyed by complete process/start/signature + window incarnation + session/lock/policy generation + geometry/scale and still pass all boundary checks. The current “latest cached frame after deadline” behavior must never enter proof mode.

**Producer lifecycle (L2-09):** a dedicated consumer executor MUST never start legacy display prewarm/live/diff producers. Reusing a daemon requires a quiescence barrier before consumer admission: stop and await all prior capture producers, detach late callbacks, clear shareable-content/stream buffers, diff baselines, thumbnails and encoded images, then establish the new policy/session. Cleanup uncertainty means unavailable. Legacy traffic cannot coexist and restart a producer in that consumer executor. All v0.8 capture producers, including legacy background callbacks, are subject to protected policy at acquisition time; merely withholding their output is insufficient. Policy/session revocation stops affected producers and invalidates their retained data. In-flight non-cancellable callbacks may finish privately, but cannot repopulate a live cache or publish after their generation is invalidated. A stream without sufficient ongoing protected-surface exclusion is unsupported, even with `--allow-global`.

For macOS 13: install the stream output before start, accept only a valid nonempty `.complete` screen frame associated with the request's filter, copy the surface while valid, check its contentRect/scale against the bound transform, and stop/remove the stream before release. Wait for bounded stop completion; timeout/error is a failure. Reject idle/blank/incomplete frames and stale samples; do not treat a previous cached image as an answer when no frame arrives. For 14+, record the actual capture API invocation/callback interval; if the API provides no authoritative source-frame timestamp use `source_frame_continuous_ns:null`, not the callback time masquerading as pixel creation time. SCStream sample timing is only converted into this boot clock after its clock mapping is verified; otherwise null with an explicit limitation. A caller requiring unavailable source freshness gets `CAPTURE_SOURCE_UNPROVABLE`.

Bind crop/contentRect, shadow policy, output dimensions, color space and point-to-pixel mapping. Exclude shadows where supported, use reviewed contentRect cropping on the macOS 13 single-window stream, and never read pixels outside that surface. A covered window may be captureable; minimized/off-Space/protected-content surfaces may be missing, stale or blank. Missing/uncertain frames refuse; capture does not alter the user's desktop to fix them. Unchanged/blank content alone cannot prove whether an app rendered recently or whether all secure content is present; report limits rather than inventing that evidence.

### 8.2 `windows --thumbnails` catalog

This command is for a human picker, exposed only through a trusted owner session in XYZStudio. It is not a model enumeration tool and does not establish a lock or grant. Catalog discovery has an explicit owner authorization scope; since the user has not selected a window yet, it cannot pretend to use a pre-existing user lock for every row. Each thumbnail is individually bound to its freshly observed candidate and guarded pre/post capture before release.

The discovery exception authorizes bounded metadata/icons only. **Every thumbnail separately requires Allowed application/window/current-composition evidence and `surface-continuity` before capture**, under the same immutable Studio exclusions as locked-window reads. Human picker ownership and `--show-all` do not waive this gate. Unknown browser/Electron/extension-hosted surfaces remain metadata-only/unavailable; no screenshot or AX-content probe may bootstrap classification. If even a title/icon source would expose protected content, use a fixed generic category/icon and omit the title. Freeze attribution/composition/context revisions in each candidate's evidence and invalidate on change before/during capture or before publication. A future classifier cannot be enabled just because it emits the string Allowed.

Default candidate filters: CG/SC agree, layer 0, onscreen and intersects an active screen, nonzero opacity where known, frame at least **120 × 80 pt**, nonempty trimmed title. Sort main candidates by descending area with stable owner/window tie-breaks. `--show-all` relaxes title/min-size/layer/onscreen discovery filters and marks reasons; it never relaxes protected policy, signing, self/helper exclusions, source proof or capture checks. Missing geometry is `null` and unselectable, never fabricated as zero. Compatibility `windows --all` retains its legacy meaning; it is not an alias that bypasses proof rules.

Return small aspect-preserving thumbnails bounded to 256 × 160 pixels (PNG by default), at most 20 per page and 8 MiB total. Metadata pagination prevents unbounded enumeration/capture cost. Downsampling occurs inside the guarded SCK operation; compute digests for the returned raster/file. No full-size image or AX content is needed for the picker. Protected rows are omitted by default; show-all may return a redacted unavailable category row without sensitive title/thumbnail. Owner UI can use a local app icon with `thumbnail_status:"unavailable"` and a reason. An icon must never be labeled a captured window thumbnail.

Catalog envelope schema is closed: `{schema_version:1, catalog_revision, executor, generated_at, policy_sha256, entries, next_cursor, omitted_counts}`. `executor` and `generated_at` reuse §6 types; catalog revision/cursor are opaque session-scoped tokens. Each closed entry contains `{target_id, display_label, title, frame, filter_reasons, identity, selectable, unavailable_code, thumbnail_status, thumbnail}`:

- `target_id` is random, short-lived, bound to executor/session/catalog/policy revision and the observed candidate. It is not an encoded bare window number. TTL is at most 5 seconds; selection refreshes and revalidates, never extends the old token silently.
- `identity` is a complete observed `Binding` when available (element null), otherwise null with an unavailable code; full identity is never silently partial. It includes PID/start/signature/bundle/path and window owner/layer/frame/displays. `frame` may be null when metadata is incomplete; `selectable:false` then follows.
- `thumbnail_status` is `captured | unavailable | refused`. `thumbnail` is null or `{encoding:"base64", data, proof}`; proof uses the same capture evidence/payload hashing as §6 plus the catalog token/revision binding in its owner request. A failed thumbnail may leave a clearly marked metadata row, never an unproved successful image. No mixed/partial success inside an image proof.
- Display label/title are untrusted escaped UI text and are absent/redacted for protected entries. Filter reasons, omission counts and errors are bounded typed codes. No title is used to authorize selection.

The proposed closed catalog schema reuses the identity schema by URI. Load these schemas from a trusted local registry, never by following request-controlled remote references:

```json
{
  "$schema":"https://json-schema.org/draft/2020-12/schema",
  "$id":"urn:xyzlcu:window-catalog:1",
  "type":"object","additionalProperties":false,
  "required":["schema_version","catalog_revision","executor","generated_at","policy_sha256","entries","next_cursor","omitted_counts"],
  "properties":{
    "schema_version":{"const":1},"catalog_revision":{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Token"},
    "executor":{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Proof/properties/executor"},
    "generated_at":{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Instant"},
    "policy_sha256":{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Digest"},
    "entries":{"type":"array","maxItems":20,"items":{"$ref":"#/$defs/Entry"}},
    "next_cursor":{"oneOf":[{"type":"null"},{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Token"}]},
    "omitted_counts":{"type":"object","additionalProperties":false,"required":["protected","filtered","unavailable"],"properties":{"protected":{"type":"integer","minimum":0},"filtered":{"type":"integer","minimum":0},"unavailable":{"type":"integer","minimum":0}}}
  },
  "$defs":{
    "Entry":{
      "type":"object","additionalProperties":false,
      "required":["target_id","display_label","title","frame","filter_reasons","identity","selectable","unavailable_code","thumbnail_status","thumbnail"],
      "properties":{
        "target_id":{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Token"},
        "display_label":{"type":"string","maxLength":512},"title":{"type":["string","null"],"maxLength":4096},
        "frame":{"oneOf":[{"type":"null"},{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Frame"}]},
        "filter_reasons":{"type":"array","maxItems":16,"uniqueItems":true,"items":{"enum":["nonzero_layer","offscreen","too_small","untitled","transparent","unknown_geometry"]}},
        "identity":{"oneOf":[{"type":"null"},{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Binding"}]},
        "selectable":{"type":"boolean"},"unavailable_code":{"type":["string","null"],"maxLength":128},
        "thumbnail_status":{"enum":["captured","unavailable","refused"]},
        "thumbnail":{"oneOf":[{"type":"null"},{"type":"object","additionalProperties":false,"required":["encoding","data","proof"],"properties":{"encoding":{"const":"base64"},"data":{"type":"string"},"proof":{"$ref":"urn:xyzlcu:identity-proof:1#/$defs/Proof"}}}]}
      }
    }
  }
}
```

Semantic checks enforce captured status iff thumbnail is non-null, screenshot proof/catalog-context/digests match the exact entry, null identity/frame implies unselectable, protected entries have no title/thumbnail, and page byte/time budgets. Pagination/canonicalization conformance vectors and context/receipt schemas remain required L3 contract artifacts before implementation acceptance. No catalog token is usable as a Request binding until `bind-window` checks freshness, actual current identity and required assurance. Unknown/unprovable candidates can be displayed as unavailable; XYZStudio may continue to exclude them entirely.

### 8.3 Screen Recording / Accessibility TCC

SCK capture and thumbnails require live Screen Recording authorization in the responsible process/launching context; AX reads/actions require Accessibility separately. TCC attribution can differ between a direct core, host-launched daemon and worker, so check the actual execution path and responsible host on each supported OS. Do not promise permissions automatically transfer from Terminal to a background daemon. A picker may show CG metadata/icons while capture is denied, but it must label missing titles/geometry/identity and thumbnail unavailability truthfully.

Consumer execution never requests TCC or opens System Settings. Return the corresponding error; the separate owner UI may explain or initiate a fixed system workflow. Do not prompt during a model operation or assume historical permission status is current. Revocation during capture is failure and discards output. Tests with fake TCC or a build alone do not establish real-Mac Screen Recording/AX behavior.

## 9. Safe `open-app --bundle-id X`

This is a new typed command, separate from legacy `open` (`/usr/bin/open -a`) and `activate`. It launches an installed approved application with **no arguments, no URLs, no documents, no custom Apple Event and no caller environment injection**. It does not select, capture or lock any window.

1. Validate X as a bounded ASCII reverse-DNS identifier with no whitespace, path/URL separators or shell syntax. Consumer model input selects only an entry already permitted by the owner launch allowlist. The request carries its frozen `App`, optional existing `Process`, allowlist revision and required assurance; the model cannot supply a path/requirement itself.
2. Resolve with `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`. Its heuristic result is discovery only. If multiple installations exist (enumerate applicable candidates), require the owner's unique pinned canonical path; do not launch whichever Launch Services happened to prefer. A resolution differing from the expected app is `APP_RESOLUTION_AMBIGUOUS` or `APP_IDENTITY_CHANGED`.
3. Canonicalize the final `.app` and executable, inspect opened file identities and validate signature/requirement, bundle/signing ID and publisher. Allow component descendants only of canonical `/Applications`, `/System/Applications`, or canonical `~/Applications`. XYZStudio enables the user root only through owner policy. Reject symlink escapes, `/ApplicationsEvil`, Downloads/tmp, translocated apps, remote/external volumes, invalid/unsigned signatures and nested helper/plugin bundles pretending to be a user launch app. Pin exact approved file/content identity, revalidate before submission, and detect changes across resolution/signature checks. Roots alone do not establish code trust. Apply the system-trust gate below at admission and submission.
4. Evaluate built-in/user protected rules, suspicious identities and consumer self/helper/surface exclusions before launch. A protected app returns `PROTECTED_APP_REFUSED`, even when approved by a model action card. Unknown catalog apps follow base-policy reporting; XYZStudio's stricter allowlist/surface support still applies.
5. Require a provider satisfying requested launch assurance **before** calling AppKit. A checked path can be replaced between check and AppKit's open. `allowsRunningApplicationSubstitution:false` reduces a documented substitution behavior; it does not create an atomic inode/code pin. Generic observed launch may report that limitation, but XYZStudio requiring `launch-exact` receives `LAUNCH_BINDING_UNPROVABLE` unless a reviewed dispatcher can establish it. Never substitute post-launch validation for this precondition.
6. Submit only `NSWorkspace.openApplication(at: validatedURL, configuration: configuration, completionHandler:)`. Explicit configuration: `arguments=[]`, `environment=[:]` (no injected values; not a claim that AppKit sanitizes every ambient OS environment), `appleEvent=nil`, `activates=false`, `allowsRunningApplicationSubstitution=false`, `createsNewApplicationInstance=false`, `promptsUserIfNeeded=false`, `addsToRecentItems=false`. No `open -b/-a`, shell, `osascript`, generic URL open, fallback resolver or later activate call. Public AppKit/Gatekeeper may still display OS UI or the app may activate itself; no guarantee of suppressing all target/system behavior.
7. `activates=false` is both default and fixed consumer-v1 behavior: background launch avoids stealing focus, gives the user a chance to choose a window, and does not imply input permission. There is no consumer `--activate` option. This is narrower than XYZStudio's current design phrase “open/activate”; adopting it requires a consumer contract/UI update rather than silently claiming activation occurred.
8. Upon callback, verify returned PID, exact start time, runtime/static signing identity, bundle and executable against the approved app. If it was already running, require the frozen instance; report `already_running_verified` without activating it. Otherwise report `launched_verified`. Recheck at release and return a Process proof with nonce/timing/request/payload digests. Callback success alone is not an identity proof. Mismatch returns failure and `side_effects_possible:true`; do not kill the user's app as rollback.

Launch receipt canonical JSON contains `{status, process, activates_requested:false, frontmost_changed, requires_user_lock:true}`; `process` is the full §6 Process and `status` is `launched_verified | already_running_verified`. `frontmost_changed` is observation, not necessarily attributable to this command. It is included in the hashed payload. Pre/post proof includes the resolved App/static pin and resulting live process. No window list, screenshot or auto-lock is returned to the model.

The host must register cancellation/parent supervision before submission, serialize its launch permit with kill/Tools OFF/deadlines, and retain the original turn/owner cancellation and minimum deadline even after intentionally ending its old lock/session. XYZStudio's current 10-second approval-to-submit and 20-second operation budgets remain maxima. Failure does not restore the old lock/T4 lease. At OS acceptance the launch may be irreversible; cancellation/timeout reports `LAUNCH_OUTCOME_UNKNOWN`/possible effects, releases no stale sensitive output, never retries automatically, and never claims launch was prevented merely because the callback was cancelled. Parent/daemon channel loss must stop further primitives; supervision design and acceptance remain separate release gates.

**System trust/quarantine (L2-08):** signature validity is separate from current system launch policy. A reviewed OS-version-specific trust-assessment provider must establish that this exact installed app is eligible for this no-prompt launch at owner admission and immediately before submit. Blocked, approval-needed, translocated, changed or unknown assessment/installation state refuses before AppKit; use `APP_TRUST_UNPROVABLE` or `APP_TRUST_REFUSED` (exit 5). The provider/evidence schema, freshness, notarization/revocation/offline behavior and supported system assessment API are release gates. No supported assessment means launch unavailable, not an invented universal Gatekeeper certificate.

Never remove/alter quarantine or provenance attributes, approve first launch, disable/override Gatekeeper, change trust/assessment databases, relocate an app to evade policy, or fall back to another launcher/URL scheme to recover. `promptsUserIfNeeded=false` does not bypass this gate. Neither a valid Developer ID signature nor absence of quarantine establishes trustworthy launch eligibility. Use supported system/resource APIs for quarantine observations rather than undocumented raw attribute-bit parsing. Owner installation/first-launch handling occurs separately outside the model workflow, followed by fresh allowlist identity, assessment and approval. The app may still restore its own documents, activate or perform application behavior; no arguments and a valid signature do not sandbox it. Where that behavior cannot satisfy required surface/launch scope, do not admit the app.

## 10. Backward compatibility with 0.7.1

| Existing behavior | v0.8.0 proposal |
| --- | --- |
| Bare `windows`, plain/compact AX, image stdout, legacy JSON shapes | Preserve normal successful formats for legacy callers; new proof/catalog flags select versioned envelopes. Do not claim legacy output is a proof. |
| PID/window/title lock persisted at the socket location | Legacy lock may remain for legacy use. It cannot be upgraded into a consumer binding; require new owner selection/start/signing/instance checks. Never load unsafe/tombstoned/corrupt state as proof authority. |
| C/Swift daemon `proto:2`, `XYZ2` frames, version-mismatch direct fallback | Keep for legacy callers. Consumer uses negotiated protocol 3 and no downgrade/retry after possible submission. Unknown proof flags MUST fail before an old parser can perform an operation. Host never probes capability by executing a real action. |
| Existing `--allow-global`, `--allow-foreground`, unsafe locks, frontmost-target gate | Syntax/opt-in intent may remain for standalone legacy callers, subject to the protected-recipient rule below; these flags never override policy and unsupported global writes now refuse. They are structurally unavailable to consumers. A consumer session cannot be switched to legacy mode with an argv/env flag. No documentation example tells XYZStudio to use them. |
| `verified:true` from AX state change / successful legacy route | Preserve legacy meaning only there; proof mode separates identity assurance and effect verification. It does not relabel an old success as proof. |
| Legacy `open`/`activate` and arbitrary MCP tool | Keep outside consumer profile subject to protection rules; `open-app` is a separate typed safe-launch operation. Never route consumer launch through legacy open. |
| Unchecked content access to default protected apps | Intentionally tightened: v0.8 refuses default protected/suspicious apps before capture/AX/action/launch on all entry points, including legacy paths. If identity cannot be verified well enough to apply policy, refuse. Document this safety compatibility break in both READMEs/changelog. |
| Display capture, recording/replay and other broad legacy routes | Not consumer features. To avoid bypassing the protected policy, broad reads must be refused when they cannot exclude protected content; never promise whole-screen protected-content isolation from window checks. Legacy broad/global commands do not gain consumer credentials. |

Proof support is opt-in at the API/format level, but the default protected policy is not optional merely because a caller uses an old command. Maintain legacy numeric exit meanings where possible; new proof mode standardizes string `code` plus numeric `exit_code`. Existing `--all` and aliases must not become policy escapes. New errors must be nonzero and parseable; never reinterpret an identity failure as “try normal screenshot”.

**Protected recipients on legacy writes (L2-04):** `--allow-global`/foreground/unsafe opt-ins are not protection overrides. Before any global input, pointer hit, activation, pasteboard mutation or multi-event operation, a reviewed route must establish that every actual recipient/effect scope is permitted throughout dispatch. Unscoped global input and generic HID/coordinate/PID-event delivery cannot establish this with frontmost PID snapshots; refuse those routes where protection cannot be maintained. A protected sheet/new focus between checks, or a pointer landing on another window, cannot be repaired by a postcheck. Each event in a supported sequence needs its own barrier and recipient guarantee; never pre-authorize a whole replay/batch. Shared pasteboard writes and unverifiable legacy `open -a` resolution also refuse when they cannot satisfy the universal protection rule. This intentionally narrows legacy functionality; document it in release migration notes instead of promising full behavioral compatibility. General all-app global automation would require a separately reviewed policy/product, not an escape flag in this contract.

## 11. Test and verification plan

L1 and this L2 security critique perform document/schema/link consistency checks only; no implementation or runtime tests are run because there is no implementation. The later implementation adds meaningful tests around the coordinator/providers rather than merely checking JSON echoes. Test results must distinguish unit fakes, signed build, real TCC, real fixture GUI, third-party app support and release acceptance.

### 11.1 Permission-free unit/contract tests with injectable fakes

Use deterministic clocks, process/signature/window/AX providers and a trace of primitive invocations/output writes. For every refusal-before-dispatch, assert **zero capture/content-read/action/launch calls**, no published bytes and no fallback. For postcheck refusal assert no sensitive output, correct possible-effects state, invalidated tokens and no retry.

| Area | Required cases |
| --- | --- |
| Process | Exact match, missing/partial proc info, seconds/microseconds mismatch, forced same-PID new start, boot change, UID change, exec-in-place with unchanged start, process disappears during SecCode lookup |
| Signing | Team/signing ID/cdhash/architecture/requirement mismatch; invalid/unsigned code; signed Info/bundle inconsistency; path/symlink/inode/content replacement; Apple null-Team anchor; ad-hoc fixture cannot get production grants |
| Window | Same ID/new owner, same ID/new start, known same-process recreation, indistinguishable ABA returns unprovable under strict requirements, layer/frame beyond tolerance, exact boundary values, screen hotplug/UUID/scale/rotation change, CG/SC disagreement, missing metadata, two same-title windows never retarget |
| AX | Changed path/index/role/subrole/identifier/title hash; null vs empty; retained handle invalidated/replaced; identical descriptors without continuity refuse; duplicate matches; unprovable AX/CG association; document navigation, overlay, action/state/context change; hit test lands on different element; each nested read/action rechecks |
| Policy | Every protected product/category; expected bundle but wrong/missing team becomes suspicious; identical name/different valid ID is not a name-based match; Apple anchors; unknown signed app allowed+reported in base mode but denied for Studio unknown surface; patterns cannot execute regex/scripts |
| Policy file | Explicit first-use absence uses built-ins; accepted-overlay disappearance refuses; invalid JSON/duplicate fields/type/version; wrong UID/mode, symlink/hardlink/path race/oversize; additions; default removal refusal; explicit owner flag+exact list; immutable Studio deny survives removals; revision changes between guard/release |
| Capture | One exact SCK filter; 13 complete-frame/stop path; 14 callback path; no cached pre-request image; no fallback to display/CLI/deprecated API; timeout/blank/incomplete/unknown source/cleanup failure; geometry/contentRect mismatch; stale postcheck output discarded |
| Protocol/integrity | Strict schemas and semantic shape, duplicate keys before Value parsing, size/depth/UTF-8/nonfinite/counter limits, canonical JCS/hash vectors, nonce reuse/expiry/sequence/capacity/boot, MAC wrong key/session/domain/request/payload, downgrade refusal, JPEG-vs-PNG pixel hash semantics |
| Execution route | Client is relay only; proof executor PID is daemon/direct/worker actually performing operation; FD number alone is not transfer; old proto refuses before dispatch; no resend after timeout/partial send; sessions do not share refs/cwd/env or policy state |
| Launch | Protected refusal; duplicate bundle installations; roots/component boundary/symlink/network/translocation escape; signature invalid; resolved app changes; app replaced at submit; exact assurance unavailable means zero AppKit call; explicit false activation/substitution; args/URL/docs/env rejected; callback PID/start/signature mismatch; already-running instance and cancellation outcome |
| Consumer/global | Every global/foreground/unsafe/no-lock/paste/pid route, alias, env and generic MCP attempt refuses before event creation, including named frontmost app; observer loss and cancellation before each primitive; no production test-only bypass |
| Publication | Kill/policy/lock revision after payload acquisition but before release; action effect possible after post-mismatch; image/AX bytes absent from stdout/stderr/temp/cache/audit on failure; consumer current-lock check rejects an otherwise valid old proof |

L2 additions to this required matrix (planned, not executed):

| Finding | Additional acceptance cases |
| --- | --- |
| L2-01 | Inject kill/deadline/parent loss/TCC loss during slow validation and between AX focus/write/readback; cancellation is processed without the operation mutex; revocation-first dispatch count is zero, dispatch-first stops the next primitive; relay exit alone cannot acknowledge daemon cleanup |
| L2-02 | Renamed protected bundle; protected nested XPC/login helper with a different ID; System Settings extension under shared host; mismatched/reparented helper; unrelated same-Team app not automatically protected; unresolved host/extension attribution cannot become Allowed |
| L2-03 | Browser/Electron hosted password manager/bank/admin page, auth sheet/child composition, navigation change-and-back; owner/show-all thumbnail Unknown yields zero capture calls; classify-before-capture; exactly one CG/SC match and the validated SCWindow is the object passed to SCK; macOS 13/14.0 versus 14.2+ child scope |
| L2-04 | Unscoped allow-global, focus swap between guard/event, pointer on another/protected window, protected modal between sequence events, pasteboard/open/replay/MCP aliases; unsupported recipient guarantees yield zero events or next events |
| L2-05 | Wrong connected peer/build/start, socket replacement/restart, forged self-report/HMAC after key handoff, controller role spoof, reconnect transcript replay; no sensitive FD/envelope transfer before authenticated admission |
| L2-06 | Duplicate valid proof races at host publication, completed/unknown nonce response, old session/boot proof, restart/log restore, capacity exhaustion; at most one publication and no repeat action/tool record |
| L2-07 | First-use absence versus accepted overlay deletion, lower revision, same revision/different content, missing high-water state, interrupted owner update, explicit higher-revision reset; fail closed without dropping owner additions |
| L2-08 | Valid signature but unknown/blocked system trust, quarantine/assessment state change, first-launch approval needed, translocation and duplicate LS registrations; no AppKit call, quarantine edit, policy override or retry on precheck refusal |
| L2-09 | Consumer admission with active display prewarm/live/diff buffers; late callbacks after stop/timeout/revoke; simultaneous legacy request cannot restart producer; failed cleanup blocks admission; no stale buffers survive policy transition |

### 11.2 Integration: self-built background fixture

Build a small owned macOS fixture app in a disposable `~/Applications/XYZLCUIdentityFixture.app`, with two independently titled windows, deterministic rendered color/nonce, an editable text field and a button/counter. A test-only fixture protocol exposes process/window/control generation and explicit replacement events so a fixture identity provider can prove its own incarnations. Compile that provider only into a separate test artifact or explicitly isolated test profile; shipping consumer mode never accepts a model-provided fixture marker or universal fake assurance. Use a real development signature where available; an ad-hoc fixture test is labeled as such and cannot prove publisher support.

Launch using the proposed background AppKit route when testing observed launch, with another app frontmost. No documents, command arguments or URLs are needed. Verify PID/start/signature from independent process inspection; verify rendered fixture nonce/color and AX counter independently of proof status. Keep the system pointer still and observe frontmost before/during/after; no test sends global HID or activates the fixture to make a failing background action work. Close only disposable fixture windows/process instances whose identities the test still owns; never signal a reused PID/PGID.

Run daemon and direct paths separately. On macOS 13 test one-frame stream completion/cleanup; on 14+ test screenshot-manager behavior; include newest supported macOS and arm64/x86_64 execution where available. Universal compilation is not Intel runtime evidence. Exercise covered window, scaled display, two displays, move/resize/hotplug, close/recreate window, AX control recreation with identical labels, document-context change, app exit/relaunch, daemon death, parent/channel loss, permission revoke and cancellation at dispatch/release barriers. True OS PID/window-number reuse may be nondeterministic: fake it deterministically in unit tests and label any real churn test separately; never claim that merely relaunching reproduced reuse.

Test fresh nonce and payload hash against fixture pixels/AX payload. Tamper file/payload/proof/session key and replay nonce; verify consumer rejects without publishing. Compare 13/14 image geometry and contentRect; no other window's canary pixels may appear. Missing TCC produces explicit SKIP/UNAVAILABLE, not PASS. Human grants/revokes TCC via separate owner workflow; do not automate System Settings as a test target.

Protected refusal integration can use a signed test identity mapped by an injected test policy; real password managers/banking apps must never be captured or acted upon just to test the denylist. Read-only signature/catalog checks against installed products are separate evidence from invoking them. A successful cooperative fixture proves that fixture/provider/path, not all AX apps or atomic macOS behavior.

### 11.3 Consumer acceptance

XYZStudio uses recorded protocol fixtures for schema/nonce/MAC/digest/epoch negative tests, then a separately reviewed real executor and fixture. It verifies owner-only picker availability, unknown surface denial, self/helper exclusion, single-use approval, post-kill discard, every T1–T4 gate and launch workflow cancellation. Recheck parent-death supervision, cleanup ownership, old-instance exclusion and audit durability independently. These are not delivered merely by this identity design. Do not mark production tools available until the consumer can prove all required prerequisites for each supported route/app.

## 12. v0.8.0 delivery and release plan

1. **L1 (initial design):** review protocol, assurance limits, protected policy, safe-launch scope and Studio gaps. Deliver this Markdown plus a Chinese handoff summary. No source/build/version changes, no commit, no real GUI/TCC operations.
2. **L2 security critique (this change):** review against actual executor/relay and consumer requirements; deliver [IDENTITY_PROOF_REVIEW.md](IDENTITY_PROOF_REVIEW.md), incorporate every High/Medium required fix here with §14 traceability, and write the Chinese handoff. Docs only, no commit, no runtime acceptance.
3. **L3 contract/executor:** publish machine JSON Schemas for request/proof/error/catalog/policy/context/transform/receipts, attribution/composition/system-trust evidence, golden JCS/MAC/hash vectors, capabilities and transport-3/authenticated-handshake/FD specifications. Resolve reviewed provider support for window/control/surface continuity and exact launch; unsupported guarantees stay unavailable. Freeze per-route semantics with XYZStudio. Implement providers/coordinator, strict consumer profile, process/signing/window checks and replay/integrity sessions in independently buildable slices. Add fakes/contract tests as appropriate and keep consumer capabilities off until complete. Apply only the documented protected-global compatibility changes.
4. **L4 capture/policy/launch:** harden existing SCK routes, add owner thumbnails and user policy, then safe background launch. Wire direct/daemon/MCP through the same coordinator; disable worker/legacy fallback in proof mode. Complete the fixture acceptance matrix and label unprovable routes unsupported.
5. **L5 integration/security review:** independent review of race windows, parser/FD/socket/session handling, same-UID assumptions, policy removals, metadata privacy, orphan supervision and downgrade paths. XYZStudio adopts only supported capabilities and resolves its remaining gates; releasing LCU does not auto-enable Studio.
6. **Release candidate:** test `swift build` and `./build.sh` universal outputs on supported SDKs; link required Security APIs consistently in both build paths. Signing failure becomes fatal for distributed artifacts. Pin client and core separately, sign with a verified distribution identity, notarize distributed builds where applicable, record release checksums and executor build identity, verify daemon provenance and document ad-hoc local-build limits. Run required contract/unit and authorized real-Mac fixture tests, with OS/architecture/TCC/routes recorded.
7. **v0.8.0 release:** update Swift/C advertised versions, daemon protocol negotiation, both READMEs, changelog, SECURITY and migration notes only in the implementation/release phase. Ship both binaries together; invalidate prior proof sessions/keys/locks on upgrade, do not turn a 0.7.1 lock into a new authority. Explicitly describe protected-app/broad-capture compatibility refusals and observed-vs-instance assurance. Tag/publish only after separate authorization and all claimed-route checks pass.

Rollback means disable proof/consumer capabilities in the host and invalidate sessions, not route requests through 0.7.1. A host pinned to proof protocol 1 refuses older binaries/daemons. Release approval must identify any remaining unprovable capability; it must not claim universal atomic identity, all-app safety or XYZStudio enablement to justify a version number.

## 13. Evidence and reference notes

Local source/document observations above were read for L1; no XYZLCU/fixture execution, build, capture, input, app launch, TCC grant, third-party account access or publication was performed. Read-only installed-app metadata/signing-display inspection supplied the WeChat seed and confirmed Apple null-Team examples; it did not validate the whole catalog or any runtime action. Vendor pins not backed by validated release evidence remain release work.

L2 re-read the actual `cdcae18` Swift/C source and consumer design/review, combined three independent read-only agent reviews, and checked selected Apple API documentation. The installed-app observations in the preceding paragraph are historical L1 evidence and were not repeated in L2. This critique changes documentation only. The inline schemas remain proposals; parsing them does not verify an implementation, OS provenance, TCC or provider assurance.

Primary references for implementation review (API availability and behavior must also be checked against the supported SDK/OS matrix):

- [Apple: SecCodeCopyGuestWithAttributes](https://developer.apple.com/documentation/security/seccodecopyguestwithattributes(_:_:_:_:)) and [Code Signing Services](https://developer.apple.com/documentation/security/code-signing-services) — dynamic guest/validity versus static validation.
- [Apple: SecCodeCopySigningInformation](https://developer.apple.com/documentation/security/seccodecopysigninginformation(_:_:_:)) — disk-signature information is not itself a runtime-validity guarantee.
- [Apple TN3127: Inside Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/) — signing identifiers, anchors and publisher requirements.
- [Apple XNU proc_info.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h) and [proc.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc.h) — process start-time structure fields; installed SDK/public API availability must be verified.
- [Apple: SCShareableContent](https://developer.apple.com/documentation/screencapturekit/scshareablecontent), [desktop-independent window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)), [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager), and [complete frame status](https://developer.apple.com/documentation/screencapturekit/scframestatus/complete) — selected-window capture and stream frame handling.
- [Apple: NSWorkspace.OpenConfiguration](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration), [bundle-ID resolution](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(withbundleidentifier:)), and [application launch](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)) — explicit background configuration and resolved URL dispatch.
- [Apple: Accessibility identifier](https://developer.apple.com/documentation/appkit/nsaccessibility-c.protocol/accessibilityidentifier) — an app-supplied descriptor, not a universal control incarnation certificate.
- [1Password deployment guide](https://support.1password.com/deploy-1password/), [KeePassXC build metadata](https://github.com/keepassxreboot/keepassxc/blob/develop/src/CMakeLists.txt), and [Ghostty configuration](https://ghostty.org/docs/config/reference) — selected catalog seeds; do not infer code-signing teams from names/IDs.
- Apple App Store lookup records for [PayPal](https://itunes.apple.com/lookup?id=283646709&country=us) and [Alipay](https://itunes.apple.com/lookup?id=333206289&country=cn) — bundle-ID seeds verified during L1, without implying macOS installability or verified publisher/signature pins.
- [RFC 8785: JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785) — canonical digest/MAC bytes; duplicate-key rejection and bounded parsing remain independent requirements.

L2 primary-source clarifications: Apple defines [`SCWindow.windowID`](https://developer.apple.com/documentation/screencapturekit/scwindow/windowid) as the CG identifier and publishes [`includeChildWindows`](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/includechildwindows) for macOS 14.2+. Neither API provides universal content classification. [`OpenConfiguration`](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration) documents URL substitution, arguments, environment and first Apple Event controls; these do not certify checked-inode launch. Apple's [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) distinguishes subsystem trust policy from code-signature validity. These support the API distinctions, while this document's stronger refusal rules are design requirements, not Apple guarantees.

## 14. Review changes

Phase L2, 2026-11-15: [IDENTITY_PROOF_REVIEW.md](IDENTITY_PROOF_REVIEW.md) records **3 High and 6 Medium** findings against the original L1 input. Every required fix is incorporated as a normative design change below. Status is **design addressed / implementation pending**, not runtime remediated.

| Finding | Severity | Incorporated requirement |
| --- | --- | --- |
| L2-01 | High | §4 complete per-primitive dispatch/revocation barrier, out-of-band cancellation and actual-executor lifeline/cleanup |
| L2-02 | High | §7.1 verified protected-family/helper/extension/host attribution and Unknown refusal; §6 evidence/policy binding |
| L2-03 | Medium | §§6/8 explicit thumbnail Allowed gate, surface continuity and complete capture composition; §3.2 unique CG/SC matching and same validated object |
| L2-04 | High | §10 legacy global/foreground/unsafe flags cannot bypass protected-recipient guarantees; unsupported writes refuse |
| L2-05 | Medium | §5.1 authenticate connected controller/executor and handshake before credential/sensitive-request transfer |
| L2-06 | Medium | §4 host atomically consumes each proof/pending request once across all publication sinks, independently of executor nonce ledger |
| L2-07 | Medium | §7.2 accepted overlay high-water digest/revision; deletion/rollback/interrupted update blocks rather than resets policy |
| L2-08 | Medium | §9 system-trust/quarantine gate; no trust/provenance modification or fallback; explicit error codes in §6.3 |
| L2-09 | Medium | §8.1 capture-producer quiescence/cache purge before admission, no legacy coexistence/restart or late-callback repopulation |

§11.1 adds adversarial acceptance cases for every finding. §12 identifies this phase as critique; machine schemas, wire handshake/evidence specifications and implementation tests remain L3 work. Existing exact sec/usec starts, dynamic/static code pins, unsigned/ad-hoc limits, process/window/AX reuse refusals, actual proof producer and request nonce ledger were already present in L1; the review preserves and clarifies them rather than counting them as newly discovered omissions. Public macOS snapshot limitations remain: generic window/AX/surface continuity and exact launch stay unavailable unless a reviewed provider proves the required capability. Consumer background-only launch remains an explicit narrower contract requiring XYZStudio UI/contract agreement.
