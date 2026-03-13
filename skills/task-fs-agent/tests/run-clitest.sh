#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/clitest"
CLITEST_BIN="${CLITEST_BIN:-clitest}"

if ! command -v "$CLITEST_BIN" >/dev/null 2>&1; then
  echo "error: clitest is not installed or CLITEST_BIN is invalid" >&2
  exit 1
fi

cd "$(dirname "$SCRIPT_DIR")"
"$CLITEST_BIN" "$TEST_DIR"/*.txt
