# hiivmind-blueprint-lib

Type definition catalog for [hiivmind-blueprint](https://github.com/hiivmind/hiivmind-blueprint).

## The LLM-as-Execution-Engine Paradigm

This library introduces a novel approach to workflow execution: **the LLM interprets YAML pseudocode directly**, eliminating the need for a traditional runtime engine.

### Traditional vs LLM-Native Execution

| Traditional Approach | LLM-Native Approach |
|---------------------|---------------------|
| YAML defines structure, code implements behavior | YAML defines both structure AND behavior via pseudocode |
| Engine parses YAML → calls handler functions | LLM reads YAML → interprets `effect` pseudocode directly |
| New features require engine code changes | New features require only new type definitions |
| Deployed runtime with dependencies | Zero deployment - runs wherever the LLM runs |
| Fixed interpolation syntax | Natural language understanding of expressions |

### How It Works

Each type definition includes an `effect` field containing pseudocode that the LLM interprets:

```yaml
# From blueprint-types.md
set_flag(flag, value)
  value ∈ {true, false}
  → state.flags[flag] = value
```

When executing a workflow, the LLM:
1. Reads `blueprint-types.md` (shipped by the hiivmind-blueprint skill)
2. Reads the workflow YAML (nodes, consequences, preconditions)
3. Interprets each type by its documented signature and semantics
4. Naturally handles `${}` interpolation, error recovery, and tool calls

## Overview

This package provides a single-file type catalog at `blueprint-types.md`. The `hiivmind-blueprint` skill ships this file at build time from a pinned version of the library. There is no per-repo definitions file.

Workflow authors reference types by name; the workflow-executing LLM reads `blueprint-types.md` to interpret each name. Every type is documented as a short function-style signature with parameters, enum variants, and a one-line semantic description. See `blueprint-types.md` for the full catalog.

## Skills vs Workflows

A **skill** is a prose orchestrator (`SKILL.md`) that guides Claude through a multi-phase procedure. A **workflow** is a structured YAML definition that a skill can delegate specific phases to. This library provides type definitions for building **workflows** — the execution building blocks that skills use.

| Concept | What It Is | Defined By |
|---------|-----------|------------|
| Skill | Prose orchestrator with phases | `SKILL.md` with frontmatter |
| Workflow | Structured YAML execution graph | `workflows/*.yaml` within a skill |
| Type | Building block for workflows | `blueprint-types.md` (this repo) |

A skill may have zero, some, or all of its phases backed by workflows. This library's types are only relevant for the workflow-backed phases. See `hiivmind-blueprint/patterns/authoring-guide.md` for the full authoring guide covering both skills and workflows.

## Quick Start

1. Install the `hiivmind-blueprint` skill (ships `blueprint-types.md` automatically)
2. Write your workflow YAML using those types
3. See `hiivmind-blueprint/patterns/authoring-guide.md` for the full authoring guide

```yaml
name: my-workflow
version: "1.0.0"

start_node: check_config
default_error: error_generic

nodes:
  check_config:
    type: conditional
    condition:
      type: path_check
      path: "config.yaml"
      check: is_file
    on_true: load_config
    on_false: create_config

  load_config:
    type: action
    consequences:
      - type: local_file_ops
        operation: read
        path: "config.yaml"
        store_as: config
    on_success: done

endings:
  done:
    type: success
    message: "Configuration loaded"
  error_generic:
    type: error
    message: "Unexpected failure at ${current_node}"
```

## Endings

Endings define the outcome and terminal behavior of a workflow path. Every graph path must terminate at an ending.

### Outcome Types

| Type | Meaning |
|------|---------|
| `success` | Completed successfully |
| `failure` | Failed due to a known condition |
| `error` | Failed due to an unexpected error |
| `cancelled` | Cancelled by user |
| `indeterminate` | Outcome is ambiguous (maps to 3VL Unknown) |

### Behaviors

| Behavior | What It Does |
|----------|-------------|
| *(default)* display | Show message and summary |
| `delegate` | Hand off to another skill |
| `restart` | Loop back to a node |
| `silent` | Complete with no output |

Endings can also execute `consequences` (best-effort, logged on failure) before completing. See `examples.md` for full ending patterns in context.

## Node Types

The library defines 3 node types for workflow construction:

| Node Type | Purpose | Routing |
|-----------|---------|---------|
| `action` | Execute consequences (operations) | `on_success` / `on_failure?` (defaults to `default_error`) |
| `conditional` | Branch on a precondition | `on_true` / `on_false` / `on_unknown?` (defaults to `default_error`) |
| `user_prompt` | Present structured prompt to user | Routes by `handler_id` from options |

## State Management

Runtime state flows through execution, enabling dynamic behavior:

```yaml
state:
  current_node: "ask_source_type"
  previous_node: "check_url_provided"
  user_responses:
    ask_source_type:
      handler_id: "git"
  computed:
    config: { name: "polars", sources: [] }
    repo_url: "https://github.com/pola-rs/polars"
  flags:
    config_found: true
  checkpoints:
    before_clone: { ... }
```

### Variable Interpolation

Use `${...}` syntax to reference state values:

| Pattern | Example | Description |
|---------|---------|-------------|
| `${field}` | `${source_type}` | Top-level state field |
| `${computed.path}` | `${computed.repo_url}` | Computed value |
| `${flags.flag}` | `${flags.config_found}` | Boolean flag |
| `${user_responses.node.field}` | `${user_responses.ask_type.handler_id}` | User response |

## Type Inventory

All 34 types are defined in `blueprint-types.md` at the repo root:

- **3 node types** — `action`, `conditional`, `user_prompt`
- **9 precondition types** — 3 core + 6 extensions
- **22 consequence types** — 13 core + 3 intent (3VL) + 6 extensions

See `blueprint-types.md` for signatures, parameters, and enum variants. See `examples.md` for composite workflow examples.

### Workflows (1 workflow)

| Workflow | Description |
|----------|-------------|
| intent-detection | Reusable 3VL intent detection for dynamic routing |

## Three-Valued Logic (3VL) for Intent Detection

The library uses Kleene three-valued logic for intent detection.

### Values

| Value | Meaning | Example |
|-------|---------|---------|
| `T` (True) | Condition definitely matches | User input contains keyword |
| `F` (False) | Condition definitely doesn't match | User input lacks required keyword |
| `U` (Unknown) | Condition is uncertain or irrelevant | Optional flag not provided |

### Ranking Algorithm

When multiple rules match, candidates are ranked by:

```
(-hard_matches, +soft_matches, +effective_conditions)
```

1. **More hard matches wins** (negative = descending order)
2. **Fewer soft matches wins** (penalizes uncertainty)
3. **More effective conditions wins** (prefers specific rules)

## File Structure

```
hiivmind-blueprint-lib/
├── blueprint-types.md            # Single-file type catalog (3 nodes,
│                                 # 9 preconditions, 22 consequences)
├── package.yaml                  # Package manifest
├── CHANGELOG.md                  # Version history
│
├── workflows/                    # Reusable workflow definitions
│   └── core/
│       └── intent-detection.yaml # 3VL intent detection workflow
│
├── examples.md                   # 3 composite workflow examples
│
└── schema/                       # JSON schemas
    ├── common.json               # Shared definitions
    ├── authoring/                # Workflow authoring validation
    │   ├── workflow.json
    │   ├── node-types.json
    │   └── intent-mapping.json
    ├── config/                   # Runtime configuration
    │   ├── output-config.json
    │   └── prompts-config.json
    └── runtime/                  # Runtime output validation
        └── logging.json
```

## Versioning Policy

### Breaking Changes (Major Version)
- Removing a type
- Removing a required parameter
- Changing parameter semantics
- Renaming types

### Non-Breaking Changes (Minor Version)
- Adding new types
- Adding optional parameters
- Deprecating (not removing) types

### Patches
- Documentation fixes
- Example corrections

## License

MIT
