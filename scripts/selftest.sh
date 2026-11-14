#!/bin/bash
# Permission-free checks only: no AX trees, screenshots, apps, or input events.
set -euo pipefail
cd "$(dirname "$0")/.."
export XYZLCU_DAEMON=0
CORE="$PWD/build/xyzlcu-core"
"$CORE" selftest
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
for command in ('set-text', 'press', 'select', 'scroll-to', 'wait-text', 'observe', 'selftest', '--pid', '--allow-global', '--hold'):
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
for name, expected in {'press': {'nth', 'list', 'async'}, 'screenshot': {'max_side'}, 'type_text': {'allow_global', 'expect_front'}}.items():
    assert expected <= tools[name]['inputSchema']['properties'].keys()
assert not responses[3]['isError'] and '0.7.0' in responses[3]['content'][0]['text']
assert not responses[4]['isError'] and '"ok" : true' in responses[4]['content'][0]['text']
assert responses[5]['isError'] and 'unavailable over MCP' in responses[5]['content'][0]['text']
assert responses[6]['isError'] and 'not allowed in batch' in responses[6]['content'][0]['text']
print('CLI/help/C-client/MCP protocol checks passed (no GUI actions).')
PY
