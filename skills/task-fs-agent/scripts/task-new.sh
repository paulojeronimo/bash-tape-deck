#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'USAGE'
usage:
  task-new.sh <type> "<title>" [priority]

examples:
  task-new.sh task "Add login page"
  task-new.sh bugfix "Fix SSH key validation" high
  task-new.sh research "Evaluate local LLM stack" medium
USAGE
}

TYPE="${1:-}"
TITLE="${2:-}"
PRIORITY="${3:-medium}"
[[ -n "$TYPE" && -n "$TITLE" ]] || { usage; exit 1; }
case "$TYPE" in task|bugfix|research|docs|refactor|ops) ;; *) echo "error: invalid type: $TYPE" >&2; exit 1;; esac
case "$PRIORITY" in low|medium|high) ;; *) echo "error: invalid priority: $PRIORITY" >&2; exit 1;; esac

ensure_tasks_dirs
SKILL_ROOT="$(skill_root)"
TEMPLATES_DIR="$SKILL_ROOT/assets/task-templates"
INBOX_DIR="$(tasks_dir)/01-inbox"
SLUG="$(slugify "$TITLE")"
STAMP="$(date -u +%Y%m%d-%H%M)"
TASK_ID="${STAMP}--${TYPE}--${SLUG}"
CREATED_AT="$(date -u '+%Y-%m-%d %H:%M UTC')"
FILE="$INBOX_DIR/${TASK_ID}.adoc"

case "$TYPE" in
  task|docs|refactor|ops) TEMPLATE="$TEMPLATES_DIR/task.adoc" ;;
  bugfix) TEMPLATE="$TEMPLATES_DIR/bugfix.adoc" ;;
  research) TEMPLATE="$TEMPLATES_DIR/research.adoc" ;;
esac
[[ -f "$TEMPLATE" ]] || { echo "error: template not found: $TEMPLATE" >&2; exit 1; }

TEMPLATE_CONTENT="$(<"$TEMPLATE")"
TEMPLATE_CONTENT="${TEMPLATE_CONTENT//\{\{TITLE\}\}/$TITLE}"
TEMPLATE_CONTENT="${TEMPLATE_CONTENT//\{\{TASK_ID\}\}/$TASK_ID}"
TEMPLATE_CONTENT="${TEMPLATE_CONTENT//\{\{CREATED_AT\}\}/$CREATED_AT}"
TEMPLATE_CONTENT="${TEMPLATE_CONTENT//\{\{OBJECTIVE\}\}/$TITLE}"
TEMPLATE_CONTENT="${TEMPLATE_CONTENT//\{\{CONTEXT\}\}/Describe relevant context here.}"
TEMPLATE_CONTENT="${TEMPLATE_CONTENT//:priority: medium/:priority: $PRIORITY}"

printf '%s' "$TEMPLATE_CONTENT" > "$FILE"
replace_attr "$FILE" type "$TYPE"
printf '%s\n' "$FILE"
