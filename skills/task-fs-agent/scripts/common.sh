#!/usr/bin/env bash
set -euo pipefail

skill_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

tasks_dir() {
  printf '%s/tasks' "$(repo_root)"
}

ensure_tasks_dirs() {
  mkdir -p "$(tasks_dir)"/{01-inbox,02-doing,03-blocked,04-review,05-done}
}

slugify() {
  local input="${*:-}"
  local slug
  slug="$input"
  slug="$(printf '%s' "$slug" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$slug")"
  printf '%s' "$slug" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

replace_attr() {
  local file="$1" key="$2" value="$3"
  local tmp
  tmp="$(mktemp)"
  sed -E "s#^:${key}:.*#:${key}: ${value}#" "$file" > "$tmp"
  mv "$tmp" "$file"
}

append_note_to_section() {
  local file="$1" section="$2" note="$3"
  local header="== $section"
  local tmp line i
  local -a lines

  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done < "$file"

  local total=${#lines[@]}
  local header_idx=-1 section_end=$total

  for (( i=0; i<total; i++ )); do
    if [[ "${lines[$i]}" == "$header" ]]; then
      header_idx=$i
    elif (( header_idx >= 0 )) && [[ "${lines[$i]}" =~ ^== ]]; then
      section_end=$i
      break
    fi
  done

  tmp="$(mktemp)"

  if (( header_idx < 0 )); then
    cp "$file" "$tmp"
    printf '\n== %s\n\n- %s\n' "$section" "$note" >> "$tmp"
  else
    local insert_after=$header_idx
    for (( i=header_idx+1; i<section_end; i++ )); do
      [[ -n "${lines[$i]}" ]] && insert_after=$i
    done
    for (( i=0; i<total; i++ )); do
      printf '%s\n' "${lines[$i]}" >> "$tmp"
      [[ $i -eq $insert_after ]] && printf '%s\n' "- $note" >> "$tmp"
    done
  fi

  mv "$tmp" "$file"
}

move_state() {
  local file="$1" to_dir="$2" status="$3"
  [[ -f "$file" ]] || { echo "error: file not found: $file" >&2; exit 1; }
  local current_dir parent base target_dir target_file
  current_dir="$(dirname "$file")"
  parent="$(dirname "$current_dir")"
  base="$(basename "$file")"
  target_dir="$parent/$to_dir"
  mkdir -p "$target_dir"
  replace_attr "$file" status "$status"
  target_file="$target_dir/$base"
  mv "$file" "$target_file"
  printf '%s\n' "$target_file"
}
