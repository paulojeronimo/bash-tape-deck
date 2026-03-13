#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/functions.sh"

steps_dir_arg="${1:-}"
if [ -z "$steps_dir_arg" ]; then
  echo "Usage: ./rewind.sh <steps-dir> [N]" >&2
  exit 1
fi

if [ ! -d "$steps_dir_arg" ]; then
  echo "Steps directory not found: $steps_dir_arg" >&2
  exit 1
fi

steps_dir="$(cd "$steps_dir_arg" && pwd)"
default_run_workdir="$script_dir/build"
run_workdir="${BASH_TAPE_RUN_WORKDIR:-$default_run_workdir}"
mkdir -p "$run_workdir"
run_workdir="$(cd "$run_workdir" && pwd)"
cd "$run_workdir"

target_step="${2:-1}"

if ! [[ "$target_step" =~ ^[0-9]+$ ]]; then
  echo "Invalid step number: $target_step" >&2
  echo "Usage: ./rewind.sh <steps-dir> [N]" >&2
  exit 1
fi

rewind_script="$steps_dir/steps.${target_step}.rewind.sh"
if [ ! -x "$rewind_script" ]; then
  echo "Unsupported step: $target_step" >&2
  echo "Expected executable script: $rewind_script" >&2
  exit 1
fi
steps_file_name="steps.${target_step}.sh"
rewind_file_name="$(basename "$rewind_script")"

tape_identity_source="${BASH_TAPE_SOURCE_STEPS_DIR:-$steps_dir}"
tape_id="$(bash_tape_id "$tape_identity_source")"
tape_state_dir="$(bash_tape_state_dir "$tape_identity_source" "$run_workdir")"
tape_log_file="$(bash_tape_log_file "$tape_identity_source" "$run_workdir")"
mkdir -p "$tape_state_dir"
export BASH_TAPE_ID="$tape_id"
export BASH_TAPE_DIR="$run_workdir/.bash-tape-deck"
export BASH_TAPE_STATE_DIR="$tape_state_dir"
export BASH_TAPE_LOG_FILE="$tape_log_file"
export BASH_TAPE_STEPS_DIR="$steps_dir"
export BASH_TAPE_SOURCE_STEPS_DIR="$tape_identity_source"
export BASH_TAPE_STEPS_NUMBER="$target_step"
export BASH_TAPE_RUN_WORKDIR="$run_workdir"
log_bash_tape_event \
  "$tape_log_file" \
  "rewind_started" \
  "steps_dir" "$steps_dir" \
  "steps_number" "$target_step" \
  "steps_file" "$steps_file_name" \
  "rewind_file" "$rewind_file_name" \
  "workdir" "$run_workdir"
bash "$rewind_script"
log_bash_tape_event "$tape_log_file" "rewound" "steps_number" "$target_step" "steps_file" "$steps_file_name" "rewind_file" "$rewind_file_name"
