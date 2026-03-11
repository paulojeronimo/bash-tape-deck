#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
start_time="$(date +%s)"
passed=0
failed=0

tests=(
  "$script_dir/integration/test-devcontainer-config.sh"
  "$script_dir/integration/test-docker-wrapper.sh"
)

for test_script in "${tests[@]}"; do
  test_name="$(basename "$test_script")"
  printf '\n==> %s\n' "$test_name"
  if bash "$test_script"; then
    passed=$((passed + 1))
    printf 'PASS %s\n' "$test_name"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$test_name" >&2
    break
  fi
done

end_time="$(date +%s)"
duration=$((end_time - start_time))

printf '\nSummary\n'
printf '  Passed: %s\n' "$passed"
printf '  Failed: %s\n' "$failed"
printf '  Duration: %ss\n' "$duration"

if [ "$failed" -eq 0 ]; then
  printf 'All tests passed\n'
  exit 0
fi

exit 1
