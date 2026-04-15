# Design: Claude Code Prompt Cache Architecture in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md), [Tool Catalog](2026-04-15-claude-code-tool-catalog-design.md), [Memory Tiers](2026-04-15-claude-code-memory-tiers-design.md), [Sub-agents](2026-04-15-claude-code-subagents-design.md), [Compaction](2026-04-15-claude-code-compaction-design.md)
**Referenced by:** —

---

## 1. Scope & Non-Goals

The prompt cache is where Claude Code's economics are decided. This spec captures the **static/dynamic partition** enforced by the `SYSTEM_PROMPT_DYNAMIC_BOUNDARY` marker, the **14 known cache-break vectors** and their sticky-latch semantics, the **prefix byte-identity rules** that make caches hit, and how sub-agent forking (from the Sub-agents spec) is designed around byte-level cache alignment.

**In scope:**
- Cache partition model (static prefix / dynamic section) and the boundary marker
- Prefix ordering `tools → system → messages`
- Fourteen cache-break vectors (structural model + representative catalog)
- Sticky-latch semantics (once broken, stays broken for the session)
- Cache hit/miss byte-prefix matching; why tool ordering is stable
- Deferred tool loading as a deliberate cache trade-off
- Fork-based cache sharing for sub-agents
- Observability contract (`promptCacheBreakDetection.ts`-style telemetry)

**Out of scope:**
- The Anthropic API's cache-control wire semantics (that's the API contract, not Claude Code's internals)
- Cache pricing / billing specifics
- Hash algorithm internals (Blake2b is named; its implementation is not modeled)
- UI surfacing of cache hit rates
- Cross-*user* caching (not a feature; mentioned only to exclude)

---

## 2. Background

Every message Claude Code sends to the model is framed `tools → system → messages`. The API caches byte-identical prefixes across turns; as long as the prefix is stable, the provider returns a "cache hit" and the client pays roughly an order of magnitude less for that content. This makes cache stability a **first-class product concern**, and the leaked source shows it as such: the system prompt is split by a marker (`__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__`) into a **static half** that is shared across all users and sessions running the same version, and a **dynamic half** that holds per-session content (CLAUDE.md, MEMORY.md index, skills, MCP state). The client tracks **14 distinct cache-break vectors** through a module dedicated to cache-break detection, and each vector uses a **sticky latch** — once tripped in a session, it stays tripped. This matches an observed behavior: *sessions that start fast gradually slow down*. Sub-agents that want cache alignment with their parent must share the parent's system-prompt prefix byte-for-byte — this is why `model: 'inherit'` in the Sub-agents spec is load-bearing.

**Source grounding:** `src/constants/prompts.ts:114-115` (the boundary marker), `src/services/api/promptCacheBreakDetection.ts` (14 vectors with sticky latches), `forkSubagent.ts` (fork-based cache sharing via byte-prefix hash), `defer_loading` behavior on tool lists. See §13.

---

## 3. Types

### 3.1 Partition and scope

```lmpl
type CachePartition =
    | "static"         -- above the boundary; byte-stable across users
    | "dynamic"        -- below the boundary; per-session

type CacheScope =
    | "global"         -- cached across all users/sessions on the same client version
    | "session"        -- cached within a single session only
    | "uncached"       -- explicitly not cacheable

type CacheBoundary = {
    marker: string,                         -- "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__"
    position_in_system_prompt: int          -- byte offset; set at assembly time
}
```

### 3.2 Prefix composition

```lmpl
type PromptPrefix = {
    tools: list[ToolDefinition],            -- order matters; never sorted
    system_prompt: {
        static: string,                     -- above boundary
        boundary: CacheBoundary,
        dynamic: string                     -- below boundary
    },
    messages: list[Message]
}

-- The API's cache matches contiguously from the beginning of the serialized prefix.
-- A change anywhere in `tools` or in `system_prompt.static` invalidates everything.
```

### 3.3 Cache-break vectors

The 14 vectors are modeled as a tagged union plus a sticky-latch ledger. This spec enumerates them structurally; the exact list is the deliverable.

```lmpl
type CacheBreakVector =
    | "tool_list_mutated"              -- a tool added, removed, or reordered
    | "tool_schema_changed"            -- any ToolDefinition field edit
    | "mcp_server_registered"          -- new MCP server contributes tools
    | "mcp_server_disconnected"        -- connection drop removes tools
    | "skill_registered_mid_session"   -- skills section in static prompt changes
    | "plugin_activated_mid_session"   -- contributes tools/skills/etc.
    | "model_switched"                 -- per-session model override changes
    | "system_prompt_dynamic_section"  -- any edit to content below the boundary
    | "subdirectory_claude_md_loaded"  -- lazy load fires (first time only per dir)
    | "deferred_tool_loaded"           -- a tool that was defer_loading now materialized
    | "feature_flag_toggled"           -- feature gates affecting static content change
    | "user_type_switched"             -- internal ("ant") vs external prompt variants
    | "undercover_mode_toggled"        -- strips model names from the prompt
    | "manual_reset"                   -- user-initiated cache clear

-- Notes:
--   tool_list_mutated covers the vast majority of registry-side breaks; it's
--   listed separately from tool_schema_changed because the fix patterns differ
--   (stable registration order vs. schema immutability).
--   The 14 named vectors reflect the vectors the source's
--   promptCacheBreakDetection module tracks individually with sticky latches.
```

### 3.4 Sticky latch

```lmpl
type StickyLatch = {
    vector: CacheBreakVector,
    tripped: bool,
    tripped_at_turn: option[int],
    reason: option[string]
}

type CacheBreakLedger = {
    latches: map[CacheBreakVector, StickyLatch],
    total_breaks: int,
    first_break_turn: option[int]
}

-- Semantics: once latch.tripped == true, it never auto-resets within a session.
-- Reset requires a new session or an explicit manual reset.
invariant monotonic_sticky_latch(ledger, across_turns),
    "a tripped latch remains tripped for the remainder of the session"
```

---

## 4. Cache Architecture

### 4.1 Prefix ordering

The API expects and caches prefixes in this exact order:

```
1. tools                (JSON-serialized list of ToolDefinition)
2. system               (system prompt string, with the boundary marker inside)
3. messages             (conversation history as of this turn)
```

A change at any position invalidates everything after it. This is why the static half of the system prompt must come **before** the dynamic half — position matters.

```lmpl
invariant serialization_order_fixed,
    "serialized prefix is always tools → system → messages"
invariant dynamic_content_strictly_after_boundary,
    "every byte of dynamic content comes after the boundary marker in the serialized form"
```

### 4.2 The boundary marker

The marker is a literal string inserted into the system prompt at assembly time. Everything above it is built from code and constants (behavioral rules, stable tool descriptions, safety prompts); everything below is built from runtime state (CLAUDE.md, memory index, skills section, session flags).

```lmpl
define assemble_system_prompt(static_sections: list[string],
                             dynamic_sections: list[string]) -> string:
    return concat([
        ...static_sections,
        system_prompt_dynamic_boundary,
        ...dynamic_sections
    ])

    ensure contains(result, system_prompt_dynamic_boundary),
        "the boundary marker is always present"
    ensure all(static_sections, s -> index_of(s, result) < index_of(marker, result)),
        "static sections precede the marker"
```

### 4.3 Static half contents

- Identity and safety preamble (stable per client version)
- Core behavioral instructions (task execution, error handling, refusal patterns)
- Tool-use conventions (how to call tools, abort semantics)
- Fixed tool-descriptions block (for the builtin tools; MCP descriptions are dynamic)
- Copyright / cyber-risk / anti-injection clauses

These are byte-identical across users running the same client version, which is what enables the `"global"` scope cache hit.

### 4.4 Dynamic half contents

- CLAUDE.md content (global, project, subdirectory tiers — Memory Tiers spec §4)
- `MEMORY.md` auto-memory index (Memory Tiers spec §5.2)
- Skills section (Skills spec §8.1)
- MCP server status / resource summary
- Per-session flags (plan mode, pending tasks, etc.)

These change per session, per project, and per in-session event; they *will* break the cache, but they sit after the boundary so they only invalidate *themselves* downstream — not the static prefix above.

---

## 5. The 14 Cache-Break Vectors

Structural table. Each vector has a **trigger** (what event fires it), an **impact** (where in the prefix it breaks), and a **mitigation** (what the client does to minimize blast radius).

| # | Vector                            | Trigger                                    | Impact                  | Mitigation                                        |
|---|-----------------------------------|--------------------------------------------|-------------------------|---------------------------------------------------|
| 1 | `tool_list_mutated`               | Tool added / removed / reordered           | Invalidates from tools  | Stable registration order; defer-loading strategy |
| 2 | `tool_schema_changed`             | ToolDefinition field edited                | Invalidates from tools  | Treat schemas as append-only within a version     |
| 3 | `mcp_server_registered`           | MCP server connected mid-session           | Invalidates from tools  | Batch registrations at session start when possible|
| 4 | `mcp_server_disconnected`         | Connection drop                            | Invalidates from tools  | Retry connection before removing tools            |
| 5 | `skill_registered_mid_session`    | Plugin activation / skill install          | Invalidates from system static half | Prefer session-start activation                  |
| 6 | `plugin_activated_mid_session`    | Dynamic plugin activation                  | Invalidates from system static half | Warn user; present cost delta                    |
| 7 | `model_switched`                  | Per-session model override                 | Full invalidation       | Unavoidable; caller accepts cost                  |
| 8 | `system_prompt_dynamic_section`   | CLAUDE.md / MEMORY.md / skills changes     | Invalidates only the dynamic section | Cached prefix above boundary stays valid          |
| 9 | `subdirectory_claude_md_loaded`   | First file access under a subdir with CLAUDE.md | Invalidates dynamic section | Lazy but one-shot per directory                  |
| 10| `deferred_tool_loaded`            | A tool with `defer_loading: true` is materialized | Invalidates from tools | This is deliberate — see §7.3                    |
| 11| `feature_flag_toggled`            | Build-time or runtime flag affecting static prompt content | Full invalidation | Avoid toggling mid-session                       |
| 12| `user_type_switched`              | `USER_TYPE === 'ant'` transition           | Full invalidation       | Internal-only; should not occur in practice        |
| 13| `undercover_mode_toggled`         | Undercover mode on/off                     | Full invalidation       | Opt-in per session; rarely toggled                |
| 14| `manual_reset`                    | Explicit user action                       | Full invalidation       | Explicit acknowledgment                            |

The list reflects the cache-break detection module in the source, which treats each vector separately so its sticky latch and telemetry can be reasoned about independently.

---

## 6. Sticky Latches

### 6.1 Semantics

```lmpl
define trip_latch(ledger: CacheBreakLedger,
                 vector: CacheBreakVector,
                 reason: string,
                 turn: int) -> CacheBreakLedger:
    current <- ledger.latches[vector]
    if current.tripped: return ledger     -- already tripped; no-op

    new_latches <- update(ledger.latches, vector,
                          {vector: vector, tripped: true,
                           tripped_at_turn: some(turn), reason: some(reason)})

    return {
        ...ledger,
        latches: new_latches,
        total_breaks: ledger.total_breaks + 1,
        first_break_turn: ledger.first_break_turn otherwise some(turn)
    }

    invariant monotonic(ledger -> result),
        "a ledger update can only add breaks; it never untrips"
```

### 6.2 Why sticky?

A naive implementation might retry cache hits each turn, hoping the broken content reverts. Sticky latches are a cost-control choice: the break has already been reported to the API as a cache miss, and future prefixes containing the broken content will miss as long as the content differs. Continuously retrying and getting the same miss is pure waste. The latch codifies "stop trying; we know this won't hit."

A session that trips several latches early will pay a miss-cost on subsequent turns for those vectors, regardless of how many turns later. This explains the observed "sessions that start fast gradually slow down" pattern.

### 6.3 Reset conditions

```lmpl
define reset_ledger(ledger: CacheBreakLedger,
                   reason: "session_end" | "manual_reset" | "explicit_clear")
    -> CacheBreakLedger:
    return {latches: map_of_untripped_latches(),
            total_breaks: 0,
            first_break_turn: none}

    ensure all(result.latches, l -> not l.tripped),
        "after reset, all latches are untripped"
```

---

## 7. Cache Hit/Miss Accounting

### 7.1 Byte-prefix matching

The API caches by hashing the serialized prefix. As long as the byte sequence is identical to a previous request, the server can return the cached-path bill. The moment a byte changes, the cache misses from that byte to the end.

```lmpl
invariant cache_hit_requires_byte_identity,
    "cache hit requires identical byte prefix; not JSON-equivalent, not structurally-equivalent"
```

### 7.2 Stable tool order

Tools are **never sorted** at serialization time — sorting would produce a canonical order that differs from the registration order and invalidate caches for users who previously saw a different order. The source uses zero `.sort()` calls on the tool list for this reason.

```lmpl
invariant tool_list_order_preserved_across_turns,
    "the serialized tool list is in insertion order; never re-sorted"
```

This means tool registration is *architecturally* order-sensitive: a plugin that registers late will invalidate cached prefixes for users who previously had no such plugin. Plugin spec §7.1 addresses this by activating at session start when possible.

### 7.3 Deferred tool loading as a trade-off

Some tools declare `defer_loading: true`. They do not appear in the serialized tool list until first invoked. This is a **deliberate cache trade-off**: the tool's description is excluded from the cacheable prefix, preserving cache stability for sessions that never use the tool. When the tool *is* invoked for the first time, the cache breaks (vector #10) — but only then, and only if it's the specific vector that matters.

```lmpl
define defer_loading(def: ToolDefinition) -> bool:
    -- Authors opt in per tool; the client honors the flag at serialization.
    ...

invariant deferred_tool_absent_from_prefix_until_used(def, prefix),
    "a deferred tool is omitted from the cacheable prefix until it is first invoked"
```

### 7.4 Byte-prefix hashing

The client hashes serialized prefixes (Blake2b variants, per source comments) to detect drift locally — it can predict whether a request will hit before sending it, and the `promptCacheBreakDetection` module uses this to attribute a miss to a specific vector.

```lmpl
define prefix_hash(prefix: PromptPrefix, variant: "full" | "static_only") -> bytes:
    @boundary(inputs: PromptPrefix, outputs: bytes)
    -- Implementation: Blake2b over the canonical serialization.
    ...

    ensure hash_is_deterministic(prefix, variant),
        "same input yields the same hash"
```

---

## 8. Fork-Based Cache Sharing (Sub-agents)

A sub-agent spawned with `inherit_model: true` (Sub-agents spec §4.2) shares its parent's prompt cache if and only if its serialized prefix shares the parent's byte-level prefix exactly. The `cache_alignable` contract from the Sub-agents spec is refined here to its cache-layer meaning:

```lmpl
define cache_alignable_refined(parent_prefix: PromptPrefix,
                              child_prefix: PromptPrefix) -> bool:
    return prefix_hash(parent_prefix, variant: "static_only")
        == prefix_hash(child_prefix,  variant: "static_only")

    ensure result implies parent.tools == child.tools,
        "tools must match in order and content"
    ensure result implies
           parent.system_prompt.static == child.system_prompt.static,
        "static half of system prompt must be byte-identical"
```

Sub-agents that need different tools or a different static prompt cannot align. They still function — they just don't share the cache. The `forkSubagent` path exists to make byte-identity trivial to achieve when it is possible.

---

## 9. Integration With Other Specs

### 9.1 Memory Tiers

Memory Tiers spec §4.4 asserts "CLAUDE.md content is never placed above SYSTEM_PROMPT_DYNAMIC_BOUNDARY." This spec is the other side of that contract: placing it above would break cache globally for every user, for every session, every turn.

### 9.2 Compaction

Compaction spec §6 calls microcompact summaries "cache-friendly" via the `CACHED_MICROCOMPACT` flag. The mechanism is: summaries are inserted into the dynamic section, not the static prefix, and subsequent turns treat the summary as a stable content block — its bytes don't change between turns unless a further compaction rewrites it, so the portion of the dynamic section below it may still hit per-session cache.

### 9.3 MCP

MCP spec §4 covers server registration. Here, vector #3 formalizes the cache cost: registering an MCP server mid-session invalidates the tools portion. MCP spec §4.1 notes servers should batch at startup; this spec explains why.

### 9.4 Skills

Skills spec §8 places the skills section in the static part of the dynamic half of the system prompt (§4.4 of this spec). Activating a new skill mid-session trips vector #5. Skills spec §8.3 already cites the budget trade-off; this is the cache-level reason behind it.

### 9.5 Plugins

Plugin spec §7.2 prefers session-start activation over mid-session activation. Vectors #5 and #6 are why.

---

## 10. Observability

The source's `promptCacheBreakDetection` module emits one telemetry event per latch trip, tagging the cause and the turn number. The spec-level contract:

```lmpl
define emit_break_telemetry(vector: CacheBreakVector,
                           reason: string,
                           turn: int) -> unit:
    @boundary(inputs: {vector, reason, turn}, outputs: unit)

    record_event({
        kind: "prompt_cache_break",
        vector: vector,
        reason: reason,
        turn: turn,
        session_id: current_session_id()
    })

    ensure event_is_attributable(vector, reason),
        "every event includes a specific vector and a human-readable reason"
```

This data feeds dashboards that the source comments refer to — latch-trip counts correlate directly with per-session cost variance.

---

## 11. LMPL Gaps and Proposed Extensions

### 11.1 Byte-identity as a type property

Cache hits require byte identity of serialized values. LMPL types are structural; byte identity of serialization is a property of the serializer plus the types plus the order of fields. A `@byte_stable(serializer)` annotation would let specs assert that a value's serialization is stable across builds — converting cache-hit obligations from prose into a checkable property.

### 11.2 Append-only / position-stable collections

Tools must never be reordered. This is a specific case of a broader pattern: "collection whose serialization is sensitive to insertion order, and whose order must be preserved." LMPL's list[T] is order-preserving but has no annotation expressing "reordering this invalidates a downstream cache." A `@position_stable(consumer)` annotation on collection types would make the constraint visible.

### 11.3 Monotone state transitions

Sticky latches are monotone — they only flip from `false` to `true`. Several other specs have the same pattern (Guardrails' session ledger, Sub-agents' memory cap). A `monotone[T, direction]` wrapper would unify them and catch accidental resets at the type level.

### 11.4 Prefix-indexed hashes as first-class

`prefix_hash(prefix, variant)` computes a hash over a *prefix* of a serialized structure. LMPL can treat hashes as opaque bytes, but the relationship "this hash depends on exactly this prefix range" is prose. A `@hash_scope(range)` annotation on hash-returning functions would make the scope explicit.

### 11.5 Cost attribution for cache events

Every cache miss has a numeric cost delta. `emit_break_telemetry` records the event but not the cost; attributing cost back to the responsible vector is prose. An explicit `@cost_event(base: cached_price, actual: uncached_price)` annotation on the emit point would let cost dashboards be derived from spec-level intent rather than ad-hoc telemetry joins.

### 11.6 Build-time feature gate effects

Feature flags (vector #11) affect whether sections of the static prompt exist. LMPL has no construct for "this section appears only when flag X is set at build time." A `@build_gated(flag)` annotation on sections of an assembled artifact would document the gate and its cache implication.

---

## 12. Cross-Spec References

| Reference                                     | From               | To                                 |
|-----------------------------------------------|--------------------|------------------------------------|
| Dynamic section placement invariant           | §4, §9.1           | Memory Tiers §4.4, §7.3            |
| `cache_alignable` refined to byte identity    | §8                 | Sub-agents §4.2                    |
| Microcompact cache envelope                   | §9.2               | Compaction §6                      |
| MCP registration break vector                 | §9.3               | MCP §4.1                           |
| Skills section placement and activation cost  | §9.4               | Skills §8.1, §8.3                  |
| Plugin activation-at-session-start rationale  | §9.5               | Plugin ecosystem §7.2              |
| Tool list order preservation                  | §7.2               | Tool catalog §3.3 (`ToolRegistry`) |

---

## 13. References

- Siddhant Khare, "The plumbing behind Claude Code" — https://siddhantkhare.com/writing/the-plumbing-behind-claude-code (`SYSTEM_PROMPT_DYNAMIC_BOUNDARY` constant at `src/constants/prompts.ts:114-115`; `DANGEROUS_uncachedSystemPromptSection()`; `promptCacheBreakDetection.ts` observability)
- Blake Crosley, "What the Claude Code Source Leak Reveals" — https://blakecrosley.com/blog/claude-code-source-leak (14 cache-break vectors; sticky latches; "sessions start fast and slow down" observation)
- Haseeb Qureshi, "Inside the Claude Code source" — https://gist.github.com/Haseeb-Qureshi/d0dc36844c19d26303ce09b42e7188c1 (Blake2b prefix hash variants; `scope: 'global'`; ~3,000 tokens of cacheable prefix)
- Karan Prasad, "How Claude Code Actually Works" — https://www.karanprasad.com/blog/how-claude-code-actually-works-reverse-engineering-512k-lines (7 static / 13 dynamic sections assembly; deliberate cache-busting boundary after MCP)
- cablate, *claude-code-research* — https://github.com/cablate/claude-code-research (prompt cache architecture; tool serialization & cache stability; deferred-loading busts prefix)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented cache architecture.
