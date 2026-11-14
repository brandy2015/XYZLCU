#!/bin/bash
# Permission-free checks only: no AX trees, screenshots, apps, or input events.
set -euo pipefail
cd "$(dirname "$0")/.."
export XYZLCU_DAEMON=0
CORE="$PWD/build/xyzlcu-core"
# Core selftest exercises the production ranking/conflict helpers with synthetic
# metadata (including XYZStudio helper windows and --pid without a selector).
"$CORE" selftest | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"] and r["screenshotRegressionChecks"] >= 10; print(json.dumps(r))'
[[ "$("$CORE" version)" == "xyzlcu 0.7.0" ]]
[[ "$(build/xyzlcu version)" == "xyzlcu 0.7.0" ]]
python3 - "$CORE" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
core = sys.argv[1]
help_text = subprocess.check_output([core, '--help'], text=True)
for command in ('--assert-no-contention', '--unsafe', 'set-text', 'press', 'select', 'scroll-to', 'wait-text', 'observe', 'selftest', '--pid', '--allow-global', '--hold'):
    assert command in help_text, command
requests = [
    {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}},
    {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['version']}}},
    {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['selftest']}}},
    {'jsonrpc': '2.0', 'id': 5, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['__stop']}}},
    {'jsonrpc': '2.0', 'id': 6, 'method': 'tools/call', 'params': {'name': 'batch', 'arguments': {'steps': ['__ax-press']}}},
]
with tempfile.TemporaryDirectory(prefix='xyzlcu-selftest-') as isolated:
    env = dict(os.environ, XYZLCU_SOCKET=isolated + '/absent.sock', XYZLCU_DAEMON='0')
    reply = subprocess.run([core, 'mcp'], input=''.join(json.dumps(r)+'\n' for r in requests), text=True, capture_output=True, env=env, timeout=20, check=True)
responses = {r['id']: r['result'] for r in map(json.loads, reply.stdout.splitlines())}
assert responses[1]['serverInfo']['version'] == '0.7.0'
assert 'allow_global' in responses[1]['instructions']
tools = {t['name']: t for t in responses[2]['tools']}
new = {'set_text', 'press', 'select_popup_item', 'scroll_to', 'wait_text', 'observe'}
legacy = {'check', 'screenshot', 'apps', 'windows', 'cursor', 'ax', 'find', 'click_element', 'click', 'type_text', 'key', 'activate', 'batch', 'xyzlcu', 'lock'}
assert new | legacy <= tools.keys()
for name in new:
    assert 'pid' in tools[name]['inputSchema']['properties'], name
for name, expected in {'press': {'nth', 'list', 'async'}, 'screenshot': {'max_side'}, 'type_text': {'allow_global', 'allow_foreground', 'assert_no_contention', 'expect_front'}, 'lock': {'unsafe'}}.items():
    assert expected <= tools[name]['inputSchema']['properties'].keys()
assert not responses[3]['isError'] and '0.7.0' in responses[3]['content'][0]['text']
assert not responses[4]['isError'] and '"ok" : true' in responses[4]['content'][0]['text']
assert responses[5]['isError'] and 'unavailable over MCP' in responses[5]['content'][0]['text']
assert responses[6]['isError'] and 'not allowed in batch' in responses[6]['content'][0]['text']
# Fail-closed policy integration tests: only denial paths with an isolated synthetic
# lock are executed. No app is opened, AX tree read, screen captured, or input posted.
with tempfile.TemporaryDirectory(prefix='xyzlcu-policy-selftest-') as isolated:
    env = dict(os.environ, XYZLCU_SOCKET=isolated + '/absent.sock', XYZLCU_DAEMON='0',
               XYZLCU_BACKGROUND='0', XYZLCU_PREWARM='0')
    for key in ('XYZLCU_TYPE_VIA', 'XYZLCU_KEY_VIA', 'XYZLCU_EVENTS_HEALTH'):
        env.pop(key, None)
    lock_path = os.path.join(isolated, 'lock.json')
    fixture = dict(pid=2147483647, windowId=4294967295, app='Synthetic closed target',
                   bundleId='', title='Policy fixture', at=0, unsafe=False)
    with open(lock_path, 'w') as f:
        json.dump(fixture, f)
    def denied(argv, expected='refused: would use global input'):
        reply = subprocess.run([core, *argv], text=True, capture_output=True, env=env, timeout=15)
        assert reply.returncode != 0, argv
        data = json.loads(reply.stdout)
        assert data['error'] == expected, (argv, data)
        if expected == 'refused: would use global input':
            assert data.get('hint'), (argv, data)
        assert {'frontmostBefore', 'frontmostAfter', 'contention', 'pointerBefore', 'pointerAfter'} <= data.keys(), (argv, data)
        return data
    cases = [
        ['type', '--via', 'hid', 'literal'], ['type', '--via', 'paste', 'literal'],
        ['key', '--via', 'events', 'a'], ['click', '--via', 'events', '10', '10'],
        ['set-text', '--via', 'paste', 'literal'], ['insert', '--via', 'paste', 'literal'],
        ['move', '10', '10'], ['drag', '0', '0', '10', '10'],
        ['activate', 'Synthetic'], ['open', 'Synthetic'], ['hide', 'Synthetic'],
        ['movewin', 'Synthetic', '0', '0'], ['replay', '/nonexistent'],
        ['record', '/nonexistent'], ['request'], ['request', '--open'],
        ['menu', '--activate', 'Edit>Select All'], ['check', '--probe'],
        ['type', '--no-lock', 'literal'],
    ]
    for argv in cases:
        denied(argv)
    closed = subprocess.run([core, 'observe'], text=True, capture_output=True, env=env, timeout=15)
    assert closed.returncode != 0 and 'lock remains active' in closed.stdout, closed
    assert os.path.isfile(lock_path), 'Exited target must not silently remove the lock'
    # One long-lived MCP process: a permitted-but-invalid probe must not leak either
    # override or forceProbe state into the next refused call.
    requests = [
        {'jsonrpc': '2.0', 'id': 21, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['check', '--probe', '--allow-global', '--invalid-selftest-option']}}},
        {'jsonrpc': '2.0', 'id': 22, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['check', '--probe']}}},
        {'jsonrpc': '2.0', 'id': 23, 'method': 'tools/call', 'params': {'name': 'type_text', 'arguments': {'text': 'literal', 'via': 'hid'}}},
        {'jsonrpc': '2.0', 'id': 24, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['version']}}},
    ]
    reply = subprocess.run([core, 'mcp'], input=''.join(json.dumps(r)+'\n' for r in requests), text=True, capture_output=True, env=env, timeout=20, check=True)
    results = {r['id']: r['result'] for r in map(json.loads, reply.stdout.splitlines())}
    assert results[21]['isError'] and 'invalid-selftest-option' in results[21]['content'][0]['text']
    for ident in (22, 23):
        assert results[ident]['isError'] and 'refused: would use global input' in results[ident]['content'][0]['text'], results[ident]
    assert not results[24]['isError']
    # Malformed or out-of-range locks fail closed rather than enabling legacy HID.
    for raw in ('{broken', json.dumps(dict(fixture, pid=-1)), json.dumps(dict(fixture, windowId=-1))):
        with open(lock_path, 'w') as f:
            f.write(raw)
        denied(['type', 'literal'], 'refused: invalid lock file; explicitly unlock or replace the lock before continuing')
    status = subprocess.check_output([core, 'lock', '--status'], env=env, text=True)
    assert json.loads(status)['valid'] is False
    subprocess.run([core, 'unlock'], env=env, capture_output=True, check=True)
    assert not os.path.exists(lock_path)
print('CLI/help/C-client/MCP protocol and strict-lock denial checks passed (no GUI actions).')
PY
