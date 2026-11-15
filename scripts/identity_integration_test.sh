#!/bin/bash
# Only our disposable fixture is launched or addressed. No activation, global input,
# TCC requests, permission changes, existing-app writes, or CI service are used.
set -euo pipefail
cd "$(dirname "$0")/.."
CORE="${XYZLCU_IDENTITY_TEST_CORE:-$PWD/build/xyzlcu-core}"
[[ -x "$CORE" ]] || { echo 'Build first: ./build.sh' >&2; exit 1; }
exec python3 scripts/identity_integration_test.py "$CORE"
