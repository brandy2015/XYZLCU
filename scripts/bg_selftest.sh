#!/bin/bash
# Permission-enabled manual acceptance only. Never sends global input or activates apps.
# Builds are deliberately separate: ./build.sh, then ./scripts/bg_selftest.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
export XYZLCU_DAEMON=0
export XYZLCU_AUTO_RESTART=0
CORE="${XYZLCU_BG_TEST_CORE:-$PWD/build/xyzlcu-core}"
[[ -x "$CORE" ]] || { echo 'Build first: ./build.sh' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required for JSON assertions.' >&2; exit 1; }
python3 - "$CORE" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

core = sys.argv[1]
work = Path(tempfile.mkdtemp(prefix='xyzlcu-bg-selftest-'))
env = dict(os.environ, XYZLCU_DAEMON='0', XYZLCU_AUTO_RESTART='0',
           XYZLCU_BACKGROUND='0', XYZLCU_PREWARM='0', XYZLCU_PROBE='0',
           XYZLCU_SOCKET=str(work / 'isolated.sock'))
# Inherited route/health test overrides must not change this acceptance recipe.
for key in ('XYZLCU_TYPE_VIA', 'XYZLCU_KEY_VIA', 'XYZLCU_EVENTS_HEALTH'):
    env.pop(key, None)
rows = []
seed = 'XYZLCU AX background ' + str(time.time_ns())
marker = ' XYZLCU PID unicode 你好 😀 '
document = work / ('XYZLCU background acceptance ' + str(time.time_ns()) + '.txt')
document.write_text('Disposable background test document.\n', encoding='utf-8')
locked = False
baseline = None
window = None
helper = work / 'ax-helper'
helper_source = work / 'ax-helper.swift'
helper_source.write_text(r'''
// AX-only acceptance helper: no activation or keyboard/mouse events.
import AppKit
import ApplicationServices

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
}
func text(_ el: AXUIElement, _ name: String) -> String { attr(el, name) as? String ?? "" }
func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attr(el, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func descendants(_ root: AXUIElement) -> [AXUIElement] {
    var result = [root], index = 0
    while index < result.count && result.count < 2000 {
        result += attr(result[index], kAXChildrenAttribute) as? [AXUIElement] ?? []
        index += 1
    }
    return result
}
func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
func require(_ okay: Bool, _ reason: String) throws {
    if !okay { throw NSError(domain: reason, code: 1) }
}
do {
    let args = CommandLine.arguments
    try require(args.count == 5, "Expected operation, pid, document path, window title")
    let operation = args[1], document = URL(fileURLWithPath: args[3])
    let app = AXUIElementCreateApplication(pid_t(args[2])!)
    let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    let filename = document.lastPathComponent
    let stem = document.deletingPathExtension().lastPathComponent
    let matches = windows.filter { window in
        let title = text(window, kAXTitleAttribute)
        let documentURL = text(window, kAXDocumentAttribute)
        return documentURL == document.absoluteString || title.contains(filename) || title.contains(stem)
            || (!args[4].isEmpty && title == args[4])
    }
    if operation == "cancel-open" {
        // Only a recognizable Open panel, never a Save panel or arbitrary alert.
        // Do this only when discovery has found no disposable document yet.
        if !matches.isEmpty { emit(["cancelled": false]); exit(0) }
        var candidates: [AXUIElement] = []
        for window in windows {
            for panel in descendants(window) where ["AXDialog", "AXSheet"].contains(text(panel, kAXRoleAttribute)) || text(panel, kAXSubroleAttribute) == "AXDialog" {
                let buttons = descendants(panel).filter { text($0, kAXRoleAttribute) == "AXButton" }
                let labels = buttons.map { text($0, kAXTitleAttribute) }
                guard labels.contains(where: { ["Open", "打开"].contains($0) }),
                      !labels.contains(where: { ["Save", "存储", "保存"].contains($0) }) else { continue }
                candidates += buttons.filter { ["Cancel", "取消"].contains(text($0, kAXTitleAttribute)) }
            }
        }
        // AXDialog and nested AXSheet may refer to the same Cancel button.
        var unique: [AXUIElement] = []
        for candidate in candidates where !unique.contains(where: { CFEqual($0, candidate) }) { unique.append(candidate) }
        try require(unique.count <= 1, "Ambiguous Open panels; no action sent")
        if let cancel = unique.first {
            try require(AXUIElementPerformAction(cancel, kAXPressAction as CFString) == .success, "Open panel AX cancel failed")
        }
        emit(["cancelled": !unique.isEmpty])
    } else {
        try require(matches.count == 1, "Disposable AX document window missing or ambiguous")
        let window = matches[0]
        if operation == "select-all" {
            let areas = descendants(window).filter { text($0, kAXRoleAttribute) == "AXTextArea" }
            try require(areas.count == 1, "Disposable document text area missing or ambiguous")
            let area = areas[0], value = text(area, kAXValueAttribute)
            var range = CFRange(location: 0, length: value.utf16.count)
            let selection = AXValueCreate(.cfRange, &range)!
            try require(AXUIElementSetAttributeValue(area, kAXSelectedTextRangeAttribute as CFString, selection) == .success, "AXSelectedTextRange write failed")
            let selected = text(area, kAXSelectedTextAttribute)
            try require(selected == value, "AXSelectedText does not equal full document")
            emit(["route": "ax-selected-text-range", "verified": true, "selectedText": selected])
        } else if operation == "close" {
            guard let close = element(window, kAXCloseButtonAttribute) else { throw NSError(domain: "Disposable window has no AXCloseButton", code: 1) }
            try require(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success, "Disposable AX close failed")
            // Closing our modified disposable document may present a save sheet.
            // Only inspect sheets attached to the exact window we just closed.
            let deadline = Date().addingTimeInterval(3)
            var discarded = false
            while Date() < deadline {
                let current = attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
                if !current.contains(where: { CFEqual($0, window) }) { emit(["closed": true]); exit(0) }
                let sheets = (attr(window, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { text($0, kAXRoleAttribute) == "AXSheet" }
                if !sheets.isEmpty && !discarded {
                    let buttons = sheets.flatMap(descendants).filter {
                        text($0, kAXRoleAttribute) == "AXButton" && ["Don't Save", "Don’t Save", "不存储", "不保存"].contains(text($0, kAXTitleAttribute))
                    }
                    try require(sheets.count == 1 && buttons.count == 1, "Unrecognized disposable save sheet; no action sent")
                    try require(AXUIElementPerformAction(buttons[0], kAXPressAction as CFString) == .success, "Disposable save sheet discard failed")
                    discarded = true
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw NSError(domain: "Disposable document did not close", code: 1)
        } else { throw NSError(domain: "Unknown helper operation", code: 1) }
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
''', encoding='utf-8')
subprocess.run(['/usr/bin/xcrun', 'swiftc', '-module-cache-path', str(work / 'module-cache'),
                str(helper_source), '-o', str(helper)],
               env=env, check=True, timeout=60)


def call(*args):
    r = subprocess.run([core, *args], env=env, text=True, capture_output=True, timeout=30)
    with (work / 'commands.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps(dict(args=args, code=r.returncode, stdout=r.stdout,
                                  stderr=r.stderr), ensure_ascii=False) + '\n')
    if r.returncode:
        raise AssertionError(f'{args[0]} exited {r.returncode}: {r.stdout.strip()} {r.stderr.strip()}')
    # Successful JSON commands emit one object. Accept pretty-printed JSON, too.
    return json.loads(r.stdout)


def ax_helper(operation, pid, title=''):
    r = subprocess.run([str(helper), operation, str(pid), str(document), title],
                       env=env, text=True, capture_output=True, timeout=10)
    with (work / 'commands.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps(dict(helper=operation, pid=pid, title=title,
                                  code=r.returncode, stdout=r.stdout, stderr=r.stderr),
                             ensure_ascii=False) + '\n')
    assert r.returncode == 0, f'AX helper {operation}: {r.stderr.strip()}'
    return json.loads(r.stdout)


def snapshot():
    apps = call('apps')
    active = [a for a in apps if a.get('active')]
    assert len(active) == 1, 'Cannot identify exactly one frontmost application'
    p = call('cursor')
    return active[0], (p['x'], p['y'])


def unchanged():
    current = snapshot()
    assert current[0]['pid'] == baseline[0]['pid'], 'Frontmost application changed'
    assert current[1] == baseline[1], 'Mouse pointer moved'


def step(label, action):
    try:
        result = action()
        if baseline is not None:
            unchanged()
        rows.append(('PASS', label, ''))
        return result
    except Exception as e:
        rows.append(('FAIL', label, str(e)))
        raise


def verify_value():
    value = call('value', '--role', 'AXTextArea').get('value', '')
    assert seed in value, 'AX-written text missing from TextEdit document'
    assert marker in value, 'Pid Unicode text missing from TextEdit document'
    return value


try:
    def permissions():
        check = call('check')
        assert check.get('accessibility') and check.get('screenRecording'), \
            'Grant AX and Screen Recording to the responsible app, then rerun'
        return check
    step('Permissions (no probe)', permissions)
    baseline = snapshot()
    assert baseline[0].get('bundleId') != 'com.apple.TextEdit', \
        'Keep Terminal or another app frontmost before starting'
    print(f"Frontmost stays: {baseline[0]['name']} (pid {baseline[0]['pid']}); pointer: {baseline[1]}")
    # LaunchServices background open only; no AppleScript, System Events, key/HID probe,
    # pasteboard writes, global mouse calls, activation or foreground/global overrides.
    def background_open():
        subprocess.run(['/usr/bin/open', '-g', '-a', 'TextEdit', str(document)],
                       env=env, check=True, timeout=15)
        # Unique file name prevents restored/previous acceptance windows matching.
        # Poll for 10 seconds; a safely identifiable Open panel can block reopening.
        deadline = time.monotonic() + 10
        cancelled_open = False
        observed = []
        while time.monotonic() < deadline:
            unchanged()
            windows = call('windows')
            textedit_pids = {a['pid'] for a in call('apps')
                             if a.get('bundleId') == 'com.apple.TextEdit'}
            observed = [w for w in windows if w.get('pid') in textedit_pids]
            matches = [w for w in observed if document.stem in w.get('title', '')]
            if len(matches) == 1:
                return matches[0]
            assert len(matches) <= 1, 'Disposable document window title is ambiguous'
            if not cancelled_open:
                for pid in textedit_pids:
                    result = ax_helper('cancel-open', pid)
                    if result.get('cancelled'):
                        cancelled_open = True
                        unchanged()
                        subprocess.run(['/usr/bin/open', '-g', '-a', 'TextEdit', str(document)],
                                       env=env, check=True, timeout=15)
            time.sleep(0.2)
        raise AssertionError('Disposable TextEdit window not found within 10 seconds; '
                             'first-launch/TCC dialog may need manual attention. '
                             f'Expected {document.name!r}; observed {observed!r}')
    window = step('open -g TextEdit document', background_open)
    target = step('Strict single-window lock', lambda: call(
        'lock', '--pid', str(window['pid']), '--window-id', str(window['id']),
        '--assert-no-contention'))
    locked = True
    assert target.get('windowId') == window['id'], 'Wrong window locked'
    result = step('AX focus + value write', lambda: call(
        'set-text', '--role', 'AXTextArea', '--via', 'ax', '--assert-no-contention', seed))
    assert result.get('verified') is True, 'AX write was not verified'
    result = step('Pid Unicode typing', lambda: call(
        'type', '--via', 'pid', '--assert-no-contention', marker))
    assert result.get('route') == 'pid-keys', 'Pid typing did not use pid-keys'
    step('Read back AX + pid text', verify_value)
    def select_all_range():
        result = ax_helper('select-all', window['pid'], window['title'])
        assert result.get('verified') is True, 'AX range selection was not verified'
        selected = call('value', '--role', 'AXTextArea').get('selectedText', '')
        assert seed in selected and marker in selected, 'AX selected text readback missing content'
        assert selected == verify_value(), 'AX selected text differs from full document'
        return result
    step('AXSelectedTextRange select all + AXSelectedText readback', select_all_range)
    def check_background_menu():
        try:
            result = call('menu', 'Edit|编辑>Select All|全选', '--assert-no-contention')
        except AssertionError as e:
            if 'Scoped background menu item is disabled' not in str(e):
                raise
            unchanged()
            rows.append(('SKIP', 'Background Edit > Select All menu',
                         'Inactive apps may validate document menu items as disabled; '
                         'no menu action sent. AX range selection passed.'))
            return
        assert result.get('route') == 'ax-menu', 'Menu did not use AX'
        unchanged()
        rows.append(('PASS', 'Background Edit > Select All menu', ''))
    check_background_menu()
    def capture():
        image = work / 'window.png'
        result = call('screenshot', '--out', str(image), '--assert-no-contention')
        assert image.is_file() and image.stat().st_size > 0, 'Window screenshot missing'
        assert result.get('route') == 'sck-window', 'Screenshot did not use window-only ScreenCaptureKit'
        return result
    step('Locked window-only screenshot', capture)
    step('Final document readback', verify_value)
    step('Frontmost app + pointer unchanged', unchanged)
except Exception as e:
    if not rows or rows[-1][0] != 'FAIL':
        rows.append(('FAIL', 'Acceptance assertion', str(e)))
finally:
    if window is not None:
        try:
            ax_helper('close', window['pid'], window['title'])
            if baseline is not None:
                unchanged()
            rows.append(('PASS', 'Close only disposable document via AXCloseButton', ''))
        except Exception as e:
            rows.append(('FAIL', 'Disposable document AX cleanup', str(e)))
    if locked:
        try:
            call('unlock')
        except Exception as e:
            rows.append(('FAIL', 'Isolated lock cleanup', str(e)))
    print('\nRESULT  CHECK')
    print('------  -----')
    for status, label, detail in rows:
        print(f'{status:6}  {label}' + (f' — {detail}' if detail else ''))
    print(f'\nArtifacts and disposable TextEdit document: {work}')
    print('Cleanup targets only the unique disposable document; TextEdit is never quit.')
    print('Checks compare snapshots; keep the pointer still during this acceptance run.')
    print('No global input, activation, pasteboard writes, or TCC requests were sent.')
sys.exit(1 if any(r[0] == 'FAIL' for r in rows) else 0)
PY
