#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
FILE="${1:-}"
AGENT_NAME="${2:-}"
[[ -n "$FILE" ]] || { echo "usage: $0 tasks/01-inbox/<file>.adoc [agent-name]" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "error: file not found: $FILE" >&2; exit 1; }
if [[ -n "$AGENT_NAME" ]]; then
  replace_attr "$FILE" agent "$AGENT_NAME"
fi
move_state "$FILE" 02-doing doing
