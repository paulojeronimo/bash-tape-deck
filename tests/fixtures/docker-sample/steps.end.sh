#!/usr/bin/env bash
set -euo pipefail

if [ -f "${BASH_TAPE_STATE_DIR:?}/begin.txt" ]; then
  printf '%s\n' "end" > demo-output/hook-end.txt
  rm -f "${BASH_TAPE_STATE_DIR}/begin.txt"
fi
