---
name: task-fs-agent
description: Manage project work as filesystem-based AsciiDoc tasks using an inbox/doing/blocked/review/done workflow. Use when humans and AI agents collaborate through files in a git repository and need standardized task naming, templates, and state transitions.
compatibility: Designed for repository-local installation. Uses Bash scripts, AsciiDoc task files, and a tasks/ directory at the project root.
metadata:
  author: paulojeronimo
  version: "1.0"
---

# Task FS Agent

This skill defines a repository-local workflow for humans and AI agents to collaborate through task files.

The task queue is the filesystem. Each task is an AsciiDoc document. Moving a file between directories changes its state.

## Repository layout

Install this skill under:

```text
skills/task-fs-agent/
```

Expose skills to agents through:

```text
.agents/skills -> ../skills
.claude/skills -> ../skills
```

Create the workflow directories at the repository root:

```text
tasks/
  01-inbox/
  02-doing/
  03-blocked/
  04-review/
  05-done/
```

## Progressive disclosure

Keep this file normative and short. Use these companion files when needed:

- Usage examples: `references/examples.adoc`
- Workflow explanation: `references/workflow.adoc`
- Task templates: `assets/task-templates/`
- Helper scripts: `scripts/`
- Automated tests: `tests/clitest/`

## Discovery rules

Agents should not guess paths. Use these fixed conventions.

1. Skill root: `skills/task-fs-agent/`
2. Templates live in: `assets/task-templates/`
3. Executable helpers live in: `scripts/`
4. Human-facing examples live in: `references/examples.adoc`
5. Automated tests live in: `tests/clitest/`
6. The project task queue lives in: `tasks/`

When a helper is needed, prefer these scripts first:

- `scripts/task-new.sh`
- `scripts/task-claim.sh`
- `scripts/task-review.sh`
- `scripts/task-done.sh`
- `scripts/task-block.sh`
- `scripts/task-note.sh`
- `scripts/task-list.sh`

When validating helper behavior, use:

- `tests/run-clitest.sh`

## Workflow states

- `01-inbox`: newly created tasks, not yet claimed
- `02-doing`: task currently being worked on
- `03-blocked`: task cannot proceed safely
- `04-review`: work complete, waiting for validation
- `05-done`: finished and accepted

## Core rules

1. Never start work on a task still in `tasks/01-inbox/`.
2. Claim work by moving the file to `tasks/02-doing/`.
3. Use the helper scripts when available instead of renaming files manually.
4. Only move a task to `05-done` when its Definition of Done is satisfied.
5. If the implementation is complete but needs review, move it to `04-review`.
6. If the task cannot proceed safely, move it to `03-blocked` and explain why.
7. Never delete task files.
8. Prefer appending notes instead of overwriting history.
9. Keep the filename stable after creation.

## Task naming

Use this filename format:

```text
YYYYMMDD-HHMM--type--slug.adoc
```

Allowed types:

- `task`
- `bugfix`
- `research`
- `docs`
- `refactor`
- `ops`

Slug rules:

- lowercase ASCII only
- words separated by `-`
- no accents
- no spaces
- no punctuation except `-`

## Task creation

Always create tasks from a template in `assets/task-templates/`.

Preferred command:

```bash
skills/task-fs-agent/scripts/task-new.sh <type> "<title>" [priority]
```

Templates currently available:

- `assets/task-templates/task.adoc`
- `assets/task-templates/bugfix.adoc`
- `assets/task-templates/research.adoc`

## Required task sections

Each task document must include:

- title
- metadata attributes
- objective
- context
- inputs
- steps
- definition of done
- execution notes
- decisions
- blockers

## Priority handling

Tasks may include:

```asciidoc
:priority: high
```

Allowed values: `high`, `medium`, `low`.

Prefer tasks in this order:

1. higher priority
2. older timestamp
3. simpler work only when priorities are equal and batching helps

## Ownership

Tasks may include:

```asciidoc
:owner: human
:agent: codex
```

When an agent claims a task, it may update `:agent:`.

## Safe state transitions

Use these scripts:

- claim: `scripts/task-claim.sh`
- review: `scripts/task-review.sh`
- done: `scripts/task-done.sh`
- blocked: `scripts/task-block.sh`

For notes during execution, use:

- `scripts/task-note.sh`

## Validation

Changes to helper scripts should be validated with:

- `shellcheck` on modified `scripts/*.sh`
- `CLITEST_BIN=/path/to/clitest bash tests/run-clitest.sh`

The `clitest` suite covers the current helper flows for:

- task creation
- claim
- notes
- review
- done
- blocked
- list
- slug generation

For examples, see `references/examples.adoc`.
For the design rationale, see `references/workflow.adoc`.
