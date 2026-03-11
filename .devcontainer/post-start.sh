#!/usr/bin/env bash
set -euo pipefail

workspace_dir="${WORKSPACE_DIR:-${PWD}}"
build_dir="$workspace_dir/build"
docker_home_dir="$build_dir/.docker-home"

mkdir -p "$docker_home_dir"
