# Examples Pruning — Design

**Date:** 2026-04-13
**Status:** Approved
**Target version:** v7.0.0 (part of the type catalog collapse branch)

## Context

The `examples/` directory contains 1,846 lines across 6 YAML files with 118
isolated per-type snippets. With `blueprint-types.md` now serving as the
canonical type reference, isolated examples are redundant — they restate what
the catalog already explains. The `explanation:` blocks often just paraphrase
the YAML.

The value of examples is showing how types **compose** into real workflows,
not how they look in isolation. Three synthetic composite workflows can
demonstrate all 34 types in context while reducing 1,846 lines to ~250.

## Goals

1. Replace 6 example YAML files with a single `examples.md` at the repo root
   containing 3 complete composite workflow snippets.
2. Collectively demonstrate all 34 types (3 nodes + 9 preconditions + 22
   consequences) across the 3 workflows.
3. Each workflow is a realistic end-to-end flow, not a contrived type sampler.

## Non-goals

- Changing `blueprint-types.md` content.
- Touching `workflows/core/intent-detection.yaml` (the real reusable workflow).
- Changing any schema files.

## Design

### File changes

**Delete:**
- `examples/consequences.yaml` (565 lines, 47 examples)
- `examples/preconditions.yaml` (390 lines, 31 examples)
- `examples/nodes.yaml` (367 lines, 14 examples)
- `examples/endings.yaml` (156 lines, 7 examples)
- `examples/execution.yaml` (285 lines, 19 examples)
- `examples/index.yaml` (83 lines)
- `examples/` directory

**Create:**
- `examples.md` at the repo root (alongside `blueprint-types.md`)

### Format

Markdown with fenced YAML code blocks. Each workflow gets:
- A `##` heading with the workflow name
- 1-2 sentence prose intro (what it does, not how)
- A type coverage annotation (which of the 34 types appear)
- The full workflow YAML as a fenced code block
- No per-snippet `explanation:` blocks — the workflow is self-documenting
  when you know the types from `blueprint-types.md`

### The 3 workflows

#### Workflow 1: Source onboarding

Checks prerequisites (tools, network, config), prompts for source type,
clones a git repo, reads config, and checkpoints state before risky
operations. Demonstrates the full lifecycle of a setup-style workflow.

**Types demonstrated (19):**
- Nodes: `action`, `conditional`, `user_prompt`
- Preconditions: `composite`, `tool_check`, `path_check`, `state_check`,
  `network_available`
- Consequences: `set_flag`, `mutate_state`, `display`, `log_node`,
  `log_entry`, `local_file_ops`, `git_ops_local`, `set_timestamp`,
  `create_checkpoint`, `rollback_checkpoint`, `install_tool`

#### Workflow 2: Web content pipeline

Verifies a source exists and is cloned, fetches web content, hashes it
for change detection, runs a Python processing script, and spawns a
parallel agent for indexing.

**Types demonstrated (14, of which 11 are unique to this workflow):**
- Nodes: `action`, `conditional`
- Preconditions: `evaluate_expression`, `python_module_available`,
  `fetch_check`, `source_check`, `path_check`
- Consequences: `web_ops`, `compute_hash`, `run_command`, `compute`,
  `evaluate`, `spawn_agent`, `inline`

#### Workflow 3: Intent-driven router

Parses user input with 3VL keyword matching, matches against intent rules,
displays candidates, and routes to the winning skill.

**Types demonstrated (12, of which 4 are unique to this workflow):**
- Nodes: `action`, `user_prompt`
- Preconditions: `composite`, `state_check`, `evaluate_expression`
- Consequences: `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules`,
  `display`, `invoke_skill`, `mutate_state`, `log_entry`

**Coverage: 19 + 11 + 4 = 34/34 types.**

### Documentation updates

- `README.md` Quick Start step 2: currently says "Write your workflow YAML
  using those types" — update to mention `examples.md` alongside
  `blueprint-types.md`.
- `CLAUDE.md` sync checklist: currently references `examples/*.yaml` — update
  to reference `examples.md`.
- `package.yaml` artifacts: currently lists `examples/` — update to
  `examples.md`.

### Version

This work lands on the same `refactor/type-catalog-collapse` branch as the
v7.0.0 catalog collapse. No additional version bump needed.

## Success criteria

1. `examples.md` exists at repo root with 3 workflows.
2. Every one of the 34 type names appears at least once across the 3
   workflows (verified by grep).
3. All 6 files in `examples/` and the directory itself are deleted.
4. `README.md`, `CLAUDE.md`, and `package.yaml` references updated.
5. No remaining references to `examples/` as a directory (outside exempt
   docs/superpowers/ and CHANGELOG.md).
