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

show_done() {
  local steps_number="${1:-1}"
  local steps_executed="${2:-0}"
  local global_title="${3:-Bash Tape}"
  local global_github="${4:-paulojeronimo/bash-tape}"
  local title_preset="${5:-future-metal}"
  local summary="Steps executed: $steps_executed"
  local cols lines render_cols
  local header_text done_text
  local header_lines done_lines total_height start_y
  local line pad

  if [ -t 1 ]; then
    cols="$(terminal_cols)"
    lines="$(terminal_lines)"
    render_cols="$cols"
    if [ "$render_cols" -gt 120 ]; then
      render_cols=120
    fi

    if [ "$render_cols" -ge 40 ]; then
      header_text="$(
        cassette_art_main \
          --width "$render_cols" \
          --label "$global_title" \
          --subtitle "Steps $steps_number" \
          --title-preset "$title_preset" \
          --github "$global_github" 2>/dev/null || true
      )"
    else
      header_text="$(printf '%s\n' "$global_title" "Steps $steps_number")"
    fi

    if [ -z "$header_text" ]; then
      header_text="$(printf '%s\n' "$global_title" "Steps $steps_number")"
    fi

    if command -v toilet >/dev/null 2>&1; then
      done_text="$(toilet -f smblock "Done!" 2>/dev/null || true)"
    fi
    if [ -z "${done_text:-}" ]; then
      done_text="$(figlet "Done!")"
    fi

    header_lines="$(printf '%s\n' "$header_text" | wc -l)"
    done_lines="$(printf '%s\n' "$done_text" | wc -l)"
    total_height=$((header_lines + 2 + done_lines + 2 + 1))
    start_y=$(((lines - total_height) / 2))
    if [ "$start_y" -lt 0 ]; then
      start_y=0
    fi

    clear
    tput cup "$start_y" 0
    print_block_centered_visible "$header_text" "$render_cols"
    tput cud1
    tput cud1

    while IFS= read -r line; do
      pad=0
      if [ "${#line}" -lt "$cols" ]; then
        pad=$(((cols - ${#line}) / 2))
      fi
      printf '%*s%s\n' "$pad" '' "$line"
    done <<< "$done_text"

    tput cud1
    tput cud1
    print_centered "$summary"
  else
    render_cols="$(terminal_cols)"
    if [ "$render_cols" -gt 120 ]; then
      render_cols=120
    fi
    cassette_art_main \
      --width "$render_cols" \
      --label "$global_title" \
      --subtitle "Steps $steps_number" \
      --title-preset "$title_preset" \
      --github "$global_github" 2>/dev/null || true
    echo
    echo
    if command -v toilet >/dev/null 2>&1; then
      toilet -f smblock "Done!"
    else
      figlet "Done!"
    fi
    echo
    echo
    echo "$summary"
  fi
}

prompt_done_navigation() {
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

  prompt="e eject  |  b back  |  s stop   $(navigation_context)"

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
      b|B)
        printf -v "$result_var" '%s' "back"
        return
        ;;
    esac
  done
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
  local title_preset="future"
  local title_font=""
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
  --title-preset <preset>     future | future-border | future-metal |
                              future-border-metal | future-gay | future-border-gay
  --toilet-preset <preset>    Alias for --title-preset.
  --title-font <font>         Override title font.
  --toilet-font <font>        Alias for --title-font.
  --title-filter <filter>     Extra title filter (repeatable).
  --toilet-filter <filter>    Alias for --title-filter.
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

  cassette_emit() {
    local total_width="$1"
    local inner plate_w plate_pad title_inner_w
    local left_pad right_pad
    local title_font_resolved title_filter_line
    local -a title_preset_filters title_all_filters title_lines
    local -a brand_lines
    local github_clean
    local reel_top reel_mid reel_bot reel_margin reel_bridge
    local spacer_bridge reel_top_line reel_mid_line reel_bot_line
    local controls_long controls_medium controls_short controls
    local line

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

    if mapfile -t title_lines < <(cassette_render_toilet "$label" "$title_font_resolved" "${title_all_filters[@]}"); then
      :
    else
      title_lines=("$(cassette_center_text "$label" "$title_inner_w")")
    fi

    printf ' %s\n' "$(cassette_repeat_char '_' "$inner")"
    printf '/%s\\\n' "$(cassette_repeat_char '_' "$inner")"
    printf '|%s|\n' "$(cassette_repeat_char ' ' "$inner")"
    printf '|%s+%s+%s|\n' "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"

    for line in "${title_lines[@]}"; do
      printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_visible "$line" "$title_inner_w")" "$right_pad"
    done
    if [ -n "$subtitle" ]; then
      printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_text "$subtitle" "$title_inner_w")" "$right_pad"
    fi

    github_clean="$(cassette_normalize_github_repo "$github_repo")"
    if [ -n "$github_clean" ]; then
      printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_text "github.com/$github_clean" "$title_inner_w")" "$right_pad"
    fi

    printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_repeat_char ' ' "$title_inner_w")" "$right_pad"

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
    printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_text "$reel_top_line" "$title_inner_w")" "$right_pad"
    printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_text "$reel_mid_line" "$title_inner_w")" "$right_pad"
    printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_text "$reel_bot_line" "$title_inner_w")" "$right_pad"

    if mapfile -t brand_lines < <(cassette_render_toilet "Bash Tape" "mini"); then
      :
    else
      brand_lines=("$(cassette_center_text "Bash Tape" "$title_inner_w")")
    fi
    for line in "${brand_lines[@]}"; do
      printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_visible "$line" "$title_inner_w")" "$right_pad"
    done
    printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_text "github.com/paulojeronimo/bash-tape" "$title_inner_w")" "$right_pad"
    printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_repeat_char ' ' "$title_inner_w")" "$right_pad"

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
    printf '|%s|%s|%s|\n' "$left_pad" "$(cassette_center_text "$controls" "$title_inner_w")" "$right_pad"

    printf '|%s+%s+%s|\n' "$left_pad" "$(cassette_repeat_char '-' "$((plate_w - 2))")" "$right_pad"
    printf '|%s|\n' "$(cassette_repeat_char ' ' "$inner")"
    printf '\\%s/\n' "$(cassette_repeat_char '_' "$inner")"
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

  for w in "${widths[@]}"; do
    if [ "$i" -gt 0 ]; then
      echo
    fi
    i=$((i + 1))
    echo "# width=$w" >&2
    cassette_emit "$w" || return 1
  done
}
