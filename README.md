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
# From consequences/core/state.yaml
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
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

nodes:
  clone_source:
    type: action
    actions:
      - type: clone_repo          # Type resolved from external definitions
        url: "${source.url}"

  # Reference a reusable workflow
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
    context:
      arguments: "${arguments}"
      intent_flags: "${intent_flags}"
      intent_rules: "${intent_rules}"
    next_node: execute_dynamic_route
```

## Quick Start

1. Reference this library in your workflow's `definitions` block
2. Use consequence and precondition types in your nodes
3. Optionally reference reusable workflows

```yaml
name: my-workflow
version: "1.0.0"

definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

start_node: check_config

nodes:
  check_config:
    type: conditional
    condition:
      type: file_exists           # Precondition type from library
      path: "config.yaml"
    branches:
      on_true: load_config
      on_false: create_config

  load_config:
    type: action
    actions:
      - type: read_file           # Consequence type from library
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

Workflows execute in a 3-phase model defined in `execution/traversal.yaml`:

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

The library defines 5 node types for workflow construction:

| Node Type | Purpose | Routing |
|-----------|---------|---------|
| `action` | Execute consequences (operations) | `on_success` / `on_failure` |
| `conditional` | Branch based on a precondition | `branches.on_true` / `branches.on_false` |
| `user_prompt` | Present AskUserQuestion to user | Routes by `handler_id` from options |
| `validation_gate` | All preconditions must pass | `on_pass` / `on_fail` |
| `reference` | Load and execute sub-workflow | `next_node` after completion |

### Node Examples

**Action Node** - Execute operations:
```yaml
clone_source:
  type: action
  actions:
    - type: clone_repo
      url: "${computed.repo_url}"
      path: ".source/${computed.source_id}"
  on_success: verify_clone
  on_failure: handle_clone_error
```

**Conditional Node** - Branch on condition:
```yaml
check_config_exists:
  type: conditional
  condition:
    type: file_exists
    path: "config.yaml"
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

### Consequences (43 types)

| Category | Types | Description |
|----------|-------|-------------|
| core/state | 5 | State mutation operations |
| core/evaluation | 2 | Expression evaluation |
| core/interaction | 2 | User display |
| core/control | 3 | Control flow, checkpoints |
| core/skill | 2 | Skill/pattern invocation |
| core/utility | 2 | Timestamps, hashes |
| core/intent | 4 | 3VL intent detection |
| core/logging | 10 | Workflow execution logging |
| extensions/file-system | 4 | File operations |
| extensions/git | 4 | Git operations |
| extensions/web | 2 | Web fetch/cache |
| extensions/scripting | 3 | Script execution |

### Preconditions (27 types)

| Category | Types | Description |
|----------|-------|-------------|
| core/filesystem | 5 | File/directory checks |
| core/state | 8 | State inspection |
| core/tool | 2 | Tool availability |
| core/composite | 3 | Logical composition |
| core/expression | 1 | Arbitrary expressions |
| core/logging | 3 | Logging lifecycle |
| extensions/source | 3 | Source repository checks |
| extensions/web | 2 | Web fetch verification |

### Node Types (5 types)

| Type | Description |
|------|-------------|
| action | Execute operations, route on success/failure |
| conditional | Branch based on precondition evaluation |
| user_prompt | Present AskUserQuestion, route on response |
| validation_gate | Run multiple preconditions, all must pass |
| reference | Load and execute reference document |

### Workflows (1 workflow)

| Workflow | Description |
|----------|-------------|
| intent-detection | Reusable 3VL intent detection for dynamic routing |

## Execution Pseudocode Reference

The `execution/` directory contains YAML files that define the execution engine semantics in pseudocode form:

| File | Purpose |
|------|---------|
| `execution/traversal.yaml` | Main 3-phase execution loop |
| `execution/state.yaml` | State structure and interpolation |
| `execution/consequence-dispatch.yaml` | How consequences are executed by type |
| `execution/precondition-dispatch.yaml` | How preconditions are evaluated |
| `execution/logging.yaml` | Logging configuration hierarchy |

The `resolution/` directory defines how types and workflows are loaded:

| File | Purpose |
|------|---------|
| `resolution/type-loader.yaml` | Load types from GitHub URLs |
| `resolution/workflow-loader.yaml` | Load reusable workflows |

These files are the authoritative source for execution semantics. The LLM interprets them directly when executing workflows.

## Usage

### Type Definitions

Types are fetched directly from raw GitHub URLs at runtime:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
```

This resolves to:
```
https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/
```

The type loader fetches:
1. `consequences/index.yaml` - consequence type registry
2. `preconditions/index.yaml` - precondition type registry
3. Individual type files on demand (lazy loading)

### Reference a Reusable Workflow

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
  next_node: execute_dynamic_route
```

## Version Pinning

| Reference | Behavior |
|-----------|----------|
| `v2.0.0` | Exact version (recommended for production) |
| `v2.0` | Latest patch in v2.0.x |
| `v2` | Latest minor in v2.x.x (for development) |
| `main` | Latest commit (not recommended) |

## Extending with Custom Types

Create your own extension package:

```yaml
# mycorp-blueprint-types/package.yaml
name: mycorp-blueprint-types
extends: hiivmind/hiivmind-blueprint-lib@v2

# Reference in workflow
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
  extensions:
    - mycorp/custom-types@v1.0.0
```

## File Structure

```
hiivmind-blueprint-lib/
├── package.yaml              # Package manifest
├── consequences/
│   ├── index.yaml            # Master registry
│   ├── core/                 # 8 core categories
│   │   ├── state.yaml
│   │   ├── evaluation.yaml
│   │   └── ...
│   ├── extensions/           # 4 extension categories
│   │   ├── file-system.yaml
│   │   └── ...
│   └── schema/
│       └── consequence-definition.json
├── preconditions/
│   ├── index.yaml
│   ├── core/
│   ├── extensions/
│   └── schema/
│       └── precondition-definition.json
├── nodes/
│   ├── index.yaml
│   └── core/
├── workflows/                 # Reusable workflow definitions
│   ├── index.yaml
│   └── core/
│       └── intent-detection.yaml
├── execution/                 # Execution engine semantics (pseudocode)
│   ├── traversal.yaml        # Main execution loop
│   ├── state.yaml            # State structure & interpolation
│   ├── consequence-dispatch.yaml
│   ├── precondition-dispatch.yaml
│   └── logging.yaml
├── resolution/                # Type & workflow loading
│   ├── type-loader.yaml
│   └── workflow-loader.yaml
├── logging/                   # Logging configuration defaults
│   └── defaults.yaml
└── schema/
    └── workflow-definitions.json  # Schema for definitions block
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
