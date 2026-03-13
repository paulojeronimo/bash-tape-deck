#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  [ -f "$path" ] || fail "Expected file to exist: $path"
}

assert_contains() {
  local path="$1"
  local pattern="$2"

  grep -F -- "$pattern" "$path" >/dev/null || fail "Expected '$pattern' in $path"
}

cd "$repo_root"

assert_file_exists ".devcontainer/devcontainer.json"
assert_file_exists ".devcontainer/Dockerfile"
assert_file_exists ".devcontainer/post-start.sh"
assert_file_exists "docker/Dockerfile"
assert_file_exists "docker/build.sh"
assert_file_exists "docker/run.sh"
assert_file_exists "docker/common.sh"
assert_file_exists "docker/bin/bash-tape-deck"

assert_contains ".devcontainer/devcontainer.json" '"dockerfile": "Dockerfile"'
assert_contains ".devcontainer/devcontainer.json" '"context": "."'
assert_contains ".devcontainer/devcontainer.json" '"ghcr.io/devcontainers/features/docker-in-docker:2"'
# shellcheck disable=SC2016
assert_contains ".devcontainer/devcontainer.json" '"workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}"'
assert_contains ".devcontainer/devcontainer.json" '"remoteUser": "vscode"'
# shellcheck disable=SC2016
assert_contains ".devcontainer/devcontainer.json" '"BASH_TAPE_RUN_WORKDIR": "/workspaces/${localWorkspaceFolderBasename}/build"'
assert_contains ".devcontainer/devcontainer.json" '"postStartCommand": "bash .devcontainer/post-start.sh"'

assert_contains ".devcontainer/Dockerfile" 'FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04'
assert_contains ".devcontainer/Dockerfile" 'shellcheck'
assert_contains ".devcontainer/Dockerfile" 'figlet'
assert_contains ".devcontainer/Dockerfile" 'toilet'
assert_contains ".devcontainer/Dockerfile" 'curl -fsSL'
assert_contains ".devcontainer/Dockerfile" 'CMD ["sleep", "infinity"]'

# shellcheck disable=SC2016
assert_contains ".devcontainer/post-start.sh" 'workspace_dir="${WORKSPACE_DIR:-${PWD}}"'
# shellcheck disable=SC2016
assert_contains ".devcontainer/post-start.sh" 'mkdir -p "$docker_home_dir"'

# shellcheck disable=SC2016
grep -F 'docker build --target engine -f docker/Dockerfile -t "$engine_image" .' docker/common.sh >/dev/null || fail "Missing engine build command in docker/common.sh"
# shellcheck disable=SC2016
grep -F -- '--user "${host_uid}:${host_gid}"' docker/common.sh >/dev/null || fail "Missing standard nested docker user mapping in docker/common.sh"
assert_contains "docker/build.sh" './docker/build.sh --all <steps-dir>'
assert_contains "docker/run.sh" './docker/run.sh play.sh <steps-dir> [N]'
assert_contains "docker/Dockerfile" 'COPY docker/bin/bash-tape-deck /usr/local/bin/bash-tape-deck'

printf 'PASS: devcontainer configuration test\n'
