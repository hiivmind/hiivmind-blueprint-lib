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
# From consequences/core.yaml
types:
  set_flag:
    description:
      brief: Sets a boolean flag in workflow state
    parameters:
      - name: flag
        type: string
        required: true
      - name: value
        type: boolean
        default: true
    payload:
      kind: state_mutation
      effect: |
        state.flags[params.flag] = params.value
```

When executing a workflow, the LLM:
1. Reads the local definitions file (`.hiivmind/blueprint/definitions.yaml`)
2. Reads the workflow YAML (nodes, consequences, preconditions)
3. Interprets the `effect` pseudocode to perform each operation
4. Naturally handles interpolation, error recovery, and tool calls

## Overview

This package provides semantic type definitions that are deployed locally with each repo. Authors copy the types their workflows need from this catalog into a centralized definitions file:

```yaml
# .hiivmind/blueprint/definitions.yaml
nodes:
  action:
    description: "Execute consequences, route on success/failure"
    execution:
      effect: |
        for action in node.actions:
          result = dispatch_consequence(action, state)
          if result.failed: return route_to(node.on_failure)
        return route_to(node.on_success)

consequences:
  mutate_state:
    description: "Modify workflow state"
    parameters:
      - name: operation
        type: string
        required: true
        enum: [set, append, clear, merge]
      - name: field
        type: string
        required: true
      - name: value
        type: any
        required: false
    payload:
      kind: state_mutation
      effect: |
        if operation == "set":   state[field] = value
        if operation == "append": state[field].push(value)
        if operation == "clear":  state[field] = null
        if operation == "merge":  state[field] = merge(state[field], value)

preconditions:
  state_check:
    description: "Check state field against a condition"
    parameters:
      - name: field
        type: string
        required: true
      - name: operator
        type: string
        required: true
    evaluation:
      effect: |
        val = resolve_path(state, field)
        if operator == "not_null": return val != null
        if operator == "equals":  return val == value
        if operator == "true":    return val == true
```

Workflows no longer need a `definitions` block — types are resolved from the local file by convention.

## Skills vs Workflows

A **skill** is a prose orchestrator (`SKILL.md`) that guides Claude through a multi-phase procedure. A **workflow** is a structured YAML definition that a skill can delegate specific phases to. This library provides type definitions for building **workflows** — the execution building blocks that skills use.

| Concept | What It Is | Defined By |
|---------|-----------|------------|
| Skill | Prose orchestrator with phases | `SKILL.md` with frontmatter |
| Workflow | Structured YAML execution graph | `workflows/*.yaml` within a skill |
| Type | Building block for workflows | This catalog (`consequences/`, `preconditions/`, `nodes/`) |

A skill may have zero, some, or all of its phases backed by workflows. This library's types are only relevant for the workflow-backed phases. See `hiivmind-blueprint/patterns/authoring-guide.md` for the full authoring guide covering both skills and workflows.

## Quick Start

1. Copy needed type definitions from this catalog into `.hiivmind/blueprint/definitions.yaml`
2. Write your workflow YAML using those types
3. See `hiivmind-blueprint/patterns/authoring-guide.md` for the full authoring guide

```yaml
name: my-workflow
version: "1.0.0"

start_node: check_config

nodes:
  check_config:
    type: conditional
    condition:
      type: path_check
      path: "config.yaml"
      check: is_file
    branches:
      on_true: load_config
      on_false: create_config

  load_config:
    type: action
    actions:
      - type: local_file_ops
        operation: read
        path: "config.yaml"
        store_as: config
    on_success: done
    on_failure: error_reading

endings:
  done:
    type: success
    message: "Configuration loaded"
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

Endings can also execute `consequences` (best-effort, logged on failure) before completing. See `examples/endings.yaml` for full patterns.

## Node Types

The library defines 3 node types for workflow construction:

| Node Type | Purpose | Routing |
|-----------|---------|---------|
| `action` | Execute consequences (operations) | `on_success` / `on_failure` |
| `conditional` | Branch based on a precondition | `branches.on_true` / `branches.on_false` |
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

Types are split into core, intent, and extension files.

### Consequences (22 types across `consequences/core.yaml`, `intent.yaml`, `extensions.yaml`)

| Category | Types | Description |
|----------|-------|-------------|
| core/state | 2 | set_flag, mutate_state |
| core/evaluation | 2 | evaluate, compute |
| core/interaction | 1 | display (text, table, markdown, json) |
| core/control | 4 | create_checkpoint, rollback_checkpoint, spawn_agent, inline |
| core/utility | 1 | set_timestamp |
| core/intent | 3 | evaluate_keywords, parse_intent_flags, match_3vl_rules |
| core/logging | 2 | log_node, log_entry |
| extensions/file-system | 1 | local_file_ops (read, write, mkdir, delete) |
| extensions/git | 1 | git_ops_local (clone, pull, fetch, get-sha) |
| extensions/hashing | 1 | compute_hash |
| extensions/web | 1 | web_ops (fetch, cache) |
| extensions/scripting | 1 | run_command (bash, python, node, etc.) |
| extensions/package | 1 | install_tool |
| core/control | 1 | invoke_skill |

### Preconditions (9 types across `preconditions/core.yaml`, `extensions.yaml`)

| Category | Types | Description |
|----------|-------|-------------|
| core/composite | 1 | composite (operator: all, any, none, xor) |
| core/expression | 1 | evaluate_expression |
| core/state | 1 | state_check (true, false, equals, not_null, null) |
| extensions/filesystem | 1 | path_check (exists, is_file, is_directory, contains_text) |
| extensions/tools | 1 | tool_check (available, version_gte) |
| extensions/network | 1 | network_available |
| extensions/python | 1 | python_module_available |
| extensions/git | 1 | source_check (exists, cloned, has_updates) |
| extensions/web | 1 | fetch_check (succeeded, has_content) |

### Node Types (3 types in `nodes/workflow_nodes.yaml`)

| Type | Description |
|------|-------------|
| action | Execute operations, route on success/failure |
| conditional | Branch based on precondition evaluation |
| user_prompt | Present structured prompt, route on response |

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
├── package.yaml                  # Package manifest
├── CHANGELOG.md                  # Version history
│
├── consequences/
│   ├── core.yaml                 # 13 core consequence types
│   ├── intent.yaml               # 3 intent detection (3VL) types
│   └── extensions.yaml           # 6 extension consequence types
│
├── preconditions/
│   ├── core.yaml                 # 3 core precondition types
│   └── extensions.yaml           # 6 extension precondition types
│
├── nodes/
│   └── workflow_nodes.yaml       # 3 node type definitions
│
├── workflows/                    # Reusable workflow definitions
│   └── core/
│       └── intent-detection.yaml # 3VL intent detection workflow
│
├── examples/                     # Usage examples
│   ├── consequences.yaml
│   ├── preconditions.yaml
│   ├── nodes.yaml
│   ├── endings.yaml
│   └── execution.yaml
│
└── schema/                       # JSON schemas
    ├── common.json               # Shared definitions
    ├── definitions/
    │   ├── type-definition.json  # Catalog type definition schema
    │   └── execution-definition.json
    ├── authoring/
    │   ├── workflow.json
    │   ├── node-types.json
    │   └── intent-mapping.json
    ├── runtime/
    │   └── logging.json
    ├── config/
    │   ├── output-config.json
    │   └── prompts-config.json
    └── resolution/
        └── definitions.json      # Per-repo definitions.yaml schema
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
