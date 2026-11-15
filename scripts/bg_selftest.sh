#!/bin/bash
# v0.8 background acceptance uses only the owned fixture, never installed apps.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ./scripts/identity_integration_test.sh "$@"
