#!/usr/bin/env bash

# Validate prerequisite state from steps.2.sh
# id: step3-validate-state
if [ ! -x fibonacci-lab/src/fib-recursive.sh ] || [ ! -x fibonacci-lab/src/fib-memo.sh ]; then
  echo "Inconsistent state"
  exit 1
fi

# Create the shared Fibonacci library foundation
# id: step3-create-library-foundation
cat > fibonacci-lab/src/fibonacci.lib.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

declare -Ag FIB_MEMO_CACHE
FIB_MEMO_CACHE[0]=0
FIB_MEMO_CACHE[1]=1

fib_validate_input() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]]
}
SCRIPT

# Add the iterative implementation to the shared library
# id: step3-create-library-iterative
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fibonacci.lib.sh <<'SCRIPT'
fib_iterative() {
  local n="$1"
  local a=0
  local b=1
  local i

  if [ "$n" -eq 0 ]; then
    echo 0
    return
  fi

  for ((i = 1; i < n; i++)); do
    local next=$((a + b))
    a=$b
    b=$next
  done

  echo "$b"
}
SCRIPT

# Add the recursive implementation to the shared library
# id: step3-create-library-recursive
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fibonacci.lib.sh <<'SCRIPT'
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

# Add the memoized implementation to the shared library
# id: step3-create-library-memoized
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fibonacci.lib.sh <<'SCRIPT'
fib_memoized() {
  local n="$1"
  if [ -n "${FIB_MEMO_CACHE[$n]:-}" ]; then
    echo "${FIB_MEMO_CACHE[$n]}"
    return
  fi

  local a b value
  a="$(fib_memoized $((n - 1)))"
  b="$(fib_memoized $((n - 2)))"
  value=$((a + b))
  FIB_MEMO_CACHE[$n]="$value"
  echo "$value"
}
SCRIPT
chmod +x fibonacci-lab/src/fibonacci.lib.sh

# Create the CLI header and usage output
# id: step3-create-cli-header
cat > fibonacci-lab/src/fibonacci-cli.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/fibonacci.lib.sh"

usage() {
  cat <<'EOF_USAGE'
Usage:
  ./fibonacci-lab/src/fibonacci-cli.sh nth <n> [iterative|recursive|memoized]
  ./fibonacci-lab/src/fibonacci-cli.sh sequence <n> [iterative|recursive|memoized]
EOF_USAGE
}
SCRIPT

# Add CLI argument parsing and implementation dispatch
# id: step3-create-cli-dispatch
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fibonacci-cli.sh <<'SCRIPT'
mode="${1:-}"
n="${2:-}"
impl="${3:-iterative}"

if [ -z "$mode" ] || [ -z "$n" ] || ! fib_validate_input "$n"; then
  usage
  exit 1
fi

calc_nth() {
  local idx="$1"
  case "$impl" in
    iterative) fib_iterative "$idx" ;;
    recursive) fib_recursive "$idx" ;;
    memoized) fib_memoized "$idx" ;;
    *) echo "Unknown implementation: $impl" >&2; exit 1 ;;
  esac
}
SCRIPT

# Add CLI mode execution for nth and sequence
# id: step3-create-cli-modes
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fibonacci-cli.sh <<'SCRIPT'
case "$mode" in
  nth)
    calc_nth "$n"
    ;;
  sequence)
    out=""
    for ((i = 0; i < n; i++)); do
      value="$(calc_nth "$i")"
      if [ -z "$out" ]; then
        out="$value"
      else
        out+=" $value"
      fi
    done
    echo "$out"
    ;;
  *)
    usage
    exit 1
    ;;
esac
SCRIPT
chmod +x fibonacci-lab/src/fibonacci-cli.sh

# Run CLI examples with different implementations
# id: step3-run-cli-examples
{
  echo "nth(10) iterative: $(./fibonacci-lab/src/fibonacci-cli.sh nth 10 iterative)"
  echo "nth(10) memoized:  $(./fibonacci-lab/src/fibonacci-cli.sh nth 10 memoized)"
  echo "sequence(10):      $(./fibonacci-lab/src/fibonacci-cli.sh sequence 10 iterative)"
} | tee fibonacci-lab/artifacts/step3-cli.txt

# Create a comparison table for multiple inputs and implementations
# id: step3-create-comparison-table
{
  printf '%-4s %-10s %-10s %-10s\n' "n" "iterative" "recursive" "memoized"
  printf '%-4s %-10s %-10s %-10s\n' "--" "----------" "----------" "----------"
  for n in 0 1 2 3 5 8 10; do
    i_val="$(./fibonacci-lab/src/fibonacci-cli.sh nth "$n" iterative)"
    r_val="$(./fibonacci-lab/src/fibonacci-cli.sh nth "$n" recursive)"
    m_val="$(./fibonacci-lab/src/fibonacci-cli.sh nth "$n" memoized)"
    printf '%-4s %-10s %-10s %-10s\n' "$n" "$i_val" "$r_val" "$m_val"
  done
} | tee fibonacci-lab/artifacts/step3-table.txt

# Add the step 3 assertion helper
# id: step3-create-tests-helper
cat > fibonacci-lab/tests/test-step3.sh <<'TEST'
#!/usr/bin/env bash
set -euo pipefail

assert_eq() {
  local expected="$1"
  local actual="$2"
  local context="$3"

  if [ "$expected" != "$actual" ]; then
    echo "Assertion failed: $context" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}
TEST

# Add cross-implementation assertions for step 3
# id: step3-create-tests-assertions
# shellcheck disable=SC2129
cat >> fibonacci-lab/tests/test-step3.sh <<'TEST'
for n in 0 1 2 3 5 8 10; do
  iterative="$(./fibonacci-lab/src/fibonacci-cli.sh nth "$n" iterative)"
  recursive="$(./fibonacci-lab/src/fibonacci-cli.sh nth "$n" recursive)"
  memoized="$(./fibonacci-lab/src/fibonacci-cli.sh nth "$n" memoized)"

  assert_eq "$iterative" "$recursive" "iterative vs recursive for n=$n"
  assert_eq "$iterative" "$memoized" "iterative vs memoized for n=$n"
done

echo "step3 test suite passed"
TEST
chmod +x fibonacci-lab/tests/test-step3.sh

# Run final tests and write advanced notes
# id: step3-run-tests-and-notes
./fibonacci-lab/tests/test-step3.sh

cat > fibonacci-lab/docs/step3-notes.md <<'EOF_NOTES'
# Step 3 Notes

Advanced concepts introduced:

- Shared library API (`fibonacci.lib.sh`).
- Multi-mode CLI (`nth` and `sequence`).
- Cross-implementation verification tests.
- Table-oriented output for quick comparisons.

This structure is ready for packaging and reuse.
EOF_NOTES


tree -a fibonacci-lab
