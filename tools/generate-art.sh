#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

cd "$repo_root"

# shellcheck disable=SC1091
source "$repo_root/functions.sh"

label=${label:-'Your Bash Tape About XPTO'}
subtitle=${subtitle:-'Steps 1/3'}
github=${github:-'your-name/bash-tape-xpto'}

terminal_rows=${terminal_rows:-25}
animation_delay=${animation_delay:-0.02}
cassette_width=${cassette_width:-}
cassette_width_padding=${cassette_width_padding:-8}
png_frame_time=${png_frame_time:-0.5}
original_rows=""
original_cols=""
resize_mode=""

require_command() {
  local command_name="$1"
  local reason="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "$command_name" >&2
    printf 'Needed for: %s\n' "$reason" >&2
    exit 1
  fi
}

strip_ansi() {
  sed -E $'s/\x1B\\[[0-9;]*m//g'
}

visible_max_width() {
  local max_width=0
  local line plain

  while IFS= read -r line; do
    plain="$(printf '%s' "$line" | strip_ansi)"
    if [ "${#plain}" -gt "$max_width" ]; then
      max_width="${#plain}"
    fi
  done

  printf '%s\n' "$max_width"
}

resolve_cassette_width() {
  local min_width=48
  local max_width="$original_cols"
  local low high mid best_width
  local rendered_output
  local resolved_width

  if ! [[ "$max_width" =~ ^[0-9]+$ ]] || [ "$max_width" -lt "$min_width" ]; then
    max_width=120
  fi

  low="$min_width"
  high="$max_width"
  best_width="$max_width"

  while [ "$low" -le "$high" ]; do
    mid=$(((low + high) / 2))
    rendered_output="$(
      ./.private/cassette-art.sh \
        --width "$mid" \
        --label "$label" \
        --subtitle "$subtitle" \
        --github "$github" \
        --title-preset future-metal \
        2>&1
    )"

    if ! printf '%s\n' "$rendered_output" | grep -F '...' >/dev/null; then
      best_width="$mid"
      high=$((mid - 1))
    else
      low=$((mid + 1))
    fi
  done

  resolved_width=$((best_width + cassette_width_padding))
  if [ "$resolved_width" -gt "$max_width" ]; then
    resolved_width="$max_width"
  fi

  printf '%s\n' "$resolved_width"
}

capture_terminal_size() {
  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    original_rows="$(tmux display-message -p '#{pane_height}' 2>/dev/null || true)"
    original_cols="$(tmux display-message -p '#{pane_width}' 2>/dev/null || true)"
    resize_mode="tmux"
    return
  fi

  if [ -t 1 ]; then
    original_rows="$(terminal_lines)"
    original_cols="$(terminal_cols)"
    resize_mode="terminal"
  fi
}

resize_terminal() {
  capture_terminal_size

  if [ "$resize_mode" = "tmux" ]; then
    tmux resize-pane -y "$terminal_rows"
    return
  fi

  if [ "$resize_mode" = "terminal" ]; then
    stty rows "$terminal_rows" cols "$original_cols" < /dev/tty || true
  fi
}

restore_terminal() {
  if [ -z "$resize_mode" ] || [ -z "$original_rows" ] || [ -z "$original_cols" ]; then
    return
  fi

  if [ "$resize_mode" = "tmux" ]; then
    tmux resize-pane -y "$original_rows" >/dev/null 2>&1 || true
    return
  fi

  if [ "$resize_mode" = "terminal" ]; then
    stty rows "$original_rows" cols "$original_cols" < /dev/tty || true
  fi
}

trap restore_terminal EXIT

mkdir -p build images

require_command toilet "rendering the cassette title art"
require_command asciinema "recording the animated cassette session"
require_command agg "rendering images/art.gif from the asciinema cast"
require_command ffmpeg "extracting images/art.png from a rendered GIF frame"

resize_terminal

if [ -z "$cassette_width" ]; then
  cassette_width="$(resolve_cassette_width)"
fi

./.private/cassette-art.sh \
  --width "$cassette_width" \
  --label "$label" \
  --subtitle "$subtitle" \
  --github "$github" \
  --center \
  --title-preset future-metal \
  2>&1 |
  grep -A 22 '# width=' |
  sed -n '2,$p' |
  tee build/art.txt

asciinema \
  rec --overwrite -c \
  "stty rows $terminal_rows cols $original_cols && \
   CASSETTE_ANIMATION_DELAY=$animation_delay \
   ./.private/cassette-art.sh \
    --width '$cassette_width' \
    --label '$label' \
    --subtitle '$subtitle' \
    --github '$github' \
    --center \
    --animate 1 \
    --title-preset future-metal" \
  build/cassette-art.cast

agg --theme asciinema build/cassette-art.cast images/art.gif

ffmpeg \
  -y \
  -ss "$png_frame_time" \
  -i images/art.gif \
  -frames:v 1 \
  images/art.png
