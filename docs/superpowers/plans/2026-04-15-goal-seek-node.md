# goal_seek Composite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `goal_seek` composite node type as catalog + schema + fixture corpus (walker lives in a future repo).

**Architecture:** `goal_seek` is walker-expanded sugar over existing primitives. The walker (out of scope for this repo) transforms a `goal_seek` node into a bounded dispatcher loop: `entry → init|tick → checks → budget → abort → complete → dispatch → sub-process → return`. The fixture corpus (`tests/fixtures/composites/goal_seek/`) is the authoritative walker contract — each `input.yaml` is the authored composite, each `expected.yaml` is the fully-expanded primitive subgraph. The authoring schema in `schema/authoring/node-types.json` validates structure only.

**Tech Stack:** JSON Schema (Draft 2020-12), YAML fixtures, `yq` + `ajv-cli` via `scripts/validate-fixtures.sh` (already in place).

**Spec:** `docs/superpowers/specs/2026-04-15-goal-seek-node-design.md`

**Working branch:** `feat/goal-seek-node` (already checked out, based on `feat/composite-nodes`).

**Sibling repo branch:** `principle/goal-seeking-as-bounded-loop` at `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-central` — created in Task 11.

---

## Walker-contract reference (critical — read before Task 4)

The walker expansion, given a `goal_seek` node with id `G`, goals list `[A, B, C]`, targets `on_complete=DONE`, `on_abort=ABORT` (default `default_error`), `on_budget_exceeded=BUDGET` (default `default_error`), and `max_iterations=N`:

| Emitted node | Type | Behavior |
|---|---|---|
| `G__entry` | `conditional` | `goal_seek.G.iterations == null` → `G__init`; else → `G__tick`. |
| `G__init` | `action` | Consequences: set `iterations = 0`; for each goal X: set `goals.X.status = incomplete`. `on_success` → `G__dispatch_case_0`. (Skips budget/abort/complete checks on first entry — state is known-clean.) |
| `G__tick` | `action` | Consequence: increment `iterations`. `on_success` → `G__check_<first goal with success_condition>` if any, else `G__budget_check`. |
| `G__check_<X>` (one per goal with `success_condition`) | `conditional` | Evaluates `success_condition` for goal X. `on_true` → `G__mark_<X>`; `on_false` → next check (or `G__budget_check` if last). |
| `G__mark_<X>` (paired with `G__check_<X>`) | `action` | Consequence: set `goals.X.status = satisfied`. `on_success` → next check (or `G__budget_check` if last). |
| `G__budget_check` | `conditional` | `iterations > N` → `BUDGET` (or `default_error`); else → `G__abort_check`. |
| `G__abort_check` | `conditional` | `aborted == true` → `ABORT` (or `default_error`); else → `G__complete_check`. |
| `G__complete_check` | `conditional` | All goals `status ∈ {satisfied, ignored}` → `DONE`; else → `G__dispatch_case_0`. |
| `G__dispatch_case_k` (one per goal, chained) | `conditional` | `goals.<goal_k>.status == incomplete` → `<goal_k.starting_node>`; on_false → `G__dispatch_case_{k+1}`. For the final case, on_false → `default_error` (unreachable — `G__complete_check` guards). |
| `G__return_<X>` | `action` | **If X has no `success_condition`:** consequence sets `goals.X.status = satisfied`. **If X has a `success_condition`:** pass-through (no consequences) — `G__tick`'s check chain re-evaluates the condition on next iteration. In both cases `on_success` → `G__entry`. |

**Return-edge rewriting contract:** The walker expects each goal's sub-process to contain at least one terminal whose `on_success` (or equivalent) targets `G` (the goal_seek node id). The walker rewrites these to target `G__return_<X>`. Terminals that escape the subgraph are an authoring error.

**Completeness condition form:** `G__complete_check` uses a composite-shorthand `all:` condition with one child per goal: `state_check` with `operator: in`, `value: [satisfied, ignored]` on `goal_seek.<G>.goals.<X>.status`.

---

## File Map

**Create:**
- `tests/fixtures/composites/goal_seek/minimal/input.yaml`
- `tests/fixtures/composites/goal_seek/minimal/expected.yaml`
- `tests/fixtures/composites/goal_seek/with_success_conditions/input.yaml`
- `tests/fixtures/composites/goal_seek/with_success_conditions/expected.yaml`
- `tests/fixtures/composites/goal_seek/with_subagent/input.yaml`
- `tests/fixtures/composites/goal_seek/with_subagent/expected.yaml`
- `tests/fixtures/composites/goal_seek/with_abort/input.yaml`
- `tests/fixtures/composites/goal_seek/with_abort/expected.yaml`
- `tests/fixtures/composites/_negative/goal_seek_missing_goals/input.yaml`
- `tests/fixtures/composites/_negative/goal_seek_empty_goals/input.yaml`
- `tests/fixtures/composites/_negative/goal_seek_missing_max_iterations/input.yaml`
- `tests/fixtures/composites/_negative/goal_seek_missing_on_complete/input.yaml`
- `tests/fixtures/composites/_negative/goal_seek_goal_missing_starting_node/input.yaml`
- `tests/fixtures/composites/_negative/goal_seek_goal_missing_name/input.yaml`
- `tests/fixtures/composites/_walker_only/README.md` (documents walker-contract-only cases)
- `tests/fixtures/composites/_walker_only/goal_terminal_escapes_loop/input.yaml`
- `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-central/02.principles/a.execution-paradigm/goal-seeking-as-bounded-loop.md`

**Modify:**
- `schema/authoring/node-types.json` — add enum entry, `allOf` dispatch, `goal_seek_node` `$def`, bump `$comment` to v3.2
- `blueprint-composites.md` — add `goal_seek` signature block
- `package.yaml` — bump to 7.2.0, `composite_types: 2 → 3`, `node: "3.1" → "3.2"`
- `CHANGELOG.md` — add 7.2.0 section
- `README.md` — mention `goal_seek` in composite catalog section
- `CLAUDE.md` — add `goal_seek` to composite list in the composite-node section
- `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-central/02.principles/README.md` — index new principle

**Validator:** `scripts/validate-fixtures.sh` already handles Draft 2020-12 via `ajv-cli` + wrapper schema; no changes needed. The `_walker_only/` directory must be excluded from validation because those fixtures are semantically invalid for schema purposes but structurally legal.

---

## Task 1: Exclude `_walker_only/` from fixture validator

**Files:**
- Modify: `scripts/validate-fixtures.sh:107-115`

**Context:** The validator's `find` commands currently walk `tests/fixtures/composites` excluding `_negative/`. We need to also exclude `_walker_only/` so that walker-contract-only fixtures (which may pass schema validation but are semantically invalid) don't get treated as positive cases.

- [ ] **Step 1: Inspect the validator's find-path exclusion logic**

Run: `grep -n "_negative" scripts/validate-fixtures.sh`
Expected: Two matches on lines ~109 and ~115 showing `-not -path '*/_negative/*'` and `"$FIXTURES_DIR/_negative"`.

- [ ] **Step 2: Add `_walker_only/` exclusion to the positive find**

Edit `scripts/validate-fixtures.sh`. Change the positive-fixtures `find` invocation (the one under `=== Positive fixtures (must pass) ===`) from:

```bash
done < <(find "$FIXTURES_DIR" -type f \( -name 'input.yaml' -o -name 'expected.yaml' \) -not -path '*/_negative/*' -print0)
```

to:

```bash
done < <(find "$FIXTURES_DIR" -type f \( -name 'input.yaml' -o -name 'expected.yaml' \) -not -path '*/_negative/*' -not -path '*/_walker_only/*' -print0)
```

- [ ] **Step 3: Run the validator to confirm no regression**

Run: `./scripts/validate-fixtures.sh`
Expected: Existing fixtures still pass. Output ends with `All fixtures OK`.

- [ ] **Step 4: Commit**

```bash
git add scripts/validate-fixtures.sh
git commit -m "test: exclude _walker_only/ from schema validator

Walker-contract-only fixtures are structurally valid YAML that the
schema cannot reject — they document authoring errors the walker must
catch at expansion time. Excluding them keeps the schema validator
focused on its actual scope."
```

---

## Task 2: Add `goal_seek` to enum + `allOf` dispatch

**Files:**
- Modify: `schema/authoring/node-types.json`

- [ ] **Step 1: Extend the node-type enum**

Locate in `schema/authoring/node-types.json` the `properties.type.enum` under `$defs.node`:

```json
"enum": ["action", "conditional", "user_prompt", "confirm", "gated_action"],
```

Change to:

```json
"enum": ["action", "conditional", "user_prompt", "confirm", "gated_action", "goal_seek"],
```

Also update the adjacent `"description"` string to include `goal_seek` in the composite list:

```json
"description": "Node type (primitive: action/conditional/user_prompt; composite: confirm/gated_action/goal_seek)"
```

- [ ] **Step 2: Add the `allOf` dispatch entry**

In the same file, locate the `allOf` array under `$defs.node`. Append a fifth entry after the `gated_action` block:

```json
{
  "if": { "properties": { "type": { "const": "goal_seek" } } },
  "then": { "$ref": "#/$defs/goal_seek_node" }
}
```

- [ ] **Step 3: Commit**

```bash
git add schema/authoring/node-types.json
git commit -m "schema: add goal_seek to node-type enum and dispatch"
```

---

## Task 3: Add `goal_seek_node` `$def`

**Files:**
- Modify: `schema/authoring/node-types.json`

- [ ] **Step 1: Insert the `goal_seek_node` definition**

In `schema/authoring/node-types.json`, add the following new `$def` immediately after `gated_action_node` (and before `prompt`):

```json
"goal_seek_node": {
  "type": "object",
  "description": "Goal-seeking composite. Walker expands to a bounded dispatcher loop that iterates sub-processes until every goal's status is 'satisfied' or 'ignored', the abort flag is set, or the iteration budget is exhausted. See blueprint-composites.md and principle: goal-seeking-as-bounded-loop.",
  "required": ["goals", "max_iterations", "on_complete"],
  "properties": {
    "type": { "const": "goal_seek" },
    "description": { "type": "string" },
    "goals": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["name", "starting_node"],
        "properties": {
          "name": {
            "$ref": "../common.json#/$defs/identifier",
            "description": "Goal identifier. Namespaced into goal_seek.<node_id>.goals.<name>.status."
          },
          "starting_node": {
            "$ref": "../common.json#/$defs/node_reference",
            "description": "Entry node for this goal's sub-process. Sub-process terminals must route back to the goal_seek node id."
          },
          "success_condition": {
            "oneOf": [
              { "type": "string" },
              { "type": "object" }
            ],
            "description": "Optional precondition re-checked on every loop iteration. If omitted, the walker flips status to 'satisfied' as soon as the sub-process returns. If present, the return edge is a pass-through and the loop continues until the condition holds."
          },
          "run_as": {
            "type": "string",
            "enum": ["inline", "subagent"],
            "default": "inline",
            "description": "Execution mode for this goal's sub-process. 'subagent' delegates to a separate agent context at runtime (declared here, honored by hiivmind-blueprint-mcp). Default 'inline'."
          }
        },
        "additionalProperties": false
      }
    },
    "max_iterations": {
      "type": "integer",
      "minimum": 1,
      "description": "Hard cap on loop iterations. When exceeded, routes to on_budget_exceeded (or workflow default_error)."
    },
    "on_complete": {
      "$ref": "../common.json#/$defs/node_reference",
      "description": "Destination when every goal's status is 'satisfied' or 'ignored'."
    },
    "on_abort": {
      "$ref": "../common.json#/$defs/node_reference",
      "description": "Destination when any sub-process sets goal_seek.<node_id>.aborted = true. Optional — defaults to workflow default_error."
    },
    "on_budget_exceeded": {
      "$ref": "../common.json#/$defs/node_reference",
      "description": "Destination when iterations exceed max_iterations. Optional — defaults to workflow default_error."
    }
  },
  "additionalProperties": false
},
```

- [ ] **Step 2: Bump schema version in `$comment`**

Locate the top-level `$comment` in `schema/authoring/node-types.json`:

```json
"$comment": "Schema version 3.1 - Composite node support: confirm and gated_action sugar expand to primitives via walker in hiivmind-blueprint-mcp.",
```

Replace with:

```json
"$comment": "Schema version 3.2 - Adds goal_seek composite (bounded dispatcher loop). Composites (confirm, gated_action, goal_seek) expand to primitives via walker in hiivmind-blueprint-mcp.",
```

- [ ] **Step 3: Validate JSON parses**

Run: `jq . schema/authoring/node-types.json > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 4: Run the validator to confirm existing fixtures still pass**

Run: `./scripts/validate-fixtures.sh`
Expected: existing 6 positive + 3 negative fixtures still green. Ends with `All fixtures OK`.

- [ ] **Step 5: Commit**

```bash
git add schema/authoring/node-types.json
git commit -m "schema: add goal_seek_node \$def (v3.2)"
```

---

## Task 4: Positive fixture — minimal

**Files:**
- Create: `tests/fixtures/composites/goal_seek/minimal/input.yaml`
- Create: `tests/fixtures/composites/goal_seek/minimal/expected.yaml`

Scenario: a discovery dialog with two goals, no success conditions, inline only. Author provides sub-processes that terminate with `on_success: gather_user_info` (routing back to the goal_seek node). The walker rewrites those to `gather_user_info__return_<goal>`.

- [ ] **Step 1: Create the input fixture directory**

Run: `mkdir -p tests/fixtures/composites/goal_seek/minimal`

- [ ] **Step 2: Write `input.yaml`**

Create `tests/fixtures/composites/goal_seek/minimal/input.yaml`:

```yaml
gather_user_info:
  type: goal_seek
  goals:
    - name: user_name
      starting_node: collect_user_name
    - name: user_email
      starting_node: collect_user_email
  max_iterations: 10
  on_complete: summarize_info
```

- [ ] **Step 3: Write `expected.yaml`**

Create `tests/fixtures/composites/goal_seek/minimal/expected.yaml`:

```yaml
gather_user_info__entry:
  type: conditional
  condition: "goal_seek.gather_user_info.iterations == null"
  on_true: gather_user_info__init
  on_false: gather_user_info__tick

gather_user_info__init:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.gather_user_info.iterations
      value: 0
    - type: mutate_state
      operation: set
      field: goal_seek.gather_user_info.goals.user_name.status
      value: incomplete
    - type: mutate_state
      operation: set
      field: goal_seek.gather_user_info.goals.user_email.status
      value: incomplete
  on_success: gather_user_info__dispatch_case_0

gather_user_info__tick:
  type: action
  consequences:
    - type: mutate_state
      operation: increment
      field: goal_seek.gather_user_info.iterations
  on_success: gather_user_info__budget_check

gather_user_info__budget_check:
  type: conditional
  condition: "goal_seek.gather_user_info.iterations > 10"
  on_true: default_error
  on_false: gather_user_info__abort_check

gather_user_info__abort_check:
  type: conditional
  condition: "goal_seek.gather_user_info.aborted == true"
  on_true: default_error
  on_false: gather_user_info__complete_check

gather_user_info__complete_check:
  type: conditional
  condition:
    all:
      - type: state_check
        field: goal_seek.gather_user_info.goals.user_name.status
        operator: in
        value: [satisfied, ignored]
      - type: state_check
        field: goal_seek.gather_user_info.goals.user_email.status
        operator: in
        value: [satisfied, ignored]
  on_true: summarize_info
  on_false: gather_user_info__dispatch_case_0

gather_user_info__dispatch_case_0:
  type: conditional
  condition: "goal_seek.gather_user_info.goals.user_name.status == 'incomplete'"
  on_true: collect_user_name
  on_false: gather_user_info__dispatch_case_1

gather_user_info__dispatch_case_1:
  type: conditional
  condition: "goal_seek.gather_user_info.goals.user_email.status == 'incomplete'"
  on_true: collect_user_email
  on_false: default_error

gather_user_info__return_user_name:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.gather_user_info.goals.user_name.status
      value: satisfied
  on_success: gather_user_info__entry

gather_user_info__return_user_email:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.gather_user_info.goals.user_email.status
      value: satisfied
  on_success: gather_user_info__entry
```

- [ ] **Step 4: Run the validator**

Run: `./scripts/validate-fixtures.sh`
Expected: the `minimal` fixture (both `input.yaml` and `expected.yaml`) validates green. All existing fixtures still pass.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/composites/goal_seek/minimal
git commit -m "test: add goal_seek minimal positive fixture"
```

---

## Task 5: Positive fixture — with_success_conditions

**Files:**
- Create: `tests/fixtures/composites/goal_seek/with_success_conditions/input.yaml`
- Create: `tests/fixtures/composites/goal_seek/with_success_conditions/expected.yaml`

Scenario: a polling loop. Two goals: `service_ready` (polls an external service; `success_condition` checks `status.service == "ready"`) and `config_loaded` (no condition — satisfies on sub-process return). Demonstrates `G__check_<X>` / `G__mark_<X>` insertion and the return-edge pass-through rule for goals with success conditions.

- [ ] **Step 1: Create the fixture directory**

Run: `mkdir -p tests/fixtures/composites/goal_seek/with_success_conditions`

- [ ] **Step 2: Write `input.yaml`**

Create `tests/fixtures/composites/goal_seek/with_success_conditions/input.yaml`:

```yaml
wait_for_readiness:
  type: goal_seek
  goals:
    - name: service_ready
      starting_node: poll_service
      success_condition: "status.service == 'ready'"
    - name: config_loaded
      starting_node: load_config
  max_iterations: 30
  on_complete: start_work
  on_budget_exceeded: timeout_handler
```

- [ ] **Step 3: Write `expected.yaml`**

Create `tests/fixtures/composites/goal_seek/with_success_conditions/expected.yaml`:

```yaml
wait_for_readiness__entry:
  type: conditional
  condition: "goal_seek.wait_for_readiness.iterations == null"
  on_true: wait_for_readiness__init
  on_false: wait_for_readiness__tick

wait_for_readiness__init:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.wait_for_readiness.iterations
      value: 0
    - type: mutate_state
      operation: set
      field: goal_seek.wait_for_readiness.goals.service_ready.status
      value: incomplete
    - type: mutate_state
      operation: set
      field: goal_seek.wait_for_readiness.goals.config_loaded.status
      value: incomplete
  on_success: wait_for_readiness__dispatch_case_0

wait_for_readiness__tick:
  type: action
  consequences:
    - type: mutate_state
      operation: increment
      field: goal_seek.wait_for_readiness.iterations
  on_success: wait_for_readiness__check_service_ready

wait_for_readiness__check_service_ready:
  type: conditional
  condition: "status.service == 'ready'"
  on_true: wait_for_readiness__mark_service_ready
  on_false: wait_for_readiness__budget_check

wait_for_readiness__mark_service_ready:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.wait_for_readiness.goals.service_ready.status
      value: satisfied
  on_success: wait_for_readiness__budget_check

wait_for_readiness__budget_check:
  type: conditional
  condition: "goal_seek.wait_for_readiness.iterations > 30"
  on_true: timeout_handler
  on_false: wait_for_readiness__abort_check

wait_for_readiness__abort_check:
  type: conditional
  condition: "goal_seek.wait_for_readiness.aborted == true"
  on_true: default_error
  on_false: wait_for_readiness__complete_check

wait_for_readiness__complete_check:
  type: conditional
  condition:
    all:
      - type: state_check
        field: goal_seek.wait_for_readiness.goals.service_ready.status
        operator: in
        value: [satisfied, ignored]
      - type: state_check
        field: goal_seek.wait_for_readiness.goals.config_loaded.status
        operator: in
        value: [satisfied, ignored]
  on_true: start_work
  on_false: wait_for_readiness__dispatch_case_0

wait_for_readiness__dispatch_case_0:
  type: conditional
  condition: "goal_seek.wait_for_readiness.goals.service_ready.status == 'incomplete'"
  on_true: poll_service
  on_false: wait_for_readiness__dispatch_case_1

wait_for_readiness__dispatch_case_1:
  type: conditional
  condition: "goal_seek.wait_for_readiness.goals.config_loaded.status == 'incomplete'"
  on_true: load_config
  on_false: default_error

wait_for_readiness__return_service_ready:
  type: action
  consequences: []
  on_success: wait_for_readiness__entry

wait_for_readiness__return_config_loaded:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.wait_for_readiness.goals.config_loaded.status
      value: satisfied
  on_success: wait_for_readiness__entry
```

Note the two return-edge shapes:
- `service_ready` has a `success_condition`, so `return_service_ready` has **empty consequences** — status flips only when the `G__check_service_ready` conditional evaluates true on a subsequent `G__tick`.
- `config_loaded` has no `success_condition`, so `return_config_loaded` sets `status = satisfied` directly.

- [ ] **Step 4: Run the validator**

Run: `./scripts/validate-fixtures.sh`
Expected: new fixture green, all others still pass.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/composites/goal_seek/with_success_conditions
git commit -m "test: add goal_seek fixture with success_condition pass-through"
```

---

## Task 6: Positive fixture — with_subagent

**Files:**
- Create: `tests/fixtures/composites/goal_seek/with_subagent/input.yaml`
- Create: `tests/fixtures/composites/goal_seek/with_subagent/expected.yaml`

Scenario: same shape as `minimal` but one goal is tagged `run_as: subagent`. The expansion carries a runtime hint `run_as: subagent` on the return node (walker preserves it so runtime can honor delegation).

- [ ] **Step 1: Create the fixture directory**

Run: `mkdir -p tests/fixtures/composites/goal_seek/with_subagent`

- [ ] **Step 2: Write `input.yaml`**

Create `tests/fixtures/composites/goal_seek/with_subagent/input.yaml`:

```yaml
research_and_summarize:
  type: goal_seek
  goals:
    - name: deep_research
      starting_node: spawn_research_agent
      run_as: subagent
    - name: outline
      starting_node: draft_outline
  max_iterations: 5
  on_complete: publish_report
```

- [ ] **Step 3: Write `expected.yaml`**

Create `tests/fixtures/composites/goal_seek/with_subagent/expected.yaml`:

```yaml
research_and_summarize__entry:
  type: conditional
  condition: "goal_seek.research_and_summarize.iterations == null"
  on_true: research_and_summarize__init
  on_false: research_and_summarize__tick

research_and_summarize__init:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.research_and_summarize.iterations
      value: 0
    - type: mutate_state
      operation: set
      field: goal_seek.research_and_summarize.goals.deep_research.status
      value: incomplete
    - type: mutate_state
      operation: set
      field: goal_seek.research_and_summarize.goals.outline.status
      value: incomplete
  on_success: research_and_summarize__dispatch_case_0

research_and_summarize__tick:
  type: action
  consequences:
    - type: mutate_state
      operation: increment
      field: goal_seek.research_and_summarize.iterations
  on_success: research_and_summarize__budget_check

research_and_summarize__budget_check:
  type: conditional
  condition: "goal_seek.research_and_summarize.iterations > 5"
  on_true: default_error
  on_false: research_and_summarize__abort_check

research_and_summarize__abort_check:
  type: conditional
  condition: "goal_seek.research_and_summarize.aborted == true"
  on_true: default_error
  on_false: research_and_summarize__complete_check

research_and_summarize__complete_check:
  type: conditional
  condition:
    all:
      - type: state_check
        field: goal_seek.research_and_summarize.goals.deep_research.status
        operator: in
        value: [satisfied, ignored]
      - type: state_check
        field: goal_seek.research_and_summarize.goals.outline.status
        operator: in
        value: [satisfied, ignored]
  on_true: publish_report
  on_false: research_and_summarize__dispatch_case_0

research_and_summarize__dispatch_case_0:
  type: conditional
  condition: "goal_seek.research_and_summarize.goals.deep_research.status == 'incomplete'"
  on_true: spawn_research_agent
  on_false: research_and_summarize__dispatch_case_1

research_and_summarize__dispatch_case_1:
  type: conditional
  condition: "goal_seek.research_and_summarize.goals.outline.status == 'incomplete'"
  on_true: draft_outline
  on_false: default_error

research_and_summarize__return_deep_research:
  type: action
  run_as: subagent
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.research_and_summarize.goals.deep_research.status
      value: satisfied
  on_success: research_and_summarize__entry

research_and_summarize__return_outline:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.research_and_summarize.goals.outline.status
      value: satisfied
  on_success: research_and_summarize__entry
```

Note the `run_as: subagent` hint attached to `research_and_summarize__return_deep_research`. This sibling-field convention parallels how the walker marks other runtime hints (the exact field location — return node vs dispatch edge — is a walker detail; this fixture pins it on the return node).

- [ ] **Step 4: Run the validator**

Run: `./scripts/validate-fixtures.sh`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/composites/goal_seek/with_subagent
git commit -m "test: add goal_seek fixture with subagent run_as hint"
```

---

## Task 7: Positive fixture — with_abort

**Files:**
- Create: `tests/fixtures/composites/goal_seek/with_abort/input.yaml`
- Create: `tests/fixtures/composites/goal_seek/with_abort/expected.yaml`

Scenario: author wires a user-cancel path where a sub-process sets `aborted = true` via `mutate_state` before routing back. The composite declares `on_abort: user_cancelled`. Expansion is structurally identical to `minimal` — the abort is a state-level signal, not a shape change — but this fixture pins down the `on_abort` target wiring (`abort_check` routes to `user_cancelled`, not `default_error`).

- [ ] **Step 1: Create the fixture directory**

Run: `mkdir -p tests/fixtures/composites/goal_seek/with_abort`

- [ ] **Step 2: Write `input.yaml`**

Create `tests/fixtures/composites/goal_seek/with_abort/input.yaml`:

```yaml
guided_setup:
  type: goal_seek
  goals:
    - name: project_name
      starting_node: ask_project_name
    - name: project_dir
      starting_node: ask_project_dir
  max_iterations: 5
  on_complete: scaffold
  on_abort: user_cancelled
```

- [ ] **Step 3: Write `expected.yaml`**

Create `tests/fixtures/composites/goal_seek/with_abort/expected.yaml`:

```yaml
guided_setup__entry:
  type: conditional
  condition: "goal_seek.guided_setup.iterations == null"
  on_true: guided_setup__init
  on_false: guided_setup__tick

guided_setup__init:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.guided_setup.iterations
      value: 0
    - type: mutate_state
      operation: set
      field: goal_seek.guided_setup.goals.project_name.status
      value: incomplete
    - type: mutate_state
      operation: set
      field: goal_seek.guided_setup.goals.project_dir.status
      value: incomplete
  on_success: guided_setup__dispatch_case_0

guided_setup__tick:
  type: action
  consequences:
    - type: mutate_state
      operation: increment
      field: goal_seek.guided_setup.iterations
  on_success: guided_setup__budget_check

guided_setup__budget_check:
  type: conditional
  condition: "goal_seek.guided_setup.iterations > 5"
  on_true: default_error
  on_false: guided_setup__abort_check

guided_setup__abort_check:
  type: conditional
  condition: "goal_seek.guided_setup.aborted == true"
  on_true: user_cancelled
  on_false: guided_setup__complete_check

guided_setup__complete_check:
  type: conditional
  condition:
    all:
      - type: state_check
        field: goal_seek.guided_setup.goals.project_name.status
        operator: in
        value: [satisfied, ignored]
      - type: state_check
        field: goal_seek.guided_setup.goals.project_dir.status
        operator: in
        value: [satisfied, ignored]
  on_true: scaffold
  on_false: guided_setup__dispatch_case_0

guided_setup__dispatch_case_0:
  type: conditional
  condition: "goal_seek.guided_setup.goals.project_name.status == 'incomplete'"
  on_true: ask_project_name
  on_false: guided_setup__dispatch_case_1

guided_setup__dispatch_case_1:
  type: conditional
  condition: "goal_seek.guided_setup.goals.project_dir.status == 'incomplete'"
  on_true: ask_project_dir
  on_false: default_error

guided_setup__return_project_name:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.guided_setup.goals.project_name.status
      value: satisfied
  on_success: guided_setup__entry

guided_setup__return_project_dir:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: goal_seek.guided_setup.goals.project_dir.status
      value: satisfied
  on_success: guided_setup__entry
```

- [ ] **Step 4: Run the validator**

Run: `./scripts/validate-fixtures.sh`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/composites/goal_seek/with_abort
git commit -m "test: add goal_seek fixture with on_abort wired to user_cancelled"
```

---

## Task 8: Negative fixtures

**Files:**
- Create: `tests/fixtures/composites/_negative/goal_seek_missing_goals/input.yaml`
- Create: `tests/fixtures/composites/_negative/goal_seek_empty_goals/input.yaml`
- Create: `tests/fixtures/composites/_negative/goal_seek_missing_max_iterations/input.yaml`
- Create: `tests/fixtures/composites/_negative/goal_seek_missing_on_complete/input.yaml`
- Create: `tests/fixtures/composites/_negative/goal_seek_goal_missing_starting_node/input.yaml`
- Create: `tests/fixtures/composites/_negative/goal_seek_goal_missing_name/input.yaml`

Each of these must fail schema validation (the validator's negative-fixture pipeline expects rejection).

- [ ] **Step 1: Create all six directories**

Run:
```bash
mkdir -p tests/fixtures/composites/_negative/goal_seek_missing_goals \
         tests/fixtures/composites/_negative/goal_seek_empty_goals \
         tests/fixtures/composites/_negative/goal_seek_missing_max_iterations \
         tests/fixtures/composites/_negative/goal_seek_missing_on_complete \
         tests/fixtures/composites/_negative/goal_seek_goal_missing_starting_node \
         tests/fixtures/composites/_negative/goal_seek_goal_missing_name
```

- [ ] **Step 2: Write `goal_seek_missing_goals/input.yaml`**

```yaml
bad:
  type: goal_seek
  max_iterations: 5
  on_complete: done
```

- [ ] **Step 3: Write `goal_seek_empty_goals/input.yaml`**

```yaml
bad:
  type: goal_seek
  goals: []
  max_iterations: 5
  on_complete: done
```

- [ ] **Step 4: Write `goal_seek_missing_max_iterations/input.yaml`**

```yaml
bad:
  type: goal_seek
  goals:
    - name: g1
      starting_node: start_g1
  on_complete: done
```

- [ ] **Step 5: Write `goal_seek_missing_on_complete/input.yaml`**

```yaml
bad:
  type: goal_seek
  goals:
    - name: g1
      starting_node: start_g1
  max_iterations: 5
```

- [ ] **Step 6: Write `goal_seek_goal_missing_starting_node/input.yaml`**

```yaml
bad:
  type: goal_seek
  goals:
    - name: g1
  max_iterations: 5
  on_complete: done
```

- [ ] **Step 7: Write `goal_seek_goal_missing_name/input.yaml`**

```yaml
bad:
  type: goal_seek
  goals:
    - starting_node: start_g1
  max_iterations: 5
  on_complete: done
```

- [ ] **Step 8: Run the validator and confirm all six are rejected**

Run: `./scripts/validate-fixtures.sh`
Expected: summary line shows at least 6 additional negative fixtures `correctly rejected`. `0 unexpectedly passed`. Exit code 0.

- [ ] **Step 9: Commit**

```bash
git add tests/fixtures/composites/_negative/goal_seek_*
git commit -m "test: add goal_seek negative fixtures for schema-enforced constraints"
```

---

## Task 9: Walker-contract-only fixture and README

**Files:**
- Create: `tests/fixtures/composites/_walker_only/README.md`
- Create: `tests/fixtures/composites/_walker_only/goal_terminal_escapes_loop/input.yaml`

Scenario: a sub-process's terminal escapes the goal_seek subgraph (routes to a node outside the loop instead of back to the goal_seek node). This is structurally valid YAML that the authoring schema cannot reject — the walker must catch it at expansion time via subgraph-reachability analysis. The fixture lives here as a documented expected-rejection case for walker test suites in `hiivmind-blueprint-mcp`.

- [ ] **Step 1: Create the directory**

Run: `mkdir -p tests/fixtures/composites/_walker_only/goal_terminal_escapes_loop`

- [ ] **Step 2: Write the README**

Create `tests/fixtures/composites/_walker_only/README.md`:

```markdown
# Walker-contract-only fixtures

Fixtures in this directory are **structurally valid YAML** that the authoring
JSON schema cannot reject. They represent authoring errors that only the
walker (in `hiivmind-blueprint-mcp`) can catch at expansion time via graph-level
analysis (reachability, return-edge tracing, etc.).

This directory is **excluded from `scripts/validate-fixtures.sh`**. It exists
as a cross-repo contract: walker test suites should consume these fixtures
and assert rejection with a clear diagnostic.

## Index

- `goal_terminal_escapes_loop/` — a `goal_seek` sub-process whose terminal
  routes to a node outside the loop. The walker must reject with an error
  identifying the offending goal and terminal node.
```

- [ ] **Step 3: Write `goal_terminal_escapes_loop/input.yaml`**

```yaml
# Walker-contract violation: the 'collect_name' sub-process terminal
# routes to 'unrelated_node' instead of back to 'gather_info'. The walker
# must detect this via subgraph reachability analysis and reject.
gather_info:
  type: goal_seek
  goals:
    - name: user_name
      starting_node: collect_name
  max_iterations: 5
  on_complete: done

collect_name:
  type: user_prompt
  prompt:
    question: "What is your name?"
    header: "NAME"
    options:
      - { id: "ok", label: "OK" }
  on_response:
    "ok":
      consequences:
        - type: mutate_state
          operation: set
          field: profile.name
          value: "${user_response}"
      next_node: unrelated_node   # ← escapes the goal_seek loop
```

- [ ] **Step 4: Run the validator to confirm the walker-only dir is excluded**

Run: `./scripts/validate-fixtures.sh`
Expected: the walker-only fixture does **not** appear in either positive or negative tallies. Validator finishes green.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/composites/_walker_only
git commit -m "test: document walker-contract-only fixture for escape detection"
```

---

## Task 10: Add `goal_seek` to `blueprint-composites.md`

**Files:**
- Modify: `blueprint-composites.md`

- [ ] **Step 1: Append the signature block**

Open `blueprint-composites.md`. After the `gated_action` block (the last composite entry), add a blank line and append:

```
goal_seek(goals[], max_iterations, on_complete, on_abort?, on_budget_exceeded?)
  goals              = [{name, starting_node, success_condition?, run_as?}]
    name                = identifier (namespaced into goal_seek.<node_id>.goals.<name>)
    starting_node       = node reference; entry point for this goal's sub-process
    success_condition   = optional precondition re-checked on each loop iteration;
                          if omitted, walker flips status=satisfied on return
    run_as              ∈ {inline, subagent}, default inline
  max_iterations     = positive integer budget (safety rail)
  on_complete        = next_node when all goals satisfied-or-ignored
  on_abort           defaults to workflow default_error
  on_budget_exceeded defaults to workflow default_error
  → Bounded dispatcher loop. First-incomplete-wins over goals[]. Each goal's
    sub-process is responsible for routing its terminal back to the goal_seek
    node; the walker rewrites those edges to status-update return nodes.
    See principles: composite-primitive-canary, goal-seeking-as-bounded-loop.
```

- [ ] **Step 2: Commit**

```bash
git add blueprint-composites.md
git commit -m "docs: add goal_seek signature to blueprint-composites.md"
```

---

## Task 11: New principle in hiivmind-blueprint-central

**Files:**
- Create: `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-central/02.principles/a.execution-paradigm/goal-seeking-as-bounded-loop.md`
- Modify: `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-central/02.principles/README.md`

- [ ] **Step 1: Create and check out the principle branch**

Run:
```bash
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-central
git fetch origin --quiet
git checkout -b principle/goal-seeking-as-bounded-loop origin/main
```

If the branch already exists locally from an earlier attempt, use `git checkout principle/goal-seeking-as-bounded-loop` instead.

- [ ] **Step 2: Create the principle document**

Create `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-central/02.principles/a.execution-paradigm/goal-seeking-as-bounded-loop.md`:

```markdown
# Goal-Seeking as a Bounded Loop

**Category:** execution-paradigm
**Introduced:** 2026-04-15
**Related:** composite-primitive-canary, confirmations-as-explicit-state

## Rule

Goal-seeking workflows are expressed as composite loops with explicit
namespaced state, a mandatory iteration budget, and a per-goal completion
predicate. There is no unbounded loop primitive.

## Why

LLM-as-execution-engine workflows must terminate deterministically. A
budget plus per-goal evidence keeps the runtime provably bounded and
debuggable. "Loop until we feel done" is not acceptable; "loop until every
goal has recorded evidence of satisfaction or ignore, or the budget is
exhausted" is.

Concretely, the `goal_seek` composite (in `hiivmind-blueprint-lib`'s
`blueprint-composites.md`) enforces three structural guarantees at
expansion time:

1. **Namespaced state** — every status field lives under
   `goal_seek.<node_id>.goals.<name>.status`, preventing cross-loop
   collisions and making progress inspectable.
2. **Iteration budget** — `max_iterations` is required; exceeding it
   routes to `on_budget_exceeded` (or workflow `default_error`).
3. **Explicit completion predicate** — a goal becomes `satisfied` either
   when its sub-process returns (default) or when its `success_condition`
   holds on a subsequent tick. `ignored` is an explicit author-set state,
   never inferred.

This is a successful canary outcome under `composite-primitive-canary`:
iterative goal-seeking decomposes cleanly into `action`, `conditional`,
and `user_prompt` primitives via sugar. No loop primitive is warranted.

## How to apply

- **Reviewing workflow PRs:** if an author has wired a manual back-edge
  (a node's `on_success` or `next_node` pointing at an upstream node)
  outside a `goal_seek` composite, flag it. Either the pattern should be
  expressed as `goal_seek`, or the reviewer should understand why the
  composite doesn't fit and document the gap (candidate for a new
  composite).
- **Reviewing primitive proposals:** any future proposal for a
  first-class loop primitive (`loop`, `while`, `repeat_until`, etc.) must
  justify why `goal_seek` expansion is insufficient for the target use
  case. The canary principle's burden-of-proof applies.
- **Authoring goal_seek nodes:** always specify `max_iterations` with a
  realistic upper bound for the use case (discovery dialogs: 10–20;
  polling: whatever the SLA permits). A budget of 1000 is a smell —
  either the loop shouldn't be bounded this way, or the goal isn't
  structured correctly.
```

- [ ] **Step 3: Index the principle in the README**

Open `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-central/02.principles/README.md`. Locate the section for `a.execution-paradigm` (or the flat index of all principles if the README is flat). Add a new entry:

```markdown
- [goal-seeking-as-bounded-loop](a.execution-paradigm/goal-seeking-as-bounded-loop.md) — bounded loops with namespaced state and mandatory budget; no unbounded loop primitive
```

Place it alphabetically within its section, or at the end of the relevant section if the file is not sorted.

- [ ] **Step 4: Commit in the sibling repo**

Run:
```bash
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-central
git add 02.principles/a.execution-paradigm/goal-seeking-as-bounded-loop.md 02.principles/README.md
git commit -m "principle: goal-seeking as bounded loop

Captures the design discipline that iterative goal-seeking must be
expressed as a bounded composite with namespaced state, a mandatory
iteration budget, and per-goal completion evidence. No unbounded loop
primitive.

Cross-references composite-primitive-canary: goal_seek is a successful
canary outcome — iteration decomposes into existing primitives via sugar."
```

- [ ] **Step 5: Return to the blueprint-lib repo**

Run: `cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib`

Verify: `git branch --show-current` → `feat/goal-seek-node`.

---

## Task 12: Release metadata — package.yaml, CHANGELOG, README, CLAUDE.md

**Files:**
- Modify: `package.yaml`
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump `package.yaml`**

In `package.yaml`:

- Change `version: "7.1.0"` → `version: "7.2.0"`
- Change `schemas.node: "3.1"` → `schemas.node: "3.2"`
- Change `composite_types: 2` → `composite_types: 3`
- Update the description paragraph to mention `goal_seek` alongside `confirm` and `gated_action` (find the sentence listing composite types and add `goal_seek`).

- [ ] **Step 2: Add CHANGELOG entry**

Open `CHANGELOG.md`. Immediately under the top-level header (and above the 7.1.0 section), insert:

```markdown
## [7.2.0] - 2026-04-15

### Added
- `goal_seek` composite node type — bounded dispatcher loop over a list of goals, each with an optional `success_condition` precondition and optional `run_as: subagent` delegation hint. Walker-expanded to primitives (`action`, `conditional`), no new primitive introduced.
- `tests/fixtures/composites/goal_seek/` — four positive fixtures (`minimal`, `with_success_conditions`, `with_subagent`, `with_abort`) pinning down the walker contract including the pass-through return edge when a goal has a `success_condition`.
- `tests/fixtures/composites/_negative/goal_seek_*` — six negative fixtures covering missing/empty required fields and per-goal shape violations.
- `tests/fixtures/composites/_walker_only/` — new directory for walker-contract-only fixtures (structurally legal YAML that only the walker can reject). First inhabitant: `goal_terminal_escapes_loop`.

### Changed
- `schema/authoring/node-types.json` bumped to version 3.2: adds `goal_seek` to the node-type enum, adds `goal_seek_node` `$def`, extends `allOf` dispatch.
- `scripts/validate-fixtures.sh` excludes `_walker_only/` from schema validation.
- `blueprint-composites.md` adds the `goal_seek` signature block.

### Related
- New principle in `hiivmind-blueprint-central`: `goal-seeking-as-bounded-loop` (branch `principle/goal-seeking-as-bounded-loop`).
```

- [ ] **Step 3: Update README**

Open `README.md`. Find the composite catalog section (it lists `confirm` and `gated_action`). Add a bullet for `goal_seek`, matching the existing style — a one-sentence description plus a link to `blueprint-composites.md`. Example bullet to add:

```markdown
- **`goal_seek`** — bounded dispatcher loop over a list of goals; each goal has a sub-process that must route back to the `goal_seek` node, and the walker expands the whole thing to primitives. See `blueprint-composites.md` and the `goal-seeking-as-bounded-loop` principle.
```

- [ ] **Step 4: Update CLAUDE.md**

Open `CLAUDE.md`. Locate the "Composite Node Types (Authoring Sugar)" section. The bullet list currently has `confirm` and `gated_action`. Add a third bullet:

```markdown
- `goal_seek` — bounded dispatcher loop over a list of goals (iteration budget + per-goal completion predicate)
```

Also update the sentence "v1 composites:" to "v1 composites:" — the list simply grows; no wording change required beyond appending the bullet. If the prose numbers them (`v1` vs `v2`), leave the versioning text alone since `goal_seek` is a v7.2.0 minor addition, not a protocol version.

- [ ] **Step 5: Run the validator one more time**

Run: `./scripts/validate-fixtures.sh`
Expected: all positive fixtures pass, all negative fixtures correctly rejected. Exit 0.

- [ ] **Step 6: Commit**

```bash
git add package.yaml CHANGELOG.md README.md CLAUDE.md
git commit -m "release: v7.2.0 — goal_seek composite node

Adds goal_seek as a walker-expanded composite (bounded dispatcher loop
with namespaced state, mandatory iteration budget, per-goal completion
predicate). Schema bumped to v3.2. No new primitives.

See principle: goal-seeking-as-bounded-loop (hiivmind-blueprint-central)."
```

---

## Task 13: Final validator + sanity sweep

- [ ] **Step 1: Run the full validator from a clean shell**

Run: `./scripts/validate-fixtures.sh`
Expected: final tally — 10 positive passed, 9 negative correctly rejected (3 pre-existing + 6 new), 0 positive failed, 0 unexpectedly passed. Exit 0.

(Counts: pre-existing positive fixtures were 6 — 3 confirm + 3 gated_action. New: 4 goal_seek. Total positive = 10. Pre-existing negative: 3. New: 6. Total negative = 9.)

- [ ] **Step 2: Confirm the `_walker_only/` directory did not count**

Run: `./scripts/validate-fixtures.sh 2>&1 | grep -c _walker_only`
Expected: `0`

- [ ] **Step 3: Git log review**

Run: `git log --oneline feat/composite-nodes..feat/goal-seek-node`
Expected: 12 commits (Tasks 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12 — plus Task 11's commit lives in the sibling repo, not here).

- [ ] **Step 4: Check CLAUDE.md sync note is satisfied**

`CLAUDE.md`'s HARD-REQUIREMENT section requires cross-repo sync. For `goal_seek`:
- `examples.md` — inspect `examples.md`. If no existing example uses a goal-seeking pattern, add a short one to an existing workflow or leave a dated note in `examples.md` that `goal_seek` examples will be added when a real workflow needs them. A TODO-style placeholder is **not acceptable** — either add a real example or explicitly document that no example was added (one-sentence note), with reasoning.
- `hiivmind-blueprint/lib/patterns/authoring-guide.md` and `execution-guide.md`: out of scope for this repo's PR. Note in the PR description that these guides will need a follow-up mention of `goal_seek`.

- [ ] **Step 5: No commit needed if all green**

If `examples.md` was modified, commit:
```bash
git add examples.md
git commit -m "docs: add goal_seek example (or note: no example added, reason)"
```

Otherwise skip.

---

## Final checklist

- [ ] All 13 tasks complete (Task 11 commit is in the sibling repo).
- [ ] `./scripts/validate-fixtures.sh` exits 0.
- [ ] `schema/authoring/node-types.json` parses as valid JSON.
- [ ] `package.yaml` version is `7.2.0`, `schemas.node` is `"3.2"`, `composite_types` is `3`.
- [ ] `blueprint-composites.md` lists `goal_seek`.
- [ ] `CHANGELOG.md` has a `[7.2.0]` section.
- [ ] Sibling repo has `principle/goal-seeking-as-bounded-loop` branch with the principle doc and README index update.
- [ ] PR description (to be written at merge time) lists the follow-up sync for `hiivmind-blueprint` pattern guides.
