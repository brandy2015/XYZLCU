# Practical window capture — v0.8.1

`strict` remains the default and retains the v0.8.0 refusals. An owner may explicitly choose `practical` for one window screenshot when the residual risks below are acceptable. This choice does not enable AX reads, input, actions, activation, `open-app`, broad/display capture, legacy locks, daemon/batch/MCP capture, or XYZStudio consumer admission. A model must not choose this mode automatically, infer consent from a version number, or refresh a stale binding to follow another window.

## Assurance and residual risk

Practical capture compares the caller's complete frozen process and window binding against fresh observations twice before acquisition and again afterward. The native adapter also rechecks process identity around window observations, immediately around the SCK primitive, and before releasing the image. Every mismatch fails closed: no success proof or image bytes are returned, and no output image is published for that mismatch.

These are endpoint observations, not an atomic window-incarnation certificate. A window may close and another window in the same process may reuse its `CGWindowID` within the millisecond-scale gaps. If all checked descriptors return to identical values before the next observation, the substitution may escape detection. PID start-time/signing/executable checks do not remove this same-process window-reuse risk. No measured maximum gap or continuous isolation is promised.

The protected-app denylist remains enforced before content acquisition. It cannot classify embedded secrets, browser/Electron pages, authentication content, or every helper/extension/host family. An otherwise unprotected app can display sensitive content. Excluding SCK child windows does not classify pixels drawn inside the selected window.

The proof is unsigned diagnostic evidence. There is no authenticated controller/executor session, HMAC, replay ledger, request deadline, or OS attestation for this route. The trusted caller owns the user's lock, mode consent, nonce lifecycle, response consumption and cancellation policy. Same-UID hostile processes are outside the filesystem isolation provided by 0700/0600. Ad-hoc identity pins code contents; it does not establish publisher trust or notarization. Strict consumer capability remains unavailable.

## CLI and transport

The only admitted form is a direct, top-level invocation:

```text
xyzlcu-0.8.1 screenshot --assurance practical --request-fd N --output-dir DIR --json
```

All four options are mandatory, each appears once, and unknown flags/positionals are rejected. `--assurance strict` preserves refusal. Other commands with `--assurance practical` refuse before dispatch. `--consumer` refuses with `SESSION_INVALID` before reading the sensitive request FD. No global/foreground override, PID selector, title search, old lock or environment variable can enable this route. The C client execs its same-directory core; there is no daemon fallback or older-core retry.

`N` is an inherited private FD at least 3 containing a UTF-8 JSON request followed by EOF. The executor closes it after reading, including error paths. The reader is bounded to 256 KiB and approximately two seconds; duplicate keys, unknown keys, invalid UTF-8, malformed JSON and invalid shapes are rejected. A regular temporary file positioned at byte zero is suitable. Do not pass a command-line JSON string or a filename instead of an FD.

Practical capture requires macOS **14.2+** and an existing Screen Recording grant for the actual executor/responsible host. macOS 13 and 14.0/14.1 refuse with `SURFACE_CLASSIFICATION_UNPROVABLE`, because this implementation requires explicit child-window exclusion. Permission checks are passive; the CLI does not request permission or operate TCC dialogs. `capabilities --json` reports `default_assurance:"strict"` and a separate `practical_window_capture` capability with `explicit_only:true`, `minimum_macos:"14.2"` and `consumer_admission:false`. Its `available` is an OS/TCC observation, not approval of a supplied target.

## Closed request schema

Every field below is required; no additional fields are accepted at any object level. The request itself has no `operation` or `assurance` key: the top-level CLI fixes screenshot/practical.

```typescript
type Request = {
  schema_version: 1;
  nonce: string; // canonical unpadded base64url of exactly 32 bytes: 43 characters
  expected: { process: Process; window: Window };
  format: "png" | "jpeg";
  max_pixel_edge: number; // integer, 1...4096
};
type Window = {
  window_id: number; // integer CGWindowID, 1...4294967295
  owner_pid: number; // positive integer, equal to process.pid
  layer: 0;
  frame: { x: number; y: number; width: number; height: number };
  on_screen: true;
};
type Process = {
  boot_id: string; // boot-session UUID
  pid: number; // integer, 1...2147483647
  uid: number; // nonnegative integer; native observer requires the current UID
  start_time: { seconds: string; microseconds: number };
  app: {
    bundle_id: string;
    bundle_path: string;
    executable_path: string;
    executable_file: { device: string; inode: string; sha256: string };
    signing: {
      kind: "developer_id" | "app_store" | "apple_platform" |
            "adhoc_fixture" | "adhoc_diagnostic";
      valid: true;
      team_id: string | null;
      signing_identifier: string;
      cdhash: string;
      cdhash_algorithm: "sha1" | "sha256" | "sha256_truncated";
      architecture: "arm64" | "arm64e" | "x86_64";
      designated_requirement: string;
      requirement_sha256: string;
    };
  };
};
```

`expected` must come from the trusted user's existing lock. The CLI does not construct an owner lock, select a replacement target, or accept a catalog discovery token as a binding. Reuse the complete process observation from that lock; process diagnostics can supply metadata but do not themselves authorize capture. `adhoc_diagnostic` is the native diagnostic observer's spelling and remains unchanged in the emitted observations. Its practical-only validation adapter does not widen strict proof v1.

The complete machine-readable [practical request/proof schema](schemas/practical-window-capture.v1.schema.json) ships separately from strict proof v1. Process structure follows the existing [Process definition](schemas/identity-proof.v1.schema.json), with that practical-only signing-kind addition. Decimal file counters/start seconds are strings; start seconds must fit a positive UInt64, and microseconds are integers 0...999999. SHA-256 fields are lowercase 64-digit hex; cdhash is lowercase 40...64-digit hex. `requirement_sha256` must match the exact UTF-8 designated requirement. Developer ID/App Store kinds require a non-null Team ID. Bundle/executable paths must be absolute lexical paths without empty, dot or dot-dot components or a trailing slash, with the executable inside the bundle. Frame values must be finite and dimensions positive. Coordinates are CG desktop window points; all frame components compare exactly, with zero tolerance. Any move, resize, off-screen state, layer change, owner change, process/file/signing change or stale lock requires a new owner decision, not automatic retargeting.

The executor obtains fresh `SCShareableContent`, uniquely matches the exact window ID, cross-checks owner PID, bundle ID, layer and frame against CG metadata, and passes the same validated `SCWindow` to `SCContentFilter(desktopIndependentWindow:)` and `SCScreenshotManager`. Child windows, cursor and shadow are excluded. There is no display crop, cached image, `screencapture` command or macOS 13 stream fallback.

## Image publication and success JSON

`DIR` must already exist and be an absolute lexical real-directory path without empty, dot or dot-dot components or a trailing slash, owned by the current UID, mode exactly 0700, with no extended ACL entries. Every path component is opened with descriptor-relative no-follow traversal; symlinks are refused, including the usual `/tmp` and `/var` aliases. The real `/private/var/...` spelling is accepted without Foundation alias rewriting. Use a real path such as `os.path.realpath(...)`. Ancestors need not themselves have mode 0700. The final directory is retained by FD and its device/inode, ownership, mode and ACL are rechecked.

Only after successful checks does the executor create a random UUID-named `.png` or `.jpg` with exclusive no-follow creation. It writes a single-link, owner-only 0600 regular file with no extended ACL, verifies/fsyncs it, and checks the directory again. It never overwrites an existing file. Failed writes remove the incomplete file. Successful files remain for the caller to read and remove.

Stdout contains one JSON response and no image/base64 bytes. The CLI success shape is:

```typescript
type Success = {
  ok: true;
  proof: {
    schema_version: 1;
    kind: "window-capture";
    operation: "screenshot";
    assurance: "practical";
    nonce: string;
    observed_pre: { process: Process; window: Window };
    observed_post: { process: Process; window: Window };
    timing: {
      precheck_start: Instant; capture_start: Instant;
      capture_end: Instant; postcheck_end: Instant;
    };
    image: {
      path: string; format: "png" | "jpeg"; media_type: "image/png" | "image/jpeg";
      sha256: string; byte_length: number;
      raw_pixel_sha256: string | null;
      raw_pixel_format: "rgba8-srgb-top-left-tight-v1" | null;
      pixel_width: number; pixel_height: number;
    };
    limitations: string[];
    executor: {
      pid: number; start_time: string; boot_id: string; build_sha256: string;
      execution_mode: "direct"; client_build_sha256: null;
    };
    policy_sha256: string;
  };
  result: { path: string }; // identical to proof.image.path
};
type Instant = { continuous_ns: string; wall_utc: string };
```

This is a separate practical schema, not the strict `identity-proof:1` Success (whose assurance is an array). `observed_pre` is the final successful coordinator pre-observation; `observed_post` is the coordinator post-observation. The timestamps bound those checks and acquisition, not the later file write or a guaranteed source-frame presentation time. Native guards run in addition to the recorded coordinator observations. Actual image dimensions are positive and bounded by `max_pixel_edge`; no upscaling is requested.

`image.sha256` is ordinary SHA-256 over the exact encoded file bytes, without the strict payload domain prefix. The native path also provides `raw_pixel_sha256` over a tightly packed, top-left, 8-bit RGBA sRGB raster with premultiplied alpha, `width * height * 4` bytes, before file encoding. `raw_pixel_format` names that normalization. For JPEG this is the pre-encoding raster hash; it is **not** the hash of pixels decoded from the lossy JPEG. Consumers verifying the saved file should use `image.sha256` and `byte_length`.

## Errors and exit status

Failures use the existing versioned identity error envelope, with no `proof`, `result`, image bytes or success path:

```typescript
type Failure = {
  schema_version: 1; ok: false; code: string; exit_code: number;
  nonce: string | null; phase: "parse" | "precheck" | "operation" | "postcheck" | "release";
  dispatch_state: "not_dispatched" | "dispatched";
  side_effects_possible: false; retryable: false;
  mismatch_fields: string[]; message: string; mac: null;
};
```

A valid parsed nonce is echoed; malformed or unread requests yield null. `dispatched` means capture was attempted, not that an image was published. No automatic retry is indicated. Most errors use exit 4; the existing shared envelope maps the following groups explicitly:

| Exit | Codes and meaning |
| --- | --- |
| 2 | `INVALID_REQUEST`, `DUPLICATE_JSON_KEY`, `REQUEST_TOO_LARGE`: flag/FD/JSON/schema/bounds refusal |
| 3 | `PROOF_PROTOCOL_UNSUPPORTED`, `PROOF_CAPABILITY_UNSUPPORTED`: unsupported protocol/capability negotiation |
| 4 | `PID_REUSED` (start time), `PROCESS_IDENTITY_MISMATCH` (PID), `PROCESS_UID_MISMATCH` (UID), `BOOT_MISMATCH`, `BUNDLE_ID_MISMATCH`, `EXECUTABLE_IDENTITY_MISMATCH`, `SIGNING_IDENTITY_MISMATCH`: frozen identity changed |
| 4 | `WINDOW_ID_REUSED`, `WINDOW_OWNER_MISMATCH`, `WINDOW_LAYER_MISMATCH`, `WINDOW_FRAME_MISMATCH`, `WINDOW_NOT_FOUND`: window changed, missing or ineligible |
| 4 | `PROTECTED_APP_REFUSED`, `PROTECTED_IDENTITY_SUSPICIOUS`, `POLICY_CHANGED`, `POLICY_INVALID`, `POLICY_PERMISSION_INVALID`: protected policy or private directory/ACL refusal |
| 4 | `IDENTITY_UNPROVABLE`, `SESSION_INVALID`, `SURFACE_CLASSIFICATION_UNPROVABLE`, `PROCESS_NOT_FOUND`, `PROCESS_IDENTITY_UNAVAILABLE`, `PROCESS_UID_MISMATCH`, `SIGNATURE_INVALID`, `SIGNATURE_UNPROVABLE`: unsupported route/admission, old OS or unavailable native identity |
| 5 | `TCC_SCREEN_RECORDING_REQUIRED`, `CAPTURE_UNAVAILABLE`, `CAPTURE_SOURCE_UNPROVABLE`, `APP_IDENTITY_CHANGED`: missing permission, capture/encoding/output failure or native executable/bundle change |
| 1 | `INTERNAL_ERROR`: unexpected internal failure |

Codes identify the first failed gate; multiple changes need not all be reported. `parse` covers options/request validation, `precheck` the initial native/policy checks, `operation` acquisition, `postcheck` post-observation/payload checks, and `release` the final guard/file publication. Error message text is diagnostic, bounded and not a stable parsing contract. The CLI tracks whether acquisition was dispatched when reporting later release failures; `dispatched` still conveys no successful image publication.

## Minimal inherited-FD example

This example assumes the owner already saved exactly the frozen `expected` object (`process` and `window`) in a private `~/private-lock.json`, and explicitly chose practical capture for it. It does not discover, launch or activate a target. Run only for a target the user authorized.

```python
import base64, hashlib, json, os, secrets, subprocess, tempfile

core = os.path.expanduser("~/.local/lib/xyzlcu/0.8.1/xyzlcu-core")
with open(os.path.expanduser("~/private-lock.json"), encoding="utf-8") as f:
    expected = json.load(f)
nonce = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")
request = {"schema_version": 1, "nonce": nonce, "expected": expected,
           "format": "png", "max_pixel_edge": 1024}
# mkdtemp creates the private directory; realpath avoids /tmp symlink aliases.
output_dir = os.path.realpath(tempfile.mkdtemp(prefix="xyzlcu-capture-",
    dir=os.path.realpath(tempfile.gettempdir())))
os.chmod(output_dir, 0o700)
with tempfile.TemporaryFile(mode="w+b") as request_file:
    request_file.write(json.dumps(request, separators=(",", ":")).encode())
    request_file.flush()
    request_file.seek(0)
    completed = subprocess.run([
        core, "screenshot", "--assurance", "practical",
        "--request-fd", str(request_file.fileno()), "--output-dir", output_dir, "--json"
    ], pass_fds=(request_file.fileno(),), capture_output=True, text=True)
response = json.loads(completed.stdout)
if completed.returncode or not response.get("ok"):
    raise RuntimeError(response)  # no fallback or automatic rebind
assert response["proof"]["assurance"] == "practical"
assert response["proof"]["nonce"] == nonce
assert response["proof"]["observed_pre"] == expected
assert response["proof"]["observed_post"] == expected
with open(response["result"]["path"], "rb") as f:
    image = f.read()
assert len(image) == response["proof"]["image"]["byte_length"]
assert hashlib.sha256(image).hexdigest() == response["proof"]["image"]["sha256"]
# The caller owns the successful image and directory and removes them when done.
```

If the parent directory applies an inherited ACL, the output is refused; the owner must prepare an ACL-free private destination. The CLI does not edit TCC or owner policy to make the example succeed.

## Verification and side-by-side installations

The deterministic test suite covers all process/window pin mismatches at both prechecks and the postcheck, PID/window reuse/owner change, protected refusal before capture, strict separation, practical action refusal and encoded-byte hashing. `swift test` and `scripts/unit_test.sh` each passed the same **86 XCTest / 0 failures**, including 24 practical tests and real `/private/var` path regressions. `scripts/selftest.sh` passed 239 CLI/client/MCP/batch assertions, with zero global events created/posted. The new practical fixture suite passed **34 PASS / 0 SKIP / 0 FAIL** through both core and client, and the primary agent repeated it on the final universal client. Actual owned-window SCK capture produced a 420×252 PNG; encoded and decoded-normalized raw SHA-256 matched the proof, and complete pre/post bindings matched the supplied lock. The fixture was built and launched without activation; no other app was captured. Screen Recording was passively available in this tested host context, with no request or dialog interaction. Missing Screen Recording in another context produces a named SKIP, not successful pixel verification.

The unchanged strict fixture suite passed 22 PASS / 4 provider SKIP / 0 FAIL; its final `bg_selftest.sh` wrapper repeat had 21 PASS / 5 SKIP / 0 FAIL, with the extra SKIP recording externally moved pointer metadata between passive snapshots. No pointer event was posted. Strict AX/window-instance/surface-provider positives remain unavailable. These wrapper repeats are duplicate coverage, not additional distinct tests. The published practical Request/Success schema was validated against both real fixture proofs. Intel slices were compiled and signature-verified; runtime tests used native Apple Silicon.

An independent agent reviewed the production diff before commit and reviewed the fixes again. Its native ad-hoc schema compatibility and macOS ACL privacy findings were fixed and regression-tested. Integration also exposed Foundation alias rewriting of `/private/var`; practical lexical validation now preserves real paths while no-follow opens still reject symlinks. No unresolved security findings remained; the documented practical window-incarnation and sensitive-content limitations remain intentional.

This release uses side-by-side installation:

```text
~/.local/lib/xyzlcu/0.8.1/{xyzlcu,xyzlcu-core}
~/.local/lib/xyzlcu/0.7.1/{xyzlcu,xyzlcu-core}
~/.local/bin/xyzlcu-0.8.1
~/.local/bin/xyzlcu-0.7.1
```

Versioned wrappers set `XYZLCU_DAEMON=0` and `XYZLCU_AUTO_RESTART=0`, then exec the absolute `~/.local/lib/xyzlcu/0.8.1/xyzlcu` or `~/.local/lib/xyzlcu/0.7.1/xyzlcu` path respectively. Each client finds its own co-located core; wrappers isolate side versions from resident daemons. The unversioned `~/.local/bin/xyzlcu` and `xyzlcu-core` remain at 0.8.0. A 0.7.1 entry point retains that historical version's behavior; it is never a fallback for failed practical/strict requests. Build locally with `./build.sh`; do not use `--install` when preserving the default installation. Distributed local builds remain ad-hoc signed. TCC must be checked in the actual invocation context; an existing grant or successful build does not establish a new path's permission.
