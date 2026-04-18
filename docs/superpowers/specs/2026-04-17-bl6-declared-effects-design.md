# BL6 — `declared_effects` Workflow-Level Block (v8.1.0)

**Date:** 2026-04-17
**Status:** DESIGN
**Target version:** blueprint-lib v8.1.0 (minor, purely additive)
**Source of truth:** hiivmind-blueprint-central commit `c13d65e`, S2 spec §3 — effect-envelope design.
**Addendum reference:** hiivmind-blueprint-central `docs/superpowers/specs/2026-04-16-s1-blueprint-lib-alignment-addendum.md` lines 257, 261–306, 352–357.

---

## Goal

Add the optional top-level `declared_effects:` block to the blueprint-lib workflow schema so authors can narrow the inferred `data_mcps` effect envelope on a per-alias basis. Unblocks S3 implementation in hiivmind-blueprint-central, which currently cannot ship because blueprint-lib's workflow schema rejects the key under its `additionalProperties: false` root.

No existing type signature changes. No node-type changes. No behavior change for workflows that omit the block.

## Background

As of blueprint-lib v8.0.0 (shipped 2026-04-17) the workflow schema already carries BL1–BL5:

- BL1: `mcp_tool_call` consequence
- BL2: workflow-scoped `payload_types`
- BL3: `trust_mode` enum
- BL4: `data_mcps` alias→`name@semver` map
- BL5: `ending` node primitive (replaces the `terminal_nodes` list originally proposed)

S2 §3 defines a hybrid effect-envelope model:

- **Default envelope** is *inferred* from `data_mcps`: "any tool exposed by any declared MCP may be invoked, arbitrarily often." Zero author burden. Already supported in v8.0.0.
- **Explicit `declared_effects:`** narrows the envelope per alias. **Not yet supported** — schema rejects the key.

BL6 ships the explicit-narrowing surface.

## Non-goals

- Cross-alias validation (e.g. `tools ⊆ data_mcps.<alias>.tools`, `alias ∈ data_mcps`). JSON Schema cannot cross-reference across MCP servers; blueprint-lib delegates semantic validation to the consuming runtime (control-MCP), consistent with the `mcp_tool_call` model already in place.
- Runtime effect budget tally (S2 §3.7 out-of-scope).
- Reachability analysis / `static_max` computation (S2 §3.5 enforcement territory — control-MCP concern).
- Richer envelope keys (data volume caps, time windows, resource classes per SS P7). Schema reserves unknown keys; these are future extensions.
- Changing the default inferred envelope. Workflows without `declared_effects:` keep v8.0.0 semantics.

## Deliverables

| File | Change |
|---|---|
| `schema/authoring/workflow.json` | Add optional `declared_effects` property (schema shape below). Bump `$comment` version note. |
| `blueprint-types.md` | Add a new `## Declared Effects` top-level section (parallel to the existing `## Payload Types` section) describing the block and its three value forms. |
| `examples.md` | Extend the existing `## 4. MCP-Delegated Query` example with a `declared_effects:` block so the worked example exercises it. |
| `CHANGELOG.md` | New `[8.1.0] - 2026-04-17` entry — Added only (no Changed / Fixed). |
| `package.yaml` | Bump version to `8.1.0`. Stats unchanged (no new types). |
| `tests/fixtures/workflows/v8_declared_effects_narrow/input.yaml` | Positive fixture — explicit narrowed envelope. |
| `tests/fixtures/workflows/v8_declared_effects_forbidden/input.yaml` | Positive fixture — `alias: forbidden` literal. |
| `tests/fixtures/workflows/v8_declared_effects_unknown_key/input.yaml` | Positive fixture — forward-compat extension keys under an alias object. |
| `tests/fixtures/workflows/_negative/declared_effects_bad_value/input.yaml` | Neither object nor `"forbidden"` string. |
| `tests/fixtures/workflows/_negative/declared_effects_bad_alias_name/input.yaml` | Alias fails `^[a-z_][a-z0-9_-]*$`. |
| `tests/fixtures/workflows/_negative/declared_effects_negative_max_count/input.yaml` | `max_call_count: -1`. |

**Cross-repo sync** (required per `CLAUDE.md`'s hard-requirement checklist):

| Location | Change |
|---|---|
| `hiivmind-blueprint/lib/patterns/authoring-guide.md` | Add `declared_effects:` subsection showing the three value forms; position alongside existing `trust_mode`/`data_mcps` authoring guidance. |
| `hiivmind-blueprint/lib/patterns/execution-guide.md` | One-paragraph note stating load-time envelope enforcement is the control-MCP's responsibility, not blueprint-lib's — consistent with `mcp_tool_call`'s type-agnostic posture. |
| `hiivmind-blueprint` skill bundle | Re-ship `blueprint-types.md` on next release. |

**No sync needed** in `hiivmind-blueprint-central`: the addendum already documents BL6 at lines 261–306; only its `Status: PROPOSED` → `SHIPPED` note (line 290) and the `Pending upstream ship` resolution note (lines 352–357) need flipping. That flip happens as a separate blueprint-central commit after this PR merges.

## Schema shape

Added under `workflow.json#/properties`:

```json
"declared_effects": {
  "type": "object",
  "description": "Optional per-alias effect envelope narrowing the inferred default from data_mcps (BL6). Keys are aliases declared in data_mcps (or unused aliases used as forbidden documentation). Values are either the string literal 'forbidden' or an object with optional 'tools' and 'max_call_count'. Cross-alias validation (tools ⊆ data_mcps.<alias>.tools, alias ∈ data_mcps) is delegated to the consuming runtime.",
  "propertyNames": { "pattern": "^[a-z_][a-z0-9_-]*$" },
  "additionalProperties": {
    "oneOf": [
      { "const": "forbidden" },
      {
        "type": "object",
        "properties": {
          "tools": {
            "type": "array",
            "items": { "type": "string", "pattern": "^[a-z_][a-z0-9_]*$" },
            "uniqueItems": true,
            "description": "Allowed tool names on this alias. Subset of the data-MCP's published tools (runtime-checked)."
          },
          "max_call_count": {
            "type": "integer",
            "minimum": 0,
            "description": "Hard cap on invocations of this alias per workflow run (static upper bound)."
          }
        },
        "additionalProperties": true
      }
    ]
  }
}
```

### Design notes on the schema

- **`additionalProperties: true` inside the alias object** — intentional. S2 §3.4 reserves unknown keys for forward-compatible extension (data volume caps, time windows, resource classes per SS P7). Schema accepts them today so v0 workflows don't break when v1 adds vocabulary.
- **`max_call_count: 0` is valid** — equivalent to `forbidden` at the allowlist level but allows authors to keep the alias entry with its `tools: []` for documentation. Not conceptually different from `forbidden` in enforcement terms.
- **`propertyNames` pattern on `declared_effects`** mirrors the pattern already in `data_mcps` (lines 31 of current `workflow.json`) so aliases have identical shape constraints.
- **Alias name pattern for `tools` items** (`^[a-z_][a-z0-9_]*$`) matches MCP tool naming conventions — lowercase snake_case, no hyphens. Stricter than alias names because aliases are workflow-local labels whereas tool names are MCP-server-exported identifiers.

## `blueprint-types.md` catalog entry (proposed content)

New top-level section, placed immediately after `## Payload Types`:

```markdown
## Declared Effects

Optional workflow-level block narrowing the default inferred effect envelope
from `data_mcps`. Workflows that omit the block accept any tool exposed by any
declared alias, invoked arbitrarily many times. Authors who want fine-grained
control add a `declared_effects:` block at the top level of the workflow YAML.

Each key is an alias (same naming rules as `data_mcps`); each value is either:

| Value form | Meaning |
|---|---|
| `forbidden` | Explicit deny — alias MUST NOT be invoked from this workflow. Readable documentation even when the alias is absent from `data_mcps`. |
| `{ tools: [...] }` | Restrict to a subset of the MCP's tools. Unlisted tools are forbidden. |
| `{ tools: [...], max_call_count: N }` | As above, with a hard cap on total invocations across the workflow run. |
| `{ max_call_count: N }` | Cap invocations without narrowing the tool list. |

Cross-alias validation (is `<tool>` actually exported by the MCP? is the alias
declared in `data_mcps`?) is enforced at workflow load time by the consuming
runtime — blueprint-lib validates only the syntactic shape.
```

## Worked example (extension to `examples.md` §4)

The existing `## 4. MCP-Delegated Query` example declares `data_mcps` for `crm` and `billing`. Extend it with:

```yaml
declared_effects:
  crm:
    tools: [search_customers, get_account]   # read-only subset
  billing:
    tools: [create_invoice]
    max_call_count: 1                        # cap across workflow run
  shell: forbidden                           # documentation — not in data_mcps
```

The prose around the example calls out that this block is optional and describes what each value form means. The pre-existing `mcp_tool_call` consequences in that example already invoke `crm.search_customers` / `billing.create_invoice`, so the narrowing is faithful to what the workflow actually does.

## Fixtures

### Positive

- **`v8_declared_effects_narrow`** — full workflow declaring two aliases in `data_mcps` plus `declared_effects` with both `tools` and `max_call_count` on one, `tools` only on the other.
- **`v8_declared_effects_forbidden`** — alias with value `forbidden` (both declared and undeclared aliases).
- **`v8_declared_effects_unknown_key`** — alias object including a non-standard key (e.g. `data_volume_cap_mb: 100`) to confirm forward-compat acceptance.

### Negative (must fail validation)

- **`declared_effects_bad_value`** — alias set to `true` (neither object nor `"forbidden"` string).
- **`declared_effects_bad_alias_name`** — alias like `CRM` or `billing-1!` that fails the `propertyNames` pattern.
- **`declared_effects_negative_max_count`** — `max_call_count: -1`.

## Validation

`scripts/validate-workflows.sh` already exists from v8.0.0 and walks `tests/fixtures/workflows/`. New fixtures under that tree are picked up automatically. Negative fixtures under `_negative/` are expected to fail and counted as such.

## Versioning

v8.0.0 → v8.1.0 per `CLAUDE.md`'s versioning table: "Add new types → Minor." `declared_effects` is a new optional top-level field; omitting it is equivalent to prior behavior. No existing workflow breaks.

`$comment` in `workflow.json` header bumps from "Schema version 4.0" to "Schema version 4.1" with a note about BL6.

## Out of scope

- Static reachability analysis or `count_exceeds_envelope` checks (S2 §3.5). Control-MCP concern.
- `signature_status`, `illegal_state`, session-bound gated-mode machinery (S2 §§1, 4). Control-MCP concern.
- Updating the S1/S2 addendum status notes in blueprint-central. Happens as a follow-up commit in that repo post-merge.
- Tagging/releasing v8.1.0. Separate release step after merge to `develop`.

## Risks

- **Alias typo in `declared_effects` silently passes blueprint-lib schema.** Mitigation: control-MCP enforces `alias ∈ data_mcps OR value == "forbidden"` at load time. Documented as author contract in the catalog entry.
- **Forward-compat trap: unknown keys under alias object are silently accepted today.** Authors who misspell a future key (`max_call_coutn: 3`) don't get a warning. Accepted risk — consistent with the spec §3.4 decision to reserve the keyspace.
- **`max_call_count` interpretation ambiguity.** "Across workflow run" in S2 §3.4 means static upper bound summed across all reachable paths through the workflow DAG. Catalog entry states this explicitly so the control-MCP has a contract to enforce.

## Sequencing

1. Merge this BL6 PR to `hiivmind-blueprint-lib` develop, tag v8.1.0.
2. Update `hiivmind-blueprint` authoring/execution guides (separate PR, tag when ready).
3. In `hiivmind-blueprint-central`, flip `Status: PROPOSED` → `SHIPPED` in the S1 addendum and clear the resolution note at line 352.
4. S3 implementation proceeds with the envelope surface available.

---

## Task breakdown (handoff to writing-plans)

Seven tasks, all low-risk prose/schema/fixture edits:

1. **Schema** — add `declared_effects` to `workflow.json`, bump header comment.
2. **Catalog** — add subsection to `blueprint-types.md`.
3. **Example** — extend `## 4. MCP-Delegated Query` in `examples.md`.
4. **Fixtures** — three positive + three negative under `tests/fixtures/workflows/`.
5. **Version + Changelog** — bump `package.yaml` to 8.1.0; add `[8.1.0]` entry.
6. **Blueprint repo sync** — authoring-guide and execution-guide updates.
7. **Verification** — run `scripts/validate-workflows.sh` and existing validators; spot-check a single fixture via ajv-cli.
