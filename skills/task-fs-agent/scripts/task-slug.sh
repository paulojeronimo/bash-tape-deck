#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ $# -gt 0 ]] || { echo "usage: $0 \"Task title here\"" >&2; exit 1; }
slugify "$*"
printf '\n'
