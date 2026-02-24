# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Overview

**hiivmind-blueprint-lib** is a type definition catalog for the [hiivmind-blueprint](https://github.com/hiivmind/hiivmind-blueprint) workflow system. It provides:

- **22 consequence types** - Operations that workflows can execute
- **9 precondition types** - Conditions workflows can check
- **3 node types** - Building blocks for workflow graphs
- **1 reusable workflow** - Intent detection with 3-valued logic

The key paradigm: **LLM-as-execution-engine**. Type definitions include `effect` pseudocode that the LLM interprets directly - no traditional runtime engine required.

Types are deployed locally: authors copy needed definitions from this catalog into `.hiivmind/blueprint/definitions.yaml` in their repo. No remote loading or version resolution at runtime.

## File Structure

```
consequences/core.yaml            # 13 core consequence types
consequences/intent.yaml          # 3 intent detection (3VL) types
consequences/extensions.yaml      # 6 extension consequence types
preconditions/core.yaml           # 3 core precondition types
preconditions/extensions.yaml     # 6 extension precondition types
nodes/workflow_nodes.yaml         # All 3 node types
```

### Schema Directory

```
schema/
├── definitions/    # Type definition schemas (type-definition, execution-definition)
├── authoring/      # Workflow authoring schemas (workflow, node-types, intent-mapping)
├── runtime/        # Runtime schemas (logging)
├── config/         # Configuration schemas (output-config, prompts-config)
├── resolution/     # Definitions file schema (definitions.json)
└── common.json     # Shared definitions
```

## HARD REQUIREMENT: Cross-Repository Synchronization

**When modifying YAML type definitions, you MUST also update related files to prevent divergence.**

Any change to these files:
- `consequences/core.yaml`, `consequences/intent.yaml`, `consequences/extensions.yaml`
- `preconditions/core.yaml`, `preconditions/extensions.yaml`
- `nodes/workflow_nodes.yaml`

**MUST be synchronized with:**

| Location | Purpose |
|----------|---------|
| `schema/` (this repo) | JSON schemas must match YAML structure |
| `examples/` (this repo) | Usage examples must reflect current API |
| `hiivmind-blueprint/patterns/` | Authoring and execution guides |

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

3. **Guide sync** - Check and update:
   - `hiivmind-blueprint/patterns/authoring-guide.md` (type reference tables)
   - `hiivmind-blueprint/patterns/execution-guide.md` (dispatch semantics)

### Analysis Scope

When analyzing or planning changes to type definitions, ALWAYS consider impact on:
- Schema validation (will existing workflows fail validation?)
- Examples (do they still work?)
- Pattern guides (are type tables now incorrect?)

## Key Concepts

### Type Definition Structure (Catalog Format)

Each type in the catalog follows this structure:

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
    kind: state_mutation|tool_call|computation|side_effect
    effect: |
      # Pseudocode that the LLM interprets
      state.computed[params.store_as] = result
```

### Slimmed-Down Format (definitions.yaml)

When copied into `.hiivmind/blueprint/definitions.yaml`, types use a simpler format:

```yaml
consequences:
  type_name:
    description: "What this type does"
    parameters:
      - name: param_name
        type: string
        required: true
    payload:
      kind: state_mutation
      effect: |
        state[field] = value
```

Catalog metadata (category, since, replaces, related, state_reads/writes) is omitted.

### Three-Valued Logic (3VL)

The `intent` category uses Kleene 3-valued logic:
- `T` (True) - Definite match
- `F` (False) - Definite non-match
- `U` (Unknown) - Uncertain or "don't care" (in rules)

Key types: `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules`

## Common Tasks

### Adding a New Type

1. Open the appropriate file based on where the type belongs:
   - `consequences/core.yaml` for core consequences
   - `consequences/intent.yaml` for 3VL intent types
   - `consequences/extensions.yaml` for extension consequences
   - `preconditions/core.yaml` for core preconditions
   - `preconditions/extensions.yaml` for extension preconditions

2. Add the type definition following the catalog schema structure

3. Update `package.yaml` stats if needed

4. Update README.md type counts if changed

### Validating Changes

JSON schemas in `schema/` define valid structures. Key schemas:
- `schema/definitions/type-definition.json` - Catalog type definitions
- `schema/resolution/definitions.json` - Per-repo definitions.yaml format
- `schema/authoring/workflow.json` - Workflow structure

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

This library has no runtime dependencies. It serves as a catalog that authors copy from at authoring time.
