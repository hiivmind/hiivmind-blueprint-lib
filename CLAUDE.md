# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Overview

**hiivmind-blueprint-lib** is a type definition catalog for the [hiivmind-blueprint](https://github.com/hiivmind/hiivmind-blueprint) workflow system. It provides:

- **23 consequence types** - Operations that workflows can execute (includes mcp_tool_call)
- **9 precondition types** - Conditions workflows can check
- **4 node types** - Building blocks for workflow graphs (action, conditional, user_prompt, ending)
- **1 reusable workflow** - Intent detection with 3-valued logic
- **Payload Types** - Per-workflow data-shape declarations

The key paradigm: **LLM-as-execution-engine**. Type definitions include `effect` pseudocode that the LLM interprets directly - no traditional runtime engine required.

The `hiivmind-blueprint` skill ships `blueprint-types.md` from a pinned version of this library. Consuming repos reference types by name in their workflow YAML; there is no per-repo definitions file.

## File Structure

```
blueprint-types.md                # Single-file type catalog (all 34 types)
```

### Schema Directory

```
schema/
├── authoring/      # Workflow authoring schemas (workflow, node-types, intent-mapping)
├── runtime/        # Runtime schemas (logging)
├── config/         # Configuration schemas (output-config, prompts-config)
└── common.json     # Shared definitions
```

## HARD REQUIREMENT: Cross-Repository Synchronization

**When modifying `blueprint-types.md`, you MUST also update related files to prevent divergence.**

Any change to `blueprint-types.md` MUST be synchronized with:

| Location | Purpose |
|----------|---------|
| `examples.md` (this repo) | Composite workflow examples must use current type names and enum variants |
| `hiivmind-blueprint/lib/patterns/authoring-guide.md` | Authoring guidance referencing the catalog |
| `hiivmind-blueprint/lib/patterns/execution-guide.md` | Execution guidance referencing the catalog |
| `hiivmind-blueprint` skill bundle | The skill ships `blueprint-types.md` at build time; bundle must re-copy after changes |

### Synchronization Checklist

Before completing any change to `blueprint-types.md`:

1. **Examples sync** — update `examples.md` if a type, parameter, or enum variant was renamed or removed.
2. **Patterns sync** — update the two `hiivmind-blueprint/lib/patterns/*` files if the change affects authoring or execution guidance.
3. **Skill bundle** — ensure the next `hiivmind-blueprint` skill release re-ships the updated file.

### Analysis Scope

When analyzing or planning changes to `blueprint-types.md`, ALWAYS consider impact on:
- Existing workflow call sites (will `type: X` still resolve? Will required params still be present?)
- Examples (do they still work?)
- The two pattern guides in `hiivmind-blueprint` (are their references still accurate?)

## Key Concepts

### Type Catalog Format

All types are defined in a single file: `blueprint-types.md`. Each type is a function-style signature:

```
type_name(required_param, optional?)
  param ∈ {enum, variants}   # if applicable
  → one-line outcome / return meaning
```

**Conventions:**
- `?` suffix marks optional parameters.
- `X ∈ {a, b, c}` lists enum variants.
- `→` marks the outcome.
- All string parameters support `${}` state interpolation.
- Preconditions return true, false, or unknown. Consequences mutate state or the world.

Workflow YAML references types via `type: <name>` plus sibling keys for parameters. See `examples.md` for composite workflow examples.

### Composite Node Types (Authoring Sugar)

In addition to the four primitive node types, blueprint supports **composite nodes** — author-time syntactic sugar documented in `blueprint-composites.md` (separate from `blueprint-types.md`). v1 composites:

- `confirm` — yes/no prompt with structural state gating
- `gated_action` — multi-way CASE/WHEN dispatch
- `goal_seek` — bounded dispatcher loop over a list of goals (iteration budget + per-goal completion predicate)

Composites are walker-expanded into primitive nodes before execution. The walker implementation lives in `hiivmind-blueprint-mcp` (separate repo). **This repo contains only the catalog, schema, and fixture corpus** — no walker code, no Python runtime.

When modifying composite definitions, also update:

1. `schema/authoring/node-types.json` — composite sub-schemas
2. `blueprint-composites.md` — author-facing signature
3. `tests/fixtures/composites/` — expansion contract fixtures (the authoritative walker target)

When modifying primitives in a way that could affect composite expansion, notify `hiivmind-blueprint-mcp` maintainers — walker expanders may need updates to stay contract-valid.

### Three-Valued Logic (3VL)

The `intent` category uses Kleene 3-valued logic:
- `T` (True) - Definite match
- `F` (False) - Definite non-match
- `U` (Unknown) - Uncertain or "don't care" (in rules)

Key types: `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules`

## Common Tasks

### Adding a New Type

1. Open `blueprint-types.md` at the repo root.
2. Add the type to the appropriate section (`## Nodes`, `## Preconditions` → `### Core`/`### Extensions`, or `## Consequences` → the appropriate category).
3. Write the signature in the established format (`name(params) → meaning`, with enum variants indented below if applicable).
4. Update `package.yaml.stats` if counts changed.
5. Ensure the type is demonstrated in `examples.md` (add to an existing workflow or note if a new workflow is needed).
6. Update the two pattern guides in `hiivmind-blueprint/lib/patterns/` if the new type affects authoring or execution guidance.

### Validating Changes

There is no JSON schema for `blueprint-types.md` — it is a human/LLM reference document, not structured data. Validation is by inspection:

- Does the signature format match the conventions in the file's header?
- Do the parameters and enum variants match the behavior documented in the `→` line?
- Are existing examples in `examples.md` still consistent with the type?

Workflow authoring schemas (`schema/authoring/*`) are type-agnostic: they validate workflow structure but delegate type-specific validation to runtime (the LLM). Changes to `blueprint-types.md` never require schema changes.

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
4. Example coverage - Types should appear in `examples.md` workflows

## Dependencies

This library has no runtime dependencies. It serves as a catalog that authors copy from at authoring time.
