#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
output_txt="$script_dir/files.txt"
output_adoc="$script_dir/files.adoc"

if ! command -v git >/dev/null 2>&1; then
  echo "git command not found" >&2
  exit 1
fi

if ! git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Repository root not detected: $repo_root" >&2
  exit 1
fi

declare -A descriptions=()
while IFS=$'\t' read -r path description; do
  [ -n "$path" ] || continue
  descriptions["$path"]="$description"
done <<'MAP'
.devcontainer	Development Container assets for local and cloud workspaces.
.devcontainer/Dockerfile	Dev Container image definition for local and Codespaces development.
.devcontainer/devcontainer.json	Dev Container configuration consumed by supported editors and the devcontainer CLI.
.devcontainer/post-start.sh	Post-start hook that prepares the workspace defaults inside the Dev Container.
.gitignore	Root ignore rules for generated and local-only files.
AGENTS.md	Repository-specific agent rules for code generation, testing, and commits.
LICENSE	MIT license for the project.
README.adoc	Main project document assembled from the section files in docs/.
diagrams	PlantUML source diagrams used by the documentation.
diagrams/architecture-components.puml	PlantUML diagram describing the main Bash Tape components.
diagrams/architecture-docker.puml	PlantUML diagram describing the Docker-oriented runtime flow.
diagrams/architecture-playback-flow.puml	PlantUML diagram describing playback behavior and navigation.
diagrams/architecture-workdir.puml	PlantUML diagram describing workspace and state directories.
docker	Docker runtime assets and wrapper scripts.
docker/Dockerfile	Runtime Docker image definition used by the Bash Tape engine.
docker/bin	Container entrypoint helpers.
docker/bin/bash-tape	Container entrypoint that dispatches to play and rewind.
docker/build.sh	Wrapper that builds the engine image and sample-specific images.
docker/common.sh	Shared functions and defaults used by the Docker wrapper scripts.
docker/run.sh	Wrapper that runs tapes and sample-specific container commands.
docs	AsciiDoc source files that compose the main README.
docs/_	Shared documentation fragments.
docs/_/attributes.adoc	Shared AsciiDoc attributes reused across the documentation set.
docs/architecture.adoc	Architecture section of the README.
docs/author.adoc	Author section of the README.
docs/current-capabilities.adoc	Current capabilities section of the README.
docs/current-parser-limitations.adoc	Documentation of the current parser constraints and tradeoffs.
docs/development-model.adoc	Development model section of the README.
docs/files.adoc	Literal wrapper that includes docs/files.txt in the README.
docs/files.adoc.sh	Generator for docs/files.txt and docs/files.adoc.
docs/files.txt	Generated two-column file inventory rendered inside docs/files.adoc.
docs/license.adoc	License section of the README.
docs/navigation.adoc	Navigation section of the README.
docs/next-steps.adoc	Planned work and roadmap section of the README.
docs/references.adoc	Reference links section of the README.
docs/requirements.adoc	Requirements section of the README.
docs/step-file-format.adoc	Documentation for the tape step file format.
docs/tests.adoc	Testing section of the README.
docs/usage.adoc	Usage section of the README.
docs/what-this-project-does.adoc	Project overview section of the README.
functions.sh	Shared shell functions for playback, rendering, logging, and cassette art.
images	Image assets referenced by the documentation.
images/art.png	Rendered artwork displayed at the top of the README.
play.sh	Interactive tape player for local execution.
rewind.sh	Tape rewind dispatcher for local execution.
samples	Public sample tapes shipped with the project.
samples/.gitignore	Ignore rules for generated content under public samples.
samples/fibonacci	Sample tutorial that teaches Bash through Fibonacci implementations.
samples/fibonacci/.gitignore	Ignore rules for generated files in the Fibonacci sample.
samples/fibonacci/docker.extend.sh	Sample-specific Docker extensions for the Fibonacci tape.
samples/fibonacci/steps.1.rewind.sh	Rewind logic for the first Fibonacci tape.
samples/fibonacci/steps.1.sh	First Fibonacci tape.
samples/fibonacci/steps.2.rewind.sh	Rewind logic for the second Fibonacci tape.
samples/fibonacci/steps.2.sh	Second Fibonacci tape.
samples/fibonacci/steps.3.rewind.sh	Rewind logic for the third Fibonacci tape.
samples/fibonacci/steps.3.sh	Third Fibonacci tape.
samples/fibonacci/steps.yaml	Metadata and narration content for the Fibonacci tapes.
tests	Automated test suite and fixtures.
tests/fixtures	Static test fixtures used by integration tests.
tests/fixtures/docker-sample	Fixture tape used to exercise the Docker wrapper end to end.
tests/fixtures/docker-sample/steps.1.sh	Fixture tape used by Docker integration tests.
tests/fixtures/docker-sample/steps.begin.sh	Fixture initialization hook used by Docker integration tests.
tests/fixtures/docker-sample/steps.end.sh	Fixture cleanup hook used by Docker integration tests.
tests/fixtures/docker-sample/steps.yaml	Fixture metadata used by Docker integration tests.
tests/integration	Integration tests that validate the main user flows.
tests/integration/test-devcontainer-config.sh	Integration test that validates the Dev Container configuration files.
tests/integration/test-docker-wrapper.sh	Integration test that exercises the Docker wrappers end to end.
tests/run.sh	Test runner that executes the current automated test suite.
MAP

is_public_path() {
  local path="$1"
  [[ ! "$path" =~ (^|/)\.private($|/) ]]
}

add_ancestors() {
  local path="$1"
  local parent

  parent="${path%/*}"
  while [ "$parent" != "$path" ] && [ -n "$parent" ] && [ "$parent" != "." ]; do
    printf '%s\n' "$parent"
    path="$parent"
    parent="${path%/*}"
  done
}

node_depth() {
  local path="$1"
  awk -F/ '{print NF-1}' <<<"$path"
}

node_parent() {
  local path="$1"
  if [[ "$path" != */* ]]; then
    printf ''
    return
  fi
  printf '%s' "${path%/*}"
}

node_name() {
  local path="$1"
  printf '%s' "${path##*/}"
}

render_tree_label() {
  local path="$1"
  local depth parent prefix="" ancestor last_flag
  local -a parts=()

  IFS=/ read -r -a parts <<<"$path"
  depth=${#parts[@]}

  if [ "$depth" -eq 1 ]; then
    printf '%s' "${parts[0]}"
    return
  fi

  parent=""
  for ((i = 0; i < depth - 1; i++)); do
    if [ -z "$parent" ]; then
      ancestor="${parts[$i]}"
    else
      ancestor="$parent/${parts[$i]}"
    fi

    if [ $i -lt $((depth - 2)) ]; then
      last_flag="${is_last_sibling[$ancestor]}"
      if [ "$last_flag" = "1" ]; then
        prefix+="    "
      else
        prefix+="|   "
      fi
    fi

    parent="$ancestor"
  done

  last_flag="${is_last_sibling[$path]}"
  if [ "$last_flag" = "1" ]; then
    prefix+="\\-- "
  else
    prefix+="+-- "
  fi

  printf '%s%s' "$prefix" "$(node_name "$path")"
}

declare -A node_kinds=()
declare -A is_last_sibling=()

mapfile -t tracked_files < <(git -C "$repo_root" ls-files | sort)
tracked_files+=("docs/files.adoc.sh" "docs/files.txt")
mapfile -t tracked_files < <(printf '%s\n' "${tracked_files[@]}" | sort -u)

for path in "${tracked_files[@]}"; do
  is_public_path "$path" || continue
  node_kinds["$path"]="file"
  while IFS= read -r ancestor; do
    [ -n "$ancestor" ] || continue
    is_public_path "$ancestor" || continue
    node_kinds["$ancestor"]="dir"
  done < <(add_ancestors "$path")
done

mapfile -t nodes < <(printf '%s\n' "${!node_kinds[@]}" | sort)

missing=()
for path in "${nodes[@]}"; do
  if [ -z "${descriptions[$path]:-}" ]; then
    missing+=("$path")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Missing file descriptions in docs/files.adoc.sh:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

for index in "${!nodes[@]}"; do
  path="${nodes[$index]}"
  parent="$(node_parent "$path")"
  depth="$(node_depth "$path")"
  is_last=1

  for ((next_index = index + 1; next_index < ${#nodes[@]}; next_index++)); do
    next_path="${nodes[$next_index]}"
    next_depth="$(node_depth "$next_path")"
    if [ "$next_depth" -le "$depth" ]; then
      if [ "$(node_parent "$next_path")" = "$parent" ]; then
        is_last=0
      fi
      break
    fi
  done

  is_last_sibling["$path"]="$is_last"
done

declare -A tree_labels=()
max_tree_width=4

for path in "${nodes[@]}"; do
  tree_labels["$path"]="$(render_tree_label "$path")"
  if [ "${#tree_labels[$path]}" -gt "$max_tree_width" ]; then
    max_tree_width="${#tree_labels[$path]}"
  fi
done

{
  printf "%-${max_tree_width}s  %s\n" "Tree" "Description"
  printf "%-${max_tree_width}s  %s\n" "$(printf '%*s' "$max_tree_width" '' | tr ' ' '-')" "-----------"
  for path in "${nodes[@]}"; do
    printf "%-${max_tree_width}s  %s\n" "${tree_labels[$path]}" "${descriptions[$path]}"
  done
} > "$output_txt"

cat > "$output_adoc" <<'EOF_ADOC'
= Files

This section is generated by `docs/files.adoc.sh`.

[source,text]
----
include::files.txt[]
----
EOF_ADOC
