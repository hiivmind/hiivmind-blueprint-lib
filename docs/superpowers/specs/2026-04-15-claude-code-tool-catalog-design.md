# Design: Claude Code Tool Catalog & Execution in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md)
**Referenced by:** Guardrails (future), Sub-agents (future), Compaction (future)

---

## 1. Scope & Non-Goals

This spec captures the **tool interface, registry, and execution lifecycle** used by Claude Code, in the two-layer structure established by the core-loop spec. A representative subset of five canonical tools is modeled in full to show how the framework bites.

**In scope:**
- `Tool` interface contract (every tool implements the same shape)
- `ToolDefinition`, `ToolCall`, `ToolResult` refined from the core-loop spec
- `ToolRegistry` lookup and lifecycle
- Execution lifecycle: discover → validate → permission-check → partition → invoke → serialize
- Concurrency partitioning by category tag
- Five canonical tools: Read, Write, Bash, WebFetch, Task
- MCP tools as an extension point

**Out of scope** (other specs, or intentional omissions):
- Permission / guardrail mechanics — `canUseTool()` and approval gates are opaque here (see Guardrails spec)
- `bashSecurity.ts` 5-layer validation — acknowledged, not modeled (see Guardrails spec)
- Sub-agent fork mechanics inside `Task` — opaque here (see Sub-agents spec)
- MCP protocol itself — only the extension point and trust tagging, not the transport
- Exhaustive tool enumeration — 50+ builtins exist; only 5 are modeled

---

## 2. Background

A *tool* in Claude Code is a permission-gated capability the model can invoke by emitting a `tool_use` block in its response. Every tool — built-in or MCP-loaded — implements the same interface: a typed schema, a category tag that drives concurrency and permission decisions, and an `invoke()` body guarded by a `@boundary`. The execution layer discovers tools at startup, validates each `tool_use` against its schema, consults the permission system, partitions the calls in a turn by category (readonly tools run concurrently; mutating tools serialize), and serializes results back as `tool_result` blocks.

**Source grounding:** `src/Tool.ts` defines the interface; `src/tools/` contains the 40+ builtin implementations; MCP loading happens at registry bootstrap. See §10.

---

## 3. Types

### 3.1 Tool identity and invocation

```lmpl
type ToolName = string    -- globally unique within a registry

type ToolSource =
    | {kind: "builtin"}
    | {kind: "mcp", server: string}

type ToolCategory =
    | "readonly"              -- no side effects; safe to run concurrently
    | "mutating_filesystem"   -- writes to local filesystem
    | "mutating_world"        -- irreversible external effect (process spawn, network POST)
    | "external_read"         -- network read (idempotent but non-local)
    | "meta"                  -- dispatches sub-agents or manipulates the loop itself

type ToolDefinition = {
    name: ToolName,
    description: string,
    input_schema: JsonSchema,
    category: ToolCategory,
    source: ToolSource,
    requires_approval: bool,
    invoke: function(ToolCall, ToolInvocationContext) -> ToolResult
}
```

### 3.2 Invocation records

```lmpl
type ToolCall = {
    id: string,
    name: ToolName,
    arguments: record           -- must validate against the tool's input_schema
}

type ToolResult = {
    id: string,                 -- matches ToolCall.id
    status: "success" | "error" | "aborted" | "denied",
    content: string | list[ContentBlock],
    is_error: bool,
    provenance: record          -- tool name, duration, source, etc.
}
```

### 3.3 Registry

```lmpl
type ToolRegistry = map[ToolName, ToolDefinition]

define lookup(registry: ToolRegistry, name: ToolName) -> option[ToolDefinition]:
    ensure result.some implies result.value.name == name,
        "registry lookup is keyed by name"

define register(registry: ToolRegistry, def: ToolDefinition) -> ToolRegistry:
    require def.name not in registry, "tool names must be unique within a registry"
    require valid_schema(def.input_schema), "input_schema must be a valid JSON schema"
```

### 3.4 Invocation context

Ambient context threaded through every invocation — the LMPL expression of `tool_use_context` from the core-loop spec.

```lmpl
type ToolInvocationContext = {
    abort_controller: AbortController,
    working_directory: string,
    approval_callback: function(ToolCall) -> bool,
    permission_mode: string,        -- opaque; see Guardrails spec
    session_id: string,
    turn_count: int                 -- for telemetry / ordering
}
```

---

## 4. The Tool Interface Contract

Every tool — builtin or MCP — must satisfy this contract. Violations are authoring errors, not runtime errors.

```lmpl
define tool_contract(def: ToolDefinition) -> bool:
    ensure length(def.name) > 0,                       "name is non-empty"
    ensure length(def.description) > 0,                "description is non-empty"
    ensure valid_schema(def.input_schema),             "input_schema is valid JSON schema"
    ensure def.category in known_categories,           "category is a known tag"
    ensure def.requires_approval implies
           def.category in mutating_categories,        "approval only for mutating tools"
    ensure idempotent(def.invoke) when
           def.category == "readonly",                 "readonly tools must be idempotent"
```

`idempotent` is a meta-predicate — a documentation obligation on tool authors, not a runtime check.

---

## 5. Execution Lifecycle

One `tool_use` block from the model passes through six stages. The core-loop spec's §5.3 `act` stage is the call site; this section refines what happens inside it.

### 5.1 Stage sequence

```lmpl
define execute_tool_call(call: ToolCall,
                         registry: ToolRegistry,
                         ctx: ToolInvocationContext) -> ToolResult:

    -- 1. Discover
    def <- lookup(registry, call.name)
    require def.some, "tool must exist in the registry at invocation time"

    -- 2. Validate
    require validates_against(call.arguments, def.value.input_schema),
        "arguments must match the tool's input_schema"

    -- 3. Permission check (opaque; see Guardrails spec)
    permission <- can_use_tool(def.value, call, ctx)
    match permission:
        case "deny":   return denied_result(call)
        case "ask":
            approved <- ctx.approval_callback(call)
            require approved, "user denied tool invocation"
        case "allow":  skip

    -- 4. Abort checkpoint
    require not aborted(ctx.abort_controller), "abort preempts invocation"

    -- 5. Invoke
    attempt:
        result <- def.value.invoke(call, ctx)
    on failure(err):
        result <- error_result(call, err)

    -- 6. Serialize
    return annotate_provenance(result, def.value, ctx)
```

### 5.2 Concurrency partition

A single assistant reply may contain multiple `tool_use` blocks in one turn. They partition by category into a concurrent batch and a serial batch.

```lmpl
define partition_calls(calls: list[ToolCall], registry: ToolRegistry)
    -> {concurrent: list[ToolCall], serial: list[ToolCall]}:

    concurrent, serial <- [], []
    for call in calls:
        def <- unwrap(lookup(registry, call.name))
        match def.category:
            case "readonly":        append(concurrent, call)
            case "external_read":   append(concurrent, call)
            case _:                 append(serial, call)

    return {concurrent: concurrent, serial: serial}

define execute_turn_tool_calls(calls: list[ToolCall],
                               registry: ToolRegistry,
                               ctx: ToolInvocationContext) -> list[ToolResult]:

    partition <- partition_calls(calls, registry)

    concurrently:
        ro_results <- invoke_all(partition.concurrent, registry, ctx)
    join ro_results

    -- Mutating tools run in the order the model emitted them.
    serial_results <- []
    for call in partition.serial:
        result <- execute_tool_call(call, registry, ctx)
        append(serial_results, result)
        if result.status == "aborted": break

    -- Result order must match call order for correct pairing with tool_use blocks.
    return reorder_by_call_id(concat(ro_results, serial_results), calls)

    ensure length(result) == length(calls),
        "every tool_use must produce exactly one tool_result"
    ensure pairs_by_id(result, calls),
        "tool_result.id must match tool_use.id for each pair"
```

### 5.3 Approval gate integration

Approval is integrated at stage 3 of §5.1 but delegated to the guardrail layer. This spec asserts only the *contract* between loop and guardrail:

```lmpl
define can_use_tool(def: ToolDefinition,
                    call: ToolCall,
                    ctx: ToolInvocationContext) -> "allow" | "ask" | "deny":
    @boundary(
        inputs: {def: ToolDefinition, call: ToolCall, ctx: ToolInvocationContext},
        outputs: {"allow" | "ask" | "deny"}
    )
    -- Implementation lives in the Guardrails spec.
    -- Contract: must be a pure function of (def, call, ctx.permission_mode, session history).
```

---

## 6. Canonical Tools

Five tools modeled in full. Each shows how the framework expresses a specific capability.

### 6.1 Read — pure readonly file op

```lmpl
define tool Read:
    name: "Read"
    description: "Read a file from the local filesystem"
    category: "readonly"
    source: {kind: "builtin"}
    requires_approval: false

    input_schema: {
        path: string,
        offset?: int,
        limit?: int
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {path: string, offset?: int, limit?: int},
            outputs: {content: string, truncated: bool}
        )
        require is_absolute(call.arguments.path), "path must be absolute"
        require not aborted(ctx.abort_controller)

        ensure result.status != "error" implies exists(call.arguments.path),
            "success implies the file exists at invocation time"
```

### 6.2 Write — mutating file op

```lmpl
define tool Write:
    name: "Write"
    description: "Write content to a file on the local filesystem"
    category: "mutating_filesystem"
    source: {kind: "builtin"}
    requires_approval: true

    input_schema: {
        path: string,
        content: string
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {path: string, content: string},
            outputs: {bytes_written: int}
        )
        @requires_approval

        require is_absolute(call.arguments.path), "path must be absolute"
        require within_working_tree(call.arguments.path, ctx.working_directory),
            "writes constrained to working directory unless overridden"

        ensure result.status == "success" implies
               file_content(call.arguments.path) == call.arguments.content,
            "post-state reflects the requested content"
```

### 6.3 Bash — mutating, security-heavy

The Bash tool's security is substantial (`bashSecurity.ts` implements 5 layers of validation with 23 numbered checks). This spec treats that layer as **opaque**; it is the primary subject of the Guardrails spec.

```lmpl
define tool Bash:
    name: "Bash"
    description: "Execute a shell command"
    category: "mutating_world"
    source: {kind: "builtin"}
    requires_approval: true

    input_schema: {
        command: string,
        timeout_ms?: int,
        run_in_background?: bool
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {command: string, timeout_ms?: int, run_in_background?: bool},
            outputs: {stdout: string, stderr: string, exit_code: int}
        )
        @requires_approval

        -- Delegated to the Guardrails layer (see Guardrails spec).
        require bash_security_check(call.arguments.command) == "allow",
            "command must pass all security layers"
        require not aborted(ctx.abort_controller)

        ensure result.provenance.exit_code in [0..255], "exit code is a byte"
        ensure result.status == "aborted" when aborted(ctx.abort_controller),
            "abort mid-execution produces an aborted result, not a success"
```

### 6.4 WebFetch — external I/O

```lmpl
define tool WebFetch:
    name: "WebFetch"
    description: "Fetch a URL and return its content as clean text"
    category: "external_read"
    source: {kind: "builtin"}
    requires_approval: false

    input_schema: {
        url: string,
        prompt?: string
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {url: string, prompt?: string},
            outputs: {content: string, fetched_at: timestamp, final_url: string}
        )

        require starts_with(call.arguments.url, "https://") or
                starts_with(call.arguments.url, "http://"),
            "url must be http(s)"
        require not in_blocklist(call.arguments.url), "url must not be blocklisted"

        attempt:
            content <- fetch(call.arguments.url, timeout: default_timeout)
            return success_result(content)
        on failure(err):
            match err.kind:
                case "timeout":    return error_result(call, "fetch timed out")
                case "network":    return error_result(call, "network error")
                case "http_error": return error_result(call, "http error: " + err.status)
                case _:            propagate err

        ensure result.status == "success" implies
               length(result.content) <= max_fetch_bytes,
            "fetched content is bounded"
```

### 6.5 Task — sub-agent dispatch

`Task` is a *meta* tool: it dispatches a sub-agent that runs its own query loop (the spec #0 `query` function, recursively). The fork mechanics — how a new `State` is seeded, how memory is scoped, whether the sub-agent shares the prompt cache — live in the Sub-agents spec. This spec captures only the interface.

```lmpl
define tool Task:
    name: "Task"
    description: "Dispatch a sub-agent to perform a bounded task"
    category: "meta"
    source: {kind: "builtin"}
    requires_approval: false

    input_schema: {
        description: string,         -- 3-5 word summary for the UI
        prompt: string,              -- the sub-agent's task
        subagent_type?: string       -- "general-purpose" by default
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {description: string, prompt: string, subagent_type?: string},
            outputs: {summary: string, artifacts?: list[record]}
        )

        require length(call.arguments.prompt) > 0, "sub-agent prompt must be non-empty"
        require call.arguments.subagent_type in known_subagent_types or
                not some(call.arguments.subagent_type),
            "subagent_type must be known when supplied"

        -- Opaque: the Sub-agents spec defines spawn_subagent and the isolation model.
        sub_result <- spawn_subagent(call.arguments, ctx)

        ensure sub_result.turn_count <= max_subagent_iterations,
            "sub-agents must terminate within their own iteration budget"
        ensure not leaks_parent_state(sub_result),
            "sub-agent results must not echo the parent's private state"

        return success_result(sub_result.summary)
```

---

## 7. MCP Tools as an Extension Point

MCP (Model Context Protocol) lets external servers register tools at runtime. The framework expresses MCP as a `ToolSource` variant; the protocol itself is not modeled here.

```lmpl
define register_mcp_tool(registry: ToolRegistry,
                        server: string,
                        remote_def: McpToolDefinition) -> ToolRegistry:
    -- MCP tools default to the most restrictive category unless the
    -- server explicitly declares otherwise; MCP tools are not trusted
    -- for concurrency grouping without a declaration.
    category <- remote_def.declared_category otherwise "mutating_world"

    local_def <- {
        name: namespaced_name(server, remote_def.name),    -- "mcp__<server>__<tool>"
        description: remote_def.description,
        input_schema: remote_def.input_schema,
        category: category,
        source: {kind: "mcp", server: server},
        requires_approval: category in mutating_categories,
        invoke: mcp_proxy_invoke(server, remote_def.name)
    }

    return register(registry, local_def)

    require tool_contract(local_def), "MCP tool must satisfy the Tool contract"
```

**Trust note:** MCP tools are less trusted than builtins. The concurrency partition treats an MCP tool as mutating unless the MCP server asserts otherwise, and the guardrail layer may apply stricter defaults (detailed in the Guardrails spec).

---

## 8. LMPL Gaps and Proposed Extensions

### 8.1 JSON schema as a first-class type

The `input_schema: JsonSchema` field presumes a schema system LMPL doesn't define. Options:

- **Punt** — treat `JsonSchema` as a domain primitive with a `validates_against` predicate.
- **Borrow** — adopt JSON Schema as the canonical schema language for tool inputs.
- **Derive** — let LMPL type declarations *be* the schema, compile-time.

**Recommendation:** Derive. `define tool Read: input_schema: {path: string, offset?: int, limit?: int}` is already a record type in LMPL; making it the single source of truth eliminates a parallel schema language.

### 8.2 Category-driven concurrency

`partition_calls` dispatches on `ToolCategory`. A `@concurrency_class(cat)` annotation on tool definitions would let the planner reason about partitioning without the runtime tag lookup:

```lmpl
@concurrency_class("readonly")
define tool Read: ...
```

Tooling could then warn if a `@concurrency_class("readonly")` tool's `invoke` body contains a mutating call.

### 8.3 Result-to-call pairing

`pairs_by_id` is a cross-list invariant that's awkward to state locally. A `@paired_by(id)` annotation on a pair of lists would make this structural:

```lmpl
ensure @paired_by(id) results with calls
```

### 8.4 Approval as an effect

`@requires_approval` is declared on a tool but applied at execution time via a callback threaded through `ctx`. Treating approval as an ambient *effect* (like exceptions) rather than an annotation-plus-callback would make it harder to accidentally bypass.

### 8.5 Tool authoring as a typeclass

All tools share a shape; LMPL has no "trait/typeclass" to express "this record type must implement `invoke`." Currently we assert the contract as a predicate (`tool_contract`), which is fine for specs but redundant for authors. Worth considering for a v2.

---

## 9. Cross-Spec References

| Reference                                   | From                             | To (future spec)       |
|---------------------------------------------|----------------------------------|------------------------|
| `can_use_tool` — permission dispatch        | §5.1 stage 3, §5.3               | Guardrails (#2)        |
| `bash_security_check` — 5-layer validation  | §6.3                             | Guardrails (#2)        |
| `spawn_subagent` — fork mechanics           | §6.5                             | Sub-agents (#4)        |
| Tool invocation from the loop's `act` stage | core-loop spec §5.3              | Core loop (#0, written)|

The core loop spec calls `execute_turn_tool_calls` from its `act` stage; this spec refines what happens inside. The Guardrails spec will refine `can_use_tool` and `bash_security_check`. The Sub-agents spec will refine `spawn_subagent`.

---

## 10. References

- `src/Tool.ts` — interface definition (referenced in analyses; not reproduced)
- Siddhant Khare, "The plumbing behind Claude Code" — https://siddhantkhare.com/writing/the-plumbing-behind-claude-code (40+ tools, concurrency partition)
- Justin Henderson, "The Recon Module Came to Life" — https://darkdossier.substack.com/p/the-recon-module-came-to-life-what (tool taxonomy, bashSecurity structure)
- Varonis Threat Labs, "A Look Inside Claude's Leaked AI Coding Agent" — https://www.varonis.com/blog/claude-code-leak (50+ agent tool execution flow)
- bits-bytes-nn, "Claude Code Architecture Analysis" — https://bits-bytes-nn.github.io/insights/agentic-ai/2026/03/31/claude-code-architecture-analysis.html (StreamingToolExecutor, concurrency)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented interface and lifecycle.
