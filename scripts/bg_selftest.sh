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
document = work / 'XYZLCU background acceptance.txt'
document.write_text('Disposable background test document.\n', encoding='utf-8')
locked = False
baseline = None


def call(*args):
    r = subprocess.run([core, *args], env=env, text=True, capture_output=True, timeout=30)
    with (work / 'commands.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps(dict(args=args, code=r.returncode, stdout=r.stdout,
                                  stderr=r.stderr), ensure_ascii=False) + '\n')
    if r.returncode:
        raise AssertionError(f'{args[0]} exited {r.returncode}: {r.stdout.strip()} {r.stderr.strip()}')
    # Successful JSON commands emit one object. Accept pretty-printed JSON, too.
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
        # Wait for AX-visible document window without manipulating app/window state.
        for _ in range(60):
            unchanged()
            windows = call('windows')
            textedit_pids = {a['pid'] for a in call('apps')
                             if a.get('bundleId') == 'com.apple.TextEdit'}
            matches = [w for w in windows if document.stem in w.get('title', '')
                       and w.get('pid') in textedit_pids]
            if len(matches) == 1:
                return matches[0]
            time.sleep(0.2)
        raise AssertionError('TextEdit document window not found; inspect first-launch or TCC dialogs manually')
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
    def select_all_menu():
        result = call('menu', 'Edit|编辑>Select All|全选', '--assert-no-contention')
        assert result.get('route') == 'ax-menu', 'Menu did not use AX'
        value = call('value', '--role', 'AXTextArea')
        selected = value.get('selectedText', '')
        assert seed in selected and marker in selected, \
            'AX menu did not select document text (some macOS versions disable background Edit commands)'
        return result
    step('AX Edit > Select All + readback', select_all_menu)
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
    print('Document remains open for inspection; close it manually when finished.')
    print('Checks compare snapshots; keep the pointer still during this acceptance run.')
    print('No global input, activation, pasteboard writes, or TCC requests were sent.')
sys.exit(1 if any(r[0] == 'FAIL' for r in rows) else 0)
PY
