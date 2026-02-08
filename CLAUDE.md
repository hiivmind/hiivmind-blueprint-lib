# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Overview

**hiivmind-blueprint-lib** is a type definition library for the [hiivmind-blueprint](https://github.com/hiivmind/hiivmind-blueprint) workflow system. It provides:

- **43 consequence types** - Operations that workflows can execute
- **27 precondition types** - Conditions workflows can check
- **5 node types** - Building blocks for workflow graphs
- **1 reusable workflow** - Intent detection with 3-valued logic

The key paradigm: **LLM-as-execution-engine**. Type definitions include `effect` pseudocode that the LLM interprets directly - no traditional runtime engine required.

## File Structure

All types are consolidated into single YAML files per category:

```
consequences/consequences.yaml    # All 43 consequence types
preconditions/preconditions.yaml  # All 27 precondition types
nodes/workflow_nodes.yaml         # All 5 node types
execution/engine_execution.yaml   # Execution engine semantics
```

Each directory also has:
- `index.yaml` - Registry pointing to the consolidated file
- `_deprecated/` - Old directory structure (do not modify)

### Schema Directory

```
schema/
├── definitions/    # Type definition schemas (consequence, precondition, node, execution)
├── authoring/      # Workflow authoring schemas (workflow, node-types, intent-mapping)
├── runtime/        # Runtime schemas (logging)
├── config/         # Configuration schemas (output-config, prompts-config)
├── resolution/     # Type loading schemas
└── common.json     # Shared definitions
```

## HARD REQUIREMENT: Cross-Repository Synchronization

**When modifying YAML type definitions, you MUST also update related files to prevent divergence.**

Any change to these files:
- `consequences/consequences.yaml`
- `consequences/index.yaml`
- `preconditions/preconditions.yaml`
- `preconditions/index.yaml`
- `nodes/workflow_nodes.yaml`
- `nodes/index.yaml`
- `execution/engine_execution.yaml`
- `execution/index.yaml`

**MUST be synchronized with:**

| Location | Purpose |
|----------|---------|
| `schema/` (this repo) | JSON schemas must match YAML structure |
| `examples/` (this repo) | Usage examples must reflect current API |
| `hiivmind-blueprint-author/references/` | Reference documentation for authors |
| `hiivmind-blueprint-author/lib/patterns/` | Pattern libraries using these types |

### Synchronization Checklist

Before completing any YAML change:

1. **Schema sync** - Update JSON schemas in `schema/` if:
   - New parameters added
   - Parameter types changed
   - Required/optional status changed
   - New type added

2. **Example sync** - Update `examples/` if:
   - Type behavior changed
   - New type added
   - Parameters renamed or removed

3. **External reference sync** - Check and update:
   - `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-author/references/`
   - `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-author/lib/patterns/`

### Analysis Scope

When analyzing or planning changes to type definitions, ALWAYS consider impact on:
- Schema validation (will existing workflows fail validation?)
- Examples (do they still work?)
- External documentation (is it now incorrect?)
- Pattern libraries (do patterns use the changed type?)

## Key Concepts

### Type Definition Structure

Each type follows this structure:

```yaml
type_name:
  description:
    brief: One-line description
    detailed: Extended explanation (optional)
  category: category_name
  parameters:
    - name: param_name
      type: string|boolean|number|object|array
      required: true|false
      default: value (if not required)
      description: What this parameter does
  payload:
    kind: state_mutation|tool_call|composite|display
    effect: |
      # Pseudocode that the LLM interprets
      state.computed[params.store_as] = result
```

### Three-Valued Logic (3VL)

The `intent` category uses Kleene 3-valued logic:
- `T` (True) - Definite match
- `F` (False) - Definite non-match
- `U` (Unknown) - Uncertain or "don't care" (in rules)

Key types: `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules`, `dynamic_route`

## Common Tasks

### Adding a New Type

1. Open the appropriate consolidated file:
   - `consequences/consequences.yaml` for consequences
   - `preconditions/preconditions.yaml` for preconditions

2. Add the type definition following the schema structure

3. Update `package.yaml` stats if needed

4. Update README.md type counts if changed

### Modifying Execution Semantics

Edit `execution/engine_execution.yaml`. This contains the complete execution engine pseudocode including:
- Traversal logic (3-phase model)
- State management
- Consequence dispatch
- Precondition evaluation
- Logging configuration

### Validating Changes

JSON schemas in `schema/` define valid structures. Key schemas:
- `schema/definitions/consequence-definition.json`
- `schema/definitions/precondition-definition.json`
- `schema/definitions/node-definition.json`

## Versioning

This library follows semantic versioning:

| Change Type | Version Bump |
|-------------|--------------|
| Remove type or required parameter | Major |
| Change parameter semantics | Major |
| Add new types | Minor |
| Add optional parameters | Minor |
| Documentation fixes | Patch |

Current version: Check `package.yaml`

## Git Workflow

- Main branch: `main`
- **PRs to `main` must come from `release/*` or `hotfix/*` branches** — enforced by CI (`Validate PR Source Branch` required check)
- Use `/prepare-release` to automate: create release branch, bump version, update changelog, and open PR to `main`
- Releases are tagged (e.g., `v2.0.0`, `v2.1.0`) automatically when PRs to `main` are merged
- Workflows reference specific versions via GitHub raw URLs
- See `RELEASING.md` for the full release process

## GitHub Operations

This project uses [hiivmind-pulse-gh](https://github.com/hiivmind/hiivmind-pulse-gh) for GitHub automation.

Route ALL GitHub operations through the plugin for automatic context enrichment:
- `/hiivmind-pulse-gh:hiivmind-pulse-gh create issue for [description]`
- `/hiivmind-pulse-gh:hiivmind-pulse-gh discover` to explore capabilities

## Testing Considerations

Since types are interpreted by LLMs (not compiled code), validation focuses on:
1. Schema compliance - JSON schemas validate structure
2. Pseudocode clarity - `effect` blocks must be unambiguous
3. Parameter completeness - Required params must be documented
4. Example coverage - Types should have usage examples

## Dependencies

This library has no runtime dependencies. It's fetched via raw GitHub URLs:

```
https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/
```

Consuming workflows specify the version in their `definitions` block.
