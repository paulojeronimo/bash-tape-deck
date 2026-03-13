#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
sample_dir="tests/fixtures/docker-sample"
workspace_root="$(mktemp -d "$repo_root/build/test-docker-wrapper.XXXXXX")"
run_workdir="$workspace_root/workdir"
output_file="$workspace_root/play.output"
build_output_file="$workspace_root/build.output"

cleanup() {
  rm -rf "$workspace_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

section() {
  printf -- '\n[%s]\n' "$1"
}

run_and_capture() {
  local label="$1"
  local output_path="$2"
  shift 2

  printf -- '-> %s\n' "$label"
  if "$@" >"$output_path" 2>&1; then
    printf -- '   ok\n'
    return 0
  fi

  printf -- '   failed\n' >&2
  printf -- '\n--- %s output ---\n' "$label" >&2
  sed -n '1,220p' "$output_path" >&2 || true
  printf -- '--- end output ---\n' >&2
  return 1
}

assert_file_exists() {
  local path="$1"
  [ -e "$path" ] || fail "Expected file to exist: $path"
}

assert_contains() {
  local path="$1"
  local pattern="$2"
  grep -F "$pattern" "$path" >/dev/null || fail "Expected '$pattern' in $path"
}

cd "$repo_root"

command -v docker >/dev/null 2>&1 || fail "docker command not found"

section "Build sample image"
run_and_capture \
  "docker/build.sh --all $sample_dir" \
  "$build_output_file" \
  ./docker/build.sh --all "$sample_dir" || fail "Sample image build failed"

section "Run tape through Docker wrapper"
mkdir -p "$run_workdir"
run_and_capture \
  "docker/run.sh play.sh $sample_dir" \
  "$output_file" \
  bash -lc "printf '\\nb\\ne\\n' | BASH_TAPE_RUN_WORKDIR='$run_workdir' ./docker/run.sh play.sh '$sample_dir'" || fail "Tape playback failed"

section "Validate generated files"
assert_file_exists "$run_workdir/demo-output/step1.txt"
assert_file_exists "$run_workdir/demo-output/hook-begin.txt"
assert_file_exists "$run_workdir/demo-output/hook-end.txt"
printf -- '-> generated files are present\n'

section "Validate tape log"
log_file="$(find "$run_workdir/.bash-tape-deck" -maxdepth 1 -type f -name '*.jsonl' | head -n 1)"
[ -n "$log_file" ] || fail "Expected a tape JSONL log file"
printf -- '-> log file: %s\n' "$log_file"

case "$(basename "$log_file")" in
  tests-fixtures-docker-sample--*.jsonl) ;;
  *)
    fail "Unexpected tape log file name: $(basename "$log_file")"
    ;;
esac

assert_contains "$log_file" '"event":"back"'
assert_contains "$log_file" '"steps_file":"steps.1.sh"'
assert_contains "$log_file" '"event":"ejected"'
printf -- '-> log contains back, steps_file, and ejected events\n'

printf 'PASS: docker wrapper integration test\n'
