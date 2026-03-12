#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
mkdir -p "$repo_root/build"
workspace_root="$(mktemp -d "$repo_root/build/test-public-commit-helpers.XXXXXX")"
help_stdout_file="$workspace_root/help-stdout.txt"
help_stderr_file="$workspace_root/help-stderr.txt"
missing_stdout_file="$workspace_root/missing-stdout.txt"
missing_stderr_file="$workspace_root/missing-stderr.txt"

cleanup() {
  rm -rf "$workspace_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local pattern="$2"
  grep -F -- "$pattern" "$path" >/dev/null || fail "Expected '$pattern' in $path"
}

cd "$repo_root"

bash .private/common/generate-public-commit-notes.sh --help >"$help_stdout_file" 2>"$help_stderr_file"
assert_contains "$help_stdout_file" "generate-public-commit-notes.sh [output-file]"

if bash .private/common/do-public-commit.sh >"$missing_stdout_file" 2>"$missing_stderr_file"; then
  fail "Expected do-public-commit.sh without notes file to fail"
fi
assert_contains "$missing_stderr_file" "Error: commit notes file not provided."

printf 'PASS: public commit helpers test\n'
