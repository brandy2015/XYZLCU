#!/bin/bash
# Permission-free checks only: no AX trees, screenshots, app launches, or input events.
set -euo pipefail
cd "$(dirname "$0")/.."
export XYZLCU_DAEMON=0
CORE="$PWD/build/xyzlcu-core"
# Core selftest exercises the production ranking/conflict helpers with synthetic
# metadata (including XYZStudio helper windows and --pid without a selector).
"$CORE" selftest | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"] and r["screenshotRegressionChecks"] >= 10; print(json.dumps(r))'
[[ "$("$CORE" version)" == "xyzlcu 0.7.1" ]]
[[ "$(build/xyzlcu version)" == "xyzlcu 0.7.1" ]]
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
assert responses[1]['serverInfo']['version'] == '0.7.1'
assert 'allowGlobal' in responses[1]['instructions']
tools = {t['name']: t for t in responses[2]['tools']}
new = {'set_text', 'press', 'select_popup_item', 'scroll_to', 'wait_text', 'observe'}
legacy = {'check', 'screenshot', 'apps', 'windows', 'cursor', 'ax', 'find', 'click_element', 'click', 'type_text', 'key', 'activate', 'batch', 'xyzlcu', 'lock'}
assert new | legacy <= tools.keys()
for name in new:
    assert 'pid' in tools[name]['inputSchema']['properties'], name
for name, expected in {'press': {'nth', 'list', 'async'}, 'screenshot': {'max_side'}, 'type_text': {'allow_global', 'allow_foreground', 'assert_no_contention', 'expect_front'}, 'lock': {'unsafe'}}.items():
    assert expected <= tools[name]['inputSchema']['properties'].keys()
for name in ('click_element', 'click', 'type_text', 'key', 'activate', 'batch', 'xyzlcu'):
    opt = tools[name]['inputSchema']['properties']['allowGlobal']
    assert opt['type'] == 'boolean' and opt.get('default') is False, (name, opt)
assert not responses[3]['isError'] and '0.7.1' in responses[3]['content'][0]['text']
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
        assert data.get('globalEventsCreated') == 0 and data.get('globalEventsPosted') == 0, (argv, data)
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
        ['menu', '--activate', 'Edit>Select All'],
        ['type', '--no-lock', 'literal'],
    ]
    for argv in cases:
        denied(argv)
    closed = subprocess.run([core, 'observe'], text=True, capture_output=True, env=env, timeout=15)
    assert closed.returncode != 0 and 'lock remains active' in closed.stdout, closed
    assert os.path.isfile(lock_path), 'Exited target must not silently remove the lock'
    # check --probe remains diagnostic-only, even with a strict lock and with the
    # historical probe environment override inherited. No CGEvent may be created.
    diagnostic_env = dict(env, XYZLCU_PROBE='1')
    diagnostic = subprocess.run([core, 'check', '--probe'], text=True, capture_output=True,
                                env=diagnostic_env, timeout=15, check=True)
    diagnostic_data = json.loads(diagnostic.stdout)
    for route in ('events', 'mouse'):
        assert diagnostic_data['paths'][route].get('probeMs') is None, diagnostic_data
    # One long-lived MCP process: an invalid read-only probe must not leak an
    # override or forceProbe state into a later input call.
    requests = [
        {'jsonrpc': '2.0', 'id': 21, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['check', '--probe', '--invalid-selftest-option'], 'allowGlobal': True}}},
        {'jsonrpc': '2.0', 'id': 22, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['check', '--probe']}}},
        {'jsonrpc': '2.0', 'id': 23, 'method': 'tools/call', 'params': {'name': 'type_text', 'arguments': {'text': 'literal', 'via': 'hid'}}},
        {'jsonrpc': '2.0', 'id': 24, 'method': 'tools/call', 'params': {'name': 'xyzlcu', 'arguments': {'args': ['version']}}},
    ]
    reply = subprocess.run([core, 'mcp'], input=''.join(json.dumps(r)+'\n' for r in requests), text=True, capture_output=True, env=env, timeout=20, check=True)
    results = {r['id']: r['result'] for r in map(json.loads, reply.stdout.splitlines())}
    assert results[21]['isError'] and 'invalid-selftest-option' in results[21]['content'][0]['text']
    assert not results[22]['isError'], results[22]
    assert results[23]['isError'] and 'refused: would use global input' in results[23]['content'][0]['text'], results[23]
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
# Unlocked policy tests use a separate state directory. Every input invocation
# below must terminate in argument validation or the safety gate, before event
# construction, app activation, clipboard writes, or any AX mutation. Never add
# a successful --allow-global call to this permission-free suite.
with tempfile.TemporaryDirectory(prefix='xyzlcu-global-gate-selftest-') as isolated:
    env = dict(os.environ, XYZLCU_SOCKET=isolated + '/absent.sock', XYZLCU_DAEMON='0',
               XYZLCU_BACKGROUND='0', XYZLCU_PREWARM='0', XYZLCU_PROBE='0')
    for key in ('XYZLCU_TYPE_VIA', 'XYZLCU_KEY_VIA', 'XYZLCU_EVENTS_HEALTH', 'XYZLCU_ALLOW_GLOBAL'):
        env.pop(key, None)
    lock_path = os.path.join(isolated, 'lock.json')

    def invoke(argv, command_env=None):
        return subprocess.run([core, *argv], text=True, capture_output=True,
                              env=command_env or env, timeout=15)

    def refusal(argv, code='GLOBAL_INPUT_REFUSED', command_env=None):
        reply = invoke(argv, command_env)
        assert reply.returncode != 0, (argv, reply.stdout, reply.stderr)
        data = json.loads(reply.stdout)
        assert data.get('ok') is False and data.get('code') == code, (argv, data)
        assert data.get('globalEventsCreated') == 0 and data.get('globalEventsPosted') == 0, (argv, data)
        assert not data.get('route'), (argv, data)
        if code == 'GLOBAL_INPUT_REFUSED':
            assert data['error'].startswith('global input refused: no lock and no verified frontmost target;'), (argv, data)
            assert 'pass --app/--pid (must be frontmost) or --allow-global' in data['error'], (argv, data)
            front = data['frontmostBefore']
            # The refusal message must identify the actual frontmost app, not
            # merely echo the intended (possibly nonexistent) target.
            assert str(front['pid']) in data['error'] or (front.get('name') and front['name'] in data['error']), (argv, data)
        return data

    for argv in (['type', '--via', 'events', 'x'], ['type', '--via', 'hid', 'x'],
                 ['key', 'a'], ['key', '--via', 'events', 'a'],
                 ['click', '10', '10'], ['move', '10', '10'],
                 ['drag', '0', '0', '10', '10'], ['scroll', '0', '1'],
                 ['activate', 'XYZLCU nonexistent safety target'],
                 ['open', 'XYZLCU nonexistent safety target']):
        refusal(argv)
    # The old environment variable is deliberately not an opt-in.
    refusal(['type', '--via', 'events', 'x'], command_env=dict(env, XYZLCU_ALLOW_GLOBAL='1'))

    # These impossible targets cannot become frontmost during a concurrent app
    # switch. A real inactive GUI app would risk sending input if it gained focus
    # between discovery and dispatch; live-app mismatch policy is tested with
    # synthetic front/target identities in the core selftest instead.
    refusal(['click', '--app', 'invalid.xyzlcu.selftest.nonfrontmost', '10', '10'])
    refusal(['move', '--pid', '2147483647', '10', '10'])

    def argument_error(argv, option):
        reply = invoke(argv)
        assert reply.returncode != 0, (argv, reply.stdout, reply.stderr)
        data = json.loads(reply.stdout)
        assert data.get('ok') is False, (argv, data)
        assert data.get('code') not in ('GLOBAL_INPUT_REFUSED', 'LOCK_FAILED'), (argv, data)
        assert option in data.get('error', ''), (argv, data)
        return data

    # A failed lock always leaves a tombstone, including parser/selector errors.
    bad_locks = [
        ['--delay', '1', 'lock', '--window-id', 'bad'],
        ['lock', '--status', '--unknown-selftest-option'],
        ['lock', '--app', 'invalid.xyzlcu.selftest.target', '--window-id', 'bad'],
        ['lock', '--app', 'invalid.xyzlcu.selftest.target', '--window-id', ''],
        ['lock', '--app', 'invalid.xyzlcu.selftest.target', '--window-id'],
        ['lock', '--window-id', '--app', 'invalid.xyzlcu.selftest.target'],
        ['lock', '--app', 'invalid.xyzlcu.selftest.target', '--unknown-selftest-option'],
        ['lock', '--app', 'invalid.xyzlcu.selftest.target'],
    ]
    for index, argv in enumerate(bad_locks):
        # Replacing an existing lock must fail closed as well as initial locking.
        if index % 2:
            with open(lock_path, 'w') as f:
                json.dump(fixture, f)
        failed = invoke(argv)
        assert failed.returncode != 0, (argv, failed.stdout)
        assert os.path.isfile(lock_path), (argv, 'Failed lock did not persist a tombstone')
        status = json.loads(subprocess.check_output([core, 'lock', '--status'], env=env, text=True))
        assert status.get('state') == 'lock-failed' and status.get('code') == 'LOCK_FAILED', (argv, status)
        refusal(['type', 'x'], 'LOCK_FAILED')
        refusal(['__ax-press'], 'LOCK_FAILED')
        refusal(['type', '--via', 'events', 'x'], 'LOCK_FAILED')
        # LOCK_FAILED also blocks otherwise non-global routes until explicit unlock.
        refusal(['type', '--via', 'pid', '--pid', '2147483647', 'x'], 'LOCK_FAILED')
        subprocess.run([core, 'unlock'], env=env, text=True, capture_output=True, check=True)
        assert not os.path.exists(lock_path)
        refusal(['type', '--via', 'events', 'x'])
    # Script continuation must retain the failed-lock state in the same process.
    chained = invoke(['run', '--continue-on-error', "lock --window-id ''; type --via events x"])
    assert chained.returncode != 0, chained
    decoder = json.JSONDecoder()
    remaining = chained.stdout.strip()
    chain_results = []
    while remaining:
        item, offset = decoder.raw_decode(remaining)
        chain_results.append(item)
        remaining = remaining[offset:].lstrip()
    assert len(chain_results) == 2 and chain_results[1]['code'] == 'LOCK_FAILED', chain_results
    assert all(item['globalEventsCreated'] == item['globalEventsPosted'] == 0 for item in chain_results), chain_results
    subprocess.run([core, 'unlock'], env=env, capture_output=True, check=True)
    for argv, option in ((['type', '--via', '', 'x'], '--via'),
                         (['type', 'x', '--via'], '--via'),
                         (['type', '--via', '--', 'x'], '--via'),
                         (['type', '--app', '--via', 'events', 'x'], '--app'),
                         (['type', '--app', '', '--via', 'events', 'x'], '--app'),
                         (['key', '--pid', '', 'a'], '--pid'),
                         (['lock', '--window-id', ''], '--window-id'),
                         (['lock', '--window-id'], '--window-id'),
                         (['lock', '--window-id', '--'], '--window-id')):
        argument_error(argv, option)
        if os.path.exists(lock_path):
            subprocess.run([core, 'unlock'], env=env, capture_output=True, check=True)

    # MCP uses the same gate, and a failed lock persists across calls in one
    # long-lived process (the MCP server's in-process daemon execution path).
    def request(ident, name, arguments):
        return {'jsonrpc': '2.0', 'id': ident, 'method': 'tools/call',
                'params': {'name': name, 'arguments': arguments}}

    calls = [
        request(31, 'type_text', {'text': 'x', 'via': 'events'}),
        request(32, 'key', {'keys': ['a'], 'via': 'events', 'allowGlobal': False}),
        request(33, 'click', {'x': 10, 'y': 10}),
        request(34, 'activate', {'app': 'XYZLCU nonexistent safety target'}),
        request(35, 'xyzlcu', {'args': ['move', '10', '10']}),
        request(36, 'batch', {'steps': ['type --via events x']}),
        request(37, 'xyzlcu', {'args': ['lock', '--window-id', '']}),
        request(38, 'type_text', {'text': 'x', 'via': 'events'}),
        request(39, 'lock', {'unlock': True}),
        request(40, 'type_text', {'text': 'x', 'via': 'events'}),
    ]
    reply = subprocess.run([core, 'mcp'], input=''.join(json.dumps(r)+'\n' for r in calls),
                           text=True, capture_output=True, env=env, timeout=30, check=True)
    results = {r['id']: r['result'] for r in map(json.loads, reply.stdout.splitlines())}
    def mcp_refusal(ident, code):
        result = results[ident]
        assert result['isError'], result
        body = next(c['text'] for c in result['content'] if code in c.get('text', ''))
        data, _ = json.JSONDecoder().raw_decode(body[body.index('{'):])
        assert data.get('code') == code and data.get('ok') is False, result
        assert data.get('globalEventsCreated') == 0 and data.get('globalEventsPosted') == 0, result
    for ident in (31, 32, 33, 34, 35, 36, 40):
        mcp_refusal(ident, 'GLOBAL_INPUT_REFUSED')
    assert results[37]['isError'] and '--window-id' in str(results[37]['content']), results[37]
    mcp_refusal(38, 'LOCK_FAILED')
    assert not results[39]['isError'] and not os.path.exists(lock_path), results[39]
print('CLI/help/C-client/MCP protocol, strict-lock, and global-gate denial checks passed (no GUI actions).')
PY
