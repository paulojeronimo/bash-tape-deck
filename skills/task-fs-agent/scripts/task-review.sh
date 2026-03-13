#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
FILE="${1:-}"
[[ -n "$FILE" ]] || { echo "usage: $0 tasks/02-doing/<file>.adoc" >&2; exit 1; }
move_state "$FILE" 04-review review
