# Plan: `secure-api-proxy` — Generic MCP Plugin for Credential-Isolated API Calls

## Context

When Claude Code skills need to call authenticated APIs, credentials are inevitably exposed in the LLM's context window — whether hardcoded, read from env vars, or fetched from secret managers. The resolved key appears in bash tool calls, logs, and conversation history. Gateway scripts solve this by hiding credentials behind a process boundary, but they're brittle, API-specific, and high-overhead.

**MCP provides the perfect solution**: an MCP server runs as a separate process. The LLM calls a named tool with parameters (profile, path, method, body) and receives only the response. Credentials are resolved and injected entirely within the server process — they never enter the LLM context, logs, or conversation history.

This plan creates a **generic, reusable Claude Code plugin** that any skill author can use to make authenticated API calls without exposing credentials.

## Architecture

### How It Works

```
┌──────────────┐         MCP (stdio/JSON-RPC)         ┌─────────────────────┐
│  Claude LLM  │ ──── secure_api_call(profile,path) ──→ │  secure-api-proxy   │
│              │ ←──── { status: 200, body: ... }  ──── │  (bash + jq + curl) │
└──────────────┘                                        └──────┬──────────────┘
                                                               │
    LLM never sees credentials                                 │ reads
                                                               ▼
                                                  ┌─────────────────────────┐
                                                  │  profiles.yaml          │
                                                  │  ┌───────────────────┐  │
                                                  │  │ stripe:           │  │
                                                  │  │   base_url: ...   │  │
                                                  │  │   auth:           │  │
                                                  │  │     type: bearer  │  │
                                                  │  │     source: env   │──┼──→ $STRIPE_API_KEY
                                                  │  │     key: STRIPE.. │  │
                                                  │  └───────────────────┘  │
                                                  │  ┌───────────────────┐  │
                                                  │  │ github:           │  │
                                                  │  │   auth:           │  │
                                                  │  │     source: cmd   │──┼──→ `gh auth token`
                                                  │  └───────────────────┘  │
                                                  └─────────────────────────┘
```

### Security Model

| Threat | Protection |
|--------|-----------|
| LLM training data exposure | Credentials never enter conversation context |
| Prompt injection exfiltration | No credentials in LLM memory to steal |
| Log/audit leakage | Tool calls show `profile="stripe"`, not `sk-live-...` |
| Screen sharing exposure | Only profile names and API paths visible |
| LLM provider breach | Conversation history contains no secrets |

## Plugin Structure

```
secure-api-proxy/
├── .claude-plugin/
│   └── plugin.json               # Plugin manifest
├── .mcp.json                     # MCP server declaration
├── servers/
│   └── secure_api_proxy.sh       # MCP server (bash, ~200 lines)
├── skills/
│   └── secure-api/
│       └── SKILL.md              # Teaches Claude when/how to use the proxy
├── examples/
│   └── profiles.example.yaml     # Example profile configuration
├── LICENSE
└── README.md
```

## MCP Server Design

### Dependencies
- `bash` (4.0+)
- `jq` (JSON processing)
- `curl` (HTTP calls)
- `yq` (YAML parsing — for reading profiles.yaml)

### Tools Exposed

**1. `secure_api_call`** — Execute an authenticated HTTP request

```json
{
  "name": "secure_api_call",
  "description": "Execute an authenticated HTTP API call. Credentials are resolved securely and never exposed.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "profile":       { "type": "string",  "description": "API profile name from config" },
      "method":        { "type": "string",  "enum": ["GET","POST","PUT","PATCH","DELETE","HEAD"], "default": "GET" },
      "path":          { "type": "string",  "description": "API path appended to base_url" },
      "body":          { "type": "string",  "description": "JSON request body" },
      "query":         { "type": "string",  "description": "Query string (e.g. 'limit=10&offset=0')" },
      "extra_headers": { "type": "object",  "description": "Additional headers (auth injected automatically)" }
    },
    "required": ["profile", "path"]
  }
}
```

**2. `list_api_profiles`** — Discover available profiles (no credentials shown)

```json
{
  "name": "list_api_profiles",
  "description": "List configured API profiles with base URLs. Credentials are never shown.",
  "inputSchema": { "type": "object", "properties": {} }
}
```

### Profile Configuration Format

**`profiles.yaml`** (shareable, no secrets):

```yaml
profiles:
  stripe:
    base_url: https://api.stripe.com
    auth:
      type: bearer                # bearer | basic | api-key-header | custom
      source: env                 # env | file | command
      key: STRIPE_API_KEY         # env var name | file path | shell command
    default_headers:
      Content-Type: application/json

  github:
    base_url: https://api.github.com
    auth:
      type: bearer
      source: command
      key: "gh auth token"
    default_headers:
      Accept: application/vnd.github+v3+json

  openai:
    base_url: https://api.openai.com
    auth:
      type: bearer
      source: file
      key: ~/.config/openai/api_key    # single-line file
```

### Auth Types

| Type | Header Generated |
|------|-----------------|
| `bearer` | `Authorization: Bearer <credential>` |
| `basic` | `Authorization: Basic <credential>` |
| `api-key-header` | `X-API-Key: <credential>` |
| `custom` | `<header_name>: <credential>` (requires `header_name` field) |

### Credential Sources

| Source | Resolution |
|--------|-----------|
| `env` | Read from environment variable: `${!key}` |
| `file` | Read from file: `cat "$key" \| tr -d '\n'` |
| `command` | Execute shell command: `eval "$key"` |

### MCP Server Implementation (`servers/secure_api_proxy.sh`)

Core logic (~200 lines bash):

1. **Protocol layer**: Read JSON-RPC from stdin, dispatch to handlers, write responses to stdout
2. **`initialize`**: Return server info and capabilities
3. **`tools/list`**: Return the two tool definitions
4. **`tools/call`**:
   - Parse profile name from args
   - Read profile from `$PROXY_PROFILES` (YAML file path)
   - Resolve credential from configured source
   - Build curl command with injected auth header
   - Execute curl, capture response
   - Return response body + status code as tool result
   - **Credential never leaves this process**

### `.mcp.json` (Plugin Root)

```json
{
  "mcpServers": {
    "secure-api-proxy": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/secure_api_proxy.sh",
      "args": [],
      "env": {
        "PROXY_PROFILES": "${SECURE_API_PROFILES:-${HOME}/.config/secure-api-proxy/profiles.yaml}"
      }
    }
  }
}
```

The single env var `PROXY_PROFILES` points to the profiles config. All other env vars (API keys etc.) are inherited by the child process from the user's shell environment.

### SKILL.md

```markdown
---
name: secure-api
description: >
  Make authenticated API calls through the secure proxy MCP server.
  Use when any task requires calling an external REST API with authentication.
  Credentials are managed securely and never exposed to the conversation.
  Trigger phrases: "call API", "fetch from API", "API request",
  "authenticated request", "secure API call".
---

# Secure API Proxy

When you need to make authenticated HTTP API calls, use the MCP tools
from the secure-api-proxy server instead of curl or direct HTTP calls.

## Discovery
Call `list_api_profiles` first to see which APIs are configured.

## Making Calls
Use `secure_api_call` with:
- `profile`: The API profile name (from list_api_profiles)
- `path`: The API endpoint path
- `method`: HTTP method (defaults to GET)
- `body`: JSON request body (for POST/PUT/PATCH)

## Important
- NEVER ask the user for API keys or credentials
- NEVER attempt to read credential files or environment variables directly
- ALWAYS use the secure_api_call tool — it handles authentication automatically
```

## Implementation Steps

1. **Create repo and plugin scaffold** — `.claude-plugin/plugin.json`, directory structure
2. **Write MCP protocol handler** — JSON-RPC 2.0 over stdio (initialize, tools/list, tools/call)
3. **Write credential resolver** — `resolve_credential(source, key)` supporting env/file/command
4. **Write auth injector** — `build_auth_header(type, credential)` for bearer/basic/api-key/custom
5. **Write curl executor** — Build and execute curl with injected auth, return response
6. **Write `list_api_profiles` handler** — Parse profiles.yaml, return names + base_urls only
7. **Write SKILL.md** — Guide for LLM usage
8. **Write example profiles** — `profiles.example.yaml` with common APIs
9. **Test locally** — `echo '{"jsonrpc":"2.0","method":"tools/call",...}' | ./servers/secure_api_proxy.sh`
10. **Test with Claude Code** — `claude --plugin-dir ./secure-api-proxy`

## Verification

1. **Unit test (no network)**: Pipe JSON-RPC messages to the server, verify tool list and error handling
2. **Integration test**: Configure a profile for a public API (e.g., `httpbin.org`), make a call, verify response
3. **Security test**: Confirm that running `claude --debug` with the plugin shows tool calls with profile names but NO credentials in any output
4. **Plugin install test**: `claude --plugin-dir ./secure-api-proxy` → `/mcp` shows the server → `list_api_profiles` returns configured profiles

## Open Questions (Resolved)

- **yq dependency**: Required for YAML parsing. Could fall back to JSON profiles if yq not available, but yq is already common in the hiivmind ecosystem. Document as a dependency.
- **Env var inheritance**: MCP stdio servers inherit the parent process environment. For plugin MCP servers, Claude Code docs state "access to same environment variables as manually configured servers." If specific env vars aren't available, `source: command` with `printenv VAR` works as a fallback.
