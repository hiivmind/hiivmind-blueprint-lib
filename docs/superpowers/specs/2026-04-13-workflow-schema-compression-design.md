# Workflow Schema Compression — Design

**Date:** 2026-04-13
**Status:** Approved
**Target version:** v7.0.0 (part of the type catalog collapse branch)

## Context

The workflow YAML format (validated by `schema/authoring/workflow.json`) was designed
for explicitness. Every action node requires `on_failure`, every conditional nests
its branches under `branches:`, and consequence arrays use inconsistent naming
(`actions:`, `consequence:`, `consequences:`). With the type catalog already
compressed to signature-style prose, the workflow YAML is now the main source of
verbosity.

The format must remain **machine-traversable** — a Python tree-walking function
will parse and execute these workflows without LLM help for structural navigation.
Compression targets ceremony that serves neither the walker nor the LLM: redundant
nesting, predictable defaults, and inconsistent naming.

## Goals

1. Reduce workflow YAML verbosity by ~30-40% without losing structural integrity.
2. Maintain deterministic traversability by a Python walker function.
3. Unify consequence naming across all contexts.
4. Introduce syntactic sugar that the walker normalizes to canonical form before execution.
5. Upgrade conditionals from binary to ternary (true/false/unknown).

## Non-goals

- Per-type call-site sugar (e.g., `mutate_state` shorthand) — follow-up work.
- Compact ending syntax — separate concern.
- Changes to `blueprint-types.md` content beyond convention updates.
- Building the Python walker — planned separately.

## Design

### Change 1: `consequences:` everywhere

**Problem:** The same concept (a typed operation from the 22 consequence types) uses
three different names:

| Context | Current key | Items are |
|---------|------------|-----------|
| Action node | `actions:` | consequences |
| Response handler | `consequence:` (singular) | consequences |
| Ending | `consequences:` | consequences |

**Fix:** Use `consequences:` (plural) everywhere. Parallels `preconditions` naming.

**Schema changes:**
- `schema/authoring/node-types.json`: `action_node.actions` → `action_node.consequences`
- `schema/authoring/node-types.json`: `response_handler.consequence` → `response_handler.consequences`
- `schema/authoring/workflow.json`: ending `consequences` — no change (already correct)

**Type catalog changes:**
- `blueprint-types.md`: action node signature `action(actions[], ...)` → `action(consequences[], ...)`

### Change 2: Default failure routing

**Problem:** Every action node requires `on_failure`, even though most route to a
generic error ending. This adds a line to every action node for predictable behavior.

**Fix:** Add a required `default_error` field at the workflow level. `on_failure`
becomes optional on action nodes — when omitted, the walker routes to `default_error`.

**Workflow-level addition:**
```yaml
name: my-workflow
version: "1.0.0"
start_node: first_node
default_error: error_generic   # required, must reference a valid ending

endings:
  error_generic:
    type: error
    message: "Unexpected failure at ${current_node}"
```

**Walker rule:** Node has `on_failure`? Use it. Missing? Use workflow `default_error`.

**Schema changes:**
- `schema/authoring/workflow.json`: add required `default_error` field with
  `$ref: common.json#/$defs/node_reference`
- `schema/authoring/node-types.json`: remove `on_failure` from `action_node.required`

### Change 3: Ternary conditionals with flattened branches

**Problem:** Conditionals are binary (true/false) with branches nested under a
`branches:` wrapper. There is no handling for evaluation failure (condition can't
be resolved), which conflates "condition is false" with "couldn't evaluate."

**Fix:** Two changes:
1. Flatten `branches:` — `on_true` and `on_false` become direct keys on the node.
2. Add optional `on_unknown` for evaluation failure. When omitted, routes to
   `default_error`.

**Before:**
```yaml
check_config:
  type: conditional
  condition:
    type: path_check
    path: "data/config.yaml"
    check: is_file
  branches:
    on_true: load_config
    on_false: ask_source_type
```

**After:**
```yaml
check_config:
  type: conditional
  condition:
    type: path_check
    path: "data/config.yaml"
    check: is_file
  on_true: load_config
  on_false: ask_source_type
  on_unknown: error_config_check  # optional, defaults to default_error
```

**Schema changes:**
- `schema/authoring/node-types.json`: remove `branches` object from
  `conditional_node`; add `on_true`, `on_false` (required), `on_unknown` (optional)
  as direct properties.

**Type catalog changes:**
- `blueprint-types.md`: update conditional signature from
  `conditional(condition, branches{on_true, on_false}, audit?)` to
  `conditional(condition, on_true, on_false, on_unknown?, audit?)`
- Update conventions: "Preconditions return boolean" → "Preconditions return
  true, false, or unknown (when evaluation fails)."

### Change 4: Condition shorthand

**Problem:** The most common conditional pattern wraps a simple expression in
three levels of nesting:
```yaml
condition:
  type: evaluate_expression
  expression: "flags.content_changed == true"
```

Composite conditions similarly nest `type: composite, operator: all, conditions: [...]`.

**Fix:** Two sugar forms that the walker normalizes before execution:

**String shorthand** — when `condition` is a string, normalize to
`{type: evaluate_expression, expression: <string>}`:
```yaml
condition: "flags.content_changed == true"
```

**Composite shorthand** — `all:`, `any:`, `none:`, `xor:` as direct keys normalize
to `{type: composite, operator: <key>, conditions: <array>}`:
```yaml
condition:
  all:
    - type: tool_check
      tool: git
      capability: available
    - type: network_available
```

**Full object form always available** as escape hatch for complex or unusual cases.

**Walker normalization rule:**
- `condition` is string → `{type: evaluate_expression, expression: <string>}`
- `condition` is object with key in `{all, any, none, xor}` AND no `type:` key → `{type: composite, operator: <key>, conditions: <value>}`
- `condition` is object with `type:` key → pass through (canonical form)

**Schema changes:**
- `schema/authoring/node-types.json`: `conditional_node.condition` accepts string
  OR object. The object form accepts either `{type: ...}` (canonical) or
  `{all|any|none|xor: [...]}` (composite sugar).

### Change 5: Response handler shorthand and dynamic routing

**Problem:** Response handlers are verbose for the common case of "pick an option,
go to a node":
```yaml
on_response:
  git:
    consequence:
      - type: mutate_state
        operation: set
        field: source_type
        value: git
    next_node: git_setup
```

Enumerating N options with nearly identical handlers is redundant when the option ID
already carries the routing information.

**Fix:** Two sugar forms:

**String shorthand** — handler value is a string, normalize to `{next_node: <string>}`:
```yaml
on_response:
  local: done   # → { next_node: "done" }
```

**Dynamic routing** — `next_node` supports `${}` interpolation for runtime dispatch:
```yaml
on_response:
  selected:
    next_node: "${user_responses.ask_source.handler_id}_setup"
```

Or with the string shorthand for the ultimate one-liner:
```yaml
on_response:
  selected: "${user_responses.show_candidates.action}"
```

**Walker validation rule:**
- Literal `next_node` (no `${}`): must resolve to a valid node or ending ID — static check
- Interpolated `next_node` (contains `${}`): validated at execution time only

**Schema changes:**
- `schema/authoring/node-types.json`: `response_handler` in `on_response` accepts
  string OR object. String normalizes to `{next_node: <string>}`.

### Change 6: Optional `initial_state`

**Problem:** Every workflow declares `initial_state` with boilerplate empty objects:
```yaml
initial_state:
  phase: setup
  flags: {}
  computed: {}
```

**Fix:** `initial_state` becomes optional. When omitted, the walker initializes with
empty defaults. When provided, only non-default fields need to be declared — no need
for empty `flags: {}` or `computed: {}`.

**Walker initialization rule:** Always ensure `flags` and `computed` exist as empty
objects in state, regardless of whether `initial_state` declares them.

**Schema changes:**
- `schema/authoring/workflow.json`: remove `initial_state` from any implicit
  requirement (it is already not in `required`, but examples always include it —
  establish that omission is valid).

## File changes

### Schema updates
- `schema/authoring/workflow.json` — add required `default_error`, confirm
  `initial_state` optional
- `schema/authoring/node-types.json` — `actions`→`consequences` rename,
  `consequence`→`consequences` rename, flatten `branches`, add `on_unknown`,
  condition sugar (string | object), response handler sugar (string | object),
  remove `on_failure` from required

### Type catalog
- `blueprint-types.md` — update node signatures (action, conditional), update
  conventions (ternary preconditions)

### Examples
- `examples.md` — rewrite all 3 workflows using compressed format. Must demonstrate:
  - Default failure routing (omitted `on_failure`)
  - Ternary conditional (`on_unknown`)
  - Condition string shorthand
  - Composite shorthand (`all:`)
  - Bare response handler (string form)
  - Dynamic `${}` routing in response handler
  - Omitted `initial_state` boilerplate (no empty `flags: {}`)

### Documentation
- `CLAUDE.md` — update any references to `actions:` or `branches:`
- `README.md` — update if workflow snippets appear
- `CHANGELOG.md` — add entry

### Cross-repo (hiivmind-blueprint)
- `lib/patterns/execution-guide.md` — update for new node structure
- `lib/patterns/authoring-guide.md` — update for new syntax options

## Walker normalization spec

The Python walker normalizes sugar forms to canonical form **before** execution.
After normalization, the engine always sees canonical form. This means the LLM
execution layer never encounters sugar — it always gets the explicit structure.

| Input form | Canonical form |
|-----------|---------------|
| `condition: "expr"` | `condition: {type: evaluate_expression, expression: "expr"}` |
| `condition: {all: [...]}` | `condition: {type: composite, operator: all, conditions: [...]}` |
| `on_failure` omitted | `on_failure: <workflow.default_error>` |
| `on_unknown` omitted | `on_unknown: <workflow.default_error>` |
| `handler: "node_id"` | `handler: {next_node: "node_id"}` |
| `initial_state` omitted | `initial_state: {flags: {}, computed: {}}` |

## Success criteria

1. All 3 example workflows rewritten using compressed syntax.
2. Schema validates both sugar and canonical forms.
3. `blueprint-types.md` signatures updated.
4. No remaining references to `actions:` (on action nodes) or `branches:` in
   workflow-facing files.
5. Walker normalization table is complete and unambiguous.

## Version

This work lands on the same `refactor/type-catalog-collapse` branch as v7.0.0.
No additional version bump needed.
