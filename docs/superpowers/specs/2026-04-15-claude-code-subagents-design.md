# Design: Claude Code Sub-agents & Coordinator Mode in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md), [Tool Catalog](2026-04-15-claude-code-tool-catalog-design.md)
**Referenced by:** Compaction (future), Guardrails (future)

---

## 1. Scope & Non-Goals

This spec captures the **sub-agent fork primitive, isolation model, and coordinator-mode prompt contracts** used by Claude Code.

**In scope:**
- `spawn_subagent` — the fork primitive referenced by Tool catalog §6.5 and (future) Compaction
- Three isolation levels: `Task`, `InProcessTeammate`, remote teammate
- Cache-alignment contract (`model: 'inherit'`) for prompt-prefix sharing
- Memory and iteration bounds (`TEAMMATE_MESSAGES_UI_CAP = 50`, per-subagent `max_iterations`)
- Coordinator mode as a prompt-level contract annotation
- Swarm as a `concurrently` pattern over `spawn_subagent` (brief)
- Sub-agent lifecycle: spawn → run → harvest → terminate

**Out of scope:**
- Delegation *prompt wording* (prompt engineering, not specification)
- Transport details for remote teammates (SSE, polling, JWT) — reserved for a Bridge spec
- Sub-agent tool catalog differences (inherited from parent with scoping rules; scoping is a Guardrails concern)
- Session persistence, JSONL transcripts (State/persistence spec)

---

## 2. Background

A *sub-agent* in Claude Code is a child instance that runs its own `query()` loop (from the core-loop spec) with a bounded task, its own iteration budget, and an isolation model that determines how it shares process state with the parent. There are three isolation levels: `Task` (separate subagent with no shared memory), `InProcessTeammate` (same process, shared terminal, state isolated via `AsyncLocalStorage`), and remote teammate (a teammate running in a different process or machine, reached via a bridge). Coordinator mode is *not* a separate runtime — it is a prompt-level contract: the coordinator's system prompt defines how it delegates, aggregates, and synthesizes, and the sub-agents are ordinary Claude instances with different system prompts.

**Source grounding:** `coordinator/coordinatorMode.ts` (coordinator prompt contract); `agents/Task.ts`, `agents/InProcessTeammate.ts`, `bridge/*` (isolation implementations); the `TEAMMATE_MESSAGES_UI_CAP = 50` constant introduced after a 36.8GB memory leak with 292 concurrent agents. See §10.

---

## 3. Types

### 3.1 Sub-agent identity

```lmpl
type SubagentType =
    | "general_purpose"
    | "coordinator"
    | string                   -- named specialist (e.g., "Explore", "code-reviewer")

type IsolationModel =
    | "task"                   -- fire-and-forget; no shared state; single terminal result
    | "in_process_teammate"    -- same process; AsyncLocalStorage isolation; bounded message buffer
    | "remote_teammate"        -- different process/host; message-passing over bridge
```

### 3.2 Input and output

```lmpl
type SubagentSpec = {
    subagent_type: SubagentType,
    description: string,             -- 3-5 word UI label
    prompt: string,                  -- the task for the sub-agent
    max_iterations: int,             -- hard cap on the sub-agent's query loop
    isolation: IsolationModel,
    inherit_model: bool,             -- if true, share parent's model for cache alignment
    inherit_tools: option[list[ToolName]],   -- none = all; some = filtered subset
    timeout_ms: option[int]
}

type SubagentResult = {
    status: "success" | "error" | "timeout" | "aborted" | "iteration_cap",
    summary: string,                 -- the one canonical artifact returned to the parent
    artifacts?: list[record],        -- optional structured outputs
    turn_count: int,                 -- iterations consumed
    tokens_used: {input: int, output: int, cache_read: int, cache_write: int}
}
```

### 3.3 Live-agent handle (non-Task isolations)

```lmpl
type SubagentHandle = {
    id: string,
    spec: SubagentSpec,
    status: "pending" | "running" | "completed" | "failed" | "aborted",
    send: function(Message) -> unit,    -- only for in_process / remote teammates
    messages: bounded_list[Message]     -- see §5.2 for the bound
}
```

`Task`-isolated sub-agents do not expose a handle; they are single-shot and return only a `SubagentResult`.

---

## 4. The Fork Primitive

### 4.1 `spawn_subagent`

```lmpl
define spawn_subagent(spec: SubagentSpec,
                     parent_ctx: ToolInvocationContext) -> SubagentResult:
    @boundary(
        inputs: {spec: SubagentSpec, parent_ctx: ToolInvocationContext},
        outputs: SubagentResult
    )

    require length(spec.prompt) > 0, "sub-agent prompt must be non-empty"
    require spec.max_iterations > 0, "iteration budget must be positive"
    require cache_alignable(spec, parent_ctx) when spec.inherit_model,
        "inherit_model requires byte-compatible system prompt prefix"

    child_params <- seed_child_params(spec, parent_ctx)
    child_state  <- initial_state(child_params)

    attempt:
        final_message <- query(child_params)          -- core-loop spec #0
        return {
            status: "success",
            summary: extract_summary(final_message),
            artifacts: extract_artifacts(final_message),
            turn_count: child_params.turn_count,
            tokens_used: child_params.telemetry
        }
    on failure(err):
        return map_error_to_result(err)

    ensure result.turn_count <= spec.max_iterations,
        "sub-agent must terminate within its iteration budget"
    ensure not leaks_parent_state(result, parent_ctx),
        "sub-agent results must not echo the parent's private state"
    ensure result.tokens_used.input >= 0, "token accounting must be non-negative"
```

### 4.2 Cache-alignment contract

Sub-agents spawned with `inherit_model: true` share the parent's prompt cache. Alignment is byte-level — a one-character difference in the system prompt invalidates the cache.

```lmpl
define cache_alignable(spec: SubagentSpec, parent_ctx: ToolInvocationContext) -> bool:
    ensure result implies
           byte_prefix(child_system_prompt(spec), parent_system_prompt(parent_ctx))
           is shared,
        "alignable iff child system prompt has the parent's prefix"
    ensure result implies spec.inherit_model,
        "cache alignment only makes sense when the model is inherited"
```

The @model_capability annotation on the sub-agent should declare `"cache_aligned"` when this contract holds, so static checkers can reason about it.

### 4.3 Isolation guarantees

Every isolation model must satisfy:

```lmpl
invariant not leaks_parent_state(subagent_view, parent_state),
    "a sub-agent can see only what its spec explicitly grants"

invariant subagent_effects(subagent) subset parent_approved_effects,
    "sub-agent cannot perform effects the parent cannot"

invariant bounded_subagent_memory(subagent),
    "sub-agent's observable state has a finite upper bound"
```

These are spec-level contracts. The three isolation refinements in §5 show how each satisfies them.

---

## 5. Isolation Model Refinements

### 5.1 `Task` — single-shot, fully isolated

```lmpl
-- isolation: "task"
-- The sub-agent spawns, runs its query loop to completion, and returns
-- one SubagentResult. No live handle. No mid-flight messages. The
-- simplest and most common case.

define spawn_task(spec: SubagentSpec, parent_ctx: ToolInvocationContext)
    -> SubagentResult:
    require spec.isolation == "task"

    -- Task sub-agents do not expose a handle; the parent blocks on the result.
    return spawn_subagent(spec, parent_ctx)

    ensure result.status in ["success", "error", "timeout", "iteration_cap"],
        "task sub-agents always produce a terminal result"
```

### 5.2 `InProcessTeammate` — shared process, isolated state

In-process teammates share the terminal with the parent. State isolation uses `AsyncLocalStorage` (per-async-context state) rather than separate processes. The message buffer is capped:

```lmpl
-- TEAMMATE_MESSAGES_UI_CAP = 50
-- Added after an incident: 292 concurrent agents consumed 36.8GB of
-- memory before this cap was introduced.
define teammate_message_cap: int <- 50

define spawn_in_process_teammate(spec: SubagentSpec,
                                parent_ctx: ToolInvocationContext)
    -> SubagentHandle:
    require spec.isolation == "in_process_teammate"

    handle <- {
        id: generate_id(),
        spec: spec,
        status: "pending",
        send: make_sender(handle),
        messages: bounded_list(cap: teammate_message_cap)
    }

    spawn_async(fun() -> query(seed_child_params(spec, parent_ctx)))
    return handle

    invariant length(handle.messages) <= teammate_message_cap,
        "teammate message buffer must not exceed the cap"
    invariant no_shared_mutable_state(handle, parent_ctx),
        "parent and teammate share the process but not mutable state"
```

### 5.3 Remote teammate — cross-process or cross-host

Remote teammates run in a different process or host, reached via a bridge (REPL, SSE, or polling transport). The transport is out of scope for this spec; what matters is the trust boundary:

```lmpl
-- isolation: "remote_teammate"
-- Messages cross a trust boundary. Inputs and outputs are serialized and
-- re-validated on each hop.

define spawn_remote_teammate(spec: SubagentSpec,
                            parent_ctx: ToolInvocationContext,
                            bridge: Bridge)
    -> SubagentHandle:
    require spec.isolation == "remote_teammate"
    require authenticated(bridge), "bridge must be authenticated"

    handle <- register_remote(bridge, spec, parent_ctx)
    return handle

    ensure messages_validated_on_ingress(handle),
        "every inbound message must be re-validated on the parent side"
    ensure tokens_budgeted(handle, parent_ctx),
        "remote sub-agent tokens count against the parent's budget"
```

---

## 6. Coordinator Mode as a Prompt Contract

Coordinator mode is not a runtime feature. It is a **system-prompt contract** that governs how a coordinator sub-agent delegates, aggregates, and synthesizes. This spec expresses it as a prompt-level annotation with enforceable output contracts.

### 6.1 The `@coordinator_mode` annotation

```lmpl
@coordinator_mode
@system_prompt
instructions: string <- "
    You are a coordinator. Delegate sub-tasks to specialist sub-agents
    via the Task tool. Aggregate their results. Synthesize — do not relay.
    Cite which sub-agent contributed each claim.
"

@agent("coordinator", "Orchestrates specialist sub-agents")
@max_iterations(max_coordination_turns)
```

The annotation is informational today (prompt-level) but a future LMPL extension could promote it to a checked contract (§8.3).

### 6.2 Output contracts

```lmpl
define coordinator_response(turn: CoordinatorTurn) -> message["assistant"]:
    ensure synthesized(result) and not relayed(result),
        "coordinator must synthesize sub-agent outputs, not paste them"
    ensure every claim in result has contributor in sub_results,
        "every claim must be attributable to a sub-agent"
    ensure length(result.delegations) >= 2 when complex(turn.task),
        "complex tasks delegate to at least 2 specialists"
    ensure not leaks_internal_delegation_structure(result),
        "output does not expose delegation plumbing to the user"
```

### 6.3 Swarm as `concurrently` over `spawn_subagent`

Swarm mode is the pattern of fanning out multiple specialists in parallel and merging their results. It requires no new primitives — it's a standard `concurrently` block over `spawn_subagent` calls:

```lmpl
define swarm_dispatch(tasks: list[SubagentSpec],
                     parent_ctx: ToolInvocationContext)
    -> list[SubagentResult]:
    require length(tasks) >= 2, "swarm requires at least two parallel tasks"

    concurrently:
        results <- map(tasks, spec -> spawn_subagent(spec, parent_ctx))
    join results

    return results

    ensure length(results) == length(tasks), "one result per dispatched task"
```

Swarm does not need its own primitive. If that changes in a future version, it deserves a dedicated spec section.

---

## 7. Lifecycle & Termination

Every sub-agent progresses through the same lifecycle regardless of isolation model:

| Phase       | Responsibility                                                              |
|-------------|-----------------------------------------------------------------------------|
| **Spawn**   | `spawn_subagent` validates spec, seeds child params, registers handle (if applicable) |
| **Run**     | Child's own `query()` loop executes with its own iteration budget            |
| **Harvest** | Parent receives `SubagentResult` (Task) or drains handle (teammate)          |
| **Terminate** | Child loop exits via its own `end_turn` transition or a bound trip         |

### 7.1 Termination conditions

```lmpl
define subagent_termination_reason(result: SubagentResult) -> string:
    match result.status:
        case "success":        return "end_turn"
        case "iteration_cap":  return "max_iterations_exceeded"
        case "timeout":        return "timeout_ms_exceeded"
        case "aborted":        return "parent_abort_propagated"
        case "error":          return "uncaught_error"

    ensure result.status in ["success", "iteration_cap", "timeout",
                             "aborted", "error"],
        "every sub-agent reaches exactly one terminal status"
```

### 7.2 Abort propagation

```lmpl
invariant aborted(parent_ctx.abort_controller) implies
          aborted(subagent_ctx.abort_controller),
    "parent abort must propagate to all live sub-agents"
```

### 7.3 Token accounting

Sub-agent token usage counts against the parent's session budget. Ownership is explicit:

```lmpl
require parent_ctx.token_budget.remaining >= estimated_cost(spec),
    "must have sufficient parent token budget before spawning"

ensure parent_ctx.token_budget.remaining ==
       old(parent_ctx.token_budget.remaining) - result.tokens_used.input
                                              - result.tokens_used.output,
    "sub-agent tokens are deducted from the parent after harvest"
```

---

## 8. LMPL Gaps and Proposed Extensions

### 8.1 Bounded collections as first-class

`TEAMMATE_MESSAGES_UI_CAP = 50` is enforced via a `bounded_list(cap: 50)` pseudo-primitive. A real LMPL `bounded_list[T, n]` type would express this structurally instead of as a runtime check. Companion to the `bounded_counter` gap from the core-loop spec (§8.5 there).

### 8.2 Cache-alignment as a structural property

`cache_alignable` returns true iff the child's system prompt starts with the parent's. LMPL has no way to assert "string A is a prefix of string B" structurally — only as a predicate. A `@prefix_of(parent)` annotation or a `prefix_stable[T]` type would make cache invariants checkable at the spec level rather than inferable from prose.

### 8.3 Prompt-level contracts as checked annotations

`@coordinator_mode` is currently informational. Promoting it to a checked annotation — where tooling verifies the system prompt contains the required delegation/synthesis obligations — would let specs enforce prompt contracts the same way they enforce code contracts. This would need a "prompt lint" pass distinct from LMPL type-checking.

### 8.4 Effects scoping across process boundaries

Remote teammates cross a trust boundary where inputs and outputs are serialized and re-validated. LMPL's `@boundary` annotation captures this at function-call granularity but not at agent-lifetime granularity. An `@isolation(trust_level)` annotation on agent definitions would make the boundary visible to readers and checkers.

### 8.5 Recursive type of `query`

Sub-agents run `query()`, which in turn can invoke tools (including `Task`), which can spawn sub-agents. The specs are already mutually recursive via cross-references; LMPL has no explicit support for mutual recursion between specs. This is a documentation-ergonomics gap, not a correctness gap.

---

## 9. Cross-Spec References

| Reference                          | From                                | To                                |
|------------------------------------|-------------------------------------|-----------------------------------|
| `query(child_params)`              | §4.1 (body of `spawn_subagent`)     | Core loop (#0, written)           |
| `spawn_subagent` invocation        | Tool catalog §6.5 (`Task` tool)     | Tool catalog (#3, written)        |
| `spawn_subagent` for autoCompact   | §4.1                                | Compaction (future)               |
| `can_use_tool` / inherited tools   | §3.2 (`inherit_tools`)              | Guardrails (future)               |
| Bridge for remote teammates        | §5.3                                | Bridge spec (not yet scheduled)   |

---

## 10. References

- Redreamality, "Claude Code Leak: A Deep Dive into Anthropic's AI Coding Agent Architecture" — https://redreamality.com/blog/claude-code-source-leak-architecture-analysis/ (three isolation levels; 36.8GB / 292 agents incident; `TEAMMATE_MESSAGES_UI_CAP`)
- l3tchupkt, "Claude Code CLI Runtime: Deep Reverse-Engineering Analysis" — https://github.com/l3tchupkt/claude-code (`coordinator/coordinatorMode.ts` behavioral contract)
- Blake Crosley, "What the Claude Code Source Leak Reveals" — https://blakecrosley.com/blog/claude-code-source-leak (coordinator mode as prompt-level implementation, not code)
- cablate, *claude-code-research* — https://github.com/cablate/claude-code-research (6 built-in agents, Coordinator mode, Swarm, 50-message cap)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented sub-agent model.
