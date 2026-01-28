# hiivmind-blueprint-lib

Externalized type definitions and reusable workflows for [hiivmind-blueprint](https://github.com/hiivmind/hiivmind-blueprint).

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

### Workflows (1 workflow)

| Workflow | Description |
|----------|-------------|
| intent-detection | Reusable 3VL intent detection for dynamic routing |

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
3. Individual type files on demand

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
