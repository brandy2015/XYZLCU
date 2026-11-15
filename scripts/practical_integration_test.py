#!/usr/bin/env python3
"""Practical screenshot acceptance against a fresh owned background fixture only."""
import atexit
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import struct
import stat
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
CORE = Path(sys.argv[1]).resolve()
RUN = uuid.uuid4().hex
WORK = Path(tempfile.mkdtemp(prefix="xyzlcu-practical-")).resolve()
APP = WORK / "XYZLCUIdentityFixture.app"
STATE = WORK / "state.json"
HOST = WORK / "fixture-host"
WINDOW_HOST = WORK / "fixture-window"
PIXEL_HOST = WORK / "fixture-pixels"
OUTPUT = WORK / "captures"
OUTPUT.mkdir(mode=0o700)
ROWS = []
ENV = dict(os.environ, XYZLCU_DAEMON="0", XYZLCU_AUTO_RESTART="0", XYZLCU_PREWARM="0",
           XYZLCU_STREAM="0", XYZLCU_BACKGROUND="0", XYZLCU_PROBE="0", XYZLCU_SOCKET=str(WORK / "isolated.sock"))
for key in ("XYZLCU_TYPE_VIA", "XYZLCU_KEY_VIA", "XYZLCU_EVENTS_HEALTH", "XYZLCU_CORE"):
    ENV.pop(key, None)

# A private metadata-only helper queries only a known fixture ID. It does not list
# other windows, acquire pixels, request TCC, activate apps or post input events.
WINDOW_SOURCE = r'''
import Foundation
import CoreGraphics
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, let id = UInt32(args[0]), let owner = Int32(args[1]), id > 0, owner > 0 else { exit(2) }
let rows = (CGWindowListCopyWindowInfo([.optionIncludingWindow, .excludeDesktopElements], id) as? [[String: Any]]) ?? []
let matches = rows.filter { ($0[kCGWindowNumber as String] as? UInt32) == id }
guard matches.count == 1, let row = matches.first,
      (row[kCGWindowOwnerPID as String] as? Int32) == owner,
      let layer = row[kCGWindowLayer as String] as? Int,
      let visible = row[kCGWindowIsOnscreen as String] as? Bool,
      let bounds = row[kCGWindowBounds as String] as? [String: Any],
      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { exit(3) }
let value: [String: Any] = ["window_id": id, "owner_pid": owner, "layer": layer,
    "on_screen": visible, "frame": ["x":frame.minX,"y":frame.minY,"width":frame.width,"height":frame.height]]
let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
'''


PIXEL_SOURCE = r'''
import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 1,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[0]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width > 0, image.height > 0, image.width <= 4096, image.height <= 4096,
      let color = CGColorSpace(name: CGColorSpace.sRGB) else { exit(2) }
var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
let rendered = bytes.withUnsafeMutableBytes { pointer -> Bool in
    guard let context = CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: color,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
    context.translateBy(x: 0, y: CGFloat(image.height)); context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return true
}
guard rendered else { exit(3) }
let digest = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
let value: [String: Any] = ["sha256": digest, "width": image.width, "height": image.height,
    "format": "rgba8-srgb-top-left-tight-v1"]
let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
'''


def row(name, status="PASS", reason=""):
    ROWS.append({"name": name, "status": status, "reason": reason})
    print(f"{status}: {name}" + (f" — {reason}" if reason else ""), flush=True)


def run(argv, timeout=30):
    return subprocess.run([str(x) for x in argv], env=ENV, stdin=subprocess.DEVNULL,
                          capture_output=True, text=True, timeout=timeout)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def parsed(argv, allow_failure=False):
    result = run(argv)
    require(allow_failure or result.returncode == 0, f"{argv}: exit {result.returncode}: {result.stderr}")
    try:
        return result, json.loads(result.stdout)
    except ValueError:
        raise AssertionError(f"{argv}: invalid JSON stdout={result.stdout!r}, stderr={result.stderr!r}")


def state():
    try:
        return json.loads(STATE.read_text())
    except (FileNotFoundError, ValueError):
        return {}


def wait_for(predicate, message, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(message)


def fixture_command(operation):
    current = state()
    require(current.get("runID") == RUN and current.get("bundlePath") == str(APP), "fixture ownership changed")
    command_id = uuid.uuid4().hex
    temporary = WORK / "command.new"
    temporary.write_text(json.dumps({"runID": RUN, "id": command_id, "operation": operation}))
    temporary.replace(WORK / "command.json")
    if operation != "quit":
        return wait_for(lambda: (s if (s := state()).get("lastCommand") == command_id else None), "fixture command timed out")


def stable_window(window_id, owner):
    previous = None
    consecutive = 0
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        _, current = parsed([WINDOW_HOST, window_id, owner])
        consecutive = consecutive + 1 if current == previous else 0
        if consecutive >= 3:
            return current
        previous = current
        time.sleep(0.1)
    raise AssertionError("owned fixture window geometry did not settle")


def cleanup():
    # Ask our authenticated fixture to exit; never signal a potentially reused PID.
    try:
        if state().get("runID") == RUN:
            fixture_command("quit")
    except Exception:
        pass


def request(envelope, command="screenshot", assurance="practical", output_dir=OUTPUT):
    read_fd, write_fd = os.pipe()
    try:
        encoded = json.dumps(envelope).encode()
        require(len(encoded) < 16000, "fixture request exceeds bounded pipe writer")
        os.write(write_fd, encoded)
        os.close(write_fd)
        write_fd = -1
        argv = [str(CORE), command]
        if assurance is not None:
            argv += ["--assurance", assurance]
        argv += ["--request-fd", str(read_fd), "--output-dir", str(output_dir), "--json"]
        result = subprocess.run(argv, env=ENV, stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, pass_fds=(read_fd,), timeout=30)
        try:
            return result, json.loads(result.stdout)
        except ValueError:
            raise AssertionError(f"{argv}: invalid JSON stdout={result.stdout!r}, stderr={result.stderr!r}")
    finally:
        os.close(read_fd)
        if write_fd >= 0:
            os.close(write_fd)


def refusal(result, body, name, codes=None):
    require(result.returncode != 0 and body.get("ok") is False, f"{name}: request was not refused: {body}")
    if codes is not None:
        require(body.get("code") in codes, f"{name}: unexpected refusal {body}")
    require("proof" not in body and "result" not in body and "payload" not in body,
            f"{name}: refusal contains successful proof or content")
    require("base64" not in json.dumps(body).lower() and "data:image" not in json.dumps(body).lower(),
            f"{name}: refusal contains image transport")
    require(not list(OUTPUT.iterdir()), f"{name}: refusal left output image files")
    row(name)


atexit.register(cleanup)
try:
    helper_source = WORK / "FixtureWindow.swift"
    helper_source.write_text(WINDOW_SOURCE)
    pixel_source = WORK / "FixturePixels.swift"
    pixel_source.write_text(PIXEL_SOURCE)
    builds = ((APP / "Contents/MacOS/IdentityFixture", ROOT / "scripts/fixtures/IdentityFixture.swift"),
              (HOST, ROOT / "scripts/fixtures/FixtureHost.swift"), (WINDOW_HOST, helper_source), (PIXEL_HOST, pixel_source))
    for destination, source in builds:
        destination.parent.mkdir(parents=True, exist_ok=True)
        result = run(["swiftc", source, "-framework", "AppKit", "-framework", "ApplicationServices", "-o", destination], timeout=120)
        require(result.returncode == 0, result.stderr)
    plist = {"CFBundleExecutable": "IdentityFixture", "CFBundleIdentifier": "com.xyztech.xyzlcu.identity-fixture",
             "CFBundleName": "XYZLCU Practical Fixture", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
             "LSUIElement": True, "NSHighResolutionCapable": True, "XYZLCUTestRunID": RUN,
             "XYZLCUTestDirectory": str(WORK)}
    (APP / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
    signed = run(["codesign", "--force", "--sign", "-", "--identifier", plist["CFBundleIdentifier"], APP])
    require(signed.returncode == 0, signed.stderr)
    row("owned ad-hoc fixture and passive helpers build")
    _, before = parsed([HOST, "snapshot"])
    _, launched = parsed([HOST, "launch", APP])
    initial = wait_for(lambda: (s if (s := state()).get("runID") == RUN else None), "background fixture not ready")
    require(launched["pid"] == initial["pid"] and initial["bundlePath"] == str(APP), "wrong launched fixture")
    require(len(initial["windowIDs"]) == 2 and all(RUN in title for title in initial["titles"]), "fixture ownership evidence missing")
    _, after = parsed([HOST, "snapshot"])
    require(before["frontmostPID"] == after["frontmostPID"] and after["frontmostPID"] != initial["pid"], "launch changed frontmost app")
    row("owned background fixture launches without activation")

    _, capabilities = parsed([CORE, "capabilities", "--json"])
    nonce = base64.urlsafe_b64encode(os.urandom(32)).rstrip(b"=").decode()
    _, observation = parsed([CORE, "identity-observe", "--pid", str(initial["pid"]), "--nonce", nonce, "--json"])
    process = observation["observed_post"]
    require(process == observation["observed_pre"] and process["pid"] == initial["pid"], "unstable fixture process")
    require(Path(process["app"]["bundle_path"]).resolve() == APP, "observation addressed wrong app")
    window = stable_window(initial["windowIDs"][0], initial["pid"])
    require(window["on_screen"] is True and window["layer"] == 0, "fixture window not eligible")
    envelope = {"schema_version": 1, "nonce": nonce, "expected": {"process": process, "window": window},
                "format": "png", "max_pixel_edge": 1024}
    initial_binding = copy.deepcopy(envelope["expected"])
    row("fresh process and exact owned window binding collected")

    acl_output = WORK / "acl-captures"
    acl_output.mkdir(mode=0o700)
    try:
        changed_acl = run(["/bin/chmod", "+a", "everyone allow read,search", acl_output])
        require(changed_acl.returncode == 0, f"cannot create owned ACL fixture: {changed_acl.stderr}")
        result, body = request(envelope, output_dir=acl_output)
        refusal(result, body, "extended ACL on private output directory refuses before acquisition", {"POLICY_PERMISSION_INVALID"})
        require(not list(acl_output.iterdir()), "ACL refusal left an image file")
    finally:
        restored_acl = run(["/bin/chmod", "-N", acl_output])
        require(restored_acl.returncode == 0, f"cannot remove owned ACL fixture: {restored_acl.stderr}")

    nonprivate_output = WORK / "nonprivate-captures"
    nonprivate_output.mkdir(mode=0o755)
    nonprivate_output.chmod(0o755)
    output_link = WORK / "output-link"
    output_link.symlink_to(OUTPUT, target_is_directory=True)
    parent_link = WORK / "parent-link"
    parent_link.symlink_to(WORK, target_is_directory=True)
    for label, candidate in (("non0700", nonprivate_output), ("final symlink", output_link),
                             ("parent symlink", parent_link / "captures")):
        result, body = request(envelope, output_dir=candidate)
        refusal(result, body, f"{label} output directory refuses before acquisition", {"POLICY_PERMISSION_INVALID"})
        require(not list(nonprivate_output.iterdir()), "nonprivate output refusal left a file")

    for assurance in (None, "strict"):
        result, body = request(envelope, assurance=assurance)
        refusal(result, body, f"{'default' if assurance is None else 'explicit strict'} refuses practical request")
    for command in ("ax", "click", "press", "type", "key", "insert", "settext", "set-text", "open-app", "activate", "move", "request", "not-a-command"):
        result, body = request(envelope, command=command)
        refusal(result, body, f"practical {command} stays refused")
    changed = copy.deepcopy(envelope)
    changed["expected"]["process"]["start_time"]["microseconds"] = (process["start_time"]["microseconds"] + 1) % 1000000
    result, body = request(changed)
    refusal(result, body, "stale process birth fails before acquisition", {"PID_REUSED"})
    changed = copy.deepcopy(envelope)
    changed["expected"]["process"]["app"]["executable_file"]["sha256"] = "0" * 64
    result, body = request(changed)
    refusal(result, body, "changed executable digest fails before acquisition", {"EXECUTABLE_IDENTITY_MISMATCH"})
    for field, value, codes in (("owner_pid", initial["pid"] + 1, {"WINDOW_OWNER_MISMATCH"}),
                                ("layer", 1, {"WINDOW_LAYER_MISMATCH", "WINDOW_IDENTITY_MISMATCH", "WINDOW_MISMATCH"}),
                                ("on_screen", False, {"WINDOW_NOT_FOUND"})):
        changed = copy.deepcopy(envelope)
        changed["expected"]["window"][field] = value
        result, body = request(changed)
        refusal(result, body, f"changed window {field} refuses before acquisition", codes)
    changed = copy.deepcopy(envelope)
    changed["expected"]["window"]["frame"]["x"] += 1
    result, body = request(changed)
    refusal(result, body, "changed window frame refuses before acquisition", {"WINDOW_FRAME_MISMATCH"})
    # This is a deliberately false claim about our own fixture's identity; no
    # protected application is launched, queried, addressed or captured.
    changed = copy.deepcopy(envelope)
    changed["expected"]["process"]["app"]["bundle_id"] = "com.apple.Terminal"
    result, body = request(changed)
    refusal(result, body, "protected claimed binding refuses before acquisition", {"PROTECTED_APP_REFUSED", "PROTECTED_IDENTITY_SUSPICIOUS"})

    # Refresh only our fixture metadata to model a fresh caller lock after the
    # negative cases; AppKit/window-server placement can settle asynchronously.
    envelope["expected"]["window"] = stable_window(initial["windowIDs"][0], initial["pid"])
    positive_binding = copy.deepcopy(envelope["expected"])
    result, body = request(envelope)
    if result.returncode != 0:
        require(body.get("code") in {"TCC_SCREEN_RECORDING_REQUIRED", "SURFACE_CLASSIFICATION_UNPROVABLE", "UNSUPPORTED_PLATFORM"},
                f"valid owned fixture practical capture failed: {body}")
        refusal(result, body, "unavailable capture emits no pixels")
        row("positive owned-window SCK capture/hash/proof", "SKIP",
            f"{body.get('code')}; passive screen-recording preflight={capabilities.get('tcc', {}).get('screen_recording')}; no grant requested")
    else:
        require(body.get("ok") is True, "capture did not indicate success")
        proof, image_result = body["proof"], body["result"]
        verified_proof = proof
        require(proof["schema_version"] == 1 and proof["assurance"] == "practical" and proof["nonce"] == nonce, "proof contract mismatch")
        require(proof["observed_pre"] == envelope["expected"] == proof["observed_post"], "proof is not bound to exact supplied pre/post values")
        image = proof["image"]
        image_path = Path(image_result["path"])
        require(image_path == Path(image["path"]) and image_path.parent == OUTPUT, "output escaped caller directory")
        image_stat = image_path.lstat()
        require(stat.S_ISREG(image_stat.st_mode) and stat.S_IMODE(image_stat.st_mode) == 0o600, "image is not a private regular file")
        require(stat.S_IMODE(OUTPUT.stat().st_mode) == 0o700, "output directory permissions changed")
        encoded = image_path.read_bytes()
        require(image["byte_length"] == len(encoded), "encoded byte count mismatch")
        require("data" not in image_result and "base64" not in json.dumps(body).lower(), "unexpected image bytes on stdout")
        require(encoded[:8] == b"\x89PNG\r\n\x1a\n" and encoded[12:16] == b"IHDR", "capture is not encoded PNG")
        width, height = struct.unpack(">II", encoded[16:24])
        image = proof["image"]
        require(image["format"] == "png" and image["media_type"] == "image/png", "image format mismatch")
        require(image["pixel_width"] == width and image["pixel_height"] == height and max(width, height) <= 1024, "image dimensions do not match proof")
        require(image["sha256"] == hashlib.sha256(encoded).hexdigest(), "encoded-image SHA-256 mismatch")
        _, decoded = parsed([PIXEL_HOST, image_path])
        require(image["raw_pixel_format"] == decoded["format"] and image["raw_pixel_sha256"] == decoded["sha256"],
                "decoded lossless PNG raw-pixel SHA-256 mismatch")
        require(isinstance(proof["timing"], dict) and len(proof["timing"]) >= 2, "proof lacks capture timestamps")
        limitations = " ".join(proof["limitations"]).lower()
        require("reuse" in limitations and ("millisecond" in limitations or "ms" in limitations), "residual window-reuse risk missing")
        artifact_image = ROOT / "build/practical-fixture.png"
        artifact_proof = ROOT / "build/practical-proof.json"
        artifact_image.write_bytes(encoded)
        artifact_image.chmod(0o600)
        artifact_proof.write_text(json.dumps(proof, indent=2) + "\n")
        artifact_proof.chmod(0o600)
        row("owned-window SCK capture private PNG, dimensions, encoded and raw SHA-256 match proof")
        row("practical proof echoes nonce, exact pre/post binding, timestamps and residual risk")
        image_path.unlink()

    # Force our own original window to disappear; the stale binding must never
    # acquire the fixture's other/replacement window even when titles are identical.
    replacement = fixture_command("replace-window")
    require(replacement["windowGeneration"] == initial["windowGeneration"] + 1, "fixture failed to replace its own window")
    if replacement["windowIDs"][0] != initial["windowIDs"][0]:
        result, body = request(envelope)
        refusal(result, body, "destroyed fixture window binding refuses after owned recreation", {"WINDOW_NOT_FOUND", "WINDOW_OWNER_MISMATCH", "WINDOW_FRAME_MISMATCH"})
    else:
        row("destroyed fixture window binding refusal", "SKIP", "OS immediately reused the same CGWindowID; practical mode documents this residual incarnation gap")
    require(state().get("everFrontmost") is False, "fixture became frontmost")
    row("fixture reports no activation through lifecycle")
    fixture_command("quit")
    wait_for(lambda: run(["/bin/ps", "-p", initial["pid"], "-o", "stat="]).returncode != 0, "owned fixture did not exit")
    row("owned fixture exits through authenticated private command")
except Exception as error:
    row("practical integration execution", "FAIL", str(error))
finally:
    cleanup()
    counts = {status: sum(r["status"] == status for r in ROWS) for status in ("PASS", "SKIP", "FAIL")}
    report = {"runID": RUN, "core": str(CORE), "rows": ROWS, "counts": counts,
              "fixtureSigning": "ad-hoc; no publisher assurance", "os": platform.mac_ver()[0], "architecture": platform.machine(),
              "tcc": globals().get("capabilities", {}).get("tcc", {}),
              "verifiedProof": globals().get("verified_proof"),
              "positiveBinding": globals().get("positive_binding"),
              "initialBinding": globals().get("initial_binding"),
              "bindingRefreshedAfterSetup": globals().get("initial_binding") != globals().get("positive_binding"),
              "artifactImage": str(globals()["artifact_image"]) if "artifact_image" in globals() else None,
              "artifactProof": str(globals()["artifact_proof"]) if "artifact_proof" in globals() else None,
              "restrictions": "only owned background fixture; no activation, global input, TCC requests, dialog clicks or unrelated app capture",
              "notes": ["Expected birth mismatch is injected; not observed OS PID reuse.", "Window replacement is fixture-controlled; same-ID ABA remains a practical-mode limitation."]}
    report_path = Path(os.environ.get("XYZLCU_PRACTICAL_INTEGRATION_REPORT", str(ROOT / "build/practical-integration-results.json")))
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"RESULT: {counts['PASS']} passed, {counts['SKIP']} skipped, {counts['FAIL']} failed; {report_path}", flush=True)
    if counts["FAIL"]:
        print(f"Fixture diagnostics retained: {WORK}", file=sys.stderr)
    else:
        shutil.rmtree(WORK, ignore_errors=True)
    sys.exit(1 if counts["FAIL"] else 0)
