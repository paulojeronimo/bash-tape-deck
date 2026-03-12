#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
workspace_root="$(mktemp -d "$repo_root/build/test-cassette-art-animate.XXXXXX")"
stdout_file="$workspace_root/stdout.txt"
stderr_file="$workspace_root/stderr.txt"
static_stdout_file="$workspace_root/static-stdout.txt"
static_stderr_file="$workspace_root/static-stderr.txt"
top_stdout_file="$workspace_root/top-stdout.txt"
top_stderr_file="$workspace_root/top-stderr.txt"
bottom_stdout_file="$workspace_root/bottom-stdout.txt"
bottom_stderr_file="$workspace_root/bottom-stderr.txt"
metal_stdout_file="$workspace_root/metal-stdout.txt"
metal_stderr_file="$workspace_root/metal-stderr.txt"
project_stdout_file="$workspace_root/project-stdout.txt"
project_stderr_file="$workspace_root/project-stderr.txt"
subtitle_stdout_file="$workspace_root/subtitle-stdout.txt"
subtitle_stderr_file="$workspace_root/subtitle-stderr.txt"
invalid_stdout_file="$workspace_root/invalid-stdout.txt"
invalid_stderr_file="$workspace_root/invalid-stderr.txt"
invalid_center_stdout_file="$workspace_root/invalid-center-stdout.txt"
invalid_center_stderr_file="$workspace_root/invalid-center-stderr.txt"

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

assert_not_contains() {
  local path="$1"
  local pattern="$2"
  if grep -F -- "$pattern" "$path" >/dev/null; then
    fail "Did not expect '$pattern' in $path"
  fi
}

cd "$repo_root"

TERM=xterm COLUMNS=80 LINES=24 CASSETTE_ANIMATION_DELAY=0 \
  ./.private/cassette-art.sh --clear-screen --center --animate 2 --width 48 --label TEST >"$stdout_file" 2>"$stderr_file"

assert_contains "$stdout_file" $'\033[H\033[2J'
assert_contains "$stdout_file" $'\033[?25l'
assert_contains "$stdout_file" $'\033[s'
assert_contains "$stdout_file" $'\033[u'
assert_contains "$stdout_file" $'\033[?25h'
assert_contains "$stdout_file" '                /'
assert_contains "$stdout_file" '( | )'
assert_not_contains "$stderr_file" '# width='

if ./.private/cassette-art.sh --animate 0 --width 48 --label TEST >"$invalid_stdout_file" 2>"$invalid_stderr_file"; then
  fail "Expected --animate 0 to fail"
fi
assert_contains "$invalid_stderr_file" "--animate repetition count must be >= 1 or 'infinite'"

TERM=xterm COLUMNS=80 LINES=24 \
  ./.private/cassette-art.sh --clear-screen --center --width 88 --label TEST >"$static_stdout_file" 2>"$static_stderr_file"

assert_contains "$static_stdout_file" $'\033[H\033[2J'
assert_contains "$static_stdout_file" "/______________________________________________________________________________________\\"
assert_contains "$static_stderr_file" '# width=88'
assert_contains "$static_stdout_file" 'github.com/paulojeronimo/bash-tape-deck'

TERM=xterm COLUMNS=80 LINES=24 \
  ./.private/cassette-art.sh --center top --width 48 --label TEST >"$top_stdout_file" 2>"$top_stderr_file"
TERM=xterm COLUMNS=80 LINES=24 \
  ./.private/cassette-art.sh --center bottom --width 48 --label TEST >"$bottom_stdout_file" 2>"$bottom_stderr_file"
TERM=xterm COLUMNS=80 LINES=24 CASSETTE_ANIMATION_DELAY=0 \
  ./.private/cassette-art.sh --title-preset future-metal --animate 1 --width 48 --label TEST >"$metal_stdout_file" 2>"$metal_stderr_file"
TERM=xterm COLUMNS=80 LINES=24 \
  ./.private/cassette-art.sh --width 88 --project-title "My Tape" --project-url "example.com/my-tape" >"$project_stdout_file" 2>"$project_stderr_file"
TERM=xterm COLUMNS=80 LINES=24 CASSETTE_ANIMATION_DELAY=0 \
  ./.private/cassette-art.sh --animate 1 --width 48 --label TEST --subtitle SUB >"$subtitle_stdout_file" 2>"$subtitle_stderr_file"

first_top_line="$(grep -m1 '/' "$top_stdout_file")"
first_bottom_line_number="$(grep -n -m1 '/' "$bottom_stdout_file" | cut -d: -f1)"
[ "$first_top_line" = "                /______________________________________________\\" ] || fail "Expected top-centered output to start at top"
[ "$first_bottom_line_number" -gt 1 ] || fail "Expected bottom-centered output to include top padding"
assert_contains "$metal_stdout_file" $'\033[0;1;34;94m'
assert_not_contains "$metal_stderr_file" '# width='
[ "$(grep -c 'example.com/my-tape' "$project_stdout_file")" -eq 1 ] || fail "Expected custom project URL"
[ "$(grep -c '# width=88' "$project_stderr_file")" -eq 1 ] || fail "Expected width marker for custom project rendering"
[ "$(grep -c 'SUB' "$subtitle_stdout_file")" -ge 1 ] || fail "Expected subtitle to be rendered"
assert_not_contains "$subtitle_stderr_file" '# width='

if ./.private/cassette-art.sh --center middle --width 48 --label TEST >"$invalid_center_stdout_file" 2>"$invalid_center_stderr_file"; then
  fail "Expected invalid --center value to fail"
fi
assert_contains "$invalid_center_stderr_file" "--center must be one of: all, top, bottom"

printf 'PASS: cassette-art animate test\n'
