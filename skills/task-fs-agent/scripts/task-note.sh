#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
FILE="${1:-}"
NOTE="${2:-}"
SECTION="${3:-Execution Notes}"
[[ -n "$FILE" && -n "$NOTE" ]] || { echo "usage: $0 <task-file> \"note\" [section]" >&2; exit 1; }
append_note_to_section "$FILE" "$SECTION" "$NOTE"
printf '%s\n' "$FILE"
