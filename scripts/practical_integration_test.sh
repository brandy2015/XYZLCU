#!/bin/bash
# Only a newly built owned background fixture is addressed. No activation,
# input, permission requests, TCC dialog clicks, or existing-app writes occur.
set -euo pipefail
cd "$(dirname "$0")/.."
CORE="${XYZLCU_PRACTICAL_TEST_CORE:-$PWD/build/xyzlcu-core}"
[[ -x "$CORE" ]] || { echo 'Build first: ./build.sh' >&2; exit 1; }
exec python3 scripts/practical_integration_test.py "$CORE"
