#!/usr/bin/env bash

# Validate prerequisite state from steps.1.sh
# id: step2-validate-state
if [ ! -x fibonacci-lab/src/fib.sh ] || [ ! -x fibonacci-lab/tests/test-step1.sh ]; then
  echo "Inconsistent state"
  exit 1
fi

# Create the recursive Fibonacci function
# id: step2-create-recursive-script-function
cat > fibonacci-lab/src/fib-recursive.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

fib_recursive() {
  local n="$1"
  if [ "$n" -le 1 ]; then
    echo "$n"
    return
  fi
  local a b
  a="$(fib_recursive $((n - 1)))"
  b="$(fib_recursive $((n - 2)))"
  echo $((a + b))
}
SCRIPT

# Append argument parsing and recursive entry point
# id: step2-create-recursive-script-entrypoint
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fib-recursive.sh <<'SCRIPT'

n="${1:-10}"
if ! [[ "$n" =~ ^[0-9]+$ ]]; then
  echo "Usage: ./src/fib-recursive.sh [non-negative-integer]" >&2
  exit 1
fi

fib_recursive "$n"
SCRIPT
chmod +x fibonacci-lab/src/fib-recursive.sh

# Execute recursive examples for small values
# id: step2-run-recursive-examples
for n in 0 1 5 10; do
  printf 'fib_recursive(%s) = %s\n' "$n" "$(./fibonacci-lab/src/fib-recursive.sh "$n")"
done | tee fibonacci-lab/artifacts/step2-recursive.txt

# Create the memoization cache and recursive memoized function
# id: step2-create-memoized-script-function
cat > fibonacci-lab/src/fib-memo.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

declare -A memo
memo[0]=0
memo[1]=1

fib_memo() {
  local n="$1"
  if [ -n "${memo[$n]:-}" ]; then
    echo "${memo[$n]}"
    return
  fi

  local a b value
  a="$(fib_memo $((n - 1)))"
SCRIPT

# Append memoized result handling and command entry point
# id: step2-create-memoized-script-entrypoint
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fib-memo.sh <<'SCRIPT'
  b="$(fib_memo $((n - 2)))"
  value=$((a + b))
  memo[$n]="$value"
  echo "$value"
}

n="${1:-10}"
if ! [[ "$n" =~ ^[0-9]+$ ]]; then
  echo "Usage: ./src/fib-memo.sh [non-negative-integer]" >&2
  exit 1
fi

fib_memo "$n"
SCRIPT
chmod +x fibonacci-lab/src/fib-memo.sh

# Build and run a benchmark between recursive and memoized approaches
# id: step2-run-benchmark
cat > fibonacci-lab/src/benchmark-step2.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

target="${1:-30}"

start_recursive="$(date +%s%N)"
recursive_result="$(./fibonacci-lab/src/fib-recursive.sh "$target")"
end_recursive="$(date +%s%N)"

start_memo="$(date +%s%N)"
memo_result="$(./fibonacci-lab/src/fib-memo.sh "$target")"
end_memo="$(date +%s%N)"

recursive_ms=$(((end_recursive - start_recursive) / 1000000))
memo_ms=$(((end_memo - start_memo) / 1000000))

printf 'target=%s\n' "$target"
printf 'recursive=%s (%sms)\n' "$recursive_result" "$recursive_ms"
printf 'memoized=%s (%sms)\n' "$memo_result" "$memo_ms"
SCRIPT
chmod +x fibonacci-lab/src/benchmark-step2.sh

./fibonacci-lab/src/benchmark-step2.sh 15 | tee fibonacci-lab/artifacts/step2-benchmark.txt

# Document complexity trade-offs from step 2
# id: step2-write-notes
cat > fibonacci-lab/docs/step2-notes.md <<'EOF_NOTES'
# Step 2 Notes

Step 2 introduces two implementations:

- Recursive version: easy to read, expensive for larger inputs.
- Memoized version: stores previous values and avoids repeated work.

## Observation
For the same `n`, memoization should be significantly faster than plain recursion.
EOF_NOTES

# Display files created in step 2
# id: step2-show-layout
ls -la fibonacci-lab/src
ls -la fibonacci-lab/artifacts
