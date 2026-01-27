# hiivmind-blueprint-types

Externalized type definitions for [hiivmind-blueprint](https://github.com/hiivmind/hiivmind-blueprint) workflows.

## Overview

This package provides semantic type definitions that workflows can reference by URL, similar to how GitHub Actions work:

```yaml
# In your workflow.yaml
definitions:
  source: https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml

nodes:
  clone_source:
    type: action
    actions:
      - type: clone_repo          # Type resolved from external definitions
        url: "${source.url}"
```

## Why External Types?

| Embedded (Old) | External (New) |
|----------------|----------------|
| Definitions copied into each plugin | Single source of truth |
| Manual sync on updates | Version-controlled releases |
| No extension ecosystem | Third-party extensions possible |
| Plugin-coupled versioning | Independent semantic versioning |

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

## Usage

### Simple: Single Bundle Fetch

```yaml
definitions:
  source: https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml
```

### Selective: Directory-Based Loading

```yaml
definitions:
  base_url: https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/
  consequences: consequences/index.yaml
  preconditions: preconditions/index.yaml
```

### Local: Embedded Fallback

```yaml
definitions:
  source: local
  path: ./vendor/blueprint-types/v1.0.0
```

## Version Pinning

| Reference | Behavior |
|-----------|----------|
| `v1.0.0` | Exact version (recommended for production) |
| `v1.0` | Latest patch in v1.0.x |
| `v1` | Latest minor in v1.x.x (for development) |
| `main` | Latest commit (not recommended) |

## Extending with Custom Types

Create your own extension package:

```yaml
# mycorp-blueprint-types/package.yaml
name: mycorp-blueprint-types
extends: hiivmind/hiivmind-blueprint-types@v1

# Reference in workflow
definitions:
  base: https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml
  extensions:
    - https://github.com/mycorp/mycorp-blueprint-types/releases/download/v1.0.0/bundle.yaml
```

## File Structure

```
hiivmind-blueprint-types/
├── package.yaml              # Package manifest
├── bundle.yaml               # All definitions in one file
├── consequences/
│   ├── definitions/
│   │   ├── index.yaml        # Master registry
│   │   ├── core/             # 8 core categories
│   │   │   ├── state.yaml
│   │   │   ├── evaluation.yaml
│   │   │   └── ...
│   │   └── extensions/       # 4 extension categories
│   │       ├── file-system.yaml
│   │       └── ...
│   └── schema/
│       └── consequence-definition.json
├── preconditions/
│   ├── definitions/
│   │   ├── index.yaml
│   │   ├── core/
│   │   └── extensions/
│   └── schema/
│       └── precondition-definition.json
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
