#!/usr/bin/env bash
set -euo pipefail

invocation_dir="$PWD"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
cd "$repo_dir"

engine_image="${ENGINE_IMAGE:-bash-tape:engine}"
sample_image_prefix="${SAMPLE_IMAGE_PREFIX:-bash-tape}"
ext_file_name="${DOCKER_EXT_FILE:-docker.extend.sh}"
commands_file_name="${DOCKER_COMMANDS_FILE:-docker.commands.sh}"
host_uid="$(id -u)"
host_gid="$(id -g)"
workspace_dir="$invocation_dir"
play_rewind_workspace_dir="${BASH_TAPE_RUN_WORKDIR:-$repo_dir/build}"
current_runtime_image=""
# Shared with docker/run.sh after sourcing this file.
parsed_steps_dir=""
parsed_step_number=""

declare -a EXT_APT_PACKAGES=()
declare -a EXT_DOCKERFILE_LINES=()

if [ ! -d "$workspace_dir" ]; then
  echo "Workspace directory not found: $workspace_dir" >&2
  exit 1
fi
workspace_dir="$(cd "$workspace_dir" && pwd)"
if [ ! -d "$play_rewind_workspace_dir" ]; then
  mkdir -p "$play_rewind_workspace_dir"
fi
play_rewind_workspace_dir="$(cd "$play_rewind_workspace_dir" && pwd)"

print_docker_command() {
  local -a cmd=("$@")
  local rendered=""
  local part

  for part in "${cmd[@]}"; do
    rendered+="$(printf '%q' "$part") "
  done

  printf 'Executing: %s\n' "${rendered% }"
}

normalize_steps_dir() {
  local steps_dir_arg="$1"
  local resolved_steps_dir

  if [ -z "$steps_dir_arg" ]; then
    echo "Missing steps directory argument" >&2
    return 1
  fi

  if [[ "$steps_dir_arg" = /* ]]; then
    resolved_steps_dir="$steps_dir_arg"
  else
    resolved_steps_dir="$invocation_dir/$steps_dir_arg"
  fi

  if [ ! -d "$resolved_steps_dir" ]; then
    echo "Steps directory not found: $steps_dir_arg" >&2
    return 1
  fi

  (cd "$resolved_steps_dir" && pwd)
}

sanitize_tag_fragment() {
  local value="$1"
  value="${value,,}"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [ -z "$value" ]; then
    value="sample"
  fi
  printf '%s' "$value"
}

sample_image_name_for_dir() {
  local steps_dir_abs="$1"
  local base name prefix

  base="$(basename "$steps_dir_abs")"
  name="$(sanitize_tag_fragment "$base")"
  prefix="${sample_image_prefix//:/-}"
  printf '%s:%s' "$prefix" "$name"
}

image_exists() {
  local image="$1"
  docker image inspect "$image" >/dev/null 2>&1
}

load_sample_extensions() {
  local steps_dir_abs="$1"
  local ext_file="$steps_dir_abs/$ext_file_name"

  EXT_APT_PACKAGES=()
  EXT_DOCKERFILE_LINES=()

  if [ ! -f "$ext_file" ]; then
    return
  fi

  # shellcheck disable=SC1090
  source "$ext_file"
}

build_engine_image() {
  local -a cmd=(docker build --target engine -f docker/Dockerfile -t "$engine_image" .)
  print_docker_command "${cmd[@]}"
  "${cmd[@]}"
}

ensure_engine_image() {
  if image_exists "$engine_image"; then
    return
  fi

  echo "Engine image not found: $engine_image"
  echo "Building engine image..."
  build_engine_image
}

build_sample_image() {
  local steps_dir_arg="$1"
  local rebuild_engine_first="${2:-0}"
  local steps_dir_abs sample_image steps_dir_rel
  local tmp_dockerfile
  local apt_install_cmd=""
  local pkg
  local dockerfile_line

  steps_dir_abs="$(normalize_steps_dir "$steps_dir_arg")"
  sample_image="$(sample_image_name_for_dir "$steps_dir_abs")"
  if [[ "$steps_dir_abs" != "$repo_dir/"* ]]; then
    echo "Steps directory must be inside repository: $steps_dir_abs" >&2
    exit 1
  fi
  steps_dir_rel="${steps_dir_abs#"$repo_dir"/}"

  if [ "$rebuild_engine_first" = "1" ]; then
    build_engine_image
  else
    ensure_engine_image
  fi
  load_sample_extensions "$steps_dir_abs"

  if [ "${#EXT_APT_PACKAGES[@]}" -gt 0 ]; then
    for pkg in "${EXT_APT_PACKAGES[@]}"; do
      apt_install_cmd+=" $pkg"
    done
  fi

  tmp_dockerfile="$(mktemp "${TMPDIR:-/tmp}/bash-tape-sample-docker.XXXXXX")"

  {
    printf 'FROM %s\n' "$engine_image"
    printf 'USER root\n'

    if [ -n "$apt_install_cmd" ]; then
      printf 'RUN apt-get update && apt-get install -y --no-install-recommends%s && rm -rf /var/lib/apt/lists/*\n' "$apt_install_cmd"
    fi

    for dockerfile_line in "${EXT_DOCKERFILE_LINES[@]}"; do
      printf '%s\n' "$dockerfile_line"
    done

    printf 'COPY --chown=app:app %s /opt/bash-tape/steps\n' "$steps_dir_rel"
    printf 'ENV BASH_TAPE_SOURCE_STEPS_DIR="%s"\n' "$(printf '%s' "$steps_dir_rel" | sed 's/"/\\"/g')"
    printf 'ENV BASH_TAPE_DEFAULT_STEPS_DIR=/opt/bash-tape/steps\n'
    printf 'USER app\n'
    printf 'WORKDIR /workspace\n'
  } > "$tmp_dockerfile"

  local -a build_cmd=(docker build -f "$tmp_dockerfile" -t "$sample_image" .)
  print_docker_command "${build_cmd[@]}"
  "${build_cmd[@]}"
  rm -f "$tmp_dockerfile"

  echo "Built sample image: $sample_image"
}

resolve_runtime_image_for_steps() {
  local steps_dir_arg="$1"
  local steps_dir_abs sample_image

  steps_dir_abs="$(normalize_steps_dir "$steps_dir_arg")"
  sample_image="$(sample_image_name_for_dir "$steps_dir_abs")"

  if image_exists "$sample_image"; then
    printf '%s' "$sample_image"
    return
  fi

  build_sample_image "$steps_dir_abs" >/dev/null
  printf '%s' "$sample_image"
}

run_in_container() {
  local image="$1"
  local use_host_network="${2:-0}"
  local container_workspace_dir="$3"
  local container_run_workdir="${4:-}"
  local container_entrypoint="${5:-}"
  shift 5

  local -a docker_args
  local -a container_cmd

  container_cmd=("$@")
  docker_args=(
    --rm
    --user "${host_uid}:${host_gid}"
    -v "$container_workspace_dir:/workspace"
    -w /workspace
    -e "HOME=/workspace/.docker-home"
    -e "LANG=C.UTF-8"
    -e "LC_ALL=C.UTF-8"
    -e "TERM=${TERM:-xterm-256color}"
  )

  if [ -n "$container_run_workdir" ]; then
    docker_args+=(-e "BASH_TAPE_RUN_WORKDIR=$container_run_workdir")
  fi

  if [ -n "$container_entrypoint" ]; then
    docker_args+=(--entrypoint "$container_entrypoint")
  fi

  if [ "$use_host_network" = "1" ]; then
    docker_args+=(--network host)
  fi

  docker_args+=(-i)

  if [ -t 0 ] && [ -t 1 ]; then
    docker_args+=(-t)
  fi

  local -a run_cmd=(docker run "${docker_args[@]}" "$image" "${container_cmd[@]}")
  print_docker_command "${run_cmd[@]}"
  "${run_cmd[@]}"
}

sample_run_in_container() {
  local use_host_network="${1:-0}"
  shift
  run_in_container "$current_runtime_image" "$use_host_network" "$play_rewind_workspace_dir" /workspace "" "$@"
}

sample_run_in_container_with_entrypoint() {
  local use_host_network="${1:-0}"
  local entrypoint="$2"
  shift 2
  run_in_container "$current_runtime_image" "$use_host_network" "$play_rewind_workspace_dir" /workspace "$entrypoint" "$@"
}

sample_workspace_dir() {
  printf '%s' "$workspace_dir"
}

run_sample_command() {
  local steps_dir_arg="$1"
  local sample_command="$2"
  shift 2

  local steps_dir_abs commands_file

  steps_dir_abs="$(normalize_steps_dir "$steps_dir_arg")"
  current_runtime_image="$(resolve_runtime_image_for_steps "$steps_dir_abs")"
  commands_file="$steps_dir_abs/$commands_file_name"

  if [ ! -f "$commands_file" ]; then
    echo "No sample command file found: $commands_file" >&2
    echo "Supported runtime commands are: play.sh, rewind.sh, and sample commands" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$commands_file"

  if ! declare -F sample_docker_dispatch >/dev/null 2>&1; then
    echo "Invalid sample command file: missing sample_docker_dispatch function" >&2
    echo "File: $commands_file" >&2
    exit 1
  fi

  if ! sample_docker_dispatch "$sample_command" "$@"; then
    echo "Unknown sample command '$sample_command' for $steps_dir_abs" >&2
    if declare -F sample_docker_list_commands >/dev/null 2>&1; then
      echo "Available sample commands:" >&2
      sample_docker_list_commands >&2
    fi
    exit 1
  fi
}

parse_play_rewind_args() {
  local action_name="$1"
  shift

  parsed_steps_dir=""
  parsed_step_number=""

  if [ "$#" -eq 0 ]; then
    echo "Usage: ./docker/$action_name <steps-dir> [N]" >&2
    return 1
  fi

  if [ "$#" -gt 2 ]; then
    echo "Usage: ./docker/$action_name <steps-dir> [N]" >&2
    return 1
  fi

  if [ ! -d "$1" ]; then
    echo "Steps directory not found: $1" >&2
    return 1
  fi
  # shellcheck disable=SC2034
  parsed_steps_dir="$1"

  if [ "$#" -eq 1 ]; then
    return 0
  fi

  if [[ "$2" =~ ^[0-9]+$ ]]; then
    # shellcheck disable=SC2034
    parsed_step_number="$2"
    return 0
  fi

  echo "Invalid step number: $2" >&2
  echo "Usage: ./docker/$action_name <steps-dir> [N]" >&2
  return 1
}
