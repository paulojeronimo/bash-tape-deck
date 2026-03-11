#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh"

usage() {
  cat <<'USAGE'
Usage
  ./docker/build.sh
  ./docker/build.sh <steps-dir>
  ./docker/build.sh --all <steps-dir>

Commands
  Without arguments, build the engine image.
  With <steps-dir>, build the sample image for that tape.
  With --all <steps-dir>, rebuild the engine first and then build the sample.
USAGE
}

action_arg="${1:-}"
if [ -z "$action_arg" ]; then
  build_engine_image
  exit 0
fi

if [ "$action_arg" = "-h" ] || [ "$action_arg" = "--help" ] || [ "$action_arg" = "help" ]; then
  usage
  exit 0
fi

rebuild_all=0
steps_dir_for_build="$action_arg"

if [ "$action_arg" = "--all" ]; then
  rebuild_all=1
  shift
  steps_dir_for_build="${1:-}"
fi

if [ "$#" -gt 1 ]; then
  echo "Usage: ./docker/build.sh [--all] [steps-dir]" >&2
  exit 1
fi

if [ "$rebuild_all" = "1" ] && [ -z "$steps_dir_for_build" ]; then
  echo "Usage: ./docker/build.sh --all <steps-dir>" >&2
  echo "--all only makes sense when building a sample image." >&2
  exit 1
fi

if [ -n "$steps_dir_for_build" ]; then
  build_sample_image "$steps_dir_for_build" "$rebuild_all"
else
  build_engine_image
fi
