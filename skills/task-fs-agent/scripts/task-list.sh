#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
ensure_tasks_dirs
TDIR="$(tasks_dir)"
for d in 01-inbox 02-doing 03-blocked 04-review 05-done; do
  printf '\n[%s]\n' "$d"
  find "$TDIR/$d" -maxdepth 1 -type f -name '*.adoc' | sort || true
done
