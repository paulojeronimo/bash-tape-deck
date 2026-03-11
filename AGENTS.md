# Agent Rules

## Language for Generated Files
- Even if user prompts are in Portuguese, all generated code and code comments must be written in English.
- Exception: use Portuguese only when the user explicitly requests Portuguese.

## Shell Script Quality Gate
- After every modification to shell scripts (`*.sh`), run `shellcheck` on the modified scripts.
- Fix reported issues whenever possible before finishing the task.

## Commit Message Standard
- Write commit messages only in English.
- Commit messages must be relevant and detailed, clearly describing what changed and why.

## Tests for Changes
- Whenever a new feature is implemented, add or update automated tests that validate its expected behavior.
- Whenever a bug is fixed, add or update automated tests that reproduce the bug scenario and verify the fix.
- Prefer the smallest test scope that gives confidence:
  - unit-style checks for isolated logic
  - integration tests for workflow, Docker, filesystem, and state transitions
- Do not claim a fix is complete if the relevant behavior is still untested when automated testing is feasible.
- Favor meaningful coverage over a single numeric percentage target.
- Coverage expectations for this project:
  - 100% of fixed bugs should receive regression tests when automated testing is feasible.
  - 100% of critical user-facing flows should be covered by automated tests.
  - Critical flows include, at minimum: `play`, `stop`, `eject`, `rewind`, and the `docker/build.sh` and `docker/run.sh` paths.
  - Changes affecting navigation, JSONL event logs, lifecycle hooks, workdir behavior, or Docker execution should normally include integration coverage.

## Step Authoring for Bash Tape
- When generating `steps.N.sh` files, avoid commands that render as very large blocks on screen.
- As a rule, do not introduce `cat > ... <<EOF` blocks that display more than 20 lines in a single slide unless the user explicitly asks for that tradeoff.
- If a generated file would exceed that size, split the content across multiple steps or use a staged file construction approach that keeps each displayed command short enough to remain readable during playback.
- For Bash Tape, a new slide is created only when a titled step block is terminated by a blank line.
- If you split a long file creation into multiple `cat > ...` or `cat >> ...` commands but keep them in the same step block, they will still be rendered in a single slide.
- Therefore, when you want multiple slides, create multiple titled step blocks with blank lines between them.
- Optimize step authoring for presentation clarity, not only for implementation convenience.
