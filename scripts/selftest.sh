#!/bin/bash
# Permission-free regression checks. All sensitive invocations must refuse before
# AX, capture, launch, clipboard or input APIs. No global override is used.
set -euo pipefail
cd "$(dirname "$0")/.."
CORE="${XYZLCU_IDENTITY_TEST_CORE:-$PWD/build/xyzlcu-core}"
[[ -x "$CORE" ]] || { echo 'Build first: ./build.sh' >&2; exit 1; }
export XYZLCU_DAEMON=0 XYZLCU_AUTO_RESTART=0 XYZLCU_PREWARM=0 XYZLCU_STREAM=0 XYZLCU_PROBE=0
python3 - "$CORE" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

core = sys.argv[1]
count = 0
with tempfile.TemporaryDirectory(prefix='xyzlcu-safe-regression-') as work:
    env = dict(os.environ, XYZLCU_SOCKET=work + '/isolated.sock')
    for key in ('XYZLCU_TYPE_VIA', 'XYZLCU_KEY_VIA', 'XYZLCU_EVENTS_HEALTH', 'XYZLCU_ALLOW_GLOBAL', 'XYZLCU_CORE'):
        env.pop(key, None)
    def invoke(args, text=None):
        return subprocess.run([core, *args], input=text, text=True, capture_output=True, env=env, timeout=30)
    def checked(condition, detail):
        global count
        assert condition, detail
        count += 1
    for binary in (core, str(Path(core).with_name('xyzlcu'))):
        result = subprocess.run([binary, '--version'], capture_output=True, text=True, env=env, timeout=20)
        checked(result.returncode == 0 and result.stdout.strip() == 'xyzlcu 0.8.0', (binary, result))
    result = invoke(['selftest'])
    data = json.loads(result.stdout)
    checked(result.returncode == 0 and data['ok'] and data['screenshotRegressionChecks'] >= 10, data)
    result = invoke(['capabilities', '--json'])
    caps = json.loads(result.stdout)
    checked(result.returncode == 0 and caps['schema_version'] == 1 and caps['consumer_available'] is False, caps)
    checked(caps['consumer_transports'] == [], caps)
    result = invoke(['check'])
    diagnostic = json.loads(result.stdout)
    checked(result.returncode == 0 and diagnostic.get('computerOperationsAvailable') is False and diagnostic.get('consumerAvailable') is False and diagnostic.get('routeUnavailableCode') == 'IDENTITY_UNPROVABLE', diagnostic)
    checked(diagnostic.get('paths') and all(route.get('available') is False for route in diagnostic['paths'].values()), diagnostic)
    checked(diagnostic.get('typeOrder') == [] and diagnostic.get('keyOrder') == [], diagnostic)
    # Lifecycle verbs must not start a resident daemon/MCP loop when a consumer
    # profile is requested. An unread non-sensitive test FD proves the refusal
    # precedes envelope acquisition as well as lifecycle startup.
    client = str(Path(core).with_name('xyzlcu'))
    for binary in (core, client):
        for args in (['serve', '--consumer', 'xyzstudio', '--background'], ['mcp', '--consumer', 'xyzstudio']):
            result = subprocess.run([binary, *args], input='', capture_output=True, text=True, env=env, timeout=5)
            body = json.loads(result.stdout)
            checked(result.returncode != 0 and body.get('code') == 'SESSION_INVALID', (binary, args, result))
            checked(body.get('dispatch_state') == 'not_dispatched' and body.get('side_effects_possible') is False, body)
            checked(not Path(env['XYZLCU_SOCKET']).exists(), 'consumer lifecycle created a daemon socket')
            read_fd, write_fd = os.pipe()
            marker = b'not-sensitive-integration-envelope'
            try:
                os.write(write_fd, marker)
                result = subprocess.run([binary, *args, '--request-fd', str(read_fd)], input='', capture_output=True,
                                        text=True, env=env, timeout=5, pass_fds=(read_fd,))
                body = json.loads(result.stdout)
                checked(result.returncode != 0 and body.get('code') == 'SESSION_INVALID', (binary, args, result))
                os.close(write_fd)
                write_fd = -1
                checked(os.read(read_fd, len(marker) + 1) == marker, 'consumer preflight read request FD before refusal')
            finally:
                os.close(read_fd)
                if write_fd >= 0:
                    os.close(write_fd)

    # The lightweight client must execute its sibling core for every identity /
    # refusal entrypoint, even with a caller-controlled historical override.
    # This override is an owned harmless script; it only prints a sentinel.
    fake = Path(work) / 'fake-core'
    fake.write_text('#!/bin/sh\nprintf "UNEXPECTED_FAKE_CORE_OVERRIDE\\n"\n')
    fake.chmod(0o700)
    override_cases = [(['capabilities', '--json'], None),
                      (['identity-observe', '--pid', '2147483647', '--json'], 'PROCESS_NOT_FOUND'),
                      (['identity-check', '--request-fd', '-1', '--json'], 'INVALID_REQUEST'),
                      (['open-app', '--bundle-id', 'com.xyztech.xyzlcu.identity-fixture', '--json'], 'APP_TRUST_UNPROVABLE'),
                      (['bind-window', '--json'], 'IDENTITY_UNPROVABLE'),
                      (['windows', '--thumbnails', '--json'], None),
                      (['windows', '--show-all', '--json'], None),
                      (['screenshot', '--consumer', 'xyzstudio', '--json'], 'SESSION_INVALID'),
                      (['screenshot'], 'IDENTITY_UNPROVABLE'),
                      (['run', 'set-text fixture'], 'IDENTITY_UNPROVABLE')]
    for daemon_mode in ('0', '1'):
        override_env = dict(env, XYZLCU_CORE=str(fake), XYZLCU_DAEMON=daemon_mode)
        for args, expected_code in override_cases:
            result = subprocess.run([client, *args], input='', capture_output=True, text=True, env=override_env, timeout=10)
            checked('UNEXPECTED_FAKE_CORE_OVERRIDE' not in result.stdout + result.stderr, (daemon_mode, args, result))
            if not result.stdout.strip():
                raise AssertionError(('identity entrypoint returned no JSON', daemon_mode, args, result.returncode, result.stderr))
            body = json.loads(result.stdout)
            checked(body.get('schema_version') == 1 or body.get('code') == 'IDENTITY_UNPROVABLE', body)
            if expected_code:
                checked(result.returncode != 0 and body.get('code') == expected_code, (daemon_mode, args, body))
            else:
                checked(result.returncode == 0, (daemon_mode, args, body))
    sensitive = [
        ['screenshot'], ['observe'], ['ax'], ['find', 'fixture'], ['value'], ['wait'], ['wait-text', 'fixture'],
        ['taps'], ['click', '1', '1'], ['click-el', 'fixture'], ['move', '1', '1'], ['drag', '1', '1', '2', '2'],
        ['scroll', '0', '1'], ['type', 'fixture'], ['type', '--via', 'pid', '--pid', '2147483647', 'fixture'],
        ['type', '--via', 'paste', 'fixture'], ['key', 'a'], ['insert', 'fixture'], ['settext', 'fixture'],
        ['set-text', 'fixture'], ['menu', 'fixture'], ['press', 'fixture'], ['select', 'fixture'], ['scroll-to', 'fixture'],
        ['activate', 'com.xyztech.xyzlcu.identity-fixture'], ['open', 'com.xyztech.xyzlcu.identity-fixture'],
        ['hide', 'com.xyztech.xyzlcu.identity-fixture'], ['movewin', 'fixture', '0', '0'],
        ['record', str(Path(work) / 'not-created')], ['replay', str(Path(work) / 'absent')], ['request'], ['__ax-press'],
        ['lock', '--app', 'com.xyztech.xyzlcu.identity-fixture'],
    ]
    def assert_denial(body):
        checked(body.get('ok') is False and body.get('code') == 'IDENTITY_UNPROVABLE', body)
        checked(body.get('globalEventsCreated') == body.get('globalEventsPosted') == 0, body)
    for args in sensitive:
        result = invoke(args)
        checked(result.returncode != 0, (args, result))
        assert_denial(json.loads(result.stdout))
    result = invoke(['run', '--continue-on-error', 'click 1 1; set-text fixture; screenshot'])
    checked(result.returncode != 0, result)
    remaining = result.stdout.strip()
    decoder = json.JSONDecoder()
    entries = []
    while remaining:
        body, offset = decoder.raw_decode(remaining)
        entries.append(body)
        remaining = remaining[offset:].lstrip()
    checked(len(entries) == 3, entries)
    for body in entries:
        assert_denial(body)
    result = invoke(['batch'], 'type fixture\n')
    checked(result.returncode != 0, result)
    assert_denial(json.loads(result.stdout))
    calls = [
        {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    ]
    tool_cases = [('click', {'x': 1, 'y': 1}), ('type_text', {'text': 'fixture'}), ('key', {'keys': ['a']}),
                  ('set_text', {'text': 'fixture'}), ('press', {'title': 'fixture'}), ('screenshot', {}),
                  ('activate', {'app': 'com.xyztech.xyzlcu.identity-fixture'}),
                  ('xyzlcu', {'args': ['move', '1', '1']}), ('batch', {'steps': ['click 1 1', 'set-text fixture'], 'continue_on_error': True})]
    for ident, (name, args) in enumerate(tool_cases, 10):
        calls.append({'jsonrpc': '2.0', 'id': ident, 'method': 'tools/call', 'params': {'name': name, 'arguments': args}})
    result = invoke(['mcp'], ''.join(json.dumps(call) + '\n' for call in calls))
    checked(result.returncode == 0, result)
    replies = {reply['id']: reply['result'] for reply in map(json.loads, result.stdout.splitlines())}
    checked(replies[1]['serverInfo']['version'] == '0.8.0', replies[1])
    checked({'xyzlcu', 'batch', 'set_text', 'press'} <= {tool['name'] for tool in replies[2]['tools']}, replies[2])
    for ident in range(10, 10 + len(tool_cases)):
        reply = replies[ident]
        checked(reply['isError'], reply)
        texts = '\n'.join(block.get('text', '') for block in reply['content'])
        found = 0
        for index, character in enumerate(texts):
            if character != '{':
                continue
            try:
                body, _ = decoder.raw_decode(texts[index:])
            except ValueError:
                continue
            if isinstance(body, dict) and body.get('code') == 'IDENTITY_UNPROVABLE':
                assert_denial(body)
                found += 1
        checked(found >= 1, reply)
print(f'PASS: {count} permission-free CLI/C-client/MCP/batch assertions; zero global events created or posted on all refusal paths.')
PY
