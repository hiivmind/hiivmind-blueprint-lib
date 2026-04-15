# Design: Claude Code MCP (Model Context Protocol) in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md), [Tool Catalog](2026-04-15-claude-code-tool-catalog-design.md), [Guardrails](2026-04-15-claude-code-guardrails-design.md)
**Referenced by:** Skills (future), Hooks (future)

---

## 1. Scope & Non-Goals

This spec captures **how Claude Code consumes MCP servers**: discovery, handshake, the three offerings (tools, resources, prompts), trust model, and failure handling — expressed in LMPL.

**In scope:**
- Four transport variants: `stdio`, `sse`, `http`, `websocket`
- Server lifecycle: discovery → handshake → capabilities negotiation → registration → shutdown
- Tools offering and its mapping to `ToolDefinition` (Tool catalog §3.1)
- Resources offering and the two meta-tools that surface it (`ListMcpResourcesTool`, `ReadMcpResourceTool`)
- Prompts offering as user-invocable templates expanded into message sequences
- Namespacing convention (`mcp__<server>__<name>`)
- Cross-offering trust model and approval defaults
- Transport failure modes and their mapping to the loop's recovery paths

**Out of scope:**
- The MCP wire protocol itself (JSON-RPC framing, method names, exact request/response shapes) — documented by the protocol spec, not here
- MCP *server* authoring (this spec is client-side only)
- Authentication / credential stores for remote MCP servers (operational, not protocol)
- Specific real-world MCP servers — patterns shown, catalog deferred
- Slash-command dispatch mechanics beyond the MCP → slash-command mapping (deferred to Skills spec)

---

## 2. Background

MCP (Model Context Protocol) is an open protocol that lets external processes expose three kinds of capabilities to an LLM client: **tools** (invokable functions), **resources** (readable content), and **prompts** (parameterized templates). Claude Code is an MCP *client* — at startup it discovers configured MCP servers from project, user, and enterprise config sources, performs a handshake that negotiates which offerings each server provides, and registers the offerings into three parallel registries (tool, resource, prompt). At runtime it proxies tool invocations to the originating server, surfaces resources via meta-tools, and expands prompts into conversation messages when users invoke them as slash commands. MCP offerings are **lower-trust than builtins**: the concurrency partitioner treats them as mutating by default, and the guardrail layer applies stricter approval defaults.

**Source grounding:** `bridge/mcp/*`, `register_mcp_tool`, `ListMcpResourcesTool` / `ReadMcpResourceTool`, `.mcp.json` / user settings MCP config loading. See §12.

---

## 3. Types

### 3.1 Transport

```lmpl
type McpTransport =
    | {kind: "stdio", command: string, args: list[string], env: map[string, string]}
    | {kind: "sse", url: string, headers: map[string, string]}
    | {kind: "http", url: string, headers: map[string, string]}
    | {kind: "websocket", url: string, headers: map[string, string]}
```

### 3.2 Server configuration

```lmpl
type McpConfigSource =
    | "enterprise"     -- policy-managed; overrides user/project
    | "user"           -- ~/.claude.json or similar
    | "project"        -- .mcp.json at repo root
    | "ephemeral"      -- CLI flag for a single session

type McpServerSpec = {
    name: string,                       -- unique within the client
    transport: McpTransport,
    enabled: bool,
    source: McpConfigSource,
    trust_declaration: option[McpTrustDeclaration],    -- §8
    timeout_ms: int
}
```

### 3.3 Capabilities negotiation

```lmpl
type McpCapabilities = {
    tools: bool,                -- server serves tool offerings
    resources: bool,            -- server serves resource offerings
    prompts: bool,              -- server serves prompt offerings
    subscriptions: bool,        -- resources support change notifications (§6.3)
    logging: bool               -- server can emit structured logs to the client
}
```

### 3.4 Offerings

```lmpl
type McpOfferingKind = "tool" | "resource" | "prompt"

type McpOffering = {
    kind: McpOfferingKind,
    server: string,
    name: string,               -- raw name as served; not yet namespaced
    payload: McpToolDefinition | McpResource | McpPrompt
}
```

### 3.5 Namespacing

Every offering gets a namespaced client-local identifier: `mcp__<server>__<name>`. This prevents collisions between servers and makes source provenance visible in every identifier.

```lmpl
define namespaced_name(server: string, offering_name: string) -> string:
    require valid_identifier(server), "server name must be a valid identifier"
    require valid_identifier(offering_name), "offering name must be a valid identifier"
    return "mcp__" + server + "__" + offering_name

    ensure starts_with(result, "mcp__"), "MCP identifiers are always prefixed"
    ensure unique_within(result, client_registries), "namespacing guarantees uniqueness"
```

---

## 4. Server Lifecycle

### 4.1 Discovery

Config sources are merged with precedence `enterprise > user > project > ephemeral`. Enterprise disables override (a policy-blocked server cannot be re-enabled by user or project config).

```lmpl
define discover_mcp_servers() -> list[McpServerSpec]:
    enterprise <- load_mcp_config(source: "enterprise")
    user       <- load_mcp_config(source: "user")
    project    <- load_mcp_config(source: "project")
    ephemeral  <- load_mcp_config(source: "ephemeral")

    merged <- merge_with_precedence([enterprise, user, project, ephemeral])
    return filter(merged, spec -> spec.enabled)

    ensure no_duplicates_by(result, name), "server names are unique across sources"
    ensure enterprise_policy_respected(result, enterprise),
        "enterprise disables cannot be re-enabled by lower-precedence sources"
```

### 4.2 Handshake & capabilities negotiation

```lmpl
define connect_mcp_server(spec: McpServerSpec) -> McpConnection:
    @boundary(inputs: McpServerSpec, outputs: McpConnection)

    require spec.enabled
    transport <- open_transport(spec.transport)

    attempt:
        capabilities <- handshake(transport, client_capabilities())
    on failure(err):
        return failed_connection(spec, err)

    return {
        spec: spec,
        transport: transport,
        capabilities: capabilities,
        status: "ready",
        last_activity: now()
    }

    ensure result.status in ["ready", "failed"]
    ensure result.status == "ready" implies
           consistent_caps(result.capabilities, server_declared_caps),
        "client caps must be a subset of what the server offers"
```

### 4.3 Registration

Once connected, the client enumerates each offering kind the server supports and inserts them into the matching registry.

```lmpl
define register_mcp_offerings(conn: McpConnection,
                             tool_registry: ToolRegistry,
                             resource_registry: ResourceRegistry,
                             prompt_registry: PromptRegistry)
    -> {tools: ToolRegistry, resources: ResourceRegistry, prompts: PromptRegistry}:

    if conn.capabilities.tools:
        tool_defs <- list_tools(conn)
        for def in tool_defs:
            tool_registry <- register_mcp_tool(tool_registry, conn.spec.name, def)

    if conn.capabilities.resources:
        resources <- list_resources(conn)
        for r in resources:
            resource_registry <- register_mcp_resource(resource_registry,
                                                       conn.spec.name, r)

    if conn.capabilities.prompts:
        prompts <- list_prompts(conn)
        for p in prompts:
            prompt_registry <- register_mcp_prompt(prompt_registry,
                                                   conn.spec.name, p)

    return {tools: tool_registry, resources: resource_registry,
            prompts: prompt_registry}
```

### 4.4 Keepalive, shutdown, failure

```lmpl
invariant connection_alive(conn) implies recent_activity(conn, within: timeout_ms),
    "a 'ready' connection must have observed recent activity"

define shutdown_mcp_server(conn: McpConnection) -> unit:
    notify_server(conn, "shutdown")
    close_transport(conn.transport)

    ensure transport_closed(conn.transport)
    ensure offerings_deregistered(conn.spec.name),
        "all offerings from this server are removed from every registry"

define handle_connection_failure(conn: McpConnection, err: error) -> FailurePolicy:
    match conn.spec.source:
        case "enterprise":   return "retry_forever"
        case "user":         return "retry_with_backoff"
        case "project":      return "retry_with_backoff"
        case "ephemeral":    return "fail_and_disable"
```

---

## 5. Tools Offering

### 5.1 Type mapping

An MCP tool becomes a `ToolDefinition` (Tool catalog §3.1) via a lossless mapping, with trust-adjusted defaults where the MCP server did not declare.

```lmpl
type McpToolDefinition = {
    name: string,
    description: string,
    input_schema: JsonSchema,
    declared_category: option[ToolCategory],       -- §8 trust declaration
    declared_requires_approval: option[bool]
}
```

### 5.2 `register_mcp_tool` (refined from Tool catalog §7)

```lmpl
define register_mcp_tool(registry: ToolRegistry,
                        server: string,
                        remote_def: McpToolDefinition) -> ToolRegistry:

    category <- remote_def.declared_category otherwise default_mcp_category()
    requires_approval <- remote_def.declared_requires_approval
                        otherwise (category in mutating_categories)

    local_def <- {
        name: namespaced_name(server, remote_def.name),
        description: remote_def.description,
        input_schema: remote_def.input_schema,
        category: category,
        source: {kind: "mcp", server: server},
        requires_approval: requires_approval,
        invoke: mcp_proxy_invoke(server, remote_def.name)
    }

    return register(registry, local_def)

    require tool_contract(local_def), "MCP tool must satisfy the Tool contract"
    ensure local_def.source.kind == "mcp", "MCP tools are tagged in their source"
    ensure trust_downgraded_if_undeclared(local_def, remote_def),
        "undeclared categories default to the most restrictive"
```

### 5.3 Proxy invocation

```lmpl
define mcp_proxy_invoke(server: string, remote_name: string)
    -> function(ToolCall, ToolInvocationContext) -> ToolResult:
    return fun(call, ctx) ->
        attempt:
            conn <- current_connection(server)
            require conn.status == "ready", "MCP server must be connected"

            raw <- rpc_call(conn, method: "tools/call",
                           params: {name: remote_name, arguments: call.arguments},
                           timeout: conn.spec.timeout_ms)

            return sanitize_and_wrap(raw, call.id, source: {kind: "mcp", server: server})
        on failure(err):
            return map_transport_error(err, call.id)

    ensure result.provenance.source.kind == "mcp",
        "MCP-sourced results are tagged as such for guardrail context"
```

### 5.4 Trust defaults

`default_mcp_category()` returns the **most restrictive** category available — `"mutating_world"`. Servers that want concurrency or lighter approval must *declare* their tools' categories explicitly:

```lmpl
define default_mcp_category() -> ToolCategory:
    return "mutating_world"

    ensure result in mutating_categories,
        "undeclared MCP tools default to mutating (fail-closed)"
```

See §8 for the trust-declaration mechanism.

---

## 6. Resources Offering

### 6.1 Type

```lmpl
type McpResource = {
    uri: string,                    -- e.g., "file:///...", "db://...", custom schemes
    name: string,
    description: option[string],
    mime_type: option[string]
}

type ResourceRegistry = map[string, McpResource]   -- keyed by namespaced URI

define namespaced_uri(server: string, uri: string) -> string:
    return "mcp://" + server + "/" + uri
```

### 6.2 Meta-tools that surface resources

Resources are surfaced to the model **as tools** — two meta-tools let the model enumerate and read them.

```lmpl
define tool ListMcpResourcesTool:
    name: "ListMcpResourcesTool"
    description: "List MCP-exposed resources across all connected servers"
    category: "readonly"
    source: {kind: "builtin"}
    requires_approval: false

    input_schema: {
        server?: string             -- filter to a single server
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {server?: string},
            outputs: list[{uri: string, name: string, description?: string}]
        )
        resources <- all_mcp_resources(filter: call.arguments.server)
        return success_result(resources)

define tool ReadMcpResourceTool:
    name: "ReadMcpResourceTool"
    description: "Read the content of an MCP-exposed resource"
    category: "external_read"
    source: {kind: "builtin"}
    requires_approval: false

    input_schema: {
        uri: string                 -- namespaced URI from ListMcpResourcesTool
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {uri: string},
            outputs: {content: string | list[ContentBlock], mime_type?: string}
        )
        require starts_with(call.arguments.uri, "mcp://"),
            "URI must be a namespaced MCP resource URI"

        server <- extract_server_from_uri(call.arguments.uri)
        raw <- rpc_call(current_connection(server),
                       method: "resources/read",
                       params: {uri: call.arguments.uri},
                       timeout: default_timeout)

        return sanitize_and_wrap(raw, call.id,
                                 source: {kind: "mcp", server: server})
```

### 6.3 Subscriptions (when `capabilities.subscriptions == true`)

Resources may emit change notifications. The client exposes these as in-conversation system-reminder messages, not as a user-facing event.

```lmpl
define subscribe_resource(conn: McpConnection, uri: string) -> unit:
    require conn.capabilities.subscriptions,
        "server must declare subscription capability"

    rpc_call(conn, method: "resources/subscribe", params: {uri: uri})

    ensure pending_notifications(conn) includes future changes for uri,
        "subscription is registered on the server side"

define handle_resource_notification(notification: McpNotification) -> Message:
    -- Surfaces as a system-reminder in the next turn's context.
    return {role: "system", content: "Resource updated: " + notification.uri}
```

### 6.4 Trust and sanitization on read

Every `resources/read` response crosses the same untrusted boundary as tool outputs:

```lmpl
require sanitize_content(raw.content),
    "resource content is sanitized before delivery to the model"

ensure injection_flagged_when_suspected(result, to: user),
    "resource content carries the same injection-flagging contract as tool output"
```

---

## 7. Prompts Offering

### 7.1 Type

An MCP prompt is a parameterized template that expands into a sequence of messages.

```lmpl
type McpPromptArgument = {
    name: string,
    description: option[string],
    required: bool
}

type McpPrompt = {
    name: string,
    description: option[string],
    arguments: list[McpPromptArgument]
}

type PromptRegistry = map[string, McpPrompt]   -- keyed by namespaced name
```

### 7.2 Surfacing as slash commands

Prompts are user-invocable. The client registers each as a slash command under the namespaced name.

```lmpl
define register_mcp_prompt(registry: PromptRegistry,
                          server: string,
                          prompt: McpPrompt) -> PromptRegistry:
    local_name <- namespaced_name(server, prompt.name)
    return insert(registry, local_name, prompt)

    ensure local_name starts_with "mcp__", "prompts share the MCP namespacing"
    ensure slash_command_registered(local_name),
        "every registered MCP prompt is invocable as /<local_name>"
```

### 7.3 Expansion

When the user invokes a prompt, the client fetches its expanded content from the server and inserts the resulting messages at the **head of the next turn's messages**.

```lmpl
define expand_mcp_prompt(conn: McpConnection,
                        prompt_name: string,
                        arguments: record) -> list[Message]:
    @boundary(
        inputs: {conn: McpConnection, prompt_name: string, arguments: record},
        outputs: list[Message]
    )

    require known_prompt(conn, prompt_name), "prompt must be registered"
    require valid_arguments(arguments, known_arguments(conn, prompt_name)),
        "arguments must satisfy the prompt's declared parameters"

    raw <- rpc_call(conn, method: "prompts/get",
                   params: {name: prompt_name, arguments: arguments})

    messages <- sanitize_messages(raw.messages)
    return messages

    ensure all(messages, m -> m.role in ["system", "user", "assistant"]),
        "expanded prompts only contain well-formed messages"
    ensure not contains_tool_calls(messages),
        "expanded prompts are conversation content, not tool invocations"
```

### 7.4 Interaction with the core loop

Expanded prompts are prepended to `initial_messages` for the turn in which the user invoked them. The core loop sees them as ordinary conversation history — no new loop branch is needed.

```lmpl
define on_user_slash_command(cmd: string, args: record, state: State) -> State:
    if is_mcp_prompt(cmd):
        conn <- connection_for(cmd)
        prepended <- expand_mcp_prompt(conn, local_name(cmd), args)
        return {...state, messages: prepend_all(state.messages, prepended)}
    ...

    ensure preserved_message_order(result.messages, state.messages),
        "prepended prompt does not reorder existing history"
```

---

## 8. Trust Model

MCP offerings are lower-trust than builtins. Three mechanisms cooperate:

### 8.1 Server-level trust declaration

Servers may accompany their offerings with an explicit trust declaration. Absence defaults to most-restrictive.

```lmpl
type McpTrustDeclaration = {
    default_tool_category: option[ToolCategory],
    default_resource_sensitivity: option["public" | "internal" | "sensitive">,
    concurrency_safe_tools: list[string],       -- opt into readonly grouping
    requires_approval_tools: list[string],      -- explicit approval list
    sanitize_output: bool                       -- whether the server has self-sanitized
}
```

### 8.2 Client-side defaults

| Situation                                   | Default                              |
|---------------------------------------------|--------------------------------------|
| Tool with no declared category              | `"mutating_world"` (fail-closed)     |
| Tool not listed in `concurrency_safe_tools` | Serial execution                     |
| Resource with no sensitivity declaration    | Treat as `"internal"`                |
| Server with no trust declaration at all     | Apply all defaults above             |

### 8.3 Interaction with the guardrail resolver

MCP-sourced invocations traverse the same `can_use_tool` pipeline as builtins (Guardrails §4.1), with tighter defaults at the mode-baseline stage:

```lmpl
define mcp_adjusted_baseline(mode: PermissionMode,
                            cat: ToolCategory,
                            source: ToolSource) -> ResolvedDecision:
    base <- mode_baseline_decision(mode, cat)
    if source.kind == "mcp" and base.decision == "allow" and cat != "readonly":
        return {...base, decision: "ask", reason: "MCP source requires confirmation"}
    return base

    ensure result.decision >= base.decision,    -- "deny" > "ask" > "allow"
        "MCP adjustment is monotone toward stricter"
```

---

## 9. Error Handling & Transport Failures

Transport errors are mapped into `ToolResult` shapes that the core loop already understands. No new recovery branch is needed.

```lmpl
type McpTransportError =
    | "connection_lost"
    | "timeout"
    | "protocol_violation"       -- malformed JSON-RPC, bad method, etc.
    | "schema_mismatch"          -- response did not validate against declared schema
    | "server_error"             -- server returned an error payload

define map_transport_error(err: McpTransportError, call_id: string) -> ToolResult:
    return {
        id: call_id,
        status: "error",
        is_error: true,
        content: describe_error(err),
        provenance: {kind: "mcp_transport_error", error: err}
    }
```

Connection-loss triggers the reconnection policy from §4.4. Repeated failures within a session mark the server `failed` and de-register all its offerings.

---

## 10. LMPL Gaps and Proposed Extensions

### 10.1 Protocol-backed external types

`McpToolDefinition`, `McpResource`, `McpPrompt` are serialized JSON crossing a trust boundary. LMPL has no primitive for "this type comes from a protocol's wire format and must be validated on ingress." A `@from_protocol(schema)` annotation would make the validation obligation visible:

```lmpl
@from_protocol(schema: mcp_tool_schema)
type McpToolDefinition = ...
```

### 10.2 Monotone-toward-stricter adjustments

The `mcp_adjusted_baseline` function never loosens; it only tightens. A `@monotone(toward: "deny")` annotation on decision-adjusting functions would make this invariant structural and statically checkable.

### 10.3 Registry fan-in

Three parallel registries (tool, resource, prompt) share namespacing, lifecycle, and cleanup. LMPL expresses them as three types with three near-identical `register_*` functions. A `namespaced_registry[T]` generic would collapse the duplication and let the MCP lifecycle manipulate them uniformly.

### 10.4 Cross-boundary sanitization obligations

Every inbound MCP payload (tool result, resource content, prompt expansion) traverses `sanitize_*`. These are distinct functions with the same obligation. A `@sanitized` effect annotation ("this value has crossed a sanitization boundary") would make the non-sanitized case detectable at the spec level.

### 10.5 Slash-command registration as a side effect

`register_mcp_prompt` has a `slash_command_registered` postcondition that refers to an effect outside the registry type. This is an example of a broader gap: spec-level side effects are usually expressed as postconditions on returned values, but here the effect is in the UI layer. An `@ui_effect` annotation would document this without pretending the function is pure.

---

## 11. Cross-Spec References

| Reference                              | From                            | To                                 |
|----------------------------------------|---------------------------------|------------------------------------|
| `register_mcp_tool` — client registration | §5.2                         | Tool catalog §7                    |
| `ToolDefinition`, `ToolCategory`       | §5.1–§5.4                       | Tool catalog §3                    |
| `can_use_tool`, mode baseline          | §8.3                            | Guardrails §4.1, §8                |
| Slash-command dispatch                 | §7.2, §7.4                      | Skills / slash-commands (future)   |
| Hook interception of MCP invocations   | (not modeled here)              | Hooks (future)                     |

---

## 12. References

- Varonis Threat Labs, "A Look Inside Claude's Leaked AI Coding Agent" — https://www.varonis.com/blog/claude-code-leak (MCP tools in the 50+ tool catalog; `register_mcp_tool`)
- cablate, *claude-code-research* — https://github.com/cablate/claude-code-research (MCP bridge, namespacing, registration lifecycle)
- l3tchupkt, "Claude Code CLI Runtime: Deep Reverse-Engineering Analysis" — https://github.com/l3tchupkt/claude-code (bridge layer; `bridge/mcp/*`)
- Redreamality, "Claude Code Leak: A Deep Dive into Anthropic's AI Coding Agent Architecture" — https://redreamality.com/blog/claude-code-source-leak-architecture-analysis/ (MCP as part of the bridge / plugin marketplace story)

MCP itself is an open protocol; this spec captures Claude Code's *client* implementation patterns. Protocol-wire details are out of scope — see the MCP protocol specification directly for those. No source code is reproduced.
