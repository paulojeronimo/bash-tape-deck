#!/usr/bin/env bash
set -euo pipefail

if [ ! -d fibonacci-lab ]; then
  exit 0
fi

rm -f fibonacci-lab/src/fib-recursive.sh
rm -f fibonacci-lab/src/fib-memo.sh
rm -f fibonacci-lab/src/benchmark-step2.sh
rm -f fibonacci-lab/docs/step2-notes.md
rm -f fibonacci-lab/artifacts/step2-recursive.txt
rm -f fibonacci-lab/artifacts/step2-benchmark.txt

rm -f fibonacci-lab/src/fibonacci.lib.sh
rm -f fibonacci-lab/src/fibonacci-cli.sh
rm -f fibonacci-lab/tests/test-step3.sh
rm -f fibonacci-lab/docs/step3-notes.md
rm -f fibonacci-lab/artifacts/step3-cli.txt
rm -f fibonacci-lab/artifacts/step3-table.txt
