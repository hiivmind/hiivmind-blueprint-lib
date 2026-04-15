# Design: Claude Code Context Compaction in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md), [Sub-agents](2026-04-15-claude-code-subagents-design.md), [Hooks](2026-04-15-claude-code-hooks-design.md), [Memory Tiers](2026-04-15-claude-code-memory-tiers-design.md)
**Referenced by:** Prompt Cache (future)

---

## 1. Scope & Non-Goals

Claude Code keeps conversations running past the model's context window through a **four-tier compaction pipeline** — ordered light to heavy, decided per turn, guarded by circuit breakers. This spec captures the tier structure, the decision logic, the integration points (core loop, `spawn_subagent`, `PreCompact` hook), and the production scars (`MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3`) baked into the implementation.

**In scope:**
- Four tiers: reactive → microcompact → snip → autoCompact
- Per-turn decision pipeline and tier selection
- Threshold constants and single-shot latches
- `autoCompact`'s use of `spawn_subagent` to fork a summarization conversation
- Circuit breaker (`MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3`) and its production origin
- `PreCompact` hook integration (deferred here from Hooks §8.4)
- Recovery paths feeding back into the core loop's `reactive_compact_trigger` transition

**Out of scope:**
- Concrete summarization prompt wording — prompt engineering, not specification
- Specific threshold numbers beyond representative constants — they drift with model limits
- Client-side UI for surfacing compaction to the user
- Post-compaction re-priming of tool call state (considered here, but the detailed recovery of mid-flight tool calls is an implementation concern)

---

## 2. Background

When a session's message history approaches the model's context limit, Claude Code does not simply truncate. It runs a **pipeline of four compaction tiers**, ordered from cheap-and-local to expensive-and-destructive: `reactive` removes obviously-dead content; `microcompact` summarizes small clusters with minimal cache disruption; `snip` structurally truncates to a skeleton; `autoCompact` forks an entire Claude conversation to summarize the whole history and replace it with a condensed transcript. The selection logic is re-run every turn based on token accounting, and each tier has guardrails — reactive and snip are single-shot per window, autoCompact is hard-capped by a circuit breaker (`MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3`) added after an incident where 1,279 sessions hit 50+ consecutive compaction failures, burning ~250K API calls per day.

**Source grounding:** `src/services/compact/`, `autoCompact.ts`, the `REACTIVE_COMPACT` / `CACHED_MICROCOMPACT` / `HISTORY_SNIP` / `TOKEN_BUDGET` feature flags, the `MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3` constant and its source-comment history. See §14.

---

## 3. Types

### 3.1 Tier identifier

```lmpl
type CompactionTier =
    | "reactive"        -- tier 1; structural removal of dead content
    | "microcompact"    -- tier 2; localized summarization
    | "snip"            -- tier 3; structural truncation to skeleton
    | "auto"            -- tier 4; fork summarization subagent
```

### 3.2 Triggers

```lmpl
type CompactionTriggerReason =
    | "context_near_soft_limit"        -- crossed reactive threshold
    | "context_near_hard_limit"        -- must compact or fail
    | "explicit_user_request"          -- /compact slash command
    | "pre_turn_precheck"              -- proactive, before model call
    | "post_turn_spillover"            -- after a turn, discovered overflow

type CompactionTrigger = {
    reason: CompactionTriggerReason,
    token_count: int,
    soft_limit: int,
    hard_limit: int
}
```

### 3.3 Tracking and results

```lmpl
type AutoCompactTracking = {
    consecutive_failures: int,
    total_attempts: int,
    last_attempt_turn: int,
    breaker_tripped: bool              -- true once consecutive_failures >= cap
}

type CompactionResult = {
    tier: CompactionTier,
    status: "success" | "failed" | "blocked_by_breaker" | "blocked_by_hook",
    messages_before: int,
    messages_after: int,
    tokens_before: int,
    tokens_after: int,
    summary: option[string],           -- present for "auto"; absent for cheaper tiers
    error: option[string]
}
```

### 3.4 Constants (indicative)

```lmpl
define reactive_soft_ratio: float    <- 0.70     -- reactive kicks in at ~70% full
define microcompact_soft_ratio: float <- 0.80
define snip_soft_ratio: float         <- 0.90
define auto_hard_ratio: float         <- 0.95
define max_consecutive_autocompact_failures: int <- 3

-- The exact model-specific token limits live in configuration, not this spec.
```

---

## 4. The Decision Pipeline

### 4.1 Where it runs in the loop

Compaction check occurs at the start of each iteration of the core loop, inside the `observe` stage's `gather_turn_context` (Core Loop spec §5.1). Conceptually: *before* the model call — so the call sees a compacted history, not an overflowing one.

```lmpl
define maybe_compact(state: State, params: QueryParams) -> State:
    trigger <- evaluate_compaction_need(state, params)
    if trigger.none: return state

    tier <- select_tier(unwrap(trigger), state)

    -- PreCompact hook may block or override (§9).
    hook_decision <- run_precompact_hook(tier, state)
    match hook_decision:
        case "blocked":           return state_with_annotation(state, "compaction blocked by hook")
        case {override: new_tier}: tier <- new_tier
        case "allow":             skip

    result <- execute_tier(tier, state)
    return apply_compaction_result(state, result)
```

### 4.2 Tier selection

Selection is deterministic given the token counts and the state's per-tier latches:

```lmpl
define select_tier(trigger: CompactionTrigger, state: State) -> CompactionTier:
    ratio <- trigger.token_count / trigger.hard_limit

    if ratio < reactive_soft_ratio: raise NoCompactionNeeded

    if not state.has_attempted_reactive_compact and ratio < microcompact_soft_ratio:
        return "reactive"

    if ratio < snip_soft_ratio:
        return "microcompact"

    if ratio < auto_hard_ratio and not snip_attempted_this_window(state):
        return "snip"

    return "auto"

    ensure result in ["reactive", "microcompact", "snip", "auto"]
    invariant light_before_heavy(trigger, result),
        "the selected tier is the lightest applicable given the state's latches"
```

### 4.3 Single-shot latches

Reactive and snip are **single-shot per window** — a "window" being the span between two successful autocompacts. Repeating them is counterproductive: once you've removed dead content, removing it again does nothing. Microcompact and autoCompact can repeat across turns, each bounded by its own breaker.

```lmpl
invariant reactive_single_shot_per_window(state),
    "reactive compact does not re-execute until an autocompact resets the window"
invariant snip_single_shot_per_window(state),
    "snip does not re-execute until an autocompact resets the window"
```

---

## 5. Tier 1: Reactive

Structural removal. No LLM involvement. Removes message categories that are no longer load-bearing:

- Dead tool results whose tool_use block has been superseded
- Transient system notifications that referenced state no longer present
- Duplicate file-read results (when the same file was read twice, drop the older)

```lmpl
define tier_reactive(state: State) -> CompactionResult:
    before <- state.messages
    after  <- filter(before, m -> load_bearing(m, state))

    return {
        tier: "reactive",
        status: "success",
        messages_before: length(before),
        messages_after: length(after),
        tokens_before: token_count(before),
        tokens_after: token_count(after),
        summary: none,
        error: none
    }

    ensure result.messages_after <= result.messages_before,
        "reactive only removes, never adds"
    ensure preserves_tool_pairing(before, after),
        "a remaining tool_use still has its matching tool_result"
    ensure result.tier == "reactive"
```

**Cache impact:** removing trailing messages is cheap; the static cached prefix remains valid. Removing interior messages invalidates the cache at that point. The heuristic prefers tail removals when possible.

---

## 6. Tier 2: Microcompact

Localized summarization — a handful of messages replaced by a single synthesized summary message. Cache-friendly: summaries are tagged so the prompt cache can treat them as stable content across turns (`CACHED_MICROCOMPACT` feature flag).

```lmpl
define tier_microcompact(state: State) -> CompactionResult:
    clusters <- identify_summarizable_clusters(state.messages)
    if empty(clusters): return {tier: "microcompact", status: "success", ...(no_op)}

    -- Summarize each cluster with a lightweight model call (not a fork).
    summaries <- map(clusters, c -> summarize_cluster(c))

    new_messages <- replace_clusters_with_summaries(state.messages, clusters, summaries)

    return {
        tier: "microcompact",
        status: "success",
        messages_before: length(state.messages),
        messages_after: length(new_messages),
        tokens_before: token_count(state.messages),
        tokens_after: token_count(new_messages),
        summary: some(concat_summaries(summaries)),
        error: none
    }

    ensure result.tokens_after <= result.tokens_before,
        "microcompact must reduce token count"
    ensure preserved_semantic_continuity(state.messages, new_messages),
        "summaries preserve the meaning of their clusters for downstream reasoning"
```

Microcompact summaries are marked as such with a `{role: "system", meta: {compaction_source: "microcompact"}}` envelope so the model (and future compactions) can recognize them as already-condensed.

---

## 7. Tier 3: Snip

Structural truncation to a skeleton. Keep: the system prompt (always), the most recent N turns, every message containing a tool_use that is still "open," and any message tagged `@pinned`. Drop everything else as a block, with a single "<previous context snipped>" marker inserted.

```lmpl
define tier_snip(state: State) -> CompactionResult:
    kept <- [
        ...recent_turns(state.messages, n: snip_recent_turn_count),
        ...open_tool_use_messages(state.messages),
        ...pinned_messages(state.messages)
    ]
    deduplicated <- unique_by_order(kept, state.messages)
    marker <- snip_marker(dropped_count: length(state.messages) - length(deduplicated))

    new_messages <- insert_marker_at_boundary(deduplicated, marker)

    return {
        tier: "snip",
        status: "success",
        messages_before: length(state.messages),
        messages_after: length(new_messages),
        tokens_before: token_count(state.messages),
        tokens_after: token_count(new_messages),
        summary: none,
        error: none
    }

    ensure all(open_tool_use_messages(state.messages),
               m -> m in new_messages),
        "open tool_use messages are not snipped"
    ensure preserves_tool_pairing(new_messages, state.messages)
```

Snip is destructive and obvious; it is the last line before the fork.

---

## 8. Tier 4: AutoCompact (the heavy one)

### 8.1 Fork mechanism

AutoCompact calls `spawn_subagent` (Sub-agents spec §4.1) with a dedicated summarization prompt. The forked subagent reads the full history, produces a structured summary, and returns it as a `SubagentResult`. The parent replaces its message history with `[system_prompt, summary_message, ...recent_turns]`.

```lmpl
define tier_auto(state: State, parent_ctx: ToolInvocationContext)
    -> CompactionResult:

    -- Breaker check before forking.
    if state.auto_compact_tracking.consecutive_failures
            >= max_consecutive_autocompact_failures:
        return {tier: "auto", status: "blocked_by_breaker",
                messages_before: length(state.messages),
                messages_after: length(state.messages),
                tokens_before: token_count(state.messages),
                tokens_after: token_count(state.messages),
                summary: none,
                error: some("autocompact circuit breaker tripped")}

    spec <- {
        subagent_type: "general_purpose",
        description: "Summarize conversation",
        prompt: summarization_prompt(state.messages),
        max_iterations: 4,
        isolation: "task",
        inherit_model: true,         -- cache-align with parent
        inherit_tools: some([]),     -- summarization doesn't need tools
        timeout_ms: 120_000
    }

    attempt:
        sub_result <- spawn_subagent(spec, parent_ctx)
    on failure(err):
        return {tier: "auto", status: "failed",
                messages_before: length(state.messages),
                messages_after: length(state.messages),
                tokens_before: token_count(state.messages),
                tokens_after: token_count(state.messages),
                summary: none,
                error: some(describe(err))}

    summary_msg <- {role: "system",
                    content: sub_result.summary,
                    meta: {compaction_source: "auto"}}

    kept_recent <- recent_turns(state.messages, n: auto_recent_turn_count)
    new_messages <- concat([system_prompt_of(state), summary_msg, kept_recent])

    return {
        tier: "auto",
        status: "success",
        messages_before: length(state.messages),
        messages_after: length(new_messages),
        tokens_before: token_count(state.messages),
        tokens_after: token_count(new_messages),
        summary: some(sub_result.summary),
        error: none
    }
```

### 8.2 Circuit breaker

```lmpl
define update_autocompact_tracking(tracking: AutoCompactTracking,
                                  result: CompactionResult) -> AutoCompactTracking:
    match result.status:
        case "success":
            return {...tracking, consecutive_failures: 0,
                    total_attempts: tracking.total_attempts + 1,
                    last_attempt_turn: now_turn()}
        case "failed":
            new_consecutive <- tracking.consecutive_failures + 1
            return {...tracking,
                    consecutive_failures: new_consecutive,
                    total_attempts: tracking.total_attempts + 1,
                    last_attempt_turn: now_turn(),
                    breaker_tripped: new_consecutive
                                     >= max_consecutive_autocompact_failures}
        case "blocked_by_breaker":  return tracking
        case "blocked_by_hook":     return tracking

    invariant tracking.breaker_tripped implies
              tracking.consecutive_failures
              >= max_consecutive_autocompact_failures,
        "the breaker flag is consistent with the counter"
```

### 8.3 Production scar

The breaker exists because of a real incident:

> 1,279 sessions had 50+ consecutive autocompact failures (up to 3,272 in a single session), wasting ~250K API calls/day.

Before the breaker, a session stuck in a compaction loop would keep forking summarization subagents, each failing for the same reason, each consuming tokens on the way. The fix is blunt: three failures in a row and the tier is disabled for the rest of the session. The session degrades — subsequent turns must rely on snip or fail outright — but the client stops the hemorrhaging.

```lmpl
ensure when tracking.breaker_tripped:
    subsequent_compactions_use_tier in ["reactive", "microcompact", "snip"]
    or loop_terminates_with(context_exceeded_error),
    "once the breaker trips, autocompact is off-limits for the session"
```

---

## 9. `PreCompact` Hook Integration

The `PreCompact` hook (Hooks §8.4) fires before any tier executes. It can:

- **Block** — exit code 2; the selected compaction does not run, and the state is annotated.
- **Override strategy** — emit `{effect: "modify", path: "tier", value: "<other_tier>"}`; the client re-evaluates with the suggested tier.
- **Allow** — exit code 0; proceed.

```lmpl
type PreCompactDecision =
    | {kind: "allow"}
    | {kind: "blocked"}
    | {kind: "override", new_tier: CompactionTier}

define run_precompact_hook(tier: CompactionTier,
                          state: State) -> PreCompactDecision:
    payload <- {event: "PreCompact", planned_strategy: tier,
                token_count: token_count(state.messages)}
    results <- run_hooks_for_event({family: "session", event: "PreCompact"},
                                   payload, state.hooks_registry, current_ctx())

    if any(results, r -> interpret_exit_code(r.exit_code) == "block"):
        return {kind: "blocked"}

    override <- find_effect(results, kind: "modify", path: "tier")
    if override.some:
        require override.value in valid_tiers, "override must name a known tier"
        return {kind: "override", new_tier: override.value}

    return {kind: "allow"}

    ensure result.kind in ["allow", "blocked", "override"],
        "decision is one of the three recognized shapes"
```

An `override` from a hook does not bypass the breaker — a hook that names `"auto"` after the breaker has tripped still falls back to snip.

---

## 10. Recovery From Compaction Failure

When every tier is exhausted (or blocked), compaction reports failure. The core loop handles this as a `recover()` case — specifically the `context_near_limit` branch in the core-loop spec (§5.5 there), which produces a `{kind: "reactive_compact"}` action. At the next continue site, the loop records `transition: {reason: "reactive_compact_trigger"}` and retries — but now with the breaker in play, subsequent iterations select lighter tiers.

If even snip cannot bring the context under the hard limit, the loop raises `ContextExceeded` to be handled upstream — typically surfacing as a session-end error to the user.

```lmpl
invariant compaction_pipeline_eventually_reduces_or_fails(state),
    "the pipeline either shrinks the context or signals context_exceeded"
invariant tier_selection_monotone_toward_failure(tracking),
    "once a tier has been blocked, the selector does not revisit it this window"
```

---

## 11. Tier Contracts

Each tier satisfies a handful of shared contracts:

```lmpl
-- Every tier either succeeds or leaves state unchanged.
invariant for_every_tier:
    result.status == "success" implies result.messages_after < result.messages_before
    or result.tokens_after < result.tokens_before,
    "a successful compaction measurably shrinks either message count or tokens"

-- No tier may break an open tool_use → tool_result pair.
invariant for_every_tier:
    preserves_tool_pairing(before, after),
    "compaction does not orphan tool calls"

-- Ordering rule: lighter tiers are attempted first when eligible.
invariant selection_order: "reactive" < "microcompact" < "snip" < "auto",
    "the selector prefers the lightest applicable tier"

-- Idempotency: within a single turn, a tier's effect is idempotent once applied.
invariant idempotent_within_turn(tier, state),
    "running the same tier twice in the same turn produces the same result as once"
```

---

## 12. LMPL Gaps and Proposed Extensions

### 12.1 Pipelines of heterogeneous stages

The compaction pipeline, the Guardrails pipeline (§4.1 there), and the hook execution loop (§6.5 in Hooks) all have the same shape: ordered stages, short-circuit semantics, per-stage predicates. A `pipeline_of(stages)` construct with first-class short-circuit and monotonicity annotations would factor the pattern out of three specs.

### 12.2 Single-shot latches

`hasAttemptedReactiveCompact`, `snip_single_shot_per_window`, and similar booleans are the same pattern. A `@single_shot_per(window)` annotation on a latch field would formalize the semantics and make "reset-on-autocompact" automatic.

### 12.3 Circuit-breaker type

`auto_compact_tracking` is a specialized counter with a cap and a derived "tripped" bit. Same pattern appears in Guardrails (`session_block_count_consecutive` / `auto_mode_consecutive_block_cap`). A `circuit_breaker(cap)` type with `record_success` / `record_failure` / `is_tripped` would subsume both.

### 12.4 "Reduces-or-fails" termination contracts

`compaction_pipeline_eventually_reduces_or_fails` is a liveness contract — the pipeline must either make progress or terminate with a specific error. LMPL's `invariant` carries a safety flavor, not a liveness flavor. A `@liveness(eventual: condition)` annotation would let specs express "this loop can't spin forever."

### 12.5 Metadata-tagged messages

Compaction emits summary messages tagged `meta: {compaction_source: ...}`. Several other specs also add tags to messages. LMPL's `Message` type is open; a `@tagged_with(meta_schema)` refinement would make the tags type-checked.

### 12.6 Cost attribution for forked work

`tier_auto` spends tokens on a subagent. Accounting those tokens against the parent session is asserted via a postcondition on `spawn_subagent`, but cost *attribution* (how many tokens were "saved" vs. spent) is prose. A `@cost_account(to: principal)` annotation would let auditors verify cost claims structurally.

---

## 13. Cross-Spec References

| Reference                              | From                             | To                                 |
|----------------------------------------|----------------------------------|------------------------------------|
| `spawn_subagent` for autoCompact       | §8.1                             | Sub-agents §4.1                    |
| Loop `reactive_compact` transition     | §10                              | Core Loop §5.4, §5.5               |
| `auto_compact_tracking` field on State | §3.3                             | Core Loop §3.4                     |
| `PreCompact` hook integration          | §9                               | Hooks §8.4                         |
| Memory tiers compactability ranking    | §10 ("session first, global last") | Memory Tiers §9.4                  |
| Microcompact cache envelope            | §6 (`CACHED_MICROCOMPACT` flag)  | Prompt Cache (future)              |

---

## 14. References

- bits-bytes-nn, "Claude Code Architecture Analysis" — https://bits-bytes-nn.github.io/insights/agentic-ai/2026/03/31/claude-code-architecture-analysis.html (4-tier compaction pipeline; Context Collapse ordering; StreamingToolExecutor cost rationale)
- Redreamality, "Claude Code Leak: A Deep Dive into Anthropic's AI Coding Agent Architecture" — https://redreamality.com/blog/claude-code-source-leak-architecture-analysis/ (managed degradation pipeline; reactive → microcompact → snip → autoCompact ordering)
- Blake Crosley, "What the Claude Code Source Leak Reveals" — https://blakecrosley.com/blog/claude-code-source-leak (`MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3`; 1,279 sessions / 250K API calls/day production scar)
- Siddhant Khare, "The plumbing behind Claude Code" — https://siddhantkhare.com/writing/the-plumbing-behind-claude-code (compaction engine at `src/services/compact/`; feature flags `REACTIVE_COMPACT` / `CONTEXT_COLLAPSE` / `HISTORY_SNIP` / `CACHED_MICROCOMPACT` / `TOKEN_BUDGET`)
- alejandrobalderas, *claude-code-from-source* ch. 5 — https://github.com/alejandrobalderas/claude-code-from-source/blob/main/book/ch05-agent-loop.md (compaction inside the loop; circuit breaker rationale; light-before-heavy ordering)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented compaction pipeline.
