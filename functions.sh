#!/usr/bin/env bash

json_escape() {
  local value="${1:-}"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

bash_tape_id() {
  local steps_dir="$1"
  local repo_root=""
  local rel_path=""
  local tape_name
  local tape_hash

  if [ -d "$steps_dir" ]; then
    repo_root="$(git -C "$steps_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  fi

  if [ -n "$repo_root" ] && [[ "$steps_dir" == "$repo_root"/* ]]; then
    rel_path="${steps_dir#"$repo_root"/}"
  else
    rel_path="$steps_dir"
  fi

  tape_name="$rel_path"
  tape_name="${tape_name//\//-}"
  tape_name="${tape_name// /-}"
  tape_name="$(printf '%s' "$tape_name" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/-+/-/g; s/^-//; s/-$//')"
  tape_hash="$(printf '%s' "$steps_dir" | cksum | awk '{print $1}')"
  printf '%s--%s' "$tape_name" "$tape_hash"
}

bash_tape_log_file() {
  local steps_dir="$1"
  local run_workdir="$2"

  printf '%s/.bash-tape/%s.jsonl' \
    "$run_workdir" "$(bash_tape_id "$steps_dir")"
}

bash_tape_state_dir() {
  local steps_dir="$1"
  local run_workdir="$2"

  printf '%s/.bash-tape/%s' \
    "$run_workdir" "$(bash_tape_id "$steps_dir")"
}

log_bash_tape_event() {
  local log_file="$1"
  local event_name="$2"
  shift 2

  local timestamp
  local json_line
  local key
  local value

  mkdir -p "$(dirname "$log_file")"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  json_line="{\"ts\":\"$(json_escape "$timestamp")\",\"event\":\"$(json_escape "$event_name")\""

  while [ "$#" -gt 1 ]; do
    key="$1"
    value="$2"
    shift 2
    json_line+=",\"$(json_escape "$key")\":\"$(json_escape "$value")\""
  done

  json_line+="}"
  printf '%s\n' "$json_line" >> "$log_file"
}

bash_tape_detect_state() {
  local log_file="$1"
  local last_event

  if [ ! -f "$log_file" ]; then
    printf '%s\n' "not-started"
    return
  fi

  last_event="$(
    sed -n 's/.*"event":"\([^"]*\)".*/\1/p' "$log_file" | tail -n 1
  )"

  case "$last_event" in
    stopped)
      printf '%s\n' "stopped"
      ;;
    rewound)
      printf '%s\n' "rewound"
      ;;
    ejected)
      printf '%s\n' "ejected"
      ;;
    "")
      printf '%s\n' "not-started"
      ;;
    *)
      printf '%s\n' "running"
      ;;
  esac
}

terminal_cols() {
  local cols
  cols="$(tput cols 2>/dev/null || echo 80)"
  if ! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -le 0 ]; then
    cols=80
  fi
  echo "$cols"
}

terminal_lines() {
  local lines
  lines="$(tput lines 2>/dev/null || echo 24)"
  if ! [[ "$lines" =~ ^[0-9]+$ ]] || [ "$lines" -le 0 ]; then
    lines=24
  fi
  echo "$lines"
}

print_full_width_rule() {
  local cols

  cols="$(terminal_cols)"
  printf '%*s\n' "$cols" '' | tr ' ' '-'
}

print_centered() {
  local text="$1"
  local cols
  local pad=0

  cols="$(terminal_cols)"
  if [ "${#text}" -lt "$cols" ]; then
    pad=$(((cols - ${#text}) / 2))
  fi
  printf '%*s%s\n' "$pad" '' "$text"
}

print_centered_bold() {
  local text="$1"
  local cols
  local pad=0

  cols="$(terminal_cols)"
  if [ "${#text}" -lt "$cols" ]; then
    pad=$(((cols - ${#text}) / 2))
  fi
  printf '%*s\033[1m%s\033[0m\n' "$pad" '' "$text"
}

strip_ansi_codes() {
  sed -E $'s/\x1B\\[[0-9;]*m//g'
}

print_block_centered_visible() {
  local block="$1"
  local block_width="${2:-}"
  local cols pad

  cols="$(terminal_cols)"
  if [ -z "$block_width" ]; then
    block_width="$cols"
  fi
  if ! [[ "$block_width" =~ ^[0-9]+$ ]] || [ "$block_width" -le 0 ]; then
    block_width="$cols"
  fi

  pad=0
  if [ "$block_width" -lt "$cols" ]; then
    pad=$(((cols - block_width) / 2))
  fi

  while IFS= read -r line; do
    printf '%*s%s\n' "$pad" '' "$line"
  done <<< "$block"
}

print_figlet_centered() {
  local text="$1"
  local cols

  cols="$(terminal_cols)"
  figlet "$text" | while IFS= read -r fig_line; do
    local pad=0
    if [ "${#fig_line}" -lt "$cols" ]; then
      pad=$(((cols - ${#fig_line}) / 2))
    fi
    printf '%*s%s\n' "$pad" '' "$fig_line"
  done
}

navigation_context() {
  local run_workdir
  local context

  run_workdir="${BASH_TAPE_RUN_WORKDIR:-$PWD}"
  context="wd: $run_workdir"
  if [ "${BASH_TAPE_IN_DOCKER:-0}" = "1" ]; then
    context="$context | docker"
  fi
  printf '[%s]' "$context"
}

render_metadata() {
  local content="$1"
  if [ -z "$content" ]; then
    return
  fi
  printf '%s\n' "$content" | batcat -pP -l markdown --color always --decorations always
}

render_tape_screen() {
  local label="$1"
  local subtitle="${2:-}"
  local title_preset="${3:-future-metal}"
  local github_repo="${4:-}"
  local animate="${5:-0}"
  local center_mode="${6:-top}"
  local clear_screen="${7:-1}"
  local render_cols
  local -a render_cmd

  render_cols="$(terminal_cols)"
  if [ "$render_cols" -lt 40 ]; then
    render_cols=40
  fi
  if [ "$render_cols" -gt 120 ]; then
    render_cols=120
  fi

  render_cmd=(
    cassette_art_main
    --width "$render_cols"
    --label "$label"
    --subtitle "$subtitle"
    --title-preset "$title_preset"
  )

  if [ -n "$github_repo" ]; then
    render_cmd+=(--github "$github_repo")
  fi
  if [ "$clear_screen" = "1" ]; then
    render_cmd+=(--clear-screen)
  fi
  if [ -n "$center_mode" ]; then
    render_cmd+=(--center "$center_mode")
  fi
  if [ "$animate" != "0" ] && [ -n "$animate" ]; then
    render_cmd+=(--animate "$animate")
  fi

  "${render_cmd[@]}"
}

render_tape_frame() {
  local label="$1"
  local subtitle="${2:-}"
  local title_preset="${3:-future-metal}"
  local github_repo="${4:-}"
  local frame_index="${5:-0}"
  local center_mode="${6:-top}"
  local render_cols
  local -a render_cmd

  render_cols="$(terminal_cols)"
  if [ "$render_cols" -lt 40 ]; then
    render_cols=40
  fi
  if [ "$render_cols" -gt 120 ]; then
    render_cols=120
  fi

  render_cmd=(
    cassette_art_main
    --width "$render_cols"
    --label "$label"
    --subtitle "$subtitle"
    --title-preset "$title_preset"
    --animate-frame "$frame_index"
    --center "$center_mode"
  )

  if [ -n "$github_repo" ]; then
    render_cmd+=(--github "$github_repo")
  fi

  "${render_cmd[@]}"
}

center_line_text() {
  local text="$1"
  local cols pad=0 visible_text

  cols="$(terminal_cols)"
  visible_text="$(printf '%s' "$text" | strip_ansi_codes)"
  if [ "${#visible_text}" -lt "$cols" ]; then
    pad=$(((cols - ${#visible_text}) / 2))
  fi
  printf '%*s%s\n' "$pad" '' "$text"
}

print_block_centered_by_visible_width() {
  local block="$1"
  local max_width=0
  local line visible_line

  while IFS= read -r line; do
    visible_line="$(printf '%s' "$line" | strip_ansi_codes)"
    if [ "${#visible_line}" -gt "$max_width" ]; then
      max_width="${#visible_line}"
    fi
  done <<< "$block"

  print_block_centered_visible "$block" "$max_width"
}

render_done_block() {
  local done_text="$1"
  local summary="$2"

  printf '\n\n'
  print_block_centered_by_visible_width "$done_text"
  printf '\n\n'
  center_line_text "$summary"
}

build_done_body_block() {
  local done_text="$1"
  local summary="$2"
  render_done_block "$done_text" "$summary"
}

build_done_prefix_block() {
  local done_text="$1"
  local tape_block="$2"
  local lines tape_lines done_lines summary_lines total_height top_pad i

  lines="$(terminal_lines)"
  tape_lines="$(printf '%s\n' "$tape_block" | wc -l)"
  done_lines="$(printf '%s\n' "$done_text" | wc -l)"
  summary_lines=1
  total_height=$((tape_lines + 2 + done_lines + 2 + summary_lines))
  top_pad=$(((lines - total_height) / 2))
  if [ "$top_pad" -lt 0 ]; then
    top_pad=0
  fi

  for ((i = 0; i < top_pad; i++)); do
    printf '\n'
  done
}

build_animated_screen_block() {
  local label="$1"
  local subtitle="${2:-}"
  local title_preset="${3:-future-metal}"
  local github_repo="${4:-}"
  local frame_index="${5:-0}"
  local prefix_block="${6:-}"
  local body_block="${7:-}"
  local tape_block

  printf '%s' "$prefix_block"
  tape_block="$(render_tape_frame "$label" "$subtitle" "$title_preset" "$github_repo" "$frame_index" top)"
  printf '%s' "$tape_block"
  printf '%s' "$body_block"
}

render_screen_diff() {
  local -n previous_lines_ref="$1"
  local -n current_lines_ref="$2"
  local row_count="$3"
  local row previous_line current_line

  for ((row = 0; row < row_count; row++)); do
    previous_line="${previous_lines_ref[$row]:-__BASH_TAPE_EMPTY__}"
    current_line="${current_lines_ref[$row]:-}"
    if [ "$previous_line" != "$current_line" ]; then
      tput cup "$row" 0
      tput el
      printf '%s\033[0m' "$current_line"
    fi
  done
}

screen_prompt_loop() {
  local result_var="$1"
  local prompt="$2"
  local accept_enter="${3:-0}"
  local allow_back="${4:-0}"
  local allow_eject="${5:-0}"
  local label="$6"
  local subtitle="$7"
  local title_preset="$8"
  local github_repo="$9"
  local prefix_block="${10:-}"
  local body_block="${11:-}"
  local frame_index=0
  local choice=""
  local cols lines pad
  local delay="${CASSETTE_ANIMATION_DELAY:-0.05}"
  local screen_block
  local row_count
  # shellcheck disable=SC2034
  local -a previous_lines=()
  local -a current_lines=()

  if ! [ -t 0 ] || ! [ -t 1 ]; then
    printf '%s' "$prefix_block"
    render_tape_screen "$label" "$subtitle" "$title_preset" "$github_repo" 0 top 1
    printf '%s' "$body_block"
    IFS= read -r -s -n 1 -p "$prompt " choice || true
  else
    printf '\033[?25l'
    screen_block="$(build_animated_screen_block "$label" "$subtitle" "$title_preset" "$github_repo" "$frame_index" "$prefix_block" "$body_block")"
    printf '\033[H\033[2J%s' "$screen_block"
    mapfile -t previous_lines <<< "$screen_block"

    while true; do
      cols="$(terminal_cols)"
      lines="$(terminal_lines)"
      if [ "${#prompt}" -lt "$cols" ]; then
        pad=$(((cols - ${#prompt}) / 2))
      else
        pad=0
      fi
      tput cup $((lines - 1)) 0
      tput el
      printf '%*s%s' "$pad" '' "$prompt" > /dev/tty
      if IFS= read -r -s -n 1 -t "$delay" choice < /dev/tty; then
        break
      fi
      frame_index=$((frame_index + 1))

      screen_block="$(build_animated_screen_block "$label" "$subtitle" "$title_preset" "$github_repo" "$frame_index" "$prefix_block" "$body_block")"
      mapfile -t current_lines <<< "$screen_block"
      row_count="${#current_lines[@]}"
      if [ "${#previous_lines[@]}" -gt "$row_count" ]; then
        row_count="${#previous_lines[@]}"
      fi
      render_screen_diff previous_lines current_lines "$row_count"
      # shellcheck disable=SC2034
      previous_lines=("${current_lines[@]}")
    done
    tput cup $((lines - 1)) 0
    tput el
    printf '\033[?25h'
  fi

  case "$choice" in
    ""|$'\n'|n|N)
      if [ "$accept_enter" = "1" ]; then
        printf -v "$result_var" '%s' "next"
        return
      fi
      ;;
    e|E)
      if [ "$allow_eject" = "1" ]; then
        printf -v "$result_var" '%s' "eject"
        return
      fi
      ;;
    b|B)
      if [ "$allow_back" = "1" ]; then
        printf -v "$result_var" '%s' "back"
        return
      fi
      ;;
    s|S|q|Q)
      printf -v "$result_var" '%s' "quit"
      return
      ;;
  esac

  printf -v "$result_var" '%s' ""
}

show_done_screen() {
  local result_var="$1"
  local allow_eject="${2:-1}"
  local steps_number="${3:-1}"
  local steps_executed="${4:-0}"
  local global_title="${5:-Bash Tape}"
  local global_github="${6:-paulojeronimo/bash-tape}"
  local title_preset="${7:-future-metal}"
  local prompt
  local done_text
  local summary="Steps executed: $steps_executed"
  local tape_block
  local prefix_block
  local body_block

  prompt="e eject  |  b back  |  s stop   $(navigation_context)"

  if command -v toilet >/dev/null 2>&1; then
    done_text="$(toilet -f smblock "Done!" 2>/dev/null || true)"
  fi
  if [ -z "${done_text:-}" ]; then
    done_text="$(figlet "Done!")"
  fi

  tape_block="$(render_tape_frame "$global_title" "Steps $steps_number" "$title_preset" "$global_github" 0 top)"
  prefix_block="$(build_done_prefix_block "$done_text" "$tape_block")"
  body_block="$(build_done_body_block "$done_text" "$summary")"

  while :; do
    screen_prompt_loop \
      "$result_var" \
      "$prompt" \
      0 \
      1 \
      "$allow_eject" \
      "$global_title" \
      "Steps $steps_number" \
      "$title_preset" \
      "$global_github" \
      "$prefix_block" \
      "$body_block"
    [ -n "${!result_var}" ] && return
  done
}

show_intro_screen() {
  local result_var="$1"
  local allow_eject="${2:-1}"
  local steps_number="${3:-1}"
  local global_title="${4:-}"
  local tutorial_subtitle="${5:-}"
  local title_preset="${6:-future-metal}"
  local global_github="${7:-}"
  local intro_content="${8:-}"
  local prompt
  local body_block=""

  prompt="[ENTER]/n next  |  e eject  |  s stop   $(navigation_context)"

  if [ -n "$intro_content" ]; then
    body_block=$'\n'
    body_block+="$(render_metadata "$intro_content")"
  fi

  if [ -n "$global_title" ]; then
    while :; do
      screen_prompt_loop \
        "$result_var" \
        "$prompt" \
        1 \
        0 \
        "$allow_eject" \
      "$global_title" \
      "$tutorial_subtitle" \
      "$title_preset" \
      "$global_github" \
      "" \
      "$body_block"
      [ -n "${!result_var}" ] && return
    done
  else
    clear
    print_figlet_centered "Steps $steps_number"
    echo
    render_metadata "$intro_content"
    prompt_intro_navigation "$result_var" "$allow_eject"
  fi
}
preview_heredoc_command() {
  local cmd="$1"
  local first_line
  local target_path delim body language
  local regex="^cat[[:space:]]+>>?[[:space:]]*([^[:space:]]+)[[:space:]]+<<'([A-Za-z_][A-Za-z0-9_]*)'$"

  first_line="${cmd%%$'\n'*}"
  if [[ ! "$first_line" =~ $regex ]]; then
    return
  fi

  target_path="${BASH_REMATCH[1]}"
  delim="${BASH_REMATCH[2]}"

  if [[ "$cmd" != *$'\n'* ]]; then
    return
  fi
  body="${cmd#*$'\n'}"
  body="${body%$'\n'"$delim"}"

  case "$target_path" in
    *.sh) language="bash" ;;
    *.md) language="markdown" ;;
    *.yaml|*.yml) language="yaml" ;;
    *.json) language="json" ;;
    *) language="txt" ;;
  esac

  if ! printf '%s\n' "$body" | batcat -pP -l "$language" --color always --decorations always; then
    printf '%s\n' "$body"
  fi
  printf '%s\n' "$delim"
}

display_command() {
  local cmd="$1"
  local first_line
  local regex="^cat[[:space:]]+>>?[[:space:]]*([^[:space:]]+)[[:space:]]+<<'([A-Za-z_][A-Za-z0-9_]*)'$"

  first_line="${cmd%%$'\n'*}"
  if [[ "$cmd" == *$'\n'* ]] && [[ "$first_line" =~ $regex ]]; then
    echo "\$ $first_line"
    return
  fi

  echo "\$ $cmd"
}

pause() {
  local prompt='Press <ENTER> to continue'
  local cols lines pad=0

  cols="$(terminal_cols)"
  lines="$(terminal_lines)"
  if [ "${#prompt}" -lt "$cols" ]; then
    pad=$(((cols - ${#prompt}) / 2))
  fi

  if [ -t 0 ] && [ -t 1 ]; then
    tput cup $((lines - 1)) 0
    tput el
    printf '%*s%s' "$pad" '' "$prompt"
    read -r
  else
    echo
    read -r -p "$prompt"
  fi
}

prompt_step_navigation() {
  local current_step="$1"
  local total_steps="$2"
  local result_var="$3"
  local allow_intro_back="${4:-0}"
  local allow_eject="${5:-0}"
  local prompt
  local choice
  local cols lines pad=0
  local context

  flush_tty_input() {
    while IFS= read -r -s -n 1 -t 0.01 _ < /dev/tty; do
      :
    done
  }

  context="$(navigation_context)"
  if [ "$allow_intro_back" = "1" ]; then
    if [ "$allow_eject" = "1" ]; then
      prompt="[ENTER]/n next  |  b intro  |  e eject  |  s stop   (${current_step}/${total_steps})   $context"
    else
      prompt="[ENTER]/n next  |  b intro  |  e eject  |  s stop   (${current_step}/${total_steps})   $context"
    fi
  else
    if [ "$allow_eject" = "1" ]; then
      prompt="[ENTER]/n next  |  b back  |  e eject  |  s stop   (${current_step}/${total_steps})   $context"
    else
      prompt="[ENTER]/n next  |  b back  |  e eject  |  s stop   (${current_step}/${total_steps})   $context"
    fi
  fi

  while true; do
    if [ -t 0 ] && [ -t 1 ]; then
      flush_tty_input
      cols="$(terminal_cols)"
      lines="$(terminal_lines)"
      if [ "${#prompt}" -lt "$cols" ]; then
        pad=$(((cols - ${#prompt}) / 2))
      else
        pad=0
      fi
      tput cup $((lines - 1)) 0
      tput el
      printf '%*s%s' "$pad" '' "$prompt" > /dev/tty
      IFS= read -r -s -n 1 choice < /dev/tty || true
    else
      IFS= read -r -s -n 1 -p "$prompt " choice || true
    fi

    case "$choice" in
      ""|$'\n'|n|N)
        printf -v "$result_var" '%s' "next"
        return
        ;;
      e|E)
        if [ "$allow_eject" = "1" ]; then
          printf -v "$result_var" '%s' "eject"
          return
        fi
        ;;
      b|B)
        if [ "$allow_intro_back" = "1" ]; then
          printf -v "$result_var" '%s' "intro"
          return
        fi
        if [ "$current_step" -gt 1 ]; then
          printf -v "$result_var" '%s' "back"
          return
        fi
        ;;
      s|S|q|Q)
        printf -v "$result_var" '%s' "quit"
        return
        ;;
    esac
  done
}

prompt_intro_navigation() {
  local result_var="$1"
  local allow_eject="${2:-1}"
  local prompt
  local choice
  local cols lines pad=0

  flush_tty_input() {
    while IFS= read -r -s -n 1 -t 0.01 _ < /dev/tty; do
      :
    done
  }

  prompt="[ENTER]/n next  |  e eject  |  s stop   $(navigation_context)"

  while true; do
    if [ -t 0 ] && [ -t 1 ]; then
      flush_tty_input
      cols="$(terminal_cols)"
      lines="$(terminal_lines)"
      if [ "${#prompt}" -lt "$cols" ]; then
        pad=$(((cols - ${#prompt}) / 2))
      else
        pad=0
      fi
      tput cup $((lines - 1)) 0
      tput el
      printf '%*s%s' "$pad" '' "$prompt" > /dev/tty
      IFS= read -r -s -n 1 choice < /dev/tty || true
    else
      IFS= read -r -s -n 1 -p "$prompt " choice || true
    fi

    case "$choice" in
      ""|$'\n'|n|N)
        printf -v "$result_var" '%s' "next"
        return
        ;;
      e|E)
        if [ "$allow_eject" = "1" ]; then
          printf -v "$result_var" '%s' "eject"
          return
        fi
        ;;
      s|S|q|Q)
        printf -v "$result_var" '%s' "quit"
        return
        ;;
    esac
  done
}

show_unejected_warning() {
  local has_remaining_steps="${1:-0}"

  clear
  print_centered_bold "Tape Not Ejected"
  echo
  print_centered "steps.end.sh was not executed."
  if [ "$has_remaining_steps" = "1" ]; then
    print_centered "There are still steps remaining in this tape."
  fi
  print_centered "The environment may remain inconsistent until you eject the tape."
  echo
  pause
}

show_ejecting_message() {
  local has_end_hook="${1:-0}"

  clear
  print_centered_bold "Ejecting Tape"
  echo
  if [ "$has_end_hook" = "1" ]; then
    print_centered "steps.end.sh will be executed now."
    print_centered "This should restore the environment and finish tape cleanup."
  else
    print_centered "No steps.end.sh hook was found for this tape."
    print_centered "The tape will be ejected without additional cleanup actions."
  fi
  echo
  pause
}

run_step() {
  local step_number="$1"
  local message="$2"
  local metadata_position="$3"
  local metadata_content="$4"
  local i=0
  shift 4

  clear
  print_centered_bold "$step_number. $message"
  echo

  if [ "$metadata_position" = "before" ] && [ -n "$metadata_content" ]; then
    print_full_width_rule
    render_metadata "$metadata_content"
    print_full_width_rule
    echo
  fi

  for cmd in "$@"; do
    if [ "$i" -gt 0 ]; then
      echo
    fi
    display_command "$cmd"
    preview_heredoc_command "$cmd"
    eval "$cmd"
    i=$((i + 1))
  done

  if [ "$metadata_position" = "after" ] && [ -n "$metadata_content" ]; then
    echo
    print_full_width_rule
    render_metadata "$metadata_content"
    print_full_width_rule
  fi
}

cassette_art_main() {
  local label="BASH TAPE"
  local subtitle=""
  local github_repo=""
  local project_title="Bash Tape Deck"
  local project_url="github.com/paulojeronimo/bash-tape-deck"
  local title_preset="future"
  local title_font=""
  local animate=0
  local animate_repeat="1"
  local animate_frame_mode=0
  local animate_frame_index=0
  local animation_delay="${CASSETTE_ANIMATION_DELAY:-0.05}"
  local clear_screen=0
  local center_mode=""
  local min_width=48
  local max_width=""
  local step=8
  local single_width=""
  local -a title_filters=()
  local -A preset_font=(
    ["future"]="future"
    ["future-border"]="future"
    ["future-metal"]="future"
    ["future-border-metal"]="future"
    ["future-gay"]="future"
    ["future-border-gay"]="future"
  )
  local -A preset_filters=(
    ["future"]=""
    ["future-border"]="border"
    ["future-metal"]="metal"
    ["future-border-metal"]="border metal"
    ["future-gay"]="gay"
    ["future-border-gay"]="border gay"
  )

  cassette_usage() {
    cat <<'EOF'
Usage:
  cassette-art.sh [options]

Options:
  --label <text>              Top label text.
  --subtitle <text>           Subtitle rendered below the title.
  --github <owner/repo>       Project repository shown below title.
  --project-title <text>      Project title shown in the bottom section.
  --project-url <text>        Project URL shown below the bottom project title.
  --title-preset <preset>     future | future-border | future-metal |
                              future-border-metal | future-gay | future-border-gay
  --toilet-preset <preset>    Alias for --title-preset.
  --title-font <font>         Override title font.
  --toilet-font <font>        Alias for --title-font.
  --title-filter <filter>     Extra title filter (repeatable).
  --toilet-filter <filter>    Alias for --title-filter.
  --animate [n|infinite]      Animate the rendered title. Default: 1 repetition.
  --animate-frame <n>         Render a single animation frame.
  --clear-screen              Clear the full screen before rendering.
  --center [all|top|bottom]   Center horizontally and place vertically.
  --width <n>                 Render a single width.
  --min <n>                   Min width for range mode (default: 48).
  --max <n>                   Max width for range mode (default: terminal-based).
  --step <n>                  Step for range mode (default: 8).
  -h, --help                  Show this help.
EOF
  }

  cassette_strip_ansi() {
    sed -E $'s/\x1B\\[[0-9;]*m//g'
  }

  cassette_repeat_char() {
    local ch="$1"
    local count="$2"
    if [ "$count" -le 0 ]; then
      printf ''
      return
    fi
    printf "%${count}s" '' | tr ' ' "$ch"
  }

  cassette_center_text() {
    local text="$1"
    local width="$2"
    local tlen left right

    if [ "$width" -le 0 ]; then
      printf ''
      return
    fi

    tlen=${#text}
    if [ "$tlen" -gt "$width" ]; then
      if [ "$width" -le 3 ]; then
        printf '%.*s' "$width" "$text"
      else
        printf '%.*s...' "$((width - 3))" "$text"
      fi
      return
    fi

    left=$(((width - tlen) / 2))
    right=$((width - tlen - left))
    printf '%s%s%s' "$(cassette_repeat_char ' ' "$left")" "$text" "$(cassette_repeat_char ' ' "$right")"
  }

  cassette_center_visible() {
    local text="$1"
    local width="$2"
    local plain_len left right plain

    if [ "$width" -le 0 ]; then
      printf ''
      return
    fi

    plain="$(printf '%s' "$text" | cassette_strip_ansi)"
    plain_len=${#plain}
    if [ "$plain_len" -gt "$width" ]; then
      if [ "$width" -le 3 ]; then
        printf '%.*s' "$width" "$plain"
      else
        printf '%.*s...' "$((width - 3))" "$plain"
      fi
      return
    fi

    left=$(((width - plain_len) / 2))
    right=$((width - plain_len - left))
    printf '%s%s%s' "$(cassette_repeat_char ' ' "$left")" "$text" "$(cassette_repeat_char ' ' "$right")"
  }

  cassette_render_toilet() {
    local text="$1"
    local font="$2"
    shift 2
    local -a filters=("$@")
    local -a cmd=(toilet -f "$font")
    local filter
    local has_crop=0

    if ! command -v toilet >/dev/null 2>&1; then
      return 1
    fi

    for filter in "${filters[@]}"; do
      if [ "$filter" = "crop" ]; then
        has_crop=1
        break
      fi
    done
    if [ "$has_crop" -eq 0 ]; then
      cmd+=(-F crop)
    fi

    for filter in "${filters[@]}"; do
      [ -z "$filter" ] && continue
      cmd+=(-F "$filter")
    done
    cmd+=("$text")
    "${cmd[@]}" 2>/dev/null || return 1
  }

  cassette_normalize_github_repo() {
    local repo="$1"
    repo="${repo#https://github.com/}"
    repo="${repo#http://github.com/}"
    repo="${repo#github.com/}"
    printf '%s' "$repo"
  }

  # shellcheck disable=SC2317
  cassette_title_inner_width() {
    local total_width="$1"
    local inner plate_w

    inner=$((total_width - 2))
    plate_w=$((inner - 8))
    if [ "$plate_w" -lt 28 ]; then
      plate_w=28
    fi
    if [ "$plate_w" -gt "$inner" ]; then
      plate_w="$inner"
    fi
    printf '%s' "$((plate_w - 2))"
  }

  # shellcheck disable=SC2034
  cassette_resolve_title_lines() {
    local -n out_ref="$1"
    local title_inner_w="$2"
    local title_font_resolved title_filter_line
    local -a title_preset_filters title_all_filters

    title_font_resolved="${preset_font[$title_preset]}"
    if [ -n "$title_font" ]; then
      title_font_resolved="$title_font"
    fi
    title_filter_line="${preset_filters[$title_preset]}"
    if [ -n "$title_filter_line" ]; then
      # shellcheck disable=SC2206
      title_preset_filters=($title_filter_line)
    else
      title_preset_filters=()
    fi
    title_all_filters=("${title_preset_filters[@]}" "${title_filters[@]}")

    if mapfile -t out_ref < <(cassette_render_toilet "$label" "$title_font_resolved" "${title_all_filters[@]}"); then
      :
    else
      mapfile -t out_ref <<< "$(cassette_center_text "$label" "$title_inner_w")"
    fi
  }

  cassette_visible_length() {
    local text="$1"
    local plain

    plain="$(printf '%s' "$text" | cassette_strip_ansi)"
    printf '%s' "${#plain}"
  }

  cassette_scroll_line() {
    local text="$1"
    local viewport_width="$2"
    local offset="$3"
    local i=0 char rest seq active_sgr=""
    local sgr_regex=$'^\033\\[[0-9;]*m'
    local -a visible_cells=()
    local result="" col text_index

    while [ "$i" -lt "${#text}" ]; do
      char="${text:i:1}"
      if [ "$char" = $'\033' ]; then
        rest="${text:i}"
        if [[ "$rest" =~ $sgr_regex ]]; then
          seq="${BASH_REMATCH[0]}"
          if [ "$seq" = $'\033[0m' ]; then
            active_sgr=""
          else
            active_sgr="$seq"
          fi
          i=$((i + ${#seq}))
          continue
        fi
      fi

      if [ -n "$active_sgr" ]; then
        visible_cells+=("${active_sgr}${char}"$'\033[0m')
      else
        visible_cells+=("$char")
      fi
      i=$((i + 1))
    done

    for ((col = 0; col < viewport_width; col++)); do
      text_index=$((col - offset))
      if [ "$text_index" -ge 0 ] && [ "$text_index" -lt "${#visible_cells[@]}" ]; then
        result+="${visible_cells[$text_index]}"
      else
        result+=" "
      fi
    done

    printf '%s' "$result"
  }

  cassette_print_dynamic_frame() {
    local outer_pad="$1"
    local left_pad="$2"
    local title_inner_w="$3"
    local right_pad="$4"
    local offset="$5"
    local subtitle_text="$6"
    local github_text="$7"
    local reel_top_line="$8"
    local reel_mid_line="$9"
    local reel_bot_line="${10}"
    shift 10
    local line

    for line in "$@"; do
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_scroll_line "$line" "$title_inner_w" "$offset")" "$right_pad"
    done
    if [ -n "$subtitle_text" ]; then
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$subtitle_text" "$title_inner_w")" "$right_pad"
    fi
    if [ -n "$github_text" ]; then
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$github_text" "$title_inner_w")" "$right_pad"
    fi
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char ' ' "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$reel_top_line" "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$reel_mid_line" "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$reel_bot_line" "$title_inner_w")" "$right_pad"
  }

  cassette_render_dynamic_at_offset() {
    local outer_pad="$1"
    local left_pad="$2"
    local title_inner_w="$3"
    local right_pad="$4"
    local offset="$5"
    local subtitle_text="$6"
    local github_text="$7"
    local reel_top_line="$8"
    local reel_mid_line="$9"
    local reel_bot_line="${10}"
    shift 10

    printf '\033[u'
    cassette_print_dynamic_frame "$outer_pad" "$left_pad" "$title_inner_w" "$right_pad" "$offset" "$subtitle_text" "$github_text" "$reel_top_line" "$reel_mid_line" "$reel_bot_line" "$@"
    sleep "$animation_delay"
  }

  cassette_reel_symbol() {
    local frame_index="$1"
    local symbols=(" | " " / " " - " " \\ ")

    printf '%s' "${symbols[$((frame_index % ${#symbols[@]}))]}"
  }

  cassette_positioning() {
    local block_width="$1"
    local block_lines="$2"
    local left_pad_count=0
    local top_pad_count=0
    local terminal_width terminal_height

    if [ -n "$center_mode" ]; then
      terminal_width="$(terminal_cols)"
      terminal_height="$(terminal_lines)"
      if [ "$block_width" -lt "$terminal_width" ]; then
        left_pad_count=$(((terminal_width - block_width) / 2))
      fi
      if [ "$center_mode" = "all" ] && [ "$block_lines" -lt "$terminal_height" ]; then
        top_pad_count=$(((terminal_height - block_lines) / 2))
      elif [ "$center_mode" = "bottom" ] && [ "$block_lines" -lt "$terminal_height" ]; then
        top_pad_count=$((terminal_height - block_lines))
      fi
    fi

    printf '%s:%s' "$left_pad_count" "$top_pad_count"
  }

  cassette_print_top_pad() {
    local top_pad_count="$1"
    local i

    for ((i = 0; i < top_pad_count; i++)); do
      printf '\n'
    done
  }

  cassette_emit_animated() {
    local total_width="$1"
    local inner plate_w plate_pad title_inner_w
    local left_pad right_pad outer_pad
    local github_clean
    local reel_top reel_mid reel_bot reel_margin reel_bridge
    local spacer_bridge reel_top_line reel_mid_line reel_bot_line
    local controls_long controls_medium controls_short controls
    local line total_lines offset block_width center_offset
    local repeat_index animation_frame
    local reel_symbol
    local position_data outer_pad_count top_pad_count
    local header_github_text=""
    local dynamic_blank_line
    local -a title_lines brand_lines blank_title_lines

    if [ "$total_width" -lt 40 ]; then
      echo "Width must be >= 40: $total_width" >&2
      return 1
    fi

    inner=$((total_width - 2))
    plate_w=$((inner - 8))
    if [ "$plate_w" -lt 28 ]; then
      plate_w=28
    fi
    if [ "$plate_w" -gt "$inner" ]; then
      plate_w="$inner"
    fi
    plate_pad=$(((inner - plate_w) / 2))
    left_pad="$(cassette_repeat_char ' ' "$plate_pad")"
    right_pad="$(cassette_repeat_char ' ' "$((inner - plate_w - plate_pad))")"
    title_inner_w=$((plate_w - 2))

    cassette_resolve_title_lines title_lines "$title_inner_w"
    if mapfile -t brand_lines < <(cassette_render_toilet "$project_title" "mini"); then
      :
    else
      brand_lines=("$(cassette_center_text "$project_title" "$title_inner_w")")
    fi

    block_width=0
    for line in "${title_lines[@]}"; do
      local line_width
      line_width="$(cassette_visible_length "$line")"
      if [ "$line_width" -gt "$block_width" ]; then
        block_width="$line_width"
      fi
    done
    if [ "$block_width" -le 0 ]; then
      block_width="${#label}"
    fi
    center_offset=$(((title_inner_w - block_width) / 2))
    if [ "$center_offset" -lt 0 ]; then
      center_offset=0
    fi

    total_lines=$((14 + ${#title_lines[@]} + ${#brand_lines[@]}))
    if [ -n "$subtitle" ]; then
      total_lines=$((total_lines + 1))
    fi
    github_clean="$(cassette_normalize_github_repo "$github_repo")"
    if [ -n "$github_clean" ]; then
      total_lines=$((total_lines + 1))
      header_github_text="github.com/$github_clean"
    fi
    position_data="$(cassette_positioning "$total_width" "$total_lines")"
    outer_pad_count="${position_data%%:*}"
    top_pad_count="${position_data##*:}"
    outer_pad="$(cassette_repeat_char ' ' "$outer_pad_count")"

    if [ "$clear_screen" -eq 1 ]; then
      printf '\033[H\033[2J'
    fi
    cassette_print_top_pad "$top_pad_count"

    for _ in "${title_lines[@]}"; do
      blank_title_lines+=("$(cassette_repeat_char ' ' "$title_inner_w")")
    done

    printf '\033[?25l%s%s\n' "$outer_pad" "$(cassette_repeat_char '_' "$((inner + 1))")"
    printf '%s/%s\\\n' "$outer_pad" "$(cassette_repeat_char '_' "$inner")"
    printf '%s|%s|\n' "$outer_pad" "$(cassette_repeat_char ' ' "$inner")"
    printf '%s|%s+%s+%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"
    printf '\033[s'

    dynamic_blank_line="$(cassette_repeat_char ' ' "$title_inner_w")"
    for line in "${blank_title_lines[@]}"; do
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$line" "$right_pad"
    done
    if [ -n "$subtitle" ]; then
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$dynamic_blank_line" "$right_pad"
    fi

    if [ -n "$github_clean" ]; then
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$dynamic_blank_line" "$right_pad"
    fi

    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$dynamic_blank_line" "$right_pad"

    reel_top=".---."
    reel_mid="(   )"
    reel_bot="'---'"
    reel_margin=$((plate_w / 8))
    if [ "$reel_margin" -lt 6 ]; then
      reel_margin=6
    fi
    reel_bridge=$((plate_w - 2 - (reel_margin * 2) - (${#reel_mid} * 2) - 4))
    if [ "$reel_bridge" -lt 4 ]; then
      reel_bridge=4
    fi
    spacer_bridge="$(cassette_repeat_char ' ' "$reel_bridge")"
    reel_top_line="$(cassette_repeat_char ' ' "$reel_margin")${reel_top}${spacer_bridge}${reel_top}$(cassette_repeat_char ' ' "$reel_margin")"
    reel_symbol="$(cassette_reel_symbol 0)"
    reel_mid_line="$(cassette_repeat_char ' ' "$reel_margin")(${reel_symbol})$(cassette_repeat_char '-' "$reel_bridge")(${reel_symbol})$(cassette_repeat_char ' ' "$reel_margin")"
    reel_bot_line="$(cassette_repeat_char ' ' "$reel_margin")${reel_bot}${spacer_bridge}${reel_bot}$(cassette_repeat_char ' ' "$reel_margin")"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$dynamic_blank_line" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$dynamic_blank_line" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$dynamic_blank_line" "$right_pad"

    for line in "${brand_lines[@]}"; do
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_visible "$line" "$title_inner_w")" "$right_pad"
    done
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$project_url" "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char ' ' "$title_inner_w")" "$right_pad"

    controls_long="[PLAY]  ||  <<  >>  [STOP]  [REWIND]  [EJECT]"
    controls_medium="[PLAY] || << >> [STOP] [REWIND] [EJECT]"
    controls_short="PLAY || << >> STOP REWIND EJECT"
    if [ "${#controls_long}" -le "$title_inner_w" ]; then
      controls="$controls_long"
    elif [ "${#controls_medium}" -le "$title_inner_w" ]; then
      controls="$controls_medium"
    else
      controls="$controls_short"
    fi
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$controls" "$title_inner_w")" "$right_pad"

    printf '%s|%s+%s+%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"
    printf '%s|%s|\n' "$outer_pad" "$(cassette_repeat_char ' ' "$inner")"
    printf '%s\\%s/\n' "$outer_pad" "$(cassette_repeat_char '_' "$inner")"

    animation_frame=0

    cassette_render_dynamic_at_offset "$outer_pad" "$left_pad" "$title_inner_w" "$right_pad" "$center_offset" "$subtitle" "$header_github_text" "$reel_top_line" "$reel_mid_line" "$reel_bot_line" "${title_lines[@]}"
    repeat_index=0
    while :; do
      repeat_index=$((repeat_index + 1))
      for ((offset = center_offset - 1; offset >= -block_width; offset--)); do
        animation_frame=$((animation_frame + 1))
        reel_symbol="$(cassette_reel_symbol "$animation_frame")"
        reel_mid_line="$(cassette_repeat_char ' ' "$reel_margin")(${reel_symbol})$(cassette_repeat_char '-' "$reel_bridge")(${reel_symbol})$(cassette_repeat_char ' ' "$reel_margin")"
        cassette_render_dynamic_at_offset "$outer_pad" "$left_pad" "$title_inner_w" "$right_pad" "$offset" "$subtitle" "$header_github_text" "$reel_top_line" "$reel_mid_line" "$reel_bot_line" "${title_lines[@]}"
      done
      for ((offset = title_inner_w; offset >= center_offset; offset--)); do
        animation_frame=$((animation_frame + 1))
        reel_symbol="$(cassette_reel_symbol "$animation_frame")"
        reel_mid_line="$(cassette_repeat_char ' ' "$reel_margin")(${reel_symbol})$(cassette_repeat_char '-' "$reel_bridge")(${reel_symbol})$(cassette_repeat_char ' ' "$reel_margin")"
        cassette_render_dynamic_at_offset "$outer_pad" "$left_pad" "$title_inner_w" "$right_pad" "$offset" "$subtitle" "$header_github_text" "$reel_top_line" "$reel_mid_line" "$reel_bot_line" "${title_lines[@]}"
      done

      if [ "$animate_repeat" != "infinite" ] && [ "$repeat_index" -ge "$animate_repeat" ]; then
        break
      fi
    done

    reel_symbol="$(cassette_reel_symbol "$animation_frame")"
    reel_mid_line="$(cassette_repeat_char ' ' "$reel_margin")(${reel_symbol})$(cassette_repeat_char '-' "$reel_bridge")(${reel_symbol})$(cassette_repeat_char ' ' "$reel_margin")"
    printf '\033[u'
    cassette_print_dynamic_frame "$outer_pad" "$left_pad" "$title_inner_w" "$right_pad" "$center_offset" "$subtitle" "$header_github_text" "$reel_top_line" "$reel_mid_line" "$reel_bot_line" "${title_lines[@]}"
    printf '\033[%sB\033[?25h' "$((total_lines - 4))"
  }

  cassette_animation_offset() {
    local frame_index="$1"
    local center_offset="$2"
    local block_width="$3"
    local title_inner_w="$4"
    local cycle_len idx

    if [ "$frame_index" -le 0 ]; then
      printf '%s' "$center_offset"
      return
    fi

    cycle_len=$((title_inner_w + block_width + 1))
    idx=$(((frame_index - 1) % cycle_len))

    if [ "$idx" -lt $((center_offset + block_width)) ]; then
      printf '%s' "$((center_offset - 1 - idx))"
    else
      printf '%s' "$((title_inner_w - (idx - center_offset - block_width)))"
    fi
  }

  cassette_emit_frame() {
    local total_width="$1"
    local frame_index="$2"
    local inner plate_w plate_pad title_inner_w
    local left_pad right_pad outer_pad
    local github_clean
    local reel_top reel_bot reel_margin reel_bridge
    local spacer_bridge reel_top_line reel_mid_line reel_bot_line
    local controls_long controls_medium controls_short controls
    local line total_lines block_width center_offset offset
    local reel_symbol position_data outer_pad_count top_pad_count
    local header_github_text=""
    local -a title_lines brand_lines

    if [ "$total_width" -lt 40 ]; then
      echo "Width must be >= 40: $total_width" >&2
      return 1
    fi

    inner=$((total_width - 2))
    plate_w=$((inner - 8))
    if [ "$plate_w" -lt 28 ]; then
      plate_w=28
    fi
    if [ "$plate_w" -gt "$inner" ]; then
      plate_w="$inner"
    fi
    plate_pad=$(((inner - plate_w) / 2))
    left_pad="$(cassette_repeat_char ' ' "$plate_pad")"
    right_pad="$(cassette_repeat_char ' ' "$((inner - plate_w - plate_pad))")"
    title_inner_w=$((plate_w - 2))

    cassette_resolve_title_lines title_lines "$title_inner_w"
    if mapfile -t brand_lines < <(cassette_render_toilet "$project_title" "mini"); then
      :
    else
      brand_lines=("$(cassette_center_text "$project_title" "$title_inner_w")")
    fi

    block_width=0
    for line in "${title_lines[@]}"; do
      local line_width
      line_width="$(cassette_visible_length "$line")"
      if [ "$line_width" -gt "$block_width" ]; then
        block_width="$line_width"
      fi
    done
    if [ "$block_width" -le 0 ]; then
      block_width="${#label}"
    fi
    center_offset=$(((title_inner_w - block_width) / 2))
    if [ "$center_offset" -lt 0 ]; then
      center_offset=0
    fi
    offset="$(cassette_animation_offset "$frame_index" "$center_offset" "$block_width" "$title_inner_w")"

    total_lines=$((14 + ${#title_lines[@]} + ${#brand_lines[@]}))
    if [ -n "$subtitle" ]; then
      total_lines=$((total_lines + 1))
    fi
    github_clean="$(cassette_normalize_github_repo "$github_repo")"
    if [ -n "$github_clean" ]; then
      total_lines=$((total_lines + 1))
      header_github_text="github.com/$github_clean"
    fi
    position_data="$(cassette_positioning "$total_width" "$total_lines")"
    outer_pad_count="${position_data%%:*}"
    top_pad_count="${position_data##*:}"
    outer_pad="$(cassette_repeat_char ' ' "$outer_pad_count")"

    cassette_print_top_pad "$top_pad_count"

    printf '%s%s\n' "$outer_pad" "$(cassette_repeat_char '_' "$((inner + 1))")"
    printf '%s/%s\\\n' "$outer_pad" "$(cassette_repeat_char '_' "$inner")"
    printf '%s|%s|\n' "$outer_pad" "$(cassette_repeat_char ' ' "$inner")"
    printf '%s|%s+%s+%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"

    reel_top=".---."
    reel_bot="'---'"
    reel_margin=$((plate_w / 8))
    if [ "$reel_margin" -lt 6 ]; then
      reel_margin=6
    fi
    reel_bridge=$((plate_w - 2 - (reel_margin * 2) - 14))
    if [ "$reel_bridge" -lt 4 ]; then
      reel_bridge=4
    fi
    spacer_bridge="$(cassette_repeat_char ' ' "$reel_bridge")"
    reel_top_line="$(cassette_repeat_char ' ' "$reel_margin")${reel_top}${spacer_bridge}${reel_top}$(cassette_repeat_char ' ' "$reel_margin")"
    reel_symbol="$(cassette_reel_symbol "$frame_index")"
    reel_mid_line="$(cassette_repeat_char ' ' "$reel_margin")(${reel_symbol})$(cassette_repeat_char '-' "$reel_bridge")(${reel_symbol})$(cassette_repeat_char ' ' "$reel_margin")"
    reel_bot_line="$(cassette_repeat_char ' ' "$reel_margin")${reel_bot}${spacer_bridge}${reel_bot}$(cassette_repeat_char ' ' "$reel_margin")"

    cassette_print_dynamic_frame "$outer_pad" "$left_pad" "$title_inner_w" "$right_pad" "$offset" "$subtitle" "$header_github_text" "$reel_top_line" "$reel_mid_line" "$reel_bot_line" "${title_lines[@]}"

    for line in "${brand_lines[@]}"; do
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_visible "$line" "$title_inner_w")" "$right_pad"
    done
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$project_url" "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char ' ' "$title_inner_w")" "$right_pad"

    controls_long="[PLAY]  ||  <<  >>  [STOP]  [REWIND]  [EJECT]"
    controls_medium="[PLAY] || << >> [STOP] [REWIND] [EJECT]"
    controls_short="PLAY || << >> STOP REWIND EJECT"
    if [ "${#controls_long}" -le "$title_inner_w" ]; then
      controls="$controls_long"
    elif [ "${#controls_medium}" -le "$title_inner_w" ]; then
      controls="$controls_medium"
    else
      controls="$controls_short"
    fi
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$controls" "$title_inner_w")" "$right_pad"
    printf '%s|%s+%s+%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"
    printf '%s|%s|\n' "$outer_pad" "$(cassette_repeat_char ' ' "$inner")"
    printf '%s\\%s/\n' "$outer_pad" "$(cassette_repeat_char '_' "$inner")"
  }

  cassette_emit() {
    local total_width="$1"
    local inner plate_w plate_pad title_inner_w
    local left_pad right_pad outer_pad
    local -a title_lines
    local -a brand_lines
    local github_clean
    local reel_top reel_mid reel_bot reel_margin reel_bridge
    local spacer_bridge reel_top_line reel_mid_line reel_bot_line
    local controls_long controls_medium controls_short controls
    local line
    local total_lines position_data outer_pad_count top_pad_count

    if [ "$total_width" -lt 40 ]; then
      echo "Width must be >= 40: $total_width" >&2
      return 1
    fi

    inner=$((total_width - 2))
    plate_w=$((inner - 8))
    if [ "$plate_w" -lt 28 ]; then
      plate_w=28
    fi
    if [ "$plate_w" -gt "$inner" ]; then
      plate_w="$inner"
    fi
    plate_pad=$(((inner - plate_w) / 2))
    left_pad="$(cassette_repeat_char ' ' "$plate_pad")"
    right_pad="$(cassette_repeat_char ' ' "$((inner - plate_w - plate_pad))")"
    title_inner_w=$((plate_w - 2))

    cassette_resolve_title_lines title_lines "$title_inner_w"
    if mapfile -t brand_lines < <(cassette_render_toilet "$project_title" "mini"); then
      :
    else
      brand_lines=("$(cassette_center_text "$project_title" "$title_inner_w")")
    fi
    total_lines=$((14 + ${#title_lines[@]} + ${#brand_lines[@]}))
    if [ -n "$subtitle" ]; then
      total_lines=$((total_lines + 1))
    fi
    github_clean="$(cassette_normalize_github_repo "$github_repo")"
    if [ -n "$github_clean" ]; then
      total_lines=$((total_lines + 1))
    fi
    position_data="$(cassette_positioning "$total_width" "$total_lines")"
    outer_pad_count="${position_data%%:*}"
    top_pad_count="${position_data##*:}"
    outer_pad="$(cassette_repeat_char ' ' "$outer_pad_count")"

    if [ "$clear_screen" -eq 1 ]; then
      printf '\033[H\033[2J'
    fi
    cassette_print_top_pad "$top_pad_count"

    printf '%s%s\n' "$outer_pad" "$(cassette_repeat_char '_' "$((inner + 1))")"
    printf '%s/%s\\\n' "$outer_pad" "$(cassette_repeat_char '_' "$inner")"
    printf '%s|%s|\n' "$outer_pad" "$(cassette_repeat_char ' ' "$inner")"
    printf '%s|%s+%s+%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"

    for line in "${title_lines[@]}"; do
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_visible "$line" "$title_inner_w")" "$right_pad"
    done
    if [ -n "$subtitle" ]; then
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$subtitle" "$title_inner_w")" "$right_pad"
    fi

    if [ -n "$github_clean" ]; then
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "github.com/$github_clean" "$title_inner_w")" "$right_pad"
    fi

    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char ' ' "$title_inner_w")" "$right_pad"

    reel_top=".---."
    reel_mid="(   )"
    reel_bot="'---'"
    reel_margin=$((plate_w / 8))
    if [ "$reel_margin" -lt 6 ]; then
      reel_margin=6
    fi
    reel_bridge=$((plate_w - 2 - (reel_margin * 2) - (${#reel_mid} * 2) - 4))
    if [ "$reel_bridge" -lt 4 ]; then
      reel_bridge=4
    fi
    spacer_bridge="$(cassette_repeat_char ' ' "$reel_bridge")"
    reel_top_line="$(cassette_repeat_char ' ' "$reel_margin")${reel_top}${spacer_bridge}${reel_top}$(cassette_repeat_char ' ' "$reel_margin")"
    reel_mid_line="$(cassette_repeat_char ' ' "$reel_margin")${reel_mid}$(cassette_repeat_char '-' "$reel_bridge")${reel_mid}$(cassette_repeat_char ' ' "$reel_margin")"
    reel_bot_line="$(cassette_repeat_char ' ' "$reel_margin")${reel_bot}${spacer_bridge}${reel_bot}$(cassette_repeat_char ' ' "$reel_margin")"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$reel_top_line" "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$reel_mid_line" "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$reel_bot_line" "$title_inner_w")" "$right_pad"
    for line in "${brand_lines[@]}"; do
      printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_visible "$line" "$title_inner_w")" "$right_pad"
    done
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$project_url" "$title_inner_w")" "$right_pad"
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char ' ' "$title_inner_w")" "$right_pad"

    controls_long="[PLAY]  ||  <<  >>  [STOP]  [REWIND]  [EJECT]"
    controls_medium="[PLAY] || << >> [STOP] [REWIND] [EJECT]"
    controls_short="PLAY || << >> STOP REWIND EJECT"
    if [ "${#controls_long}" -le "$title_inner_w" ]; then
      controls="$controls_long"
    elif [ "${#controls_medium}" -le "$title_inner_w" ]; then
      controls="$controls_medium"
    else
      controls="$controls_short"
    fi
    printf '%s|%s|%s|%s|\n' "$outer_pad" "$left_pad" "$(cassette_center_text "$controls" "$title_inner_w")" "$right_pad"

    printf '%s|%s+%s+%s|\n' "$outer_pad" "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"
    printf '%s|%s|\n' "$outer_pad" "$(cassette_repeat_char ' ' "$inner")"
    printf '%s\\%s/\n' "$outer_pad" "$(cassette_repeat_char '_' "$inner")"
  }

  while [ $# -gt 0 ]; do
    case "$1" in
      --label)
        label="${2:-}"
        shift 2
        ;;
      --subtitle)
        subtitle="${2:-}"
        shift 2
        ;;
      --github)
        github_repo="${2:-}"
        shift 2
        ;;
      --project-title)
        project_title="${2:-}"
        shift 2
        ;;
      --project-url)
        project_url="${2:-}"
        shift 2
        ;;
      --title-preset|--toilet-preset)
        title_preset="${2:-}"
        shift 2
        ;;
      --title-font|--toilet-font)
        title_font="${2:-}"
        shift 2
        ;;
      --title-filter|--toilet-filter)
        title_filters+=("${2:-}")
        shift 2
        ;;
      --animate)
        animate=1
        if [ $# -gt 1 ] && [[ "${2:-}" != --* ]]; then
          animate_repeat="${2:-}"
          shift 2
        else
          shift
        fi
        ;;
      --animate-frame)
        animate_frame_mode=1
        animate_frame_index="${2:-}"
        shift 2
        ;;
      --clear-screen)
        clear_screen=1
        shift
        ;;
      --center)
        center_mode="all"
        if [ $# -gt 1 ] && [[ "${2:-}" != --* ]]; then
          center_mode="${2:-}"
          shift 2
        else
          shift
        fi
        ;;
      --width)
        single_width="${2:-}"
        shift 2
        ;;
      --min)
        min_width="${2:-}"
        shift 2
        ;;
      --max)
        max_width="${2:-}"
        shift 2
        ;;
      --step)
        step="${2:-}"
        shift 2
        ;;
      -h|--help)
        cassette_usage
        return 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        cassette_usage >&2
        return 1
        ;;
    esac
  done

  if [ -z "${preset_font[$title_preset]+x}" ]; then
    echo "Invalid --title-preset: $title_preset" >&2
    return 1
  fi

  if ! [[ "$min_width" =~ ^[0-9]+$ ]] || ! [[ "$step" =~ ^[0-9]+$ ]]; then
    echo "--min and --step must be positive integers" >&2
    return 1
  fi
  if [ "$step" -le 0 ]; then
    echo "--step must be > 0" >&2
    return 1
  fi
  if [ "$animate" -eq 1 ]; then
    if [ "$animate_repeat" != "infinite" ] && ! [[ "$animate_repeat" =~ ^[0-9]+$ ]]; then
      echo "--animate must be followed by an integer >= 1 or 'infinite'" >&2
      return 1
    fi
    if [ "$animate_repeat" != "infinite" ] && [ "$animate_repeat" -lt 1 ]; then
      echo "--animate repetition count must be >= 1 or 'infinite'" >&2
      return 1
    fi
  fi
  if [ "$animate_frame_mode" -eq 1 ] && ! [[ "$animate_frame_index" =~ ^[0-9]+$ ]]; then
    echo "--animate-frame must be a non-negative integer" >&2
    return 1
  fi
  if [ -n "$center_mode" ] && [ "$center_mode" != "all" ] && [ "$center_mode" != "top" ] && [ "$center_mode" != "bottom" ]; then
    echo "--center must be one of: all, top, bottom" >&2
    return 1
  fi

  local terminal_columns max_default effective_max
  local -a widths=()
  local w i=0

  terminal_columns="$(terminal_cols)"
  max_default="$terminal_columns"
  if [ "$max_default" -gt 120 ]; then
    max_default=120
  fi
  if [ "$max_default" -lt 48 ]; then
    max_default=48
  fi

  if [ -n "$max_width" ]; then
    if ! [[ "$max_width" =~ ^[0-9]+$ ]]; then
      echo "--max must be a positive integer" >&2
      return 1
    fi
    effective_max="$max_width"
  else
    effective_max="$max_default"
  fi

  if [ -n "$single_width" ]; then
    if ! [[ "$single_width" =~ ^[0-9]+$ ]]; then
      echo "--width must be a positive integer" >&2
      return 1
    fi
    widths=("$single_width")
  else
    if [ "$min_width" -gt "$effective_max" ]; then
      echo "--min cannot be greater than --max" >&2
      return 1
    fi
    w="$min_width"
    while [ "$w" -le "$effective_max" ]; do
      widths+=("$w")
      w=$((w + step))
    done
    if [ "${widths[${#widths[@]}-1]}" -ne "$effective_max" ]; then
      widths+=("$effective_max")
    fi
  fi

  if [ "$animate" -eq 1 ] || [ "$animate_frame_mode" -eq 1 ]; then
    widths=("${widths[${#widths[@]}-1]}")
  fi

  for w in "${widths[@]}"; do
    if [ "$i" -gt 0 ]; then
      echo
    fi
    i=$((i + 1))
    if [ "$animate_frame_mode" -eq 1 ]; then
      cassette_emit_frame "$w" "$animate_frame_index" || return 1
    elif [ "$animate" -eq 1 ]; then
      cassette_emit_animated "$w" || return 1
    else
      echo "# width=$w" >&2
      cassette_emit "$w" || return 1
    fi
  done
}
