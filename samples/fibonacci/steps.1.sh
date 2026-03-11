#!/usr/bin/env bash

# Prepare the Fibonacci lab workspace
# id: step1-prepare-workspace
mkdir -p fibonacci-lab/src fibonacci-lab/tests fibonacci-lab/docs fibonacci-lab/artifacts

# Create the iterative Fibonacci script header and input validation
# id: step1-create-iterative-script-header
cat > fibonacci-lab/src/fib.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

limit="${1:-10}"

if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
  echo "Usage: ./src/fib.sh [non-negative-integer]" >&2
  exit 1
fi

if [ "$limit" -eq 0 ]; then
  echo "0"
  exit 0
fi
SCRIPT

# Append the iterative loop and output logic
# id: step1-create-iterative-script-body
# shellcheck disable=SC2129
cat >> fibonacci-lab/src/fib.sh <<'SCRIPT'

a=0
b=1
sequence="0"

for ((i = 1; i < limit; i++)); do
  sequence+=" $b"
  next=$((a + b))
  a=$b
  b=$next
done

echo "$sequence"
SCRIPT
chmod +x fibonacci-lab/src/fib.sh

# Run the iterative script and capture output
# id: step1-run-iterative-script
./fibonacci-lab/src/fib.sh 12 | tee fibonacci-lab/artifacts/step1-seq.txt

# Document what the first script is doing
# id: step1-write-notes
cat > fibonacci-lab/docs/step1-notes.md <<'EOF_NOTES'
# Step 1 Notes

This first version uses an iterative loop.

## Key ideas
- Keep two moving values (`a` and `b`).
- Print values from left to right.
- Use simple integer arithmetic only.

## Why this matters
This is the easiest and safest starting point for Fibonacci in Bash.
EOF_NOTES

# Add a smoke test for the iterative implementation
# id: step1-create-test
cat > fibonacci-lab/tests/test-step1.sh <<'TEST'
#!/usr/bin/env bash
set -euo pipefail

expected="0 1 1 2 3 5 8 13 21 34"
actual="$(./fibonacci-lab/src/fib.sh 10)"

if [ "$actual" != "$expected" ]; then
  echo "Test failed" >&2
  echo "Expected: $expected" >&2
  echo "Actual:   $actual" >&2
  exit 1
fi

echo "step1 test passed"
TEST
chmod +x fibonacci-lab/tests/test-step1.sh

# Execute the test and show the project layout
# id: step1-run-test-and-tree
./fibonacci-lab/tests/test-step1.sh

tree -a fibonacci-lab
