#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh"
# Defined by docker/common.sh.
declare engine_image workspace_dir play_rewind_workspace_dir parsed_steps_dir parsed_step_number

usage() {
  cat <<'USAGE'
Usage
  ./docker/run.sh play.sh <steps-dir> [N]
  ./docker/run.sh rewind.sh <steps-dir> [N]
  ./docker/run.sh <steps-dir> <sample-command> [args...]
  ./docker/run.sh <command> [args...]

Commands
  play.sh            Run play in the sample image resolved for steps-dir
  rewind.sh          Run rewind in the sample image resolved for steps-dir
  <sample-command>   Run a sample-specific command declared in docker.commands.sh
  <command>          Run any command inside the engine image
USAGE
}

action="${1:-}"
if [ -z "$action" ] || [ "$action" = "-h" ] || [ "$action" = "--help" ] || [ "$action" = "help" ]; then
  usage
  if [ -z "$action" ]; then
    exit 1
  fi
  exit 0
fi
shift

mkdir -p "$play_rewind_workspace_dir/.docker-home"

case "$action" in
  play.sh)
    parse_play_rewind_args "run.sh play.sh" "$@" || exit 1
    runtime_image="$(resolve_runtime_image_for_steps "$parsed_steps_dir")"
    if [ -n "$parsed_step_number" ]; then
      run_in_container "$runtime_image" 0 "$play_rewind_workspace_dir" /workspace "" play "$parsed_step_number"
    else
      run_in_container "$runtime_image" 0 "$play_rewind_workspace_dir" /workspace "" play
    fi
    ;;
  rewind.sh)
    parse_play_rewind_args "run.sh rewind.sh" "$@" || exit 1
    runtime_image="$(resolve_runtime_image_for_steps "$parsed_steps_dir")"
    if [ -n "$parsed_step_number" ]; then
      run_in_container "$runtime_image" 0 "$play_rewind_workspace_dir" /workspace "" rewind "$parsed_step_number"
    else
      run_in_container "$runtime_image" 0 "$play_rewind_workspace_dir" /workspace "" rewind
    fi
    ;;
  *)
    if [ -d "$action" ]; then
      if [ -z "${1:-}" ]; then
        echo "Usage: ./docker/run.sh <steps-dir> <sample-command> [args...]" >&2
        exit 1
      fi
      run_sample_command "$action" "$@"
    else
      ensure_engine_image >/dev/null
      run_in_container "$engine_image" 0 "$workspace_dir" "" "" "$action" "$@"
    fi
    ;;
esac
