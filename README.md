# XYZLCU 0.8.1

[简体中文](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Practical capture contract](docs/IDENTITY_PROOF_PRACTICAL.md) · [Strict verification](docs/IDENTITY_PROOF_VERIFICATION.md)

A local macOS CLI with an execution-time identity protocol and conservative target guards. macOS 13+, Apple Silicon or Intel. No dependencies, hosted CI, or cloud service is required.

**Strict remains the default, preserving the v0.8.0 input and capture refusals.** Public CG/AX metadata cannot prove window/control incarnation or protected-surface continuity. Requests requiring those guarantees fail before content acquisition or dispatch. `--allow-global`, foreground overrides, PID delivery, old locks and MCP passthrough cannot enable them. XYZStudio computer operations remain unavailable. Version 0.8.1 adds only an explicit owner-selected practical window screenshot route, with the residual risks documented below.

| Shipped surface | Behavior |
| --- | --- |
| `screenshot --assurance practical --request-fd N --output-dir DIR --json` | Explicit practical capture of one caller-bound window on macOS 14.2+; private image file and observed-identity proof |
| `capabilities --json` | Actual executor identity, current passive TCC observations, supported routes and explicit limitations |
| `identity-observe --pid N --nonce TOKEN --json` | Fresh kernel start-time, executable file/digest, runtime/static signing observations before and after; diagnostic metadata only |
| `identity-check --request-fd N --json` | Revalidates a complete expected process observation and echoes a canonical nonce; mismatches fail closed |
| `windows --thumbnails --json [--show-all]` | Bounded owner metadata catalog, randomized discovery tokens, protected redaction, per-entry unavailability; no generic thumbnails are acquired |
| `open-app --bundle-id ID --json` | Typed entry point; refuses with `APP_TRUST_UNPROVABLE` until a reviewed no-prompt/exact-launch provider exists |
| Structured proof/content requests | Closed schema, guarded coordinator and injected-provider tests; production consumer admission is unavailable |
| `apps`, `windows`, `displays`, `cursor`, `check`, `whoami` | Passive discovery/diagnostics; ordinary `windows` retains its array format |

The native SCK service uses the exact validated `SCWindow`, CG/SC owner/frame cross-checks, one-shot capture and no display/CLI fallback. The native AppKit dispatcher fixes no arguments/URLs/documents, no activation, no substitution and no prompt request. Only the SCK service has an explicit practical screenshot adapter; strict/consumer admission and AppKit launch remain unavailable. Generic window/element/surface continuity, authenticated consumer transport, launch trust and exact launch remain **deferred**, rather than inferred from matching descriptors. The practical capture service refuses macOS 13/14.0/14.1 where child-composition exclusion cannot be established; this release does not claim old-OS capture acceptance.

Process observations are unsigned diagnostic evidence, not content Success envelopes, publisher distribution trust, atomic OS attestation, or authority to operate an app. Ad-hoc fixture observations are explicitly identified. A PID/start-time pair alone never authorizes input.

## Explicit practical window capture

The owner can choose the lower practical assurance level for one window screenshot:

```text
xyzlcu-0.8.1 screenshot --assurance practical --request-fd N --output-dir DIR --json
```

All flags are required. The private inherited FD contains a closed request `{schema_version:1,nonce,expected:{process,window},format,max_pixel_edge}`; `expected` must be frozen by the trusted user's lock. The executor compares complete process/signing/executable and window ID/owner/layer/frame/on-screen pins before and after exact-window SCK capture. It enforces the protected denylist and writes only after checks pass, to an existing real 0700 directory with no extended ACL, using a random 0600 ACL-free file. Stdout carries a schema-versioned proof, nonce, observations, timing, encoded-byte/raw-pixel hashes and `result.path`; it contains no image/base64 bytes.

Practical cannot detect millisecond-scale same-process window-ID reuse when the checked endpoints are identical, or classify secrets embedded inside an allowed app. It supplies no authenticated consumer session or replay protection. The caller owns consent, lock and nonce lifecycle; a model must not opt in automatically. AX, input/actions, activation and `open-app` stay refused. See the [full request/response contract, errors and inherited-FD example](docs/IDENTITY_PROOF_PRACTICAL.md). `capabilities` reports this explicit route separately; strict remains default and XYZStudio tools remain disabled.

## Build and local verification

```sh
./build.sh
./scripts/unit_test.sh           # real Swift XCTest target; injectable providers
./scripts/selftest.sh            # CLI/client/MCP refusal and pure helper checks
./scripts/identity_integration_test.sh  # builds and launches only its own background fixture
./scripts/practical_integration_test.sh  # only its own background fixture
~/.local/bin/xyzlcu-0.8.1 --version  # xyzlcu 0.8.1
```

`build.sh` builds the Swift executor and C client, normally universal arm64+x86_64, verifies ad-hoc signatures, and supports an optional default-install mode. This release preserves `~/.local/bin/{xyzlcu,xyzlcu-core}` at 0.8.0: versioned pairs live in `~/.local/lib/xyzlcu/{0.8.1,0.7.1}/`, with `xyzlcu-0.8.1` and `xyzlcu-0.7.1` wrappers in `~/.local/bin`. Each wrapper disables daemon routing/restart (`XYZLCU_DAEMON=0`, `XYZLCU_AUTO_RESTART=0`) and execs its absolute versioned client path; the client finds its co-located core. Do not use `--install` when preserving the default binaries. It reports an Intel compile failure explicitly if only arm64 can be built. These signatures are local content identity, not notarization. Release ZIPs contain both binaries and SHA-256 checksums.

Integration never activates another app, posts global input, uses a global override, or requests TCC. Missing Screen Recording/Accessibility produces named SKIPs. `scripts/bg_selftest.sh` delegates to this owned fixture suite; the old TextEdit recipe is retired. Benchmarks describe historical implementations and are not v0.8 acceptance tests.

TCC is specific to the actual process and responsible launching host. Replacing an ad-hoc binary can invalidate an old grant; an enabled toggle or old XYZStudio grant does not establish access for this executor. This release only observes status, never requests authorization or clicks dialogs. Restart resident executors after installation. Existing MCP hosts must reconnect to use the replacement binary.

## Process diagnostic JSON

```sh
xyzlcu capabilities --json
xyzlcu identity-observe --pid 1234 --nonce CANONICAL_43_CHARACTER_BASE64URL_TOKEN --json
```

For `identity-check`, pass an inherited private FD (at least 3) containing exactly `{"schema_version":1,"nonce":"<32-byte canonical base64url>","expected":<observed_pre process object>}`. The FD is bounded to 256 KiB, duplicate keys and unknown fields are rejected, and the descriptor is closed after reading. Process observation includes `boot_id`, `pid`, `uid`, exact seconds/microseconds `start_time`, app/executable paths, device/inode/SHA-256, validated signing kind/identifier/requirement, executing architecture and cdhash algorithm. `identity-check` checks the full frozen process object twice; a changed start time yields `PID_REUSED`.

The diagnostic response has `kind:"process-observation"`, nonce, actual executor, `observed_pre/post`, timing, `identity_check:"matched"` and explicit limitations. It is separate from `urn:xyzlcu:identity-proof:1` content Success. Structured errors contain stable code, numeric exit, phase, dispatch state, possible-effects flag, nonce or null, mismatch paths and `retryable:false`; no payload or success proof is published on failure. Consumer requests currently receive negotiation refusal before sensitive request/key FDs are read or forwarded to protocol 2.

The [machine-readable core schema](docs/schemas/identity-proof.v1.schema.json) is shipped alongside error and owner-policy schemas. The complete target schema and assurance rules are in [the design](docs/IDENTITY_PROOF_DESIGN.md) and [security review](docs/IDENTITY_PROOF_REVIEW.md). Discovery tokens cannot bind a window or confer an owner role. XYZStudio must retain its own admission, revisions, revocation, deadlines and atomic response consumption; do not enable its tools from a version string or a diagnostic match.

## Protected applications and owner policy

Built-in seeds cover password managers, Passwords/Keychain Access, System Settings, terminals, WeChat and payment-client families. Missing reviewed signer pins conservatively deny a known seed as suspicious. Renaming a bundle does not change its ID. Unknown signed apps are reported as unknown in base policy; unknown hosted surfaces remain unavailable to XYZStudio. Family/helper attribution and browser-hosted sensitive content need a reviewed provider; a flat list does not solve them.

The fixed account-home path is `~/Library/Application Support/XYZLCU/protected-apps.v1.json`. No model/CLI policy path or environment override exists. Parent traversal uses descriptor-relative no-follow opens; the XYZLCU directory must be user-owned 0700 and files regular, user-owned, one-link 0600, at most 256 KiB. The owner must supply `protected-apps.state.v1.json` with exactly `{"schema_version":1,"revision":"N","overlay_sha256":"<SHA-256 of exact overlay bytes>"}`. Existing overlay without matching continuity, rollback, same-revision alteration, or accepted overlay disappearance fails closed. If both are absent, the built-in policy is used for metadata and practical checks; it cannot initialize an authenticated consumer session. No policy-writing command ships.

Overlay shape is the closed schema in design §7.2. Additions support exact IDs or a final `.*`, publisher requirements and signing IDs; no scripts/regex run. Explicit removal requires `allow_builtin_removals:true` plus exact IDs (built-in rule IDs in this implementation equal bundle-ID seeds). XYZStudio must independently preserve immutable denials and owner high-water state. Local 0600 files do not isolate a malicious process running under the same UID.

## Compatibility

Legacy capture, AX reads/writes, key/mouse/PID events, activation/open, lock creation, menus, replay and permission requests return `IDENTITY_UNPROVABLE` before dispatch, including aliases and each batch/MCP member. Display prewarm and legacy stream acquisition are disabled. Metadata services and daemon lifecycle remain usable. Protocol-2 daemons cannot receive proof/key descriptors; proof traffic does not retry through an older daemon or an untrusted executable override.

Older usage and benchmark claims are available in the [0.7.1 source snapshot](https://github.com/brandy2015/XYZLCU/tree/cdcae1879cfda9c7a46aed161ee0412ba210d500). They do not describe 0.8.1 capabilities. A historical 0.7.1 installation is never a fallback for refused strict/practical requests.

Inspired by [LCU](https://github.com/amontlabs/lcu) by Amont Labs; independently implemented. See [LICENSE](LICENSE).
