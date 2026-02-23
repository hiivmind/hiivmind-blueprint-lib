# hiivmind-blueprint-lib

Externalized type definitions and reusable workflows for [hiivmind-blueprint](https://github.com/hiivmind/hiivmind-blueprint).

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
# From consequences/consequences.yaml
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
1. Reads the workflow YAML (nodes, consequences, preconditions)
2. Looks up each type's definition from this library
3. Interprets the `effect` pseudocode to perform the operation
4. Naturally handles interpolation, error recovery, and tool calls

### Benefits

- **Extensibility**: Add new consequence/precondition types by creating definition files - no engine changes needed
- **Self-describing**: Type definitions fully specify their behavior; the LLM needs no special knowledge
- **Natural handling**: The LLM naturally handles `${...}` interpolation, error messages, and edge cases
- **Zero deployment**: Updates to types apply immediately to all workflows using this library
- **Transparent**: Behavior is documented in readable pseudocode, not buried in implementation code

## Overview

This package provides semantic type definitions and reusable workflows that can be referenced by URL, similar to how GitHub Actions work:

```yaml
# In your workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.0.0

nodes:
  clone_source:
    type: action
    actions:
      - type: git_ops_local       # Type resolved from external definitions
        operation: clone
        args:
          url: "${source.url}"

  # Reference a reusable workflow
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v3.0.0:intent-detection
    input:
      arguments: "${arguments}"
      intent_flags: "${intent_flags}"
      intent_rules: "${intent_rules}"
```

## Quick Start

1. Reference this library in your workflow's `definitions` block
2. Use consequence and precondition types in your nodes
3. Optionally reference reusable workflows

```yaml
name: my-workflow
version: "1.0.0"

definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.0.0

start_node: check_config

nodes:
  check_config:
    type: conditional
    condition:
      type: path_check            # Precondition type from library
      path: "config.yaml"
      check: is_file
    branches:
      on_true: load_config
      on_false: create_config

  load_config:
    type: action
    actions:
      - type: local_file_ops      # Consequence type from library
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

## Workflow Execution Model

Workflows execute in a 3-phase model defined in `execution/engine_execution.yaml`:

### Phase 1: Initialize

```
FUNCTION initialize(workflow_path, plugin_root, runtime_flags):
    workflow = parse_yaml(read_file(workflow_path))
    types = load_types(workflow.definitions)

    # Check entry preconditions
    FOR each precondition IN workflow.entry_preconditions:
        IF evaluate_precondition(precondition) == false:
            DISPLAY error and STOP

    # Initialize state
    state = {
        current_node: workflow.start_node,
        history: [],
        user_responses: {},
        computed: {},
        flags: workflow.initial_state.flags,
        checkpoints: {}
    }
```

### Phase 2: Execute (Main Loop)

```
FUNCTION execute(workflow, types, state):
    LOOP:
        node = workflow.nodes[state.current_node]

        IF state.current_node IN workflow.endings:
            GOTO Phase 3

        # Dispatch based on node.type
        outcome = dispatch_node(node, types, state)

        # Record in history
        state.history.append({ node, outcome, timestamp })

        # Update position
        state.previous_node = state.current_node
        state.current_node = outcome.next_node
    UNTIL ending
```

### Phase 3: Complete

```
FUNCTION complete(ending, state):
    # Display result based on ending.type
    IF ending.type == "success":
        DISPLAY ending.message
    ELSE IF ending.type == "error":
        DISPLAY "Error: " + ending.message
        IF ending.recovery:
            DISPLAY "Try running: /{ending.recovery}"
```

## Node Types

The library defines 4 node types for workflow construction:

| Node Type | Purpose | Routing |
|-----------|---------|---------|
| `action` | Execute consequences (operations) | `on_success` / `on_failure` |
| `conditional` | Branch based on a precondition | `branches.on_true` / `branches.on_false` |
| `user_prompt` | Present AskUserQuestion to user | Routes by `handler_id` from options |
| `reference` | Load and execute sub-workflow | `next_node` after completion |

### Node Examples

**Action Node** - Execute operations:
```yaml
clone_source:
  type: action
  actions:
    - type: git_ops_local
      operation: clone
      args:
        url: "${computed.repo_url}"
        dest: ".source/${computed.source_id}"
  on_success: verify_clone
  on_failure: handle_clone_error
```

**Conditional Node** - Branch on condition:
```yaml
check_config_exists:
  type: conditional
  condition:
    type: path_check
    path: "config.yaml"
    check: is_file
  branches:
    on_true: load_config
    on_false: create_config
```

**User Prompt Node** - Ask user a question:
```yaml
ask_source_type:
  type: user_prompt
  prompt:
    question: "What type of source?"
    options:
      - label: "Git repository"
        handler_id: git
        next_node: configure_git
      - label: "Local directory"
        handler_id: local
        next_node: configure_local
```

## State Management

Runtime state flows through execution, enabling dynamic behavior:

```yaml
state:
  # Position tracking
  current_node: "ask_source_type"
  previous_node: "check_url_provided"

  # User interaction results
  user_responses:
    ask_source_type:
      handler_id: "git"
      raw: { selected: "Git repository" }

  # Computed values from consequences
  computed:
    config: { name: "polars", sources: [] }
    repo_url: "https://github.com/pola-rs/polars"

  # Boolean routing flags
  flags:
    config_found: true
    is_first_source: true

  # Rollback snapshots
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
| `${array[0]}` | `${computed.sources[0].id}` | Array index |
| `${array[-1]}` | `${history[-1].node}` | Negative index (last) |

## Why External Types?

| Embedded (Old) | External (New) |
|----------------|----------------|
| Definitions copied into each plugin | Single source of truth |
| Manual sync on updates | Version-controlled releases |
| No extension ecosystem | Third-party extensions possible |
| Plugin-coupled versioning | Independent semantic versioning |
| Workflows duplicated | Reusable workflow library |

## Type Inventory

All types are consolidated into single files per category for easier loading and reference.

### Consequences (23 types in `consequences/consequences.yaml`)

| Category | Types | Description |
|----------|-------|-------------|
| core/state | 2 | set_flag, mutate_state |
| core/evaluation | 2 | evaluate, compute |
| core/interaction | 1 | display (text, table, markdown, json) |
| core/control | 4 | create_checkpoint, rollback_checkpoint, spawn_agent, inline |
| core/utility | 2 | set_timestamp, compute_hash |
| core/intent | 4 | evaluate_keywords, parse_intent_flags, match_3vl_rules, dynamic_route |
| core/logging | 2 | log_node, log_entry |
| extensions/file-system | 1 | local_file_ops (read, write, mkdir, delete) |
| extensions/git | 1 | git_ops_local (clone, pull, fetch, get-sha) |
| extensions/web | 1 | web_ops (fetch, cache) |
| extensions/scripting | 1 | run_command (bash, python, node, etc.) |
| extensions/package | 1 | install_tool |
| core/control | 1 | invoke_skill |

### Preconditions (9 types in `preconditions/preconditions.yaml`)

| Category | Types | Description |
|----------|-------|-------------|
| core/composite | 1 | composite (operator: all, any, none, xor) |
| core/expression | 1 | evaluate_expression |
| core/filesystems | 1 | path_check (exists, is_file, is_directory, contains_text) |
| core/state | 1 | state_check (true, false, equals, not_null, null) |
| core/tools | 1 | tool_check (available, version_gte) |
| core/network | 1 | network_available |
| core/python | 1 | python_module_available |
| core/git | 1 | source_check (exists, cloned, has_updates) |
| core/web_fetch | 1 | fetch_check (succeeded, has_content) |

### Node Types (4 types in `nodes/workflow_nodes.yaml`)

| Type | Description |
|------|-------------|
| action | Execute operations, route on success/failure |
| conditional | Branch based on precondition evaluation |
| user_prompt | Present AskUserQuestion, route on response |
| reference | Load and execute reference document |

### Workflows (1 workflow)

| Workflow | Description |
|----------|-------------|
| intent-detection | Reusable 3VL intent detection for dynamic routing |

## Three-Valued Logic (3VL) for Intent Detection

The library uses Kleene three-valued logic for intent detection, enabling sophisticated matching when some conditions are uncertain.

### Values

| Value | Meaning | Example |
|-------|---------|---------|
| `T` (True) | Condition definitely matches | User input contains keyword |
| `F` (False) | Condition definitely doesn't match | User input lacks required keyword |
| `U` (Unknown) | Condition is uncertain or irrelevant | Optional flag not provided |

### Rule Semantics

In rule definitions, `U` means "don't care" — the condition is ignored (wildcard). In runtime state, `U` means the value is uncertain.

### Kleene Logic Truth Table

When matching state against rules:

| State | Rule | Result | Meaning |
|-------|------|--------|---------|
| `T` | `T` | **Hard match** | Definite satisfaction |
| `T` | `F` | **Exclusion** | Definite mismatch |
| `T` | `U` | **Skip** | Rule doesn't care (wildcard) |
| `F` | `T` | **Exclusion** | Definite mismatch |
| `F` | `F` | **Hard match** | Definite non-satisfaction |
| `F` | `U` | **Skip** | Rule doesn't care (wildcard) |
| `U` | `T` | **Soft match** | State uncertain, could satisfy |
| `U` | `F` | **Soft match** | State uncertain, could exclude |
| `U` | `U` | **Skip** | Rule doesn't care (wildcard) |

Key insight: When rule=`U`, the condition is **skipped entirely** (doesn't count toward any counter). When state=`U` and rule=`T`/`F`, it's a **soft match** (uncertain satisfaction).

### Ranking Algorithm

When multiple rules match, candidates are ranked by:

```
(-hard_matches, +soft_matches, +effective_conditions)
```

1. **More hard matches wins** (negative = descending order)
2. **Fewer soft matches wins** (penalizes uncertainty)
3. **More effective conditions wins** (prefers specific rules)

Where `effective_conditions` = number of non-`U` conditions in the rule.

See `match_3vl_rules` consequence type in `consequences/consequences.yaml` for implementation details.

## Execution Pseudocode Reference

The `execution/` directory contains the execution engine semantics in pseudocode form:

| File | Purpose |
|------|---------|
| `execution/engine_execution.yaml` | Complete execution engine semantics (traversal, state, dispatch, logging) |

The `resolution/` directory defines how types, workflows, and execution semantics are loaded:

| File | Purpose |
|------|---------|
| `resolution/loader.yaml` | Consolidated loader for types, workflows, and execution semantics |

These files are the authoritative source for execution semantics. The LLM interprets them directly when executing workflows.

## Usage

### Type Definitions

Types are fetched directly from raw GitHub URLs at runtime:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.0.0
```

This resolves to:
```
https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v3.0.0/
```

The type loader fetches:
1. `consequences/consequences.yaml` - all consequence type definitions
2. `preconditions/preconditions.yaml` - all precondition type definitions
3. `nodes/workflow_nodes.yaml` - all node type definitions

### Reference a Reusable Workflow

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v3.0.0:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
  next_node: execute_dynamic_route
```

## Version Pinning

| Reference | Behavior |
|-----------|----------|
| `v3.0.0` | Exact version (recommended for production) |
| `v3.0` | Latest patch in v3.0.x |
| `v3` | Latest minor in v3.x.x (for development) |
| `main` | Latest commit (not recommended) |

## Extending with Custom Types

Create your own extension package:

```yaml
# mycorp-blueprint-types/package.yaml
name: mycorp-blueprint-types
extends: hiivmind/hiivmind-blueprint-lib@v3

# Reference in workflow
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.0.0
  extensions:
    - mycorp/custom-types@v1.0.0
```

## File Structure

```
hiivmind-blueprint-lib/
├── package.yaml                  # Package manifest
├── CHANGELOG.md                  # Version history
│
├── consequences/
│   └── consequences.yaml         # All 23 consequence types
│
├── preconditions/
│   └── preconditions.yaml        # All 9 precondition types
│
├── nodes/
│   └── workflow_nodes.yaml       # 4 node type definitions
│
├── execution/
│   └── engine_execution.yaml     # Execution engine semantics
│
├── resolution/
│   └── loader.yaml               # Consolidated type/workflow/execution loader
│
├── workflows/                    # Reusable workflow definitions
│   └── core/
│       └── intent-detection.yaml # 3VL intent detection workflow
│
├── examples/                     # Usage examples
│   ├── consequences.yaml
│   ├── preconditions.yaml
│   ├── nodes.yaml
│   └── execution.yaml
│
└── schema/                       # JSON schemas
    ├── common.json               # Shared definitions
    ├── definitions/
    │   ├── type-definition.json  # Consolidated type definition schema
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
        └── loader.json           # Consolidated resolution schema
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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Adding new consequence/precondition types
- Creating extension packages
- Testing changes

## License

MIT
