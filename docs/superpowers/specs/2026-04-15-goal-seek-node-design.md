# goal_seek Composite — Design

**Status:** approved for implementation planning
**Date:** 2026-04-15
**Branch:** `feat/goal-seek-node` (based on `feat/composite-nodes`)
**Version target:** hiivmind-blueprint-lib v7.2.0

## Problem

Existing node primitives (`action`, `conditional`, `user_prompt`) and the v7.1.0
composites (`confirm`, `gated_action`) express only forward-chaining workflows:
if-this-then-that over a DAG. There is no first-class way to express
**goal-driven** workflows — those that loop until a set of conditions is
satisfied. Example use cases:

- Discovery dialogs that keep asking until required slots are filled.
- Polling loops that retry until an external service is ready.
- Refinement loops that regenerate a candidate until it passes criteria.

Authors currently simulate these by wiring manual back-edges in their workflow
graph. This is error-prone and invisible at the author's level of intent.

## Solution

A new composite node type, `goal_seek`, added to `blueprint-composites.md`.
The walker (in `hiivmind-blueprint-mcp`, out of scope for this repo) expands it
deterministically into a cluster of primitives that forms a bounded dispatcher
loop. No new primitive is introduced — the canary principle holds.

## Author-facing signature

```
goal_seek(goals[], max_iterations, on_complete, on_abort?, on_budget_exceeded?)
  goals        = [{name, starting_node, success_condition?, run_as?}]
    name              = identifier (namespaced into goal_seek.<node_id>.goals.<name>)
    starting_node     = node reference — entry point for this goal's sub-process
    success_condition = optional precondition re-checked on re-entry;
                        if omitted, walker defaults to status=satisfied on return
    run_as            ∈ {inline, subagent}, default inline
  max_iterations       = positive integer budget (safety rail)
  on_complete          = next_node when all goals satisfied-or-ignored
  on_abort             = next_node when any sub-process sets aborted=true
                         (defaults to workflow default_error)
  on_budget_exceeded   = next_node when iterations exceed max_iterations
                         (defaults to workflow default_error)
  → Loop dispatcher. First-incomplete-wins over goals[]. Each goal's
    sub-process is responsible for routing its terminal node back to the
    goal_seek node. Walker injects status updates on return edges.
```

### Author contract (walker-enforced)

1. Each `starting_node` must exist in the workflow.
2. Every terminal path of each sub-process must route back to the `goal_seek`
   node. Walker traces the reachable subgraph rooted at `starting_node` and
   rejects the workflow if any terminal leaves it.
3. Sub-processes may set `goal_seek.<node_id>.aborted = true` or
   `goal_seek.<node_id>.goals.<name>.status = ignored` via `mutate_state`
   consequences. Walker does **not** inject these — they are author-authored
   signals.

## State namespace

All state written by `goal_seek` is namespaced under the goal_seek node's own
id (`<seek_id>`) to prevent collisions across multiple goal_seek nodes in one
workflow:

```
goal_seek.<seek_id>.iterations              # integer, walker-managed
goal_seek.<seek_id>.aborted                 # boolean, default false; author may set true
goal_seek.<seek_id>.goals.<goal_name>.status
    ∈ {incomplete, satisfied, ignored}
```

`<seek_id>` is the workflow node id of the `goal_seek` node itself — no
author-chosen handle required.

## Expansion shape

Given a `goal_seek` node `G` with goals `[A, B, C]`, the walker emits the
following primitive subgraph. Node names use the `G__*` convention consistent
with the `confirm` / `gated_action` expansions.

| Node | Type | Role |
|------|------|------|
| `G__entry` | `conditional` | Checks `goal_seek.G.iterations` exists. First-time → `G__init`; subsequent → `G__tick`. |
| `G__init` | `action` | First-entry bootstrap. Consequences: set `iterations = 0`, set every goal's `status = incomplete`. `on_success` → `G__dispatch`. |
| `G__tick` | `action` | Re-entry housekeeping. Consequences: increment `iterations`; for each goal with a `success_condition`, evaluate it and set `status = satisfied` if it holds. `on_success` → `G__budget_check`. |
| `G__budget_check` | `conditional` | `iterations > max_iterations` → `on_budget_exceeded`; else → `G__abort_check`. |
| `G__abort_check` | `conditional` | `aborted == true` → `on_abort`; else → `G__complete_check`. |
| `G__complete_check` | `conditional` | All goals `satisfied` or `ignored` → `on_complete`; else → `G__dispatch`. |
| `G__dispatch` | `gated_action` (then expanded) | First-match over incomplete goals. For each goal X: `when: goal_seek.G.goals.X.status == incomplete`, `next_node: <X.starting_node>`. No `else` needed — `G__complete_check` guarantees at least one is incomplete. |
| `G__return_<goal>` | `action` | Injected by walker onto return edges. Consequence: set `goal_seek.G.goals.<goal>.status = satisfied` (only if no `success_condition` for this goal — otherwise status flip defers to `G__tick`'s re-evaluation). `on_success` → `G__entry`. |

`G__dispatch` uses the existing `gated_action` composite, which itself expands
to a chain of `conditional` + `action` nodes. Nested composite expansion is a
walker concern — the walker applies expansions bottom-up or iterates until
fixpoint.

### Control-flow summary

```
author sees: G (goal_seek)
runtime sees:
  G__entry
    → (first time)  G__init → G__dispatch
    → (subsequent)  G__tick → G__budget_check → G__abort_check
                    → G__complete_check → G__dispatch
  G__dispatch → <goal's starting_node>
  … sub-process runs …
  <sub-process terminal pointing at G> → G__return_<goal> → G__entry (loop)
```

### Return-edge rewriting

Authors write their sub-process's terminal node with `on_success: G` (or the
equivalent for their node type). The walker detects this edge and rewrites it
to `on_success: G__return_<goal>`. Walker determines which goal a sub-process
belongs to by the subgraph-reachability analysis rooted at each goal's
`starting_node`; a terminal reachable from multiple goals' starting nodes is an
authoring error and is rejected.

### `run_as: subagent`

When a goal declares `run_as: subagent`, the walker marks the goal's
`G__return_<goal>` node (or an equivalent hint on the dispatch edge) with a
runtime directive that the sub-process should execute in a delegated agent
context rather than inline. Expansion shape is otherwise identical. The
semantics of subagent execution are a runtime concern handled by
`hiivmind-blueprint-mcp`; this library only declares the field.

## Schema changes

`schema/authoring/node-types.json`:

- Bump `$comment` from v3.1 → v3.2.
- Add `goal_seek` to the `type` enum.
- Add a new `if/then` dispatch entry in the top-level `allOf`.
- Add `goal_seek_node` `$def`:
  - `type`: const `goal_seek`
  - `description`: optional string
  - `goals`: array, `minItems: 1`, `items`:
    - required: `[name, starting_node]`
    - `name`: identifier
    - `starting_node`: `node_reference`
    - `success_condition`: optional precondition (same polymorphism as
      `conditional.condition`: string shorthand, composite shorthand object, or
      canonical precondition object)
    - `run_as`: optional enum `[inline, subagent]`, default `inline`
    - `additionalProperties: false`
  - `max_iterations`: integer, `minimum: 1`
  - `on_complete`: `node_reference`
  - `on_abort`: optional `node_reference`
  - `on_budget_exceeded`: optional `node_reference`
  - required: `[goals, max_iterations, on_complete]`
  - `additionalProperties: false`

## Fixture corpus

`tests/fixtures/composites/goal_seek/`:

**Positive (each with `input.yaml` + `expected.yaml`):**
- `minimal/` — two goals, no success conditions, inline only.
- `with_success_conditions/` — goals whose status flips only when a
  precondition holds on re-entry (polling loop shape).
- `with_subagent/` — one goal declares `run_as: subagent`; expected output
  shows the runtime hint on the return node.
- `with_abort/` — sub-process sets `aborted = true` via `mutate_state`;
  walker expansion is identical but the fixture documents the abort path.

**Negative (`_negative/`):**
- `missing_goals`
- `empty_goals`
- `missing_max_iterations`
- `missing_on_complete`
- `goal_missing_starting_node`
- `goal_missing_name`

**Walker-contract fixtures (documented but not ajv-checkable):**
- `goal_terminal_escapes_loop` — sub-process terminal routes somewhere other
  than the goal_seek node; walker must reject. This lives as a documented
  expected-rejection case that the walker test suite (in
  `hiivmind-blueprint-mcp`) will consume.

## Principle capture

One new principle, in the sibling `hiivmind-blueprint-central` repo on a new
branch `principle/goal-seeking-as-bounded-loop`:

**`02.principles/a.execution-paradigm/goal-seeking-as-bounded-loop.md`**

- **Rule:** Goal-seeking workflows are expressed as composite loops with
  explicit namespaced state, a mandatory iteration budget, and a per-goal
  completion predicate. There is no unbounded loop primitive.
- **Why:** LLM-as-execution-engine workflows must terminate deterministically.
  A budget plus per-goal evidence keeps the runtime provably bounded and
  debuggable. "Loop until we feel done" is not acceptable; "loop until every
  goal has recorded evidence of satisfaction or ignore, or the budget is
  exhausted" is.
- **How applied:** Any future primitive-level loop proposal must justify why
  composite expansion is insufficient. Authors wiring back-edges manually
  outside `goal_seek` should be flagged in review.

Cross-references the existing `composite-primitive-canary` principle: goal_seek
is a successful canary outcome — iterative goal-seeking decomposes into
existing primitives via sugar, so no loop primitive is warranted.

## Package & documentation

- `package.yaml`: bump to v7.2.0; `stats.composite_types: 2 → 3`.
- `CHANGELOG.md`: new 7.2.0 entry documenting `goal_seek`.
- `README.md`: add goal_seek to the composite catalog section.
- `CLAUDE.md`: update the composites cross-reference to include goal_seek.
- `blueprint-composites.md`: add the signature block per the shape above.

## Scope fence

**In scope (this repo, this branch):**
- `blueprint-composites.md` entry
- `schema/authoring/node-types.json` additions
- Fixture corpus (positive, negative, walker-contract)
- Package metadata, changelog, README, CLAUDE.md
- New principle in `hiivmind-blueprint-central`

**Out of scope:**
- Walker implementation (Python or TypeScript) — lives in future
  `hiivmind-blueprint-mcp` repo. The fixture corpus is the authoritative walker
  contract.
- Runtime semantics of `run_as: subagent` — declared here, honored by the
  runtime.
- Any changes to existing primitives — goal_seek is pure sugar.

## Open questions

None at design time. All structural decisions resolved in brainstorming:
- Selection: first-incomplete-wins
- Termination: all-satisfied-or-ignored + max_iterations budget + explicit abort
- Completion signaling: hybrid — default walker-injected status=satisfied on
  return, optional `success_condition` for re-check on re-entry
- Sub-process return: author wires terminal → goal_seek node id; walker
  rewrites to `G__return_<goal>`
- State namespace: keyed by goal_seek node id, no author-chosen handle
