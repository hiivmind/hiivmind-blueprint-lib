# Design: Claude Code Core Agentic Loop in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review

---

## 1. Scope & Non-Goals

This spec expresses the **core query loop** of Claude Code (`src/query.ts`, ~1,729 lines) as LMPL pseudocode, in two layers:

- **Ideal skeleton** — a minimal `agent_loop` block with contracts, suitable as a pedagogical artifact for "what shape is a production agent loop."
- **Refined expansion** — the same skeleton with each stage's body replaced by its real behavior: the full `State` type, all five `transition` reasons, recovery branches, and Continue Site reassignment pattern.

**In scope:**
- `queryLoop()` control flow: observe → reason → act → update → until
- `State` type (all ~8 fields) and the Continue Site pattern
- `Transition` tagged union with all known reasons
- Stop-reason dispatch (`end_turn`, `tool_use`, recovery)
- Termination and progress contracts

**Out of scope** (deferred to future specs — see §9):
- Context management (4-tier compaction: reactive → microcompact → snip → autoCompact)
- Permission and guardrail layers (`bashSecurity.ts`, `yoloClassifier.ts`, 6 permission modes)
- Sub-agent / Coordinator / Swarm orchestration
- Hook system (`PreToolUse`, `Stop`, etc.)
- Memory tiers (`memdir/`, `CLAUDE.md` loading)
- Prompt cache boundary (`__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__`)
- Streaming token semantics (abstracted as atomic `send()` — see §8)
- Anti-distillation, undercover mode, native client attestation

---

## 2. Background

Claude Code's execution engine is a single async generator `queryLoop()` — one `while(true)` that owns the entire turn cycle. State advances through a **Continue Site pattern**: each iteration reassigns the full `State` object (`state = { ...state, ... }`) rather than mutating fields in place, making transitions atomic and recording *why* the loop continued via an explicit `transition` field. This spec captures that control flow in LMPL.

**Source grounding:** This document reconstructs `queryLoop()` behavior from the published analyses of the `cli.js.map` source map leak shipped in `@anthropic-ai/claude-code@2.1.88` on 2026-03-31. No source code is reproduced; the spec is an independent LMPL expression of the documented control flow. See §10 for references.

---

## 3. Types

### 3.1 Base

```lmpl
type Message = message[role]                      -- role in {"system", "user", "assistant", "tool"}
type Conversation = list[Message]

type StopReason =
    | "end_turn"
    | "tool_use"
    | "max_tokens"
    | "stop_sequence"
    | "error"
```

### 3.2 Tool invocation

```lmpl
type ToolCall = {
    id: string,
    name: string,
    arguments: record
}

type ToolResult = tool_result    -- from agentic profile; carries status + provenance
```

### 3.3 Transition (tagged union)

Every non-terminal loop iteration records *why* it continued. The `transition` field is the spec-level counterpart to the source's continue-site comments.

```lmpl
type Transition =
    | {reason: "tool_use"}
        -- Assistant response contained tool_use blocks; execute and feed back.
    | {reason: "max_tokens_retry", attempt: int}
        -- stop_reason == "max_tokens"; bump max_output_tokens_override and retry.
        -- Bounded by max_output_tokens_recovery_count.
    | {reason: "reactive_compact_trigger"}
        -- Token accounting crossed a threshold; hand off to compaction layer.
        -- (Compaction itself is out of scope; modeled as an opaque state delta.)
    | {reason: "model_fallback", from: string, to: string}
        -- Upstream overload; synthesize a tool_result of "Model fallback triggered",
        -- inject system message, re-issue request on fallback model.
    | {reason: "end_turn"}
        -- Terminal. The loop exits with the assistant's final message.
```

### 3.4 Mutable state

```lmpl
type State = {
    messages: Conversation,
        -- Conversation history, append-only across iterations.

    tool_use_context: record,
        -- Ambient context passed to tool executors (abort signal, approval
        -- callbacks, working directory). Shape opaque at this layer.

    auto_compact_tracking: option[{
        consecutive_failures: int,
        last_attempt_turn: int
    }],
        -- Compaction circuit-breaker state. Referenced here; compaction
        -- logic itself is a future spec.

    max_output_tokens_recovery_count: int,
        -- How many times we have already bumped max_output_tokens to
        -- recover from a truncated response. Hard-capped.

    has_attempted_reactive_compact: bool,
        -- Latch: reactive compaction is a single-shot attempt per window.

    max_output_tokens_override: option[int],
        -- Per-turn override applied after a max_tokens truncation.

    transition: option[Transition],
        -- Why the *previous* iteration continued. None on the first turn.

    turn_count: int
        -- Monotonic iteration counter, used for max_iterations contract.
}
```

### 3.5 Immutable params

`QueryParams` are fixed for the duration of a call. Separation is deliberate: it prevents accidental param mutation inside the loop and makes the eventual refactor to a pure `step(state, event, config)` reducer straightforward.

```lmpl
type QueryParams = {
    system_prompt: string,
    initial_messages: Conversation,
    tools: list[ToolDefinition],
    model: string,
    fallback_model: option[string],
    max_iterations: int,
    max_output_tokens_recovery_cap: int,    -- bounds on retry counter
    abort_controller: AbortController
}
```

---

## 4. The Ideal Skeleton

A minimal, LMPL-idiomatic expression of the loop. This is what the agentic profile's `agent_loop` block is *for* — and nearly every feature in Claude Code's production loop is an elaboration of one of these four stages.

```lmpl
@agent("claude_code_query", "Core turn-state machine of Claude Code")
@model_capability("tool_use", "long_context")
@max_iterations(params.max_iterations)

define query(params: QueryParams) -> message["assistant"]:
    require length(params.initial_messages) > 0, "must have at least one message"
    require params.max_iterations > 0, "iteration budget must be positive"

    state: State <- initial_state(params)

    agent_loop:
        observe: gather_turn_context(state, params)
        reason:  reply <- send(observation, to: model, tools: params.tools)
        act:     match reply.stop_reason:
                     case "end_turn":   reply
                     case "tool_use":   run_tools(reply.tool_calls, state.tool_use_context)
                     case _:            recover(reply, state, params)
        update:  state <- continue_site(state, reply, action_result)
        until:   state.transition.reason == "end_turn"

    ensure terminated_cleanly(state),
        "loop must reach end_turn or a bounded recovery, not an iteration-cap trip"
    ensure not contains_unresolved_tool_calls(state.messages),
        "every tool_use must be paired with a tool_result before termination"

    invariant state.turn_count <= params.max_iterations,
        "loop must terminate within the iteration budget"
    invariant progress(state, previous_state),
        "each iteration must either add a message, execute a tool, or record a transition"

    return final_message(state)
```

This skeleton is the contract. Everything in §5 refines its bodies without changing its shape.

---

## 5. Refined Expansion

Each stage below replaces a line from §4. The skeleton's visual structure is preserved so the correspondence is explicit.

### 5.1 `observe`

```lmpl
-- observe: gather_turn_context(state, params)
define gather_turn_context(state: State, params: QueryParams) -> TurnContext:
    require not aborted(params.abort_controller),
        "abort signal checked before each model call"

    return {
        messages: state.messages,
        system_prompt: params.system_prompt,
        tools: params.tools,
        max_output_tokens: state.max_output_tokens_override,
        model: current_model(state, params)    -- may be fallback after a transition
    }
```

### 5.2 `reason` — the model call

```lmpl
-- reason: reply <- send(observation, to: model, tools: params.tools)
--
-- NOTE: Streaming is intentionally abstracted. The real implementation
-- yields tokens via an AsyncGenerator and detects tool_use blocks
-- mid-stream. See §8 for the LMPL gap this exposes.
define send(ctx: TurnContext, to: model, tools: list[ToolDefinition])
    -> message["assistant"]:

    attempt:
        reply <- model_call(ctx)
        return reply
    on failure(err):
        match err.kind:
            case "overload":      raise ModelFallbackNeeded(from: ctx.model)
            case "abort":         raise Aborted
            case _:               propagate err
```

### 5.3 `act` — dispatch on `stop_reason`

```lmpl
-- act: match reply.stop_reason: case ... => ...
define act(reply: message["assistant"], state: State, params: QueryParams)
    -> ActionResult:

    match reply.stop_reason:
        case "end_turn":
            return {kind: "done", value: reply}

        case "tool_use":
            -- Read-only tools partitioned from mutating tools (concurrency
            -- partition is a real behavior worth naming).
            readonly_calls, mutating_calls <- partition(reply.tool_calls, by: is_readonly)

            concurrently:
                ro_results <- invoke_all(readonly_calls)
            join ro_results

            -- Mutating calls run sequentially, each with approval gates
            -- from the ambient tool_use_context.
            mu_results <- []
            for call in mutating_calls:
                require call.name in approved_tools(state.tool_use_context),
                    "tool must be on the approved list"
                result <- invoke(call) @requires_approval when mutates_world(call)
                append(mu_results, result)

            return {kind: "tool_results", value: concat(ro_results, mu_results)}

        case "max_tokens":
            require state.max_output_tokens_recovery_count
                        < params.max_output_tokens_recovery_cap,
                "max_tokens recovery budget exhausted"
            return {kind: "retry_larger_output"}

        case "error":
            return recover(reply, state, params)

        case _:
            raise UnexpectedStopReason(reply.stop_reason)
```

### 5.4 `update` — the Continue Site

Every continue in the real loop reassigns `State` wholesale. The helper `continue_site` is the LMPL expression of that pattern — the *only* place `state` is rebound.

```lmpl
-- update: state <- continue_site(state, reply, action_result)
define continue_site(state: State, reply: Message, action: ActionResult) -> State:
    match action.kind:
        case "done":
            return {
                ...state,
                messages: append(state.messages, reply),
                turn_count: state.turn_count + 1,
                transition: {reason: "end_turn"}
            }

        case "tool_results":
            return {
                ...state,
                messages: append_all(state.messages, [reply, ...action.value]),
                turn_count: state.turn_count + 1,
                transition: {reason: "tool_use"}
            }

        case "retry_larger_output":
            new_override <- bump_token_budget(state.max_output_tokens_override)
            return {
                ...state,
                max_output_tokens_override: some(new_override),
                max_output_tokens_recovery_count:
                    state.max_output_tokens_recovery_count + 1,
                turn_count: state.turn_count + 1,
                transition: {reason: "max_tokens_retry",
                             attempt: state.max_output_tokens_recovery_count + 1}
            }

        case "reactive_compact":
            require not state.has_attempted_reactive_compact,
                "reactive compaction is single-shot per window"
            return {
                ...state,
                messages: compact_messages(state.messages),       -- opaque here
                has_attempted_reactive_compact: true,
                turn_count: state.turn_count + 1,
                transition: {reason: "reactive_compact_trigger"}
            }

        case "model_fallback":
            return {
                ...state,
                messages: append(state.messages,
                                 synthesize_fallback_notice(action.from, action.to)),
                turn_count: state.turn_count + 1,
                transition: {reason: "model_fallback",
                             from: action.from, to: action.to}
            }
```

### 5.5 `recover` — the five recovery paths

```lmpl
define recover(reply: Message, state: State, params: QueryParams) -> ActionResult:
    match classify_error(reply):
        case "max_tokens":            return {kind: "retry_larger_output"}
        case "context_near_limit":    return {kind: "reactive_compact"}
        case "model_overload":
            require some(params.fallback_model), "no fallback configured"
            return {kind: "model_fallback",
                    from: params.model, to: unwrap(params.fallback_model)}
        case "abort":                 raise Aborted
        case _:                       propagate reply.error
```

### 5.6 Abort checkpoints

The real loop checks `abort_controller.signal` at multiple points. In LMPL we express this as a contract inside `gather_turn_context` (§5.1) and inside `send` (§5.2), and it is implicit before each `update`:

```lmpl
require not aborted(params.abort_controller), "abort must halt the loop promptly"
```

---

## 6. Transition Reason Reference

| `transition.reason`         | Trigger                                                 | State delta                                                                 | Terminal? |
|-----------------------------|---------------------------------------------------------|-----------------------------------------------------------------------------|-----------|
| `tool_use`                  | Assistant reply contains tool_use blocks                | Append reply + tool_results to messages                                     | No        |
| `max_tokens_retry`          | `stop_reason == "max_tokens"`, budget not exhausted     | Bump `max_output_tokens_override`, increment recovery counter               | No        |
| `reactive_compact_trigger`  | Token accounting crosses reactive threshold             | Compact messages, set `has_attempted_reactive_compact = true`               | No        |
| `model_fallback`            | Upstream overload on primary model                      | Inject "Model fallback triggered" notice, switch `current_model` downstream | No        |
| `end_turn`                  | Assistant emits terminal response with no tool_use      | Append reply; loop exits                                                    | **Yes**   |

---

## 7. Contracts Summary

| Contract                                                | Kind        | Purpose                                                   |
|---------------------------------------------------------|-------------|-----------------------------------------------------------|
| `length(params.initial_messages) > 0`                   | precondition| Non-empty conversation to start                           |
| `params.max_iterations > 0`                             | precondition| Positive iteration budget                                 |
| `not aborted(abort_controller)`                         | precondition| Abort checkpoint before each model call                   |
| `call.name in approved_tools(...)`                      | precondition| Tool must be on the approved list                         |
| `state.max_output_tokens_recovery_count < cap`          | precondition| Bounded max_tokens recovery                               |
| `not state.has_attempted_reactive_compact`              | precondition| Reactive compaction is single-shot                        |
| `terminated_cleanly(state)`                             | postcondition| Loop reached end_turn, not iteration cap                  |
| `not contains_unresolved_tool_calls(state.messages)`    | postcondition| Every tool_use paired with a tool_result                  |
| `state.turn_count <= params.max_iterations`             | invariant   | Termination guarantee                                     |
| `progress(state, previous_state)`                       | invariant   | Each iteration makes observable progress                  |

---

## 8. LMPL Gaps and Proposed Extensions

Writing this spec surfaced the following gaps in the agentic profile:

### 8.1 Streaming / incremental yield

The real loop streams tokens and can detect tool_use blocks mid-stream, enabling early cancellation. LMPL has no primitive for "produce a partial value incrementally." Options:

- **Punt** — document as an implementation detail below the spec layer (current choice).
- **Add a `stream` type** — `stream[T]` as a handle with `yield_chunk` / `on_complete` hooks. Stretches LMPL toward operational semantics; probably not worth it.
- **Add an `incremental` block** — sugar over a generator-style pattern, desugars to a loop with a sentinel terminator.

**Recommendation:** Leave streaming out of LMPL. The spec layer should describe *what* the loop does, not *how* the transport yields bytes. Any spec that needs to reason about partial model output should do so via explicit state (`partial_reply: option[Message]`) rather than a streaming primitive.

### 8.2 Whole-object state reassignment (Continue Site)

The `{...state, field: new_value}` spread pattern is central to how Claude Code expresses atomic transitions but is not first-class in LMPL. Proposed annotation:

```lmpl
@continue_site
state <- { ...state, messages: appended, turn_count: state.turn_count + 1, ... }
```

`@continue_site` would be a lint-level annotation meaning "this is the sole rebinding point for `state` in this scope." It helps readers and static checkers assert the invariant that partial updates don't exist.

### 8.3 `stop_reason` as a first-class terminal

Right now `until: state.transition.reason == "end_turn"` uses string equality. An `@terminal` marker on a transition variant would let tooling verify that *some* branch produces a terminal transition — a structural termination proof.

```lmpl
type Transition =
    | ...
    | @terminal {reason: "end_turn"}
```

### 8.4 Abort signals as ambient contracts

Threading `params.abort_controller` through every stage is noisy. An ambient `@abortable` annotation on `agent_loop` could inject the `not aborted(...)` precondition automatically at each stage boundary.

### 8.5 Bounded-recovery counters

Fields like `max_output_tokens_recovery_count` pair a counter with a cap and a bump operation. A `bounded_counter` type would express this pattern directly:

```lmpl
recovery: bounded_counter(cap: params.max_output_tokens_recovery_cap)
```

---

## 9. Future Specs (Roadmap)

Subsequent spec documents, in suggested order:

1. **Context management & compaction** — the 4-tier pipeline (reactive → microcompact → snip → autoCompact), `MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3` circuit breaker, opaque `compact_messages(...)` from this spec becomes concrete.
2. **Permission & guardrail layers** — 6 permission modes, `bashSecurity.ts` 5-layer validation, `yoloClassifier.ts` per-tool-call classifier, injection-flagging guardrails, `canUseTool()` interface. Refines the approval gates stubbed in §5.3.
3. **Tool catalog & execution** — full tool type system, concurrency partitioning algorithm, tool_use_context construction, result serialization contracts.
4. **Sub-agents & coordinator mode** — Task / InProcessTeammate / remote worker taxonomy, `model: 'inherit'` for cache alignment, `TEAMMATE_MESSAGES_UI_CAP` memory bounds, prompt-as-architecture pattern.
5. **Hook system** — `PreToolUse`, `PostToolUse`, `Stop`, `SessionStart` events; hook ordering vs. built-in validation.
6. **Memory tiers** — `memdir/` system, `CLAUDE.md` loading hierarchy (global → project → subdirectory), on-demand memory file retrieval.
7. **Prompt cache architecture** — `SYSTEM_PROMPT_DYNAMIC_BOUNDARY`, 14-vector break detection with sticky latches, static/dynamic section split.
8. **Streaming extension (if pursued)** — formal LMPL treatment of incremental model output per §8.1.

Each future spec should follow the same two-layer structure: an ideal LMPL expression plus a refined expansion grounded in source-level findings.

---

## 10. References

Source map leak published 2026-03-31 in `@anthropic-ai/claude-code@2.1.88` via `cli.js.map`. Analyses consulted:

- alejandrobalderas, *claude-code-from-source*, ch. 5 "Agent Loop" — https://github.com/alejandrobalderas/claude-code-from-source/blob/main/book/ch05-agent-loop.md
- 777genius, *claude-code-working*, `docs/conversation/the-loop.mdx` — https://github.com/777genius/claude-code-working
- bits-bytes-nn, "Claude Code Architecture Analysis" — https://bits-bytes-nn.github.io/insights/agentic-ai/2026/03/31/claude-code-architecture-analysis.html
- cablate, *claude-code-research* — https://github.com/cablate/claude-code-research
- l3tchupkt, "Claude Code CLI Runtime: Deep Reverse-Engineering Analysis" — https://github.com/l3tchupkt/claude-code
- Haseeb Qureshi, "Inside the Claude Code source" — https://gist.github.com/Haseeb-Qureshi/d0dc36844c19d26303ce09b42e7188c1
- Siddhant Khare, "The plumbing behind Claude Code" — https://siddhantkhare.com/writing/the-plumbing-behind-claude-code
- Blake Crosley, "What the Claude Code Source Leak Reveals" — https://blakecrosley.com/blog/claude-code-source-leak

No source code is reproduced in this document. All pseudocode is an independent LMPL expression of the documented control flow.
