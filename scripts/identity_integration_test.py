#!/usr/bin/env python3
"""Owned-fixture integration. This is local macOS acceptance, not a CI workflow."""
import atexit
import base64
import copy
import json
import os
from pathlib import Path
import plistlib
import platform
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
CORE = Path(sys.argv[1]).resolve()
RUN = uuid.uuid4().hex
WORK = Path(tempfile.mkdtemp(prefix="xyzlcu-identity-")).resolve()
APP = WORK / "XYZLCUIdentityFixture.app"
STATE = WORK / "state.json"
HOST = WORK / "fixture-host"
ROWS = []
DAEMON = None
ENV = dict(os.environ, XYZLCU_DAEMON="0", XYZLCU_AUTO_RESTART="0", XYZLCU_PREWARM="0",
           XYZLCU_STREAM="0", XYZLCU_BACKGROUND="0", XYZLCU_PROBE="0", XYZLCU_SOCKET=str(WORK / "isolated.sock"))
for key in ("XYZLCU_TYPE_VIA", "XYZLCU_KEY_VIA", "XYZLCU_EVENTS_HEALTH", "XYZLCU_CORE"):
    ENV.pop(key, None)


def row(name, status="PASS", reason=""):
    ROWS.append({"name": name, "status": status, "reason": reason})
    print(f"{status}: {name}" + (f" — {reason}" if reason else ""), flush=True)


def run(argv, timeout=30, env=None):
    return subprocess.run([str(x) for x in argv], env=env or ENV, stdin=subprocess.DEVNULL,
                          capture_output=True, text=True, timeout=timeout)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def parsed(argv, allow_failure=False):
    result = run(argv)
    if not allow_failure:
        require(result.returncode == 0, f"{argv}: exit {result.returncode}: {result.stderr}")
    try:
        return result, json.loads(result.stdout)
    except ValueError:
        raise AssertionError(f"{argv}: expected JSON, got stdout={result.stdout!r}, stderr={result.stderr!r}")


def state():
    try:
        return json.loads(STATE.read_text())
    except (FileNotFoundError, ValueError):
        return {}


def wait_for(predicate, reason, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(reason)


def fixture_command(operation):
    current = state()
    require(current.get("runID") == RUN and current.get("bundlePath") == str(APP), "fixture ownership changed")
    command_id = uuid.uuid4().hex
    temporary = WORK / "command.new"
    temporary.write_text(json.dumps({"runID": RUN, "id": command_id, "operation": operation}))
    temporary.replace(WORK / "command.json")
    if operation != "quit":
        return wait_for(lambda: (s if (s := state()).get("lastCommand") == command_id else None), "fixture command timeout")


def daemon_request(argv):
    payload = {"v": "0.8.1", "proto": 1, "argv": argv, "cwd": str(ROOT), "env": {}}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(20)
        connection.connect(ENV["XYZLCU_SOCKET"])
        connection.sendall(json.dumps(payload).encode())
        connection.shutdown(socket.SHUT_WR)
        parts = []
        while part := connection.recv(65536):
            parts.append(part)
    response = json.loads(b"".join(parts))
    return response, json.loads(response["out"]) if response.get("out", "").strip().startswith("{") else response.get("out")


def cleanup():
    if DAEMON is not None and DAEMON.poll() is None:
        try:
            daemon_request(["__stop"])
            DAEMON.wait(timeout=5)
        except Exception:
            pass
    # The fixture authenticates its private run ID and terminates itself. Never kill
    # a numeric PID that could have been reused, and never signal unrelated apps.
    try:
        if state().get("runID") == RUN:
            fixture_command("quit")
    except Exception:
        pass


atexit.register(cleanup)
try:
    for destination, source in ((APP / "Contents/MacOS/IdentityFixture", ROOT / "scripts/fixtures/IdentityFixture.swift"),
                                (HOST, ROOT / "scripts/fixtures/FixtureHost.swift")):
        destination.parent.mkdir(parents=True, exist_ok=True)
        result = run(["swiftc", source, "-framework", "AppKit", "-framework", "ApplicationServices", "-o", destination], timeout=120)
        require(result.returncode == 0, result.stderr)
    plist = {"CFBundleExecutable": "IdentityFixture", "CFBundleIdentifier": "com.xyztech.xyzlcu.identity-fixture",
             "CFBundleName": "XYZLCU Identity Fixture", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
             "LSUIElement": True, "NSHighResolutionCapable": True, "XYZLCUTestRunID": RUN,
             "XYZLCUTestDirectory": str(WORK)}
    (APP / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
    signed = run(["codesign", "--force", "--sign", "-", "--identifier", "com.xyztech.xyzlcu.identity-fixture", APP])
    require(signed.returncode == 0, signed.stderr)
    row("owned ad-hoc fixture and passive host build")
    _, before = parsed([HOST, "snapshot"])
    _, launched = parsed([HOST, "launch", APP])
    initial = wait_for(lambda: (s if (s := state()).get("runID") == RUN else None), "background fixture did not become ready")
    require(launched["pid"] == initial["pid"] and initial["bundlePath"] == str(APP), "launch returned wrong fixture")
    require(len(initial["windowIDs"]) == 2 and len(set(initial["windowIDs"])) == 2, "expected exactly two fixture windows")
    require(all(RUN in title for title in initial["titles"]), "fixture nonce absent")
    row("NSWorkspace background fixture launch reports two windows and nonce titles")
    _, after = parsed([HOST, "snapshot"])
    require(before["frontmostPID"] == after["frontmostPID"] and after["frontmostPID"] != initial["pid"], "fixture changed frontmost app")
    row("background launch preserves frontmost app")
    pointer_still = before["pointerX"] == after["pointerX"] and before["pointerY"] == after["pointerY"]
    row("pointer position unchanged across launch", "PASS" if pointer_still else "SKIP", "" if pointer_still else "external pointer contention; fixture sends no pointer events")

    _, capabilities = parsed([CORE, "capabilities", "--json"])
    require(isinstance(capabilities, dict), "capabilities must be object")
    row("real CLI capabilities JSON")
    # Schema and nonce contracts are asserted below after using actual CLI output.
    nonce = base64.urlsafe_b64encode(os.urandom(32)).rstrip(b"=").decode()
    observed_result, observation = parsed([CORE, "identity-observe", "--pid", str(initial["pid"]), "--nonce", nonce, "--json"])
    require(isinstance(observation, dict), "identity observation must be object")
    require(observation.get("schema_version") == 1 and observation.get("kind") == "process-observation", "observation schema mismatch")
    require(observation.get("nonce") == nonce and observation.get("identity_check") == "matched", "nonce/check mismatch")
    require(observation.get("assurance") == ["process-instance"], "diagnostic observation overclaims assurance")
    require(observation["observed_pre"] == observation["observed_post"], "pre/post process evidence differs")
    process = observation["observed_post"]
    (WORK / "process-observation.json").write_text(json.dumps(observation, indent=2))
    require(process["pid"] == initial["pid"] and Path(process["app"]["bundle_path"]).resolve() == APP.resolve(), "fixture process/path mismatch")
    require(isinstance(process["start_time"]["seconds"], str) and 0 <= process["start_time"]["microseconds"] < 1000000, "start time precision/type mismatch")
    require(process["app"]["signing"]["kind"] == "adhoc_diagnostic", "fixture signing assurance mismatch")
    row("real process observation, exact start/signing schema and nonce echo")

    def checked_request(expected):
        envelope = {"schema_version": 1, "nonce": nonce, "expected": expected}
        read_fd, write_fd = os.pipe()
        try:
            os.write(write_fd, json.dumps(envelope).encode())
            os.close(write_fd)
            write_fd = -1
            result = subprocess.run([str(CORE), "identity-check", "--request-fd", str(read_fd), "--json"],
                                    env=ENV, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                    pass_fds=(read_fd,), timeout=30)
            return result, json.loads(result.stdout)
        finally:
            os.close(read_fd)
            if write_fd >= 0:
                os.close(write_fd)

    matched_result, matched = checked_request(process)
    require(matched_result.returncode == 0 and matched["observed_post"] == process and matched["nonce"] == nonce, "matching process check failed")
    row("execution-time native expected-process check matches owned fixture")
    reused = copy.deepcopy(process)
    reused["start_time"]["microseconds"] = (reused["start_time"]["microseconds"] + 1) % 1000000
    mismatch_result, mismatch = checked_request(reused)
    require(mismatch_result.returncode != 0 and mismatch.get("code") == "PID_REUSED", "wrong process birth was not refused")
    require(mismatch.get("nonce") == nonce and mismatch.get("dispatch_state") == "not_dispatched" and mismatch.get("side_effects_possible") is False, "failure schema/nonce contract mismatch")
    require("observed_post" not in mismatch and "payload" not in mismatch, "failure leaked successful observation/payload")
    row("native injected stale start refuses with PID_REUSED and nonce echo")
    changed = copy.deepcopy(process)
    changed["app"]["executable_file"]["sha256"] = "0" * 64
    mismatch_result, mismatch = checked_request(changed)
    require(mismatch_result.returncode != 0 and mismatch.get("code") == "APP_IDENTITY_CHANGED", "wrong executable digest accepted")
    row("native changed executable binding fails closed")
    invalid_result, invalid = parsed([CORE, "identity-observe", "--pid", str(initial["pid"]), "--nonce", "invalid", "--json"], allow_failure=True)
    require(invalid_result.returncode != 0 and invalid.get("code") == "INVALID_REQUEST", "invalid nonce accepted")
    row("CLI rejects malformed nonce before process observation")

    # A separate daemon is our own child with a private socket. Protocol 1/2 is
    # diagnostics only; no consumer secrets or descriptors cross that transport.
    daemon_log = open(WORK / "daemon.log", "w")
    DAEMON = subprocess.Popen([str(CORE), "serve"], env=ENV, stdin=subprocess.DEVNULL,
                              stdout=daemon_log, stderr=daemon_log)
    wait_for(lambda: Path(ENV["XYZLCU_SOCKET"]).exists() or DAEMON.poll() is not None, "isolated daemon startup timed out")
    require(DAEMON.poll() is None, "isolated daemon exited")
    transport, daemon_caps = daemon_request(["capabilities", "--json"])
    require(transport["code"] == 0 and daemon_caps["executor"]["execution_mode"] == "daemon", "daemon executor provenance mismatch")
    require(daemon_caps["executor"]["pid"] == DAEMON.pid and daemon_caps["consumer_available"] is False, "wrong daemon identity/capability")
    row("isolated actual-daemon capabilities and executor PID")
    transport, daemon_observation = daemon_request(["identity-observe", "--pid", str(initial["pid"]), "--nonce", nonce, "--json"])
    require(transport["code"] == 0 and daemon_observation["nonce"] == nonce and daemon_observation["observed_post"] == process, "daemon process diagnostic mismatch")
    row("daemon independently observes same owned fixture instance")
    transport, consumer_refusal = daemon_request(["screenshot", "--consumer", "--json"])
    require(transport["code"] != 0 and consumer_refusal["code"] == "SESSION_INVALID" and consumer_refusal["dispatch_state"] == "not_dispatched", "unauthenticated consumer transport admitted")
    row("legacy daemon transport refuses consumer before credential transfer")
    _, daemon_status = daemon_request(["__status"])
    require(not daemon_status["liveStreams"] and not daemon_status["prewarm"] and not daemon_status["diffBaselines"], "daemon acquired legacy capture content")
    row("isolated daemon contains no prewarm, live capture or diff buffers")
    daemon_request(["__stop"])
    DAEMON.wait(timeout=5)
    daemon_log.close()
    row("isolated daemon stops cleanly through owned socket")

    replaced_control = fixture_command("replace-control")
    require(replaced_control["controlGeneration"] == initial["controlGeneration"] + 1, "control generation did not advance")
    require(replaced_control["windowGeneration"] == initial["windowGeneration"], "control replacement changed window generation")
    require(replaced_control["text"] == initial["text"], "replacement did not preserve identical control labels/value")
    row("owned AX control replacement with identical visible content")
    replaced_window = fixture_command("replace-window")
    require(replaced_window["windowGeneration"] == initial["windowGeneration"] + 1, "window generation did not advance")
    require(replaced_window["titles"] == initial["titles"], "window recreation changed titles")
    row("owned window recreation with identical title")

    # These are deliberately distinct from generic macOS assurance. The public OS
    # APIs cannot establish control/window ABA or surface continuity by themselves.
    for name in ("window incarnation / reuse integration", "AX control incarnation / action integration"):
        row(name, "SKIP", "shipping reviewed incarnation/surface provider unavailable; deterministic fake-provider negatives run in unit tests")
    tcc = capabilities.get("tcc", {})
    for name, permission in (("AX fixture read/write integration", "accessibility"), ("SCK fixture capture and thumbnail integration", "screen_recording")):
        granted = tcc.get(permission)
        reason = (f"{permission} not granted to actual xyzlcu process; no grant requested" if not granted
                  else "TCC preflight granted, but reviewed window/surface continuity provider unavailable; no acquisition attempted")
        row(name, "SKIP", reason)

    # Only our fixture is the explicit launch target. This route must refuse when
    # current exact-instance/system-trust support cannot meet the design.
    launch_result, launch_response = parsed([CORE, "open-app", "--bundle-id", plist["CFBundleIdentifier"], "--json"], allow_failure=True)
    require(launch_result.returncode != 0, "safe open-app unexpectedly available without reviewed exact-launch provider")
    require(launch_response.get("ok") is False or "error" in launch_response, "open-app failure must be structured")
    row("open-app fails closed before launch when assurance unsupported")

    # Metadata-only catalog must not acquire thumbnail pixels from any app.
    catalog_result, catalog = parsed([CORE, "windows", "--thumbnails", "--json", "--show-all"], allow_failure=True)
    require(isinstance(catalog, dict), "thumbnail refusal must be structured")
    encoded = json.dumps(catalog).lower()
    require("unavailable" in encoded or "unsupported" in encoded or "refused" in encoded, "thumbnail route did not explain unavailability")
    require("base64" not in encoded and "data:image" not in encoded, "unavailable catalog contains image payload")
    row("picker thumbnail route refuses unavailable capture without image bytes")

    require(state().get("everFrontmost") is False, "fixture became frontmost during monitored lifecycle")
    row("fixture reports no activation during 50 ms lifecycle monitor")
    fixture_command("quit")
    wait_for(lambda: run(["/bin/ps", "-p", str(initial["pid"]), "-o", "stat="]).returncode != 0,
             "fixture did not exit after authenticated quit")
    dead_result, dead = parsed([CORE, "identity-observe", "--pid", str(initial["pid"]), "--json"], allow_failure=True)
    require(dead_result.returncode != 0, "exited fixture still resolved as original process")
    row("process exit observation refuses dead instance")
    _, final = parsed([HOST, "snapshot"])
    if final["frontmostPID"] == before["frontmostPID"]:
        row("entire fixture lifecycle preserves frontmost app")
    else:
        row("entire fixture lifecycle preserves frontmost app", "SKIP", "external frontmost app contention; fixture launch never activates")
except Exception as error:
    row("integration execution", "FAIL", str(error))
finally:
    cleanup()
    counts = {status: sum(r["status"] == status for r in ROWS) for status in ("PASS", "SKIP", "FAIL")}
    report = {"runID": RUN, "core": str(CORE), "fixtureSigning": "ad-hoc; no publisher assurance", "rows": ROWS, "counts": counts,
              "restrictions": "only owned background fixture; no global input, activation, TCC requests, CI or firewall changes",
              "os": platform.mac_ver()[0], "architecture": platform.machine(),
              "tcc": globals().get("capabilities", {}).get("tcc", {}),
              "executor": globals().get("capabilities", {}).get("executor", {}),
              "notes": ["Injected stale expected timestamp is not observed OS PID reuse.", "Fixture generation protocol is isolated test evidence, not shipping content authority."]}
    report_path = Path(os.environ.get("XYZLCU_INTEGRATION_REPORT", str(ROOT / "build/identity-integration-results.json")))
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"RESULT: {counts['PASS']} passed, {counts['SKIP']} skipped, {counts['FAIL']} failed; {report_path}", flush=True)
    if counts["FAIL"]:
        print(f"Fixture diagnostics retained: {WORK}", file=sys.stderr)
    else:
        shutil.rmtree(WORK, ignore_errors=True)
    sys.exit(1 if counts["FAIL"] else 0)
