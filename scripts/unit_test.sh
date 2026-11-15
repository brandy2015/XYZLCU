#!/bin/bash
# Deterministic injected-provider tests. No desktop interaction or TCC requests.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift test --filter IdentityProofTests "$@"
