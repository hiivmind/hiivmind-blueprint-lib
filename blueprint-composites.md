# hiivmind-blueprint Composites

Author-time composite catalog. Composites are syntactic sugar that the walker
expands deterministically into primitive nodes before the LLM interprets
anything at runtime.

**The LLM at runtime does NOT read this file.** It reads `blueprint-types.md`
and the expanded primitive graph. Composite definitions never reach runtime.

Walker implementations (Python and TypeScript) live in `hiivmind-blueprint-mcp`.
Both must produce identical primitive subgraphs from the fixture corpus in
`tests/fixtures/composites/`.

Behavioral invariants and rationale for each composite live in principle
documents:

- `composite-primitive-canary` (c.type-system) — composites are sugar; awkward
  composites are diagnostic signals that primitives need extension.
- `confirmations-as-explicit-state` (g.trust-governance) — the `confirm`
  composite's structural decomposition is the policy; the walker expansion is
  the enforcement.

## Conventions

- `name(param1, param2, optional?)` — reference signature. `?` marks optional
  parameters. The actual YAML call site uses sibling keys, not positional args.
- `X ∈ {a, b, c}` — enum variants on the line below the signature.
- `→` describes the expansion outcome (primitive subgraph shape), not runtime
  semantics.
- All string parameters support `${}` state interpolation (same as primitives).

---

## Composites

confirm(prompt, store_as, on_confirmed, on_declined, header?)
  store_as      = dot-notation state field (convention: confirmations.<name>)
  header        defaults to "CONFIRM"
  on_confirmed  = {next_node, consequences?, label?}
  on_declined   = {next_node, label?}
  → Expands to: user_prompt → mutate_state → conditional → (optional action).
    The conditional structurally gates routing on store_as == true.
    See principle: confirmations-as-explicit-state.

gated_action(when[], else, on_unknown?)
  when          = [{condition, consequences?, next_node}]
    condition   = string (evaluate_expression shorthand) |
                  {all|any|none|xor: [...]} (composite shorthand) |
                  object (canonical precondition)
  on_unknown    defaults to workflow default_error
  → First-match-wins CASE/WHEN dispatch. Expansion: chain of conditional
    nodes, each optionally followed by an action for per-branch
    consequences. 3VL short-circuit on unknown.

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
