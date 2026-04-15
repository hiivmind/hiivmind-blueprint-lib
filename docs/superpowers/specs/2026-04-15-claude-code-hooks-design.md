# Design: Claude Code Hooks in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md), [Tool Catalog](2026-04-15-claude-code-tool-catalog-design.md), [Guardrails](2026-04-15-claude-code-guardrails-design.md), [Skills](2026-04-15-claude-code-skills-design.md)
**Referenced by:** Compaction (future), Plugin ecosystem (future)

---

## 1. Scope & Non-Goals

Hooks are user-authored shell commands that Claude Code invokes on lifecycle events: before a tool runs, after a user submits a prompt, when a session starts, and so on. This spec captures the complete hook system — event taxonomy, registration, execution semantics, effect model, and integration points with every other spec.

**In scope:**
- All three event families (tool lifecycle, conversation lifecycle, session lifecycle)
- `HookConfig` shape in `settings.json` and the registration model
- Payload serialization (JSON over stdin)
- Execution semantics: timeout, abort propagation, exit-code conventions
- Effect model: block, modify, annotate, no-op
- Matcher semantics
- Trust model: hooks are unsandboxed; trust derives from config source
- Integration points with Guardrails, Tool catalog, Core loop

**Out of scope:**
- Writing hook scripts (authoring guide, not spec)
- Plugin-bundled hook distribution — future Plugin spec
- Specific enterprise policy tooling
- Sandboxing hooks — not a feature; trust is location-based

---

## 2. Background

A **hook** is a shell command that Claude Code invokes at a named lifecycle event, passing a JSON payload on stdin and interpreting the exit code and stdout as directives. Hooks are configured in `settings.json` (user, project, or enterprise scope) and are keyed by event. Exit code `0` means allow/continue; exit code `2` means block; any other nonzero code is a hook error. Stdout can carry a structured JSON response that adds further effects — modify the inputs, append a message to the conversation, or emit telemetry. Hooks are **unsandboxed**: they run as ordinary shell commands with whatever privileges the Claude Code session has. The trust model is entirely about *where the config came from*: enterprise settings are trusted unconditionally, user settings are trusted because the user authored them, project settings prompt for confirmation on first encounter.

**Source grounding:** `settings.json` schemas for the `hooks` key; community analyses documenting the event taxonomy, exit-code semantics, and observed incidents (e.g., a SessionStart hook spawning 2 daemons). See §12.

---

## 3. Types

### 3.1 Event taxonomy

```lmpl
type HookEvent =
    | {family: "tool",         event: ToolHookEvent}
    | {family: "conversation", event: ConversationHookEvent}
    | {family: "session",      event: SessionHookEvent}

type ToolHookEvent =
    | "PreToolUse"
    | "PostToolUse"
    | "PermissionRequest"

type ConversationHookEvent =
    | "UserPromptSubmit"
    | "Stop"
    | "SubagentStop"

type SessionHookEvent =
    | "SessionStart"
    | "PreCompact"
    | "Notification"
```

### 3.2 Hook configuration

```lmpl
type HookMatcher =
    | {kind: "any"}
    | {kind: "tool_name", pattern: string}          -- glob / regex on tool name
    | {kind: "file_path", pattern: string}          -- glob on file args where applicable
    | {kind: "command_substring", needle: string}   -- for Bash calls

type HookConfig = {
    event: HookEvent,
    matcher: HookMatcher,
    command: string,                                -- shell command to execute
    timeout_ms: int,
    env: map[string, string],                       -- extra env vars
    cwd: option[string],
    origin: HookOrigin
}

type HookOrigin =
    | "enterprise"
    | "user"
    | {kind: "project", confirmed: bool}            -- first-encounter confirmation required
    | {kind: "plugin", plugin: string}
```

### 3.3 Registry

```lmpl
type HookRegistry = map[HookEvent, list[HookConfig]]

define register_hook(registry: HookRegistry, config: HookConfig) -> HookRegistry:
    require length(config.command) > 0, "command must be non-empty"
    require config.timeout_ms > 0, "timeout must be positive"
    return insert(registry, config.event, append(registry[config.event], config))

    ensure config in result[config.event], "registration is lossless"
```

### 3.4 Runtime records

```lmpl
type HookInvocation = {
    id: string,
    config: HookConfig,
    payload: HookPayload,
    started_at: timestamp,
    deadline: timestamp                     -- started_at + timeout_ms
}

type HookResult = {
    invocation_id: string,
    exit_code: int,
    stdout: string,
    stderr: string,
    duration_ms: int,
    parsed_effects: list[HookEffect]        -- see §7
}
```

---

## 4. Event Taxonomy Details

| Event                | Family       | Payload includes                                  | Allowed effects                             |
|----------------------|--------------|---------------------------------------------------|----------------------------------------------|
| `PreToolUse`         | tool         | tool_name, arguments, invocation_context          | block, modify (arguments), annotate          |
| `PostToolUse`        | tool         | tool_name, arguments, tool_result                 | annotate, telemetry                          |
| `PermissionRequest`  | tool         | tool_name, arguments, permission_mode             | override decision (allow / ask / deny)       |
| `UserPromptSubmit`   | conversation | user_message                                      | block, modify (message), annotate            |
| `Stop`               | conversation | final_message, reason                             | block (force continuation)                   |
| `SubagentStop`       | conversation | subagent_result                                   | annotate                                     |
| `SessionStart`       | session      | session_id, working_directory                     | annotate (inject context into system prompt) |
| `PreCompact`         | session      | reason, planned_strategy                          | block, modify (strategy override)            |
| `Notification`       | session      | kind, content                                     | no effect (telemetry only)                   |

**Payload shape per event family** is a tagged record type; the full `HookPayload` type is a union over all rows above. This spec asserts the shape contracts; it does not fix the field names of the wire format.

---

## 5. Registration & Discovery

### 5.1 Settings sources

```lmpl
define discover_hooks() -> HookRegistry:
    enterprise <- load_hooks_from(source: "enterprise")
    user       <- load_hooks_from(source: "user")
    project    <- load_hooks_from(source: "project")
    plugins    <- load_hooks_from(source: "plugin")

    confirmed_project <- filter(project, h -> project_confirmed(h))
    merged <- concat_all([enterprise, user, confirmed_project, plugins])
    return build_registry(merged)

    ensure all(result[event], h -> h.origin != {kind: "project", confirmed: false}),
        "unconfirmed project hooks are excluded from the active registry"
```

First-encounter project hooks surface a confirmation prompt before they ever run — the session cannot silently inherit shell commands from a repo.

### 5.2 Matcher semantics

```lmpl
define matches(config: HookConfig, payload: HookPayload) -> bool:
    match config.matcher:
        case {kind: "any"}:                   return true
        case {kind: "tool_name", pattern}:    return glob_match(pattern, payload.tool_name)
        case {kind: "file_path", pattern}:    return any_file_arg_matches(payload, pattern)
        case {kind: "command_substring", needle}:
            return payload.tool_name == "Bash"
               and contains(payload.arguments.command, needle)

    ensure result implies config.event == payload.event,
        "matcher cannot bridge events"
```

### 5.3 Precedence and merging

Hooks do **not** override each other by name — all matching hooks for an event run. Precedence matters only for *removal*: enterprise hooks cannot be disabled by lower-scope settings; user hooks cannot be disabled by project hooks; plugin hooks can be disabled by any higher scope.

---

## 6. Execution Semantics

### 6.1 Payload over stdin

Each hook receives its payload as a JSON document on stdin. Schema is event-specific; common fields (event name, session id, timestamps) are always present.

```lmpl
define invoke_hook(config: HookConfig, payload: HookPayload,
                  parent_ctx: ToolInvocationContext) -> HookResult:
    @boundary(
        inputs: {config: HookConfig, payload: HookPayload},
        outputs: HookResult
    )

    invocation <- {
        id: generate_id(),
        config: config,
        payload: payload,
        started_at: now(),
        deadline: now() + config.timeout_ms
    }

    serialized <- serialize_json(payload)
    process <- spawn_shell(config.command,
                           env: merged_env(config.env),
                           cwd: config.cwd otherwise parent_ctx.working_directory,
                           stdin: serialized)

    attempt:
        output <- wait_with_deadline(process, invocation.deadline)
    on timeout:
        kill(process)
        return timeout_result(invocation)
    on failure(err):
        return error_result(invocation, err)

    return {
        invocation_id: invocation.id,
        exit_code: output.exit_code,
        stdout: output.stdout,
        stderr: output.stderr,
        duration_ms: now() - invocation.started_at,
        parsed_effects: parse_hook_effects(output.stdout)
    }
```

### 6.2 Timeout and abort

```lmpl
invariant hook_completes_or_is_killed(invocation),
    "hooks cannot exceed their timeout; runaway hooks are terminated"

invariant aborted(parent_ctx.abort_controller) implies
          aborted(hook_ctx.abort_controller),
    "parent session abort propagates to live hook processes"
```

### 6.3 Exit-code conventions

```lmpl
type HookExitInterpretation =
    | "allow"        -- exit code 0 (or 0 + stdout effects)
    | "block"        -- exit code 2; stderr becomes the block reason
    | "error"        -- any other nonzero; treated as a hook failure

define interpret_exit_code(code: int) -> HookExitInterpretation:
    match code:
        case 0: return "allow"
        case 2: return "block"
        case _: return "error"

    -- Hook errors (non-0, non-2) do NOT block by default — they are logged.
    -- Only exit code 2 blocks. This is a deliberate fail-open for buggy hooks.
    ensure result != "block" when code != 2,
        "only exit 2 blocks; other failures log and continue"
```

### 6.4 Stdout as structured response

Optionally, a hook can emit a JSON object on stdout to declare additional effects:

```json
{"effect": "modify", "field": "arguments.command", "value": "echo safe"}
{"effect": "annotate", "role": "system", "content": "Hook observed PreToolUse for Bash"}
{"effect": "override_decision", "decision": "deny", "reason": "policy X"}
```

```lmpl
type HookEffect =
    | {kind: "modify", path: string, value: record}
    | {kind: "annotate", role: string, content: string}
    | {kind: "override_decision", decision: PermissionDecision, reason: string}
    | {kind: "telemetry", tag: string, data: record}

define parse_hook_effects(stdout: string) -> list[HookEffect]:
    ensure all(result, e -> e.kind in known_effect_kinds),
        "unknown effects are rejected at parse time"
```

### 6.5 Sequential vs parallel execution

All matching hooks for a single event run **sequentially** in registration order. This is deliberate: hooks may depend on earlier hooks' effects (e.g., an annotation from hook A may be consulted by hook B). Parallel execution would break that composition.

```lmpl
define run_hooks_for_event(event: HookEvent, payload: HookPayload,
                          registry: HookRegistry,
                          parent_ctx: ToolInvocationContext)
    -> list[HookResult]:

    matching <- filter(registry[event], h -> matches(h, payload))
    results <- []
    for config in matching:
        result <- invoke_hook(config, payload, parent_ctx)
        append(results, result)

        -- A block result short-circuits subsequent hooks for this event.
        if interpret_exit_code(result.exit_code) == "block": break

    return results
```

---

## 7. Effect Model

The effects in §6.4 map onto four capabilities the host grants to hooks. Not every event supports every effect — see the table in §4.

### 7.1 Block

Stops the event's flow. For `PreToolUse` the tool does not execute; for `UserPromptSubmit` the prompt is rejected; for `Stop` the loop is forced to continue.

```lmpl
define apply_block(event: HookEvent, result: HookResult, state: State) -> State:
    require interpret_exit_code(result.exit_code) == "block",
        "block only applies when exit code is 2"

    match event.event:
        case "PreToolUse":       return {...state, pending_tool_call: none,
                                         transition: {reason: "hook_blocked"}}
        case "UserPromptSubmit": return {...state, pending_user_message: none,
                                         annotations: append(state.annotations,
                                                             hook_block_notice(result))}
        case "Stop":             return {...state, transition: {reason: "hook_forced_continue"}}
        case _:                  raise InvalidBlockForEvent(event)
```

### 7.2 Modify

Mutates the event's subject (tool arguments, user message, etc.). Enforced via a field path in the effect payload.

```lmpl
define apply_modify(effect: HookEffect, subject: record) -> record:
    require effect.kind == "modify"
    return set_at_path(subject, effect.path, effect.value)

    ensure shape_preserved(result, subject),
        "modify cannot change the subject's type"
```

### 7.3 Annotate

Appends a message to the conversation. Often used by observer-style hooks that want the model to see "hook X fired, here's what I noticed."

```lmpl
define apply_annotate(effect: HookEffect, state: State) -> State:
    require effect.kind == "annotate"
    new_msg <- {role: effect.role, content: effect.content}
    return {...state, messages: append(state.messages, new_msg)}

    ensure length(result.messages) == length(state.messages) + 1,
        "exactly one message appended per annotate effect"
```

### 7.4 No-op / telemetry

`PostToolUse`, `Notification`, and most `SubagentStop` hooks are observer-only — they emit telemetry or external signals but do not alter state.

---

## 8. Integration With Other Specs

### 8.1 `PreToolUse` as a Guardrail layer

`PreToolUse` runs *after* the built-in guardrail pipeline (Guardrails §4.1) and can override its decision. It is the user-extensible layer on top of the safety baseline.

```lmpl
-- Guardrails §4.1 pipeline, extended:
base_decision <- can_use_tool(def, call, ctx, safety)
hook_results <- run_hooks_for_event(
    {family: "tool", event: "PreToolUse"},
    payload_from(def, call, ctx),
    registry, ctx
)

final_decision <- fold(hook_results, base_decision,
    (acc, result) -> apply_hook_decision_override(acc, result))

ensure monotone_toward_deny(base_decision, final_decision) when
       no_override_decision_effect(hook_results),
    "hooks can only tighten unless they emit an explicit override_decision effect"
```

`override_decision` is the escape hatch: a hook *can* loosen a baseline `deny` to `allow`, but only via an explicit, auditable effect — never by silently modifying inputs.

### 8.2 `PostToolUse`

Fires after each tool invocation with the result in the payload. Cannot block the invocation (it already happened) but can annotate the conversation.

### 8.3 `Stop` hook vs. core-loop `end_turn`

The loop reaches `transition: {reason: "end_turn"}` as usual; *before* the loop actually exits, the `Stop` hook runs. If it blocks, the loop rewinds to a new iteration with the hook's annotation appended — effectively forcing the model to do more work.

```lmpl
-- In the core loop, just before exiting on end_turn:
stop_results <- run_hooks_for_event(
    {family: "conversation", event: "Stop"},
    {final_message: state.last_assistant_message},
    registry, ctx
)

if any(stop_results, r -> interpret_exit_code(r.exit_code) == "block"):
    -- Rewind: the loop continues, hook annotation seeded in messages.
    state <- apply_all_effects(state, stop_results)
    state <- {...state, transition: {reason: "hook_forced_continue"}}
    -- Loop continues; end_turn is not reached this iteration.
```

This is why the core-loop spec §6 lists `end_turn` as terminal "in the absence of hook intervention" — hooks can *un-terminate* the loop, bounded by `max_iterations`.

### 8.4 `PreCompact` hook (forward reference)

Fires before the compaction pipeline runs. Can override the compaction strategy (`snip` → `auto_compact`, etc.) via a `modify` effect, or block it entirely. Fully defined in the future Compaction spec.

---

## 9. Security Considerations

Hooks execute arbitrary shell commands. The trust model:

- **Enterprise hooks** are fully trusted; organization has already vetted them.
- **User hooks** are trusted because the user authored their own settings.
- **Project hooks** require first-encounter confirmation; a cloned repo cannot silently install hooks.
- **Plugin hooks** inherit the plugin's trust level (see future Plugin spec) and can be disabled wholesale.

There is no built-in sandbox. A malicious hook can read files, exfiltrate data, spawn daemons — the same capabilities as any shell command the user could run. The community has documented incidents (notably a `SessionStart` hook that spawned two long-lived daemons before the first prompt ever rendered). This is acknowledged as an operational risk, not a spec-level defect.

```lmpl
invariant hook_trust_matches_origin_scope(config),
    "hook privileges derive from where the config was authored"
ensure project_hook_confirmed_before_first_run(config) when
       config.origin.kind == "project",
    "project-scoped hooks cannot run silently on clone"
```

---

## 10. LMPL Gaps and Proposed Extensions

### 10.1 External-process boundaries

`spawn_shell` crosses a trust boundary and returns unstructured text. LMPL's `@boundary` annotation captures inputs and outputs but not *exit code semantics as a separate effect channel*. A `@process_boundary(exit_code_semantics: ...)` annotation would make the channel explicit.

### 10.2 Exit-code-driven control flow as a construct

`interpret_exit_code(0|2|_)` is the same pattern recurring across every hook family. A `process_result` type with a pattern-matchable disposition — analogous to `ResolvedDecision` in Guardrails — would unify the pattern.

### 10.3 Fold over heterogeneous effects

Hook stdout returns a *list of effects of different kinds*. Applying them in order to a state is a `fold` with dynamic dispatch on effect `kind`. LMPL can model this as a `match` inside a `for`, but a `foldl_with_match` helper would be more idiomatic.

### 10.4 Event × allowed-effects matrix as a type

The table in §4 is checked in prose. Every `apply_*` function re-validates the event/effect combination at runtime. An `@allowed_on(events: [...])` annotation on each effect variant would let the type system statically reject `{kind: "block"}` paired with `PostToolUse`.

### 10.5 Un-terminating the loop

The `Stop` hook's ability to rewind a terminal transition is structurally interesting. §8.3 expresses it via a new transition reason (`hook_forced_continue`). A cleaner LMPL expression might treat the loop's `until` predicate as hook-aware natively, but that's a heavy change for a single-subsystem concern.

---

## 11. Cross-Spec References

| Reference                              | From                                 | To                                 |
|----------------------------------------|--------------------------------------|------------------------------------|
| `PreToolUse` on top of `can_use_tool`  | §8.1                                 | Guardrails §4.1                    |
| `PostToolUse` on tool results          | §8.2                                 | Tool catalog §5                    |
| `Stop` hook forcing re-iteration       | §8.3                                 | Core loop §6, §5.4 continue_site   |
| `PreCompact` override                  | §8.4                                 | Compaction (future)                |
| `SessionStart` daemon incident         | §9                                   | —                                  |
| Plugin-bundled hook distribution       | §3.2 (`origin: plugin`)              | Plugin ecosystem (future)          |
| MCP invocations traversing PreToolUse  | not special-cased                    | MCP §5.3                           |

---

## 12. References

- FlorianBruniaux, *claude-code-ultimate-guide* — https://github.com/FlorianBruniaux/claude-code-ultimate-guide (hook families, settings.json schema, security hooks as guardrails)
- Blake Crosley, "What the Claude Code Source Leak Reveals" — https://blakecrosley.com/blog/claude-code-source-leak (community incident with SessionStart hook spawning daemons; hooks stacking on top of the 23-check bash validation)
- Varonis Threat Labs, "A Look Inside Claude's Leaked AI Coding Agent" — https://www.varonis.com/blog/claude-code-leak (permission model layering, hooks as part of the permission surface)
- injekt, *claude-code-reverse* — https://github.com/injekt/claude-code-reverse (`PermissionRequest` event, hook events in the agentic loop)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented hook system.
