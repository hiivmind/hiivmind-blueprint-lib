# Composite Nodes — Design

**Date:** 2026-04-14
**Status:** Approved
**Scope:** `hiivmind-blueprint-lib` — add composite node catalog and schema support for the v1 composite set (`confirm`, `gated_action`). Cross-repo: new principles in `hiivmind-blueprint-central`. **Walker implementation is out of scope for this spec** — expansion code lives in a separate package (`hiivmind-blueprint-mcp`) with Python and TypeScript flavors, covered by a follow-up spec.

## Context

The current workflow language has three primitives: `action`, `conditional`, `user_prompt`. Real-world workflows repeat the same multi-node patterns — confirmation gates, multi-way condition dispatch, prose-plus-choice presentations. Authors hand-write each occurrence, which is verbose, error-prone, and inconsistent across workflows.

Some patterns also carry **safety invariants** that can't be enforced by author discipline alone. The canonical example: a confirmation gating a destructive action must separate classification, evidence, and gating into distinct structural steps so no single LLM-interpreted node can collapse the decision. Hand-written patterns get this right most of the time; the exceptions are the problem.

Composite nodes address both — reduce boilerplate AND mechanically enforce structural patterns.

## Goals

1. Define a **composite node catalog** (`blueprint-composites.md`) separate from the runtime primitive catalog, establishing that composites are authoring-time only and never reach the runtime LLM.
2. Specify the **v1 composite set** (`confirm`, `gated_action`) — their call-site signatures, expansion shapes, and safety invariants — as a binding contract that downstream walker implementations must satisfy.
3. Extend the **authoring schema** so composite call sites validate at authoring time and failed invariants (e.g. `confirm` missing `store_as`) fail with clear errors.
4. Keep the runtime LLM's world unchanged — still three primitive node types, still the same `blueprint-types.md` it reads today.
5. Codify the design discipline as principles in `hiivmind-blueprint-central`.

Walker implementation is the concern of `hiivmind-blueprint-mcp` (a separate package, yet to be created, shipping Python and TypeScript expanders) — covered by a follow-up spec. This spec defines the contract; that spec will implement it.

## Non-Goals

- **Walker implementation.** Expansion code (Python, TypeScript) lives in `hiivmind-blueprint-mcp`. Separate spec, separate repo, separate plan. This spec is the contract that implementation must satisfy.
- **User-defined composites.** Composites ship via blueprint-lib only. Authors who need a new pattern write raw primitives or submit a PR. No template DSL, no per-repo composite files, no inline `templates:` blocks.
- **Composite nesting.** Composites expand only to primitives, single pass. A composite body cannot reference another composite.
- **`narrative` composite.** Deferred. Pulls in improvise, narrative generation, and multi-choice folding — too much surface area for v1.
- **Primitive extensions.** No changes to `user_prompt`, `action`, or `conditional`. v1 composites are pure sugar over today's primitives.
- **Intent-handling redesign.** The LLM's existing semantic interpretation of user responses (fuzzy matching, reframing, injection resistance) is already sufficient for v1. No `policy` / `intent_rules` / `reframe_text` fields.
- **Runtime composite semantics.** The runtime LLM never sees composites. Everything composite-related is authoring-time or walker-phase.
- **blueprint-lib as runtime.** This spec does not introduce Python code or runtime dependencies into blueprint-lib. The lib remains catalog + schema only.

## Design

### Architectural contract

- **Composites are syntactic sugar.** Each one has a deterministic call-site → primitive-subgraph rewrite rule, defined in `blueprint-composites.md` and implemented per-language in `hiivmind-blueprint-mcp`.
- **LLM sees only primitives.** Walker expansion runs before the LLM's first interpretation pass. Composites never reach runtime.
- **Flat expansion.** No nesting, no DSL, no fixpoint. Single-pass walker expansion.
- **Separate file for composites.** `blueprint-types.md` remains the runtime catalog (primitives only). `blueprint-composites.md` is the authoring-time composite catalog.
- **Policy via structural decomposition.** Safety invariants of a composite are enforced by the shape of its expansion — multiple primitives with narrow single-purpose roles — not by annotations on the composite or runtime LLM directives.
- **Contract, not implementation.** `blueprint-composites.md` and the schema are authoritative; any language-specific walker (Python, TypeScript, future) must satisfy them. Cross-language agreement is the guarantee.

### File split

| File | Audience | Phase | Content |
|------|----------|-------|---------|
| `blueprint-types.md` | Runtime LLM + authors | Execution | 3 primitive node types, consequences, preconditions — unchanged |
| `blueprint-composites.md` (new) | Authors + schema validator | Authoring only | Composite signatures and expansion shapes; walker-stripped before runtime |

The LLM reading a workflow at runtime reads `blueprint-types.md` only. The schema validator pulls in both. Composite definitions never flow to runtime.

### Composite: `confirm`

**Call site (author-facing):**
```yaml
destroy_branch:
  type: confirm
  prompt: "Delete the branch '${branch_name}'?"
  header: "DELETE"                              # optional, default "CONFIRM"
  store_as: confirmations.delete_branch_x       # REQUIRED
  on_confirmed:
    consequences:                               # optional
      - type: git_ops_local
        operation: delete_branch
        args: {name: "${branch_name}"}
    next_node: branch_gone
  on_declined:
    next_node: cancelled
```

**Walker expansion (3 primitive nodes max):**
```yaml
destroy_branch__ask:
  type: user_prompt
  prompt:
    question: "Delete the branch '${branch_name}'?"
    header: "DELETE"
    options: [{id: yes, label: "Yes"}, {id: no, label: "No"}]
  on_response:
    yes:
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.delete_branch_x
          value: true
      next_node: destroy_branch__gate
    no:
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.delete_branch_x
          value: false
      next_node: destroy_branch__gate

destroy_branch__gate:
  type: conditional
  condition: "confirmations.delete_branch_x == true"
  on_true: destroy_branch__act      # or directly on_confirmed.next_node if no consequences
  on_false: cancelled                # on_declined.next_node

destroy_branch__act:                 # only emitted when on_confirmed.consequences is non-empty
  type: action
  consequences: [...on_confirmed.consequences...]
  on_success: branch_gone             # on_confirmed.next_node
```

**Safety invariants (enforced by expansion, documented in `confirmations-as-explicit-state` principle):**
1. `store_as` always written `true`|`false` before routing (never null).
2. Gate is structural (`conditional`), not a prompt-handler `next_node`.
3. Flag persists in state, inspectable by other nodes.
4. No intermediate node can collapse the decision — each of classify / record / gate is its own primitive.

**Fields:**
| Field | Required | Default | Purpose |
|-------|----------|---------|---------|
| `type` | yes | `confirm` | Composite dispatch |
| `prompt` | yes | — | Question text |
| `store_as` | yes | — | Dot-notation state path for the flag |
| `on_confirmed` | yes | — | `{next_node, consequences?}` for yes path |
| `on_declined` | yes | — | `{next_node}` for no path |
| `header` | no | `"CONFIRM"` | ≤ 12 chars (user_prompt constraint) |
| `on_confirmed.label` | no | `"Yes"` | Yes option label |
| `on_declined.label` | no | `"No"` | No option label |

### Composite: `gated_action`

**Call site:**
```yaml
review_decision:
  type: gated_action
  when:
    - condition: "flags.status == 'approved'"
      consequences:
        - type: mutate_state
          operation: set
          field: approval_ts
          value: "${now}"
      next_node: publish
    - condition: {all: [...]}
      next_node: merge_upstream
    - condition: "flags.status == 'rejected'"
      next_node: notify_author
  else: needs_review
  on_unknown: halt_for_audit        # optional; defaults to workflow default_error
```

**Walker expansion (N conditional nodes, plus one action per `when` with consequences):**

Each `when` becomes a `conditional`:
- Its `on_true` routes to either (a) the when's `next_node` directly if no consequences, or (b) an intermediate `action` that runs consequences then routes to `next_node`.
- Its `on_false` chains to the next `when`'s conditional — or to `else` if it's the last `when`.
- Its `on_unknown` points to the composite's `on_unknown` (or workflow `default_error`).

**Semantics:**
- **First-match-wins**, top-to-bottom. Once a condition evaluates true, that branch runs and later `when` entries aren't evaluated.
- **3VL short-circuit:** any condition returning `unknown` routes immediately to `on_unknown`. Matches today's single-`conditional` semantics applied to each link in the chain.
- **`else` is required** (schema-enforced). No silent fall-through.

**Fields:**
| Field | Required | Default | Purpose |
|-------|----------|---------|---------|
| `type` | yes | `gated_action` | Composite dispatch |
| `when` | yes (minItems 1) | — | Array of `{condition, consequences?, next_node}` |
| `else` | yes | — | Fall-through destination |
| `on_unknown` | no | workflow `default_error` | 3VL short-circuit destination |

**No safety principle** — `gated_action` is convenience sugar. It doesn't gate anything that wasn't already gateable via hand-written chained conditionals; it just makes the common pattern uniform and less error-prone.

### Walker expansion contract

The walker itself is implemented in `hiivmind-blueprint-mcp` (separate repo, separate spec). This section defines the **contract** every walker implementation must satisfy — the guarantees authors and downstream tests rely on.

**Per-composite expander contract:**
- Pure function: `(composite_call_dict, node_id) -> {generated_node_id: primitive_node_dict}`.
- No side effects, no state reads, no external calls.
- Output deterministic: same input YAML always produces identical primitive subgraph (bit-for-bit), across languages and across runs.

**Generated node-id convention:** `<original_id>__<suffix>` where suffix describes the expanded role (`__ask`, `__gate`, `__act`, `__case_0`, `__case_0__act`). Double-underscore prefix signals "walker-generated, do not hand-author." This convention is part of the contract — downstream tests and introspection tools rely on it.

**Edge patching:** Transitions in the wider workflow pointing at the composite's original id are rewritten to point at the first generated node of the expansion (`<original_id>__ask` for `confirm`, `<original_id>__case_0` for `gated_action`). Exits from the expansion use the composite's author-declared targets (`on_confirmed.next_node`, `when[].next_node`, `else`, etc.). Walker implementations must perform this patching; composite expanders only produce the subgraph.

**Expansion-pass contract:** Single pass before runtime validation. For each node where `type` ∈ composite names, dispatch to its expander, replace the node with the expansion map, patch inbound edges. Flat — no recursion, no fixpoint (per `composite-primitive-canary` principle).

**Error-handling contract:**
- Schema validation runs **before** expansion. Malformed composite call sites fail there with author-friendly messages.
- Expansion errors indicate expander bugs — walker implementations must fail loudly with composite name and original node id, not silently emit broken graphs.
- After expansion, the walker must re-validate the resulting primitive subgraph against primitive schemas as a coherence check.

**Cross-language parity:** Python and TypeScript walkers in `hiivmind-blueprint-mcp` must produce identical expansions for identical inputs. The follow-up implementation spec will define shared fixture test vectors (input YAML → expected primitive YAML) that both implementations run against.

### `blueprint-composites.md` format

Lives at the repo root alongside `blueprint-types.md`. Structure mirrors it:

```markdown
# hiivmind-blueprint Composites

Author-time composite catalog. Composites are syntactic sugar expanded by
the walker into primitive nodes before the LLM interprets anything.

The LLM at runtime does NOT read this file — it reads `blueprint-types.md`
and the expanded primitive graph. Behavioral invariants of each composite
live in principle documents, not here. See:
- composite-primitive-canary (c.type-system)
- confirmations-as-explicit-state (g.trust-governance)

## Conventions

- Function-signature format, same as blueprint-types.md
- `→` describes the expansion outcome, not runtime semantics
- Required and optional fields; optional marked with `?`

---

## Composites

confirm(prompt, store_as, on_confirmed, on_declined, header?)
  header         defaults to "CONFIRM"
  store_as       = dot-notation state field (convention: confirmations.<name>)
  on_confirmed   = {next_node, consequences?}
  on_declined    = {next_node}
  → Expands to: user_prompt → mutate_state → conditional → (optional action).
    See principle: confirmations-as-explicit-state.

gated_action(when[], else, on_unknown?)
  when           = [{condition, consequences?, next_node}]
    condition    = string | {all|any|none|xor: [...]} | canonical precondition
  on_unknown     defaults to workflow default_error
  → First-match-wins CASE/WHEN dispatch. Expansion: chain of conditional
    nodes, each optionally followed by an action for per-branch consequences.
```

Terse. Signatures + expansion shape only. Behavioral invariants and rationale live in principles.

### Schema changes

**`schema/authoring/node-types.json`:**
- `node.type` enum adds `"confirm"`, `"gated_action"` alongside the three primitives.
- Two new `$defs`: `confirm_node`, `gated_action_node`.
- `allOf` dispatch gets two new `if/then` branches.
- `confirm_node` requires: `prompt`, `store_as`, `on_confirmed`, `on_declined`.
- `gated_action_node` requires: `when` (minItems 1), `else`.
- `when[]` items require: `condition`, `next_node`. `consequences` optional.
- `condition` accepts `oneOf: [{type: string}, {type: object}]` (same polymorphism as today's `conditional`).
- `$comment` version bump to schema version 3.1 (composite support added).

**`schema/authoring/workflow.json`:** no changes. Composites are node-level; workflow schema already delegates to node-types.

**Validation pipeline:**
1. Authoring-time: composite call sites validated against `node-types.json` 3.1.
2. Walker expansion (described above).
3. Post-expansion: resulting primitive subgraph re-validated against primitive schemas as a coherence check.

### Principles introduced

**`composite-primitive-canary.md` (c.type-system, SPECIFIED)** — already drafted and committed on branch `principle/composite-primitive-canary` in `hiivmind-blueprint-central`. Captures:
- Composites are syntactic sugar that expand to primitives via walker-side deterministic rewrite.
- If a composite cannot be cleanly expressed over existing primitives, that is a diagnostic signal: extend a primitive, not the composite mechanism.
- Composites provide rails, not specifications — LLM semantic interpretation is already rich; don't reinvent it in composite knobs.
- Anti-patterns: template DSLs, nesting, user-defined composites, runtime composite semantics.

**`confirmations-as-explicit-state.md` (g.trust-governance, SPECIFIED)** — already drafted and committed on the same branch. Captures:
- Confirmations must decompose into classify → record → evaluate, with named state as the contract and a `conditional` as the gate.
- The decomposition is enforced mechanically by the `confirm` composite's walker expansion — authors cannot skip it.
- `policy-as-topology` applied to confirmations: the structure is the policy.
- Anti-patterns: routing user_prompt handlers directly to gated actions, `confirm` without `store_as`, hand-writing the 3-node pattern, evaluating the flag in an `action` instead of a `conditional`.

Both principles will transition SPECIFIED → IMPLEMENTED when this feature ships.

### Cross-repo coordination

**`hiivmind-blueprint-lib`** (this spec's scope, branch `feat/composite-nodes`):
- New file: `blueprint-composites.md`
- Schema update: `schema/authoring/node-types.json` version 3.1
- Schema fixture tests (no walker tests — walker lives elsewhere)
- Minor version bump in `package.yaml`: v3.1 → v3.2 (adds composite node types; additive/non-breaking)

**`hiivmind-blueprint-central`** (branch `principle/composite-primitive-canary`, already committed):
- Principle: `02.principles/c.type-system/composite-primitive-canary.md`
- Principle: `02.principles/g.trust-governance/confirmations-as-explicit-state.md`
- README index updates

**`hiivmind-blueprint-mcp`** (future repo, separate spec):
- Python walker implementation: `src/hiivmind_blueprint_mcp/walker/`
- TypeScript walker implementation: `packages/walker-ts/`
- Shared fixture test vectors covering v1 composites (both implementations run against the same corpus).
- The two implementations must produce bit-identical expansions for shared inputs.

**`hiivmind-blueprint` skill** (not part of this spec but must follow when implementation lands):
- Depend on `hiivmind-blueprint-mcp` (Python) for walker functionality.
- Ship `blueprint-composites.md` alongside `blueprint-types.md` in the skill bundle.
- Authoring guide additions documenting the two v1 composites.

### Testing strategy

Scope is limited to **authoring-time** validation; walker/runtime tests live in the `hiivmind-blueprint-mcp` spec.

**Schema fixture tests** (`tests/schema/test_composites.py`):
- Positive fixtures: valid composite call sites pass.
- Negative fixtures: missing required fields fail with clear error messages.
  - `confirm` without `store_as`
  - `confirm` without `prompt`, `on_confirmed`, or `on_declined`
  - `gated_action` without `else`
  - `gated_action` with empty `when` array
  - `when[]` item without `condition` or `next_node`
  - Invalid `policy` or unknown composite type names
- Canonical examples of each composite validated end-to-end against the schema.

**Shared test fixture corpus** (`tests/fixtures/composites/`):
- YAML fixtures of composite call sites paired with expected primitive expansions.
- Consumed by this repo's schema tests (negative/positive on call sites).
- Also exported as the authoritative expansion test corpus that `hiivmind-blueprint-mcp` Python and TypeScript walkers will execute against. Cross-language parity hinges on these fixtures.
- File layout: `tests/fixtures/composites/<composite_name>/<case>/input.yaml` + `expected.yaml`.

**No walker tests in this repo.** Unit tests per expander, round-trip validation, principle-compliance checks, and integration tests all belong to `hiivmind-blueprint-mcp` and will be covered by that spec.

## File changes summary

### `hiivmind-blueprint-lib`

| Action | File | Description |
|--------|------|-------------|
| CREATE | `blueprint-composites.md` | Composite catalog (author-time) |
| UPDATE | `schema/authoring/node-types.json` | Add composite sub-schemas, version 3.1 |
| UPDATE | `package.yaml` | Version bump to v3.2; stats reflect composite addition |
| UPDATE | `CHANGELOG.md` | v3.2 entry |
| UPDATE | `README.md` | Composite catalog mention + pointer to blueprint-composites.md |
| UPDATE | `CLAUDE.md` | Composite authoring note; reminder that walker is in hiivmind-blueprint-mcp |
| CREATE | `tests/schema/test_composites.py` | Schema validation fixtures (positive + negative) |
| CREATE | `tests/fixtures/composites/confirm/*/` | Call-site + expected-expansion fixture pairs |
| CREATE | `tests/fixtures/composites/gated_action/*/` | Call-site + expected-expansion fixture pairs |

### `hiivmind-blueprint-central`

Already done on branch `principle/composite-primitive-canary`:
- CREATE `02.principles/c.type-system/composite-primitive-canary.md`
- CREATE `02.principles/g.trust-governance/confirmations-as-explicit-state.md`
- UPDATE `02.principles/README.md`

## Branch

- `hiivmind-blueprint-lib`: `feat/composite-nodes` (branched from `refactor/type-catalog-collapse`)
- `hiivmind-blueprint-central`: `principle/composite-primitive-canary` (already created and committed)

## Success criteria

1. Authors can write `type: confirm` and `type: gated_action` in workflow YAML and get schema validation: positive cases pass, negative cases (missing `store_as`, missing `else`, empty `when`) fail with clear errors.
2. `blueprint-composites.md` documents both v1 composites with terse signatures and expansion shapes; points to principle files for invariants.
3. `blueprint-types.md` remains composite-free (primitives only).
4. Fixture corpus (`tests/fixtures/composites/`) defines the expected expansions authoritatively, ready to be consumed by downstream walker implementations.
5. Both new principles in `hiivmind-blueprint-central` reference `blueprint-composites.md` and `hiivmind-blueprint-mcp` for implementation.
6. `node-types.json` schema version bumped to 3.1; `package.yaml` bumped to v3.2.
7. Purely additive to blueprint-lib — no existing workflow breaks, no Python code introduced, no runtime dependencies added.

## Out-of-scope future work

- **Walker implementation spec** (`hiivmind-blueprint-mcp`). Python + TypeScript expanders, shared fixture consumption, cross-language parity tests, expansion-phase error handling, integration with the `hiivmind-blueprint` skill. Separate repo, separate spec, separate plan.
- `narrative` composite (requires improvise/narrative-gen design first).
- `on_deviation` / improvise primitive extension for `user_prompt` (LLM-in-the-loop free-form response handling).
- Additional composites as real-world usage surfaces repeated patterns (promotion happens via the canary principle).
- Skill-level authoring guides for composite patterns (`hiivmind-blueprint` repo).
