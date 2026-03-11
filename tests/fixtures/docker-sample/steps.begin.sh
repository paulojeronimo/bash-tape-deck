#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${BASH_TAPE_STATE_DIR:?}" demo-output
printf '%s\n' "begin" > "${BASH_TAPE_STATE_DIR}/begin.txt"
printf '%s\n' "begin" > demo-output/hook-begin.txt
