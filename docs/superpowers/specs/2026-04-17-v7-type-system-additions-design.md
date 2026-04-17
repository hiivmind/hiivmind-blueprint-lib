# Blueprint-lib v7.0 — Type System Additions (BL1–BL5)

> **Status:** DESIGN
> **Context:** Reconciles blueprint-lib with the gaps identified in [hiivmind-blueprint-central S1 alignment addendum](https://github.com/hiivmind/hiivmind-blueprint-central/blob/main/docs/superpowers/specs/2026-04-16-s1-blueprint-lib-alignment-addendum.md).
> **Version:** v7.0.0 — major, hard cutover, no deprecation window.

## Scope

Five coordinated additions to blueprint-lib's type system, landing in a single release:

| # | Addition | Category | Core change |
|---|---|---|---|
| BL1 | `mcp_tool_call` | Consequence | Invoke a tool on a declared data-MCP alias. |
| BL2 | Payload Types | New section in `blueprint-types.md` + new workflow-level `payload_types:` block | Convention for author-declared data shapes (per-workflow; no central registry). |
| BL3 | `trust_mode` | Workflow field | Declarative metadata: `stateless \| gated`. |
| BL4 | `data_mcps` | Workflow field | Alias → `"name@semver-range"` map. |
| BL5 | `ending` | **New 4th node type** | Retires top-level `endings:` block; endings live in `nodes:`. |

## Thesis

Current blueprint-lib has three asymmetries:

1. **Endings have authoring schema but no catalog entry.** The `endings:` top-level block in `schema/authoring/workflow.json` has a rich structure (outcome types, behaviors, recovery) but `blueprint-types.md` does not list endings as a type. Every other blueprint-lib type exists in both the authoring schema *and* the runtime catalog.
2. **MCP-tool invocation has no consequence type.** `spawn_agent`, `invoke_skill`, `run_command`, `web_ops` each cover adjacent concerns but none covers "invoke a tool on a connected MCP server," which is required for control-MCP delivery and any workflow that integrates with the external MCP ecosystem.
3. **Workflow front-matter lacks declarative hooks** for trust-mode and data-MCP dependency metadata. Both are required by the S1 control-MCP architecture and are natural workflow-level declarations.

This spec closes each gap without relaxing the minimal-primitives discipline. The nodes-map grows from three to four kinds (adding `ending`); the catalog grows from three sections to four (adding Payload Types). Both are principled expansions, not drift.

## Out of scope

- Control-MCP or runtime implementation (S3 of hiivmind-blueprint-central).
- Workflow-signing / trust enforcement mechanics (S2).
- Authoring-pipeline, marketplace, or Managed Agents changes.
- The composite walker in `hiivmind-blueprint-mcp` — a follow-up verification pass is required (see §Cross-repo sync below) but walker modifications, if needed, happen in that repo.

---

## BL5 — `ending` node type (migration anchor)

Presented first because it is the only change with significant migration surface.

### Catalog entry (new, under `## Nodes` in `blueprint-types.md`)

```
ending(outcome, message?, summary?, details?, category?,
       recovery?, behavior?, consequences?)
  outcome  ∈ {success, failure, error, cancelled, indeterminate}
  behavior = {type: silent | delegate | restart, …}  (optional; default: display message/summary)
  → terminate the workflow with the given outcome; run consequences
    best-effort (logged on failure); then apply behavior.
```

The type definition itself is the terminality signal. Schema forbids all transition slots on `ending` nodes; reaching an ending always emits `terminal: true` to the runtime FSM.

### Schema changes

**`schema/authoring/node-types.json`:**

1. Add `"ending"` to the `type` enum.
2. Add `ending_node` `$def` parallel to `action_node` / `conditional_node` / `user_prompt_node`:

```json
"ending_node": {
  "type": "object",
  "required": ["type", "outcome"],
  "properties": {
    "type":        { "const": "ending" },
    "outcome":     { "enum": ["success", "failure", "error", "cancelled", "indeterminate"] },
    "category":    { "type": "string" },
    "message":     { "type": "string" },
    "summary":     { "type": "object", "additionalProperties": true },
    "details":     { "type": "string" },
    "recovery":    { "oneOf": [ {"type": "string"}, { /* structured form, carried over unchanged */ } ] },
    "consequences":{ "type": "array", "items": { "$ref": "#/$defs/consequence" } },
    "behavior":    { /* oneOf: silent | delegate | restart, carried over unchanged */ }
  },
  "additionalProperties": false,
  "not": {
    "anyOf": [
      { "required": ["on_success"] }, { "required": ["on_failure"] },
      { "required": ["on_true"] },    { "required": ["on_false"] },
      { "required": ["on_unknown"] }, { "required": ["on_response"] }
    ]
  }
}
```

3. Add the `if/then` dispatch case to the root `node` oneOf.

**`schema/authoring/workflow.json`:**

1. Remove `endings` from the `required` array.
2. Remove the `endings` property entirely.
3. Remove the `ending` `$def` at the bottom of the file.
4. `additionalProperties: false` remains — presence of a top-level `endings:` key in a v7 workflow is a hard load-time error.
5. `default_error`: its `$ref` stays `common.json#/$defs/node_reference`; the description updates to *"Default node reference for unhandled failures. Must reference a node of type `ending`."* Load-time cross-check validates this.

### Load-time rules (new)

| Rule | Trigger | Error code |
|---|---|---|
| `ending` node with any transition slot | Schema | `schema_violation` |
| Non-ending node with no outgoing transitions | Post-schema graph check | `terminal_without_type_ending` (new) |
| Top-level `endings:` key present | Schema (additionalProperties: false) | `schema_violation` with migration hint in message |
| `default_error` target is not of type `ending` | Cross-reference validation | `default_error_must_be_ending` (new) |

### Fields migrate 1:1 from the current `endings:` block

| `endings:` entry field | `nodes:` entry (type: ending) field | Notes |
|---|---|---|
| `type` (enum: success/failure/error/cancelled/indeterminate) | `outcome` (same enum) | Renamed to avoid collision with the node's `type` key. |
| `category` | `category` | Unchanged. |
| `message` | `message` | Unchanged. |
| `summary` | `summary` | Unchanged. |
| `details` | `details` | Unchanged. |
| `recovery` (string or structured) | `recovery` | Unchanged. |
| `consequences` (best-effort array) | `consequences` | Unchanged. Best-effort semantics unchanged. |
| `behavior` (silent / delegate / restart) | `behavior` | Unchanged. Restart sub-form (target_node, max_restarts, reset_state) preserved. |

### Authoring example — before / after

```yaml
# v6.x (before)
nodes:
  clone_repo:
    type: action
    on_success: done
endings:
  done:
    type: success
    message: "Cloned."
```

```yaml
# v7.0 (after)
nodes:
  clone_repo:
    type: action
    on_success: done
  done:
    type: ending
    outcome: success
    message: "Cloned."
```

The transition arrow (`on_success: done`) is unchanged. Only the target block name and the target node's structure change.

### Restart semantics — preserved

The existing `behavior: { type: restart, target_node, max_restarts, reset_state }` form carries over intact. An `ending` node with `behavior: restart` is still a terminal node from the type system's perspective (it emits an outcome; the runtime decides whether to re-enter at `target_node` bounded by `max_restarts`). The conflation between "terminal outcome emitted" and "runtime re-entry possible" is acknowledged: terminality is about outcome declaration, not about absolute FSM exit.

---

## BL2 — Payload Types (per-workflow, no central registry)

### Key design decision: no central catalog of instances

A central registry of payload shapes does not scale to hundreds of external MCP services. `blueprint-types.md` owns the **convention** (how payload types are declared, named, referenced) but **not the instances**. Instances live at the workflow level only. No cross-workflow reuse via imports or registries in this release — the simplest sourcing model wins; we can extend later if drift becomes a real pain point.

### `blueprint-types.md` — new `## Payload Types` section

Documents the convention only:

```
# Payload Types (authoring convention)

Workflows declare payload types at the top in a `payload_types:` block.
References from consequences use the form `name@version`.

Declaration syntax:

  <name>@<version>:
    <field>: <type> (<constraints>, <optional-marker>)

Supported type descriptors:

  string             — UTF-8 text
  integer            — int64
  boolean            — true/false
  array<T>           — homogeneous array of T
  object             — arbitrary map
  enum{a, b, c}      — one of the listed literals

Constraints (optional, parenthesised):

  min_length=N, max_length=N   — string, array
  min=N, max=N                 — integer
  pattern="regex"              — string
  required / optional          — modifier (default: required)

Example:

  shake_params@1:
    question: string (min_length=1)
    context:  string (optional)
    max_tokens: integer (min=1, max=4096, optional)
```

No instances ship in v7.0. First real payload types land in workflows as they need them.

### Workflow schema change

**`schema/authoring/workflow.json`:** new optional top-level property `payload_types`.

**New file `schema/authoring/payload-types.json`:** defines the shape of a single payload-type entry (field map, type descriptors, constraints). Referenced from `workflow.json`'s `payload_types.additionalProperties`.

```json
"payload_types": {
  "type": "object",
  "description": "Workflow-scoped payload type declarations. See payload-types.json.",
  "propertyNames": { "pattern": "^[a-z_][a-z0-9_]*@\\d+$" },
  "additionalProperties": { "$ref": "payload-types.json#/$defs/payload_type" }
}
```

### Load-time rules

| Rule | Trigger | Error code |
|---|---|---|
| `params_type` on a consequence does not resolve in workflow's `payload_types:` | Cross-reference validation | `unresolved_params_type` |
| `payload_types` entry key does not match `^[a-z_][a-z0-9_]*@\d+$` | Schema | `schema_violation` |

Blueprint-lib does **not** validate that a consequence's `params` block conforms to the referenced payload type's field list. That is runtime concern (execution-guide). Blueprint-lib only validates that the *reference* resolves.

---

## BL1 — `mcp_tool_call` consequence

### Catalog entry (new, under `## Consequences` → `### Core — control`, parallel to `spawn_agent` and `invoke_skill`)

```
mcp_tool_call(tool, params, params_type?, store_as?)
  tool        = "<alias>.<tool_name>" — alias declared in workflow data_mcps:
  params      = map of literals + ${} state interpolation
  params_type = optional reference to a payload type declared in the workflow's
                payload_types: block (name@version)
  store_as    = optional state field to receive the tool result
  → invoke an MCP tool via the caller's MCP client; store the tool result at
    store_as if provided.
```

**Catalog note:** the catalog describes the *effect* (tool invocation + result capture), not the *invocation topology*. Whether the runtime calls the tool directly or emits a tool reference for the LLM's own MCP client to invoke is an execution-guide concern. This distinction matters for the S1 control-MCP's directionality-inversion invariant but does not leak into blueprint-lib.

### Schema impact

Added to `schema/authoring/node-types.json` as a new `consequence` variant (join the existing oneOf). Required keys: `type: "mcp_tool_call"`, `tool`, `params`. Optional: `params_type`, `store_as`.

### Load-time rules

| Rule | Trigger | Error code |
|---|---|---|
| `tool` does not match `^[a-z_][a-z0-9_-]*\.[a-z_][a-z0-9_-]*$` | Schema | `schema_violation` |
| Alias prefix in `tool` (part before `.`) is not a key of workflow `data_mcps:` | Cross-reference validation | `unresolved_alias` |
| `params_type` does not resolve in workflow `payload_types:` | Cross-reference validation | `unresolved_params_type` |

---

## BL3 — `trust_mode` workflow field

### Schema change

New optional property in `schema/authoring/workflow.json`:

```json
"trust_mode": {
  "type": "string",
  "enum": ["stateless", "gated"],
  "default": "stateless",
  "description": "Workflow-level trust mode. Declarative metadata consumed by runtimes; blueprint-lib validates the enum only."
}
```

Blueprint-lib validates the enum and nothing else. Consumers (hiivmind-control-mcp) apply semantic meaning.

No catalog entry is required — this is workflow front-matter, not a type.

---

## BL4 — `data_mcps` workflow field

### Schema change

New optional property in `schema/authoring/workflow.json`:

```json
"data_mcps": {
  "type": "object",
  "description": "Map of alias to MCP server name + semver range (e.g. 'eightball-tools@^1'). Aliases are used as prefixes on mcp_tool_call tool references.",
  "propertyNames": { "pattern": "^[a-z_][a-z0-9_-]*$" },
  "additionalProperties": {
    "type": "string",
    "pattern": "^[\\w-]+@[\\w.\\-\\^~><=*|,\\s]+$"
  }
}
```

### Load-time cross-check

Every `mcp_tool_call` whose `tool: foo.bar` requires the workflow's `data_mcps:` to include an `foo:` alias. Absent alias → `unresolved_alias`.

No catalog entry — workflow front-matter.

---

## Cross-repo sync (HARD REQUIREMENT per CLAUDE.md)

Each change below must be made in the same release:

| Location | Change |
|---|---|
| `blueprint-types.md` | Add `ending` node entry; add `mcp_tool_call` consequence entry; add new `## Payload Types` section. Update counts/stats. |
| `examples.md` | Rewrite all three composite examples: endings migrated into `nodes:` map; add an example using `mcp_tool_call` + `payload_types:` + `data_mcps:`. |
| `schema/authoring/workflow.json` | Remove `endings` requirement + property + `$def`. Add `trust_mode`, `data_mcps`, `payload_types` properties. Update description on `default_error`. |
| `schema/authoring/node-types.json` | Add `ending` to node type enum + `ending_node` `$def` + dispatch case. Add `mcp_tool_call` consequence variant. |
| `schema/authoring/payload-types.json` | **New file**. Defines the shape of a single payload-type entry. |
| `hiivmind-blueprint/lib/patterns/authoring-guide.md` | Update type tables. Add authoring sections for ending nodes, payload types, and `mcp_tool_call`. |
| `hiivmind-blueprint/lib/patterns/execution-guide.md` | Update dispatch semantics: `ending` node terminal logic; `mcp_tool_call` invocation topology (runtime vs LLM-client). |
| `hiivmind-blueprint` skill bundle | Re-ship `blueprint-types.md` after changes. |
| `package.yaml` | Bump to v7.0.0. Update stats (node primitive count 3→4; add Payload Types section marker). |
| `CHANGELOG.md` | v7.0.0 entry: five additions + endings migration guide. |

### Follow-up verification (tracked, not in this spec's implementation scope)

- `hiivmind-blueprint-mcp` walker: confirm `confirm` / `gated_action` / `goal_seek` composites still expand to valid primitives under the new ending-as-node model. Likely impact: `goal_seek`'s completion-predicate dispatcher may reference ending IDs; fixture tests should catch divergence.
- Fixtures in `tests/fixtures/composites/` may need refresh to reflect ending-as-node.

## Migration tooling (optional)

A shell/yq helper in `scripts/migrate-v6-to-v7.sh` that rewrites a v6.x workflow file:

1. For each entry under `endings:`, move it into `nodes:` with the key preserved, adding `type: ending` and renaming the entry's `type:` field to `outcome:`.
2. Delete the top-level `endings:` block.
3. Leaves transitions untouched — they already reference the right names.

Not required for v7.0 to ship; ships alongside if time permits.

## Versioning

Major bump from v6.x to v7.0.0. Per `CLAUDE.md`'s versioning rules:

- Removing the top-level `endings:` block is a removal of a schema-level feature → major.
- Adding four new types + one new catalog section → minor (subsumed by the major).
- All together: v7.0.0.

## Risks and open considerations

1. **Walker divergence risk.** Composite walker in `hiivmind-blueprint-mcp` may hard-code assumptions about the shape of ending targets. Mitigation: fixture-driven pre-release check (run composite expansion tests against v7 workflow fixtures before cutting v7.0).
2. **Migration friction on existing hiivmind repos.** Every workflow in hiivmind-pulse-gh, hiivmind-corpus-*, and consuming repos must migrate at the same time. Mitigation: migration script + announcement in CHANGELOG; consuming-repo owners notified before cut.
3. **Payload-type naming collisions within a workflow.** Since `payload_types:` is per-workflow, there is no cross-workflow namespace to worry about. But a single workflow author may accidentally reuse `foo@1` for two different shapes. Mitigation: key is the full `name@version` — duplicate keys are a YAML-level error at load.
4. **No payload-type reuse in v7.0.** Accepted tradeoff. If real drift pain emerges, a follow-up spec can introduce imports or per-repo shape libraries without breaking the v7.0 convention.

## What this spec does not decide

- The shape of the migration script (optional deliverable).
- Whether blueprint-lib ships a "warning" CLI to scan v6 workflows for v7 breakages pre-upgrade — nice-to-have, not required.
- Any changes to the three composites (confirm / gated_action / goal_seek). Those are in `blueprint-composites.md`, not `blueprint-types.md`, and their primitive expansion may or may not need updates — that determination happens when the walker is re-verified post-v7.
