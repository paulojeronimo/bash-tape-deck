#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
workspace_root="$(mktemp -d "$repo_root/build/test-play-screen-animation.XXXXXX")"
intro_stdout_file="$workspace_root/intro-stdout.txt"
done_stdout_file="$workspace_root/done-stdout.txt"
frame_stdout_file="$workspace_root/frame-stdout.txt"
center_stdout_file="$workspace_root/center-stdout.txt"
diff_stdout_file="$workspace_root/diff-stdout.txt"

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

TERM=xterm COLUMNS=80 LINES=24 CASSETTE_ANIMATION_DELAY=0 bash -lc '
  source functions.sh
  cassette_art_main --width 80 --label "Intro Tape" --subtitle "Steps 3" --title-preset future-metal --github "pj/example" --animate-frame 3
' >"$frame_stdout_file"

assert_contains "$frame_stdout_file" 'Steps 3'
assert_contains "$frame_stdout_file" 'github.com/pj/example'
assert_contains "$frame_stdout_file" '( \ )'

printf 's' | TERM=xterm COLUMNS=80 LINES=24 CASSETTE_ANIMATION_DELAY=0 bash -lc '
  source functions.sh
  show_intro_screen action 1 3 "Intro Tape" "Steps 3" future-metal "pj/example" "Intro body"
  printf "\naction=%s\n" "$action"
' >"$intro_stdout_file"

assert_contains "$intro_stdout_file" 'github.com/pj/example'
assert_contains "$intro_stdout_file" 'Steps 3'
assert_contains "$intro_stdout_file" 'Intro body'
assert_contains "$intro_stdout_file" 'action=quit'

printf 'b' | TERM=xterm COLUMNS=80 LINES=24 CASSETTE_ANIMATION_DELAY=0 bash -lc '
  source functions.sh
  show_done_screen action 1 3 2 "Outro Tape" "pj/example" future-metal
  printf "\naction=%s\n" "$action"
' >"$done_stdout_file"

assert_contains "$done_stdout_file" 'Steps 3'
assert_contains "$done_stdout_file" 'Steps executed: 2'
assert_contains "$done_stdout_file" 'action=back'

TERM=xterm COLUMNS=20 bash -lc '
  source functions.sh
  center_line_text $'\''\033[31mDone!\033[0m'\''
' >"$center_stdout_file"

assert_contains "$center_stdout_file" '       '
assert_contains "$center_stdout_file" $'\033[31mDone!\033[0m'

TERM=xterm bash -lc '
  source functions.sh
  prev=()
  curr=($'\''\033[31mRED'\'' "NEXT")
  render_screen_diff prev curr 2
' >"$diff_stdout_file"

assert_contains "$diff_stdout_file" $'\033[31mRED\033[0m'

printf 'PASS: play screen animation test\n'
