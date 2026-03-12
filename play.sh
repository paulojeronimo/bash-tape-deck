#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/functions.sh"

if ! command -v batcat >/dev/null 2>&1; then
  echo "Missing required command: batcat" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "Missing required command: yq" >&2
  exit 1
fi

if ! command -v figlet >/dev/null 2>&1; then
  echo "Missing required command: figlet" >&2
  exit 1
fi

steps_dir_arg="${1:-}"
if [ -z "$steps_dir_arg" ]; then
  echo "Usage: ./play.sh <steps-dir> [N]" >&2
  exit 1
fi

if [ ! -d "$steps_dir_arg" ]; then
  echo "Steps directory not found: $steps_dir_arg" >&2
  exit 1
fi

steps_dir="$(cd "$steps_dir_arg" && pwd)"
default_run_workdir="$script_dir/build"
run_workdir="${BASH_TAPE_RUN_WORKDIR:-$default_run_workdir}"
mkdir -p "$run_workdir"
run_workdir="$(cd "$run_workdir" && pwd)"
cd "$run_workdir"

tutorial_steps_number="${2:-1}"
if ! [[ "$tutorial_steps_number" =~ ^[0-9]+$ ]]; then
  echo "Invalid steps number: $tutorial_steps_number" >&2
  echo "Usage: ./play.sh <steps-dir> [N]" >&2
  exit 1
fi

steps_file="$steps_dir/steps.${tutorial_steps_number}.sh"
if [ ! -f "$steps_file" ]; then
  echo "Steps file not found: $steps_file" >&2
  exit 1
fi
steps_file_name="$(basename "$steps_file")"

tape_identity_source="${BASH_TAPE_SOURCE_STEPS_DIR:-$steps_dir}"
tape_id="$(bash_tape_id "$tape_identity_source")"
tape_state_dir="$(bash_tape_state_dir "$tape_identity_source" "$run_workdir")"
tape_log_file="$(bash_tape_log_file "$tape_identity_source" "$run_workdir")"
mkdir -p "$tape_state_dir"
export BASH_TAPE_ID="$tape_id"
export BASH_TAPE_DIR="$run_workdir/.bash-tape"
export BASH_TAPE_STATE_DIR="$tape_state_dir"
export BASH_TAPE_LOG_FILE="$tape_log_file"
export BASH_TAPE_STEPS_DIR="$steps_dir"
export BASH_TAPE_SOURCE_STEPS_DIR="$tape_identity_source"
export BASH_TAPE_STEPS_NUMBER="$tutorial_steps_number"
export BASH_TAPE_RUN_WORKDIR="$run_workdir"

metadata_file="$steps_dir/steps.yaml"
steps_begin_script="$steps_dir/steps.begin.sh"
steps_end_script="$steps_dir/steps.end.sh"
steps_intro=""
global_title=""
global_github=""
tutorial_title_preset="future-metal"
tutorial_subtitle=""
declare -A metadata_position_by_id
declare -A metadata_content_by_id

load_metadata() {
  local block_id
  local block_position
  local block_content

  if [ ! -f "$metadata_file" ]; then
    return
  fi

  global_title="$(
    yq eval -r 'select(has("steps") | not) | .title // ""' "$metadata_file"
  )"
  global_github="$(
    yq eval -r 'select(has("steps") | not) | .github // ""' "$metadata_file"
  )"
  tutorial_title_preset="$(
    yq eval -r 'select(has("steps") | not) | .["title-preset"] // "future-metal"' "$metadata_file"
  )"

  steps_intro="$(
    STEPS_NUMBER="$tutorial_steps_number" \
      yq eval -r 'select((.steps | tostring) == env(STEPS_NUMBER)) | .intro // ""' "$metadata_file"
  )"
  tutorial_subtitle="$(
    STEPS_NUMBER="$tutorial_steps_number" \
      yq eval -r 'select((.steps | tostring) == env(STEPS_NUMBER)) | .title // ""' "$metadata_file"
  )"
  if [ -z "$tutorial_subtitle" ]; then
    tutorial_subtitle="Steps $tutorial_steps_number"
  fi

  while IFS= read -r block_id; do
    [ -z "$block_id" ] && continue

    block_position="$(
      STEPS_NUMBER="$tutorial_steps_number" BLOCK_ID="$block_id" \
        yq eval -r 'select((.steps | tostring) == env(STEPS_NUMBER)) | .blocks[env(BLOCK_ID)].position // "before"' "$metadata_file"
    )"
    block_content="$(
      STEPS_NUMBER="$tutorial_steps_number" BLOCK_ID="$block_id" \
        yq eval -r 'select((.steps | tostring) == env(STEPS_NUMBER)) | .blocks[env(BLOCK_ID)].content // ""' "$metadata_file"
    )"

    metadata_position_by_id["$block_id"]="$block_position"
    metadata_content_by_id["$block_id"]="$block_content"
  done < <(
    STEPS_NUMBER="$tutorial_steps_number" \
      yq eval -r 'select((.steps | tostring) == env(STEPS_NUMBER)) | (.blocks // {} | keys | .[])' "$metadata_file"
  )
}

show_steps_metadata() {
  if [ -z "$steps_intro" ]; then
    return
  fi
  clear
  print_figlet_centered "Steps $tutorial_steps_number"
  echo
  render_metadata "$steps_intro"
  pause
}

message=""
commands=()
step_id=""
heredoc_delim=""
current_cmd=""
heredoc_regex="<<'([A-Za-z_][A-Za-z0-9_]*)'$"
id_regex="^#[[:space:]]*id:[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*$"
declare -a step_messages
declare -a step_metadata_positions
declare -a step_metadata_contents
declare -a step_command_files
steps_count=0
steps_executed=0
steps_begin_ran=0
steps_end_ran=0
has_end_hook=0
parse_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-tape-parse.XXXXXX")"
cache_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-tape-cache.XXXXXX")"

run_optional_steps_script() {
  local script_path="$1"

  if [ ! -f "$script_path" ]; then
    return
  fi

  bash "$script_path"
}

cleanup_play() {
  local exit_status="$1"

  trap - EXIT
  rm -rf "$parse_tmp_dir" "$cache_tmp_dir"
  exit "$exit_status"
}
trap 'cleanup_play $?' EXIT

command_is_complete() {
  local snippet="$1"
  local err

  if err="$(bash -n <<<"$snippet" 2>&1)"; then
    return 0
  fi

  if [[ "$err" == *"unexpected end of file"* ]] || [[ "$err" == *"here-document"* && "$err" == *"wanted"* ]]; then
    return 1
  fi

  echo "Invalid shell syntax in steps file: $steps_file" >&2
  echo "$err" >&2
  exit 1
}

load_metadata
if [ -f "$steps_end_script" ]; then
  has_end_hook=1
fi
log_bash_tape_event \
  "$tape_log_file" \
  "play_started" \
  "steps_dir" "$steps_dir" \
  "steps_number" "$tutorial_steps_number" \
  "steps_file" "$steps_file_name" \
  "workdir" "$run_workdir" \
  "state" "$(bash_tape_detect_state "$tape_log_file")"
if [ -f "$steps_begin_script" ]; then
  log_bash_tape_event "$tape_log_file" "begin_hook_started" "script" "$steps_begin_script"
fi
run_optional_steps_script "$steps_begin_script"
if [ -f "$steps_begin_script" ]; then
  log_bash_tape_event "$tape_log_file" "begin_hook_finished" "script" "$steps_begin_script"
fi
steps_begin_ran=1

eject_tape_and_exit() {
  log_bash_tape_event "$tape_log_file" "eject_requested" "steps_number" "$tutorial_steps_number" "steps_file" "$steps_file_name"
  if [ "$steps_begin_ran" = "1" ] && [ "$steps_end_ran" = "0" ] && [ "$has_end_hook" = "1" ]; then
    show_ejecting_message "$has_end_hook"
    steps_end_ran=1
    log_bash_tape_event "$tape_log_file" "end_hook_started" "script" "$steps_end_script"
    run_optional_steps_script "$steps_end_script"
    log_bash_tape_event "$tape_log_file" "end_hook_finished" "script" "$steps_end_script"
  elif [ "$has_end_hook" = "0" ]; then
    show_ejecting_message "$has_end_hook"
  fi
  log_bash_tape_event "$tape_log_file" "ejected" "steps_number" "$tutorial_steps_number" "steps_file" "$steps_file_name"
  clear
  exit 0
}

quit_tape_and_exit() {
  local has_remaining_steps="${1:-0}"
  local stop_location="${2:-step}"

  if [ "$steps_begin_ran" = "1" ] && [ "$steps_end_ran" = "0" ] && [ "$has_end_hook" = "1" ]; then
    show_unejected_warning "$has_remaining_steps"
  fi
  log_bash_tape_event \
    "$tape_log_file" \
    "stopped" \
    "steps_number" "$tutorial_steps_number" \
    "steps_file" "$steps_file_name" \
    "location" "$stop_location" \
    "remaining_steps" "$has_remaining_steps"
  clear
  exit 0
}

flush_step() {
  if [ -n "$message" ] && [ "${#commands[@]}" -gt 0 ]; then
    local step_metadata_position=""
    local step_metadata_content=""
    local cmd_file
    local cmd

    if [ -n "$step_id" ]; then
      step_metadata_position="${metadata_position_by_id[$step_id]:-}"
      step_metadata_content="${metadata_content_by_id[$step_id]:-}"
    fi

    cmd_file="${parse_tmp_dir}/step_${steps_count}.cmds"
    : > "$cmd_file"
    for cmd in "${commands[@]}"; do
      printf '%s\0' "$cmd" >> "$cmd_file"
    done

    step_messages+=("$message")
    step_metadata_positions+=("$step_metadata_position")
    step_metadata_contents+=("$step_metadata_content")
    step_command_files+=("$cmd_file")
    steps_count=$((steps_count + 1))
  fi
  message=""
  step_id=""
  commands=()
}

while IFS= read -r line <&3 || [ -n "$line" ]; do
  if [ -n "$heredoc_delim" ]; then
    current_cmd+=$'\n'"$line"
    if [ "$line" = "$heredoc_delim" ]; then
      commands+=("$current_cmd")
      current_cmd=""
      heredoc_delim=""
    fi
    continue
  fi

  if [[ "$line" =~ ^#! ]]; then
    continue
  fi

  if [ -z "$line" ] && [ -z "$current_cmd" ]; then
    flush_step
    continue
  fi

  if [ -z "$current_cmd" ] && [[ "$line" =~ ^# ]]; then
    if [[ "$line" =~ $id_regex ]]; then
      step_id="${BASH_REMATCH[1]}"
      continue
    fi
    if [ -z "$message" ]; then
      message="${line#\# }"
    fi
    continue
  fi

  if [ -n "$current_cmd" ]; then
    current_cmd+=$'\n'"$line"
  else
    current_cmd="$line"
  fi

  if [[ "$line" =~ $heredoc_regex ]]; then
    heredoc_delim="${BASH_REMATCH[1]}"
    continue
  fi

  if command_is_complete "$current_cmd"; then
    commands+=("$current_cmd")
    current_cmd=""
  fi
done 3< "$steps_file"

if [ -n "$heredoc_delim" ]; then
  echo "Unterminated heredoc in steps file: $steps_file (expected '$heredoc_delim')" >&2
  exit 1
fi

if [ -n "$current_cmd" ]; then
  if command_is_complete "$current_cmd"; then
    commands+=("$current_cmd")
  else
    echo "Incomplete command block at end of steps file: $steps_file" >&2
    exit 1
  fi
fi

flush_step

if [ "$steps_count" -eq 0 ]; then
  echo "No steps found in $steps_file" >&2
  exit 1
fi

current_index=0
has_intro=0
if [ -n "$steps_intro" ]; then
  has_intro=1
fi
in_intro="$has_intro"
in_done=0
while true; do
  if [ "$in_done" = "1" ]; then
    show_done_screen NAV_ACTION 1 "$tutorial_steps_number" "$steps_executed" "$global_title" "$global_github" "$tutorial_title_preset"
    case "$NAV_ACTION" in
      eject)
        eject_tape_and_exit
        ;;
      back)
        log_bash_tape_event "$tape_log_file" "back" "steps_file" "$steps_file_name" "from" "done" "to" "step:$steps_count"
        in_done=0
        current_index=$((steps_count - 1))
        ;;
      quit)
        quit_tape_and_exit 0 "done"
        ;;
    esac
    continue
  fi

  if [ "$in_intro" = "1" ]; then
    intro_cache_file="${cache_tmp_dir}/intro.log"
    if [ -f "$intro_cache_file" ] && [ -z "$global_title" ]; then
      clear
      cat "$intro_cache_file"
    else
      if [ -z "$global_title" ]; then
        {
          clear
          print_figlet_centered "Steps $tutorial_steps_number"
          echo
          render_metadata "$steps_intro"
        } > >(tee "$intro_cache_file")
      fi
    fi

    show_intro_screen NAV_ACTION 1 "$tutorial_steps_number" "$global_title" "$tutorial_subtitle" "$tutorial_title_preset" "$global_github" "$steps_intro"
    case "$NAV_ACTION" in
      eject)
        eject_tape_and_exit
        ;;
      next)
        log_bash_tape_event "$tape_log_file" "forward" "steps_file" "$steps_file_name" "from" "intro" "to" "step:1"
        in_intro=0
        ;;
      quit)
        quit_tape_and_exit 1 "intro"
        ;;
    esac
    continue
  fi

  step_number=$((current_index + 1))
  cache_file="${cache_tmp_dir}/step_${step_number}.log"

  if [ -f "$cache_file" ]; then
    clear
    cat "$cache_file"
  else
    mapfile -d '' -t step_cmds < "${step_command_files[$current_index]}"
    run_step \
      "$step_number" \
      "${step_messages[$current_index]}" \
      "${step_metadata_positions[$current_index]}" \
      "${step_metadata_contents[$current_index]}" \
      "${step_cmds[@]}" > >(tee "$cache_file")
    steps_executed=$((steps_executed + 1))
    log_bash_tape_event "$tape_log_file" "step_executed" "steps_file" "$steps_file_name" "step" "$step_number" "message" "${step_messages[$current_index]}"
  fi

  allow_intro_back=0
  if [ "$has_intro" = "1" ] && [ "$current_index" -eq 0 ]; then
    allow_intro_back=1
  fi

  prompt_step_navigation "$step_number" "$steps_count" NAV_ACTION "$allow_intro_back" 1
  case "$NAV_ACTION" in
    next)
      if [ "$current_index" -eq $((steps_count - 1)) ]; then
        log_bash_tape_event "$tape_log_file" "forward" "steps_file" "$steps_file_name" "from" "step:$step_number" "to" "done"
        in_done=1
        continue
      fi
      log_bash_tape_event "$tape_log_file" "forward" "steps_file" "$steps_file_name" "from" "step:$step_number" "to" "step:$((step_number + 1))"
      current_index=$((current_index + 1))
      ;;
    back)
      if [ "$current_index" -gt 0 ]; then
        log_bash_tape_event "$tape_log_file" "back" "steps_file" "$steps_file_name" "from" "step:$step_number" "to" "step:$current_index"
        current_index=$((current_index - 1))
      fi
      ;;
    intro)
      log_bash_tape_event "$tape_log_file" "back" "steps_file" "$steps_file_name" "from" "step:$step_number" "to" "intro"
      in_intro=1
      ;;
    eject)
      eject_tape_and_exit
      ;;
    quit)
      if [ "$current_index" -lt $((steps_count - 1)) ]; then
        quit_tape_and_exit 1 "step:$step_number"
      else
        quit_tape_and_exit 0 "step:$step_number"
      fi
      ;;
  esac
done
