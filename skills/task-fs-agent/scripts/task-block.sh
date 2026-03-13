#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
FILE="${1:-}"
REASON="${2:-}"
[[ -n "$FILE" && -n "$REASON" ]] || { echo "usage: $0 tasks/02-doing/<file>.adoc \"Reason\"" >&2; exit 1; }
append_note_to_section "$FILE" Blockers "$REASON"
move_state "$FILE" 03-blocked blocked
