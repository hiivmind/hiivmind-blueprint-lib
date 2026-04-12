# Blueprint Python Runtime: Dual Execution Model Analysis

## Context

This analysis follows the [spoon-core integration analysis](./spoon-core-integration-analysis.md) (ADRs 1-5) and [web3 extension types analysis](./web3-extension-types-analysis.md) (ADRs 6-10). It addresses the architectural question: **should Blueprint-lib have a Python interpreter that can execute the same workflows the LLM interprets?**

Three concrete motivations drive this:

1. **Verification** -- server re-executes workflow, compares state transitions with what the client LLM reports
2. **Progressive disclosure** -- server holds full workflow, reveals only current step to client (games, quizzes, competitions)
3. **IP protection** -- proprietary workflow logic stays server-side, never sent to client

The unifying frame: **SpoonOS as private execution** complementing Blueprint's public execution in Claude Code skills. Same YAML, two runtimes, different trust boundaries.

The spoon-core analysis said "Direction B waits for demand" (Spoon consuming Blueprint YAML). These use cases ARE the demand.

---

## 1. The Dual Execution Model

Today, Blueprint has a single execution model: the LLM reads YAML, interprets the pseudocode in `effect` blocks, and executes the workflow step by step. The user sees everything -- the full workflow definition, all state transitions, every intermediate result.

A Python runtime creates a second execution path for the same YAML definitions. This enables four distinct execution modes depending on who holds the YAML and who verifies the results.

```
                        ┌─────────────────────────────────────────────────┐
                        │            Same YAML Definition                  │
                        │                                                  │
                        │  consequences.yaml + preconditions.yaml          │
                        │  + workflow_nodes.yaml + engine_execution.yaml   │
                        └──────────────┬──────────────┬───────────────────┘
                                       │              │
                              ┌────────▼────────┐  ┌──▼──────────────┐
                              │  Public Runtime  │  │  Private Runtime │
                              │  (LLM interprets │  │  (Python executes│
                              │   pseudocode)    │  │   handlers)      │
                              └────────┬────────┘  └──┬──────────────┘
                                       │              │
                              Client-side      Server-side
                              (Claude Code)    (SpoonOS / FastAPI)
```

**Public execution**: Client LLM has YAML, interprets it, user sees everything. This is today's model -- open-source skills, educational workflows, development.

**Private execution**: Server Python runtime has YAML, executes it, client sees only inputs/outputs. The workflow definition never leaves the server. For paid IP, proprietary algorithms, competitive advantages.

**Verified execution**: Both runtimes process the same workflow. The server re-executes and compares state transitions with what the client LLM reports. For regulated workflows, auditable processes, compliance requirements.

**Progressive execution**: Server reveals workflow step-by-step. Client receives only the current step envelope (prompt, options, deadline). Future steps, scoring logic, and game state remain hidden. For games, quizzes, sealed competitions (like the footy tipping use case).

---

## 2. Four Execution Modes (Detailed)

### 2.1 Public Mode

```
┌──────────────────────────────────────┐
│  Client (Claude Code)                │
│                                      │
│  ┌──────────────────────────────┐    │
│  │  Full YAML Definition        │    │
│  │  ┌────────────────────────┐  │    │
│  │  │  LLM interprets effect │  │    │
│  │  │  pseudocode directly   │  │    │
│  │  └────────────────────────┘  │    │
│  └──────────────────────────────┘    │
│                                      │
│  State: fully visible                │
│  Workflow: fully visible             │
│  Tools: Claude Code tools            │
│                                      │
│  Server: none                        │
└──────────────────────────────────────┘
```

| Aspect | Detail |
|--------|--------|
| Client sees | Full YAML + all state + all transitions |
| Server controls | Nothing |
| Trust model | User controls everything |
| Use case | Open-source skills, development, education |
| Example | `/prepare-release` skill in this repo |

### 2.2 Verified Mode

```
┌─────────────────────┐          ┌──────────────────────┐
│  Client (LLM)       │          │  Server (Python)     │
│                      │          │                      │
│  Full YAML           │          │  Full YAML           │
│  Executes workflow   │          │  Re-executes same    │
│  Reports transitions │───log──→│  Compares transitions │
│                      │          │                      │
│  State: visible      │          │  Divergence report:  │
│  Workflow: visible   │          │  ✓ match / ✗ diff    │
│                      │          │  Attestation: signed │
└─────────────────────┘          └──────────────────────┘
```

| Aspect | Detail |
|--------|--------|
| Client sees | Full YAML + all state (same as public) |
| Server controls | Validates transitions, issues attestation |
| Trust model | Client executes, server verifies |
| Use case | Regulated workflows, audit compliance, financial processes |
| Example | Insurance claim workflow where the regulator requires proof that every step was followed |

### 2.3 Progressive Mode

```
┌─────────────────────┐          ┌──────────────────────┐
│  Client (LLM)       │          │  Server (Python)     │
│                      │          │                      │
│  Sees ONLY:          │          │  Full YAML           │
│  ┌────────────────┐  │          │  Full state          │
│  │ Step Envelope   │  │◄─step──│  Graph position      │
│  │ { prompt,       │  │          │  Future steps        │
│  │   options,      │  │          │  Scoring logic       │
│  │   deadline }    │  │          │                      │
│  └────────────────┘  │          │                      │
│                      │          │                      │
│  Response: user pick │──resp──→│  Advances state      │
│                      │          │  Sends next envelope  │
└─────────────────────┘          └──────────────────────┘
```

| Aspect | Detail |
|--------|--------|
| Client sees | Current step only (prompt + options + deadline) |
| Server controls | Workflow graph, future steps, scoring logic, game state |
| Trust model | Server reveals incrementally, client responds |
| Use case | Games, quizzes, sealed competitions, exam proctoring |
| Example | Footy tipping: server holds scoring rules + match schedule, client sees only "submit your tips for round 15" |

### 2.4 Private Mode

```
┌─────────────────────┐          ┌──────────────────────┐
│  Client (LLM)       │          │  Server (Python)     │
│                      │          │                      │
│  API interface only: │          │  Full YAML           │
│  ┌────────────────┐  │          │  Full state          │
│  │ Input:  data    │──req───→│  Full execution       │
│  │ Output: result  │◄─resp──│  All internal logic    │
│  └────────────────┘  │          │                      │
│                      │          │  x402/DID gated      │
│  No workflow visible │          │                      │
└─────────────────────┘          └──────────────────────┘
```

| Aspect | Detail |
|--------|--------|
| Client sees | Inputs and outputs only |
| Server controls | Everything -- workflow, state, logic, intermediate results |
| Trust model | Server is a black box; client pays for execution |
| Use case | Paid IP, proprietary algorithms, trade secrets |
| Example | Premium code analysis service: client sends code, receives analysis; the workflow logic (what to check, how to score) is proprietary |

### Mode Summary

| Mode | Client Sees | Server Controls | Workflow Visible? | State Visible? |
|------|------------|----------------|-------------------|----------------|
| Public | Full YAML + all state | Nothing | Yes | Yes |
| Verified | Full YAML + all state | Validates transitions | Yes | Yes |
| Progressive | Current step only | Graph, future steps, scoring | No | Partial |
| Private | Inputs/outputs only | Everything | No | No |

---

## 3. Python Interpreter Architecture

### 3.1 Core Design Principle: Hardcoded Handlers, NOT Pseudocode Parsing

The `effect` blocks in Blueprint type definitions contain pseudocode that the LLM interprets directly. A Python runtime does **not** parse this pseudocode. Instead, each of the 43 consequences and 27 preconditions becomes a Python function that implements the same semantics.

```
┌─────────────────────────┐     ┌─────────────────────────┐
│  LLM Runtime (today)    │     │  Python Runtime (new)    │
│                          │     │                          │
│  Reads effect block:     │     │  Calls handler function: │
│  ┌──────────────────┐   │     │  ┌──────────────────┐   │
│  │ if op == "set":   │   │     │  │ def mutate_state( │   │
│  │   set_state(f, v) │   │     │  │   state, params): │   │
│  │ elif op == "append│   │     │  │   op = params.op  │   │
│  │   array.push(v)   │   │     │  │   if op == "set": │   │
│  │ ...               │   │     │  │     set_nested(...)│   │
│  └──────────────────┘   │     │  └──────────────────┘   │
│                          │     │                          │
│  INTERPRETS pseudocode   │     │  EXECUTES Python code    │
│  (flexible, non-det.)    │     │  (deterministic)         │
└─────────────────────────┘     └─────────────────────────┘
```

The `effect` pseudocode serves as the **specification**. The Python handler is the **implementation** of that specification. Both produce the same state transitions for the same inputs.

### 3.2 The Instruction Set: `payload.kind` → Handler Pattern

Each consequence type declares a `payload.kind` that categorizes its behavior. This maps directly to handler patterns in the Python runtime:

| `payload.kind` | Python Handler Pattern | Example Types |
|----------------|----------------------|---------------|
| `state_mutation` | Directly modifies state dict | `set_flag`, `mutate_state`, `create_checkpoint`, `dynamic_route` |
| `computation` | Pure function: inputs → result, stored in state | `evaluate`, `compute`, `evaluate_keywords`, `match_3vl_rules`, `set_timestamp`, `compute_hash` |
| `tool_call` | Calls external tool/service, stores result | `spawn_agent`, `invoke_skill`, `local_file_ops`, `git_ops_local`, `web_ops`, `run_command` |
| `composite` | Multi-step: state mutation + side effects | `init_log`, `log_session_snapshot` |
| `side_effect` | External effects, no state change (or minimal) | `display`, `write_log`, `apply_log_retention`, `output_ci_summary` |

### 3.3 Core Modules

```
blueprint_runtime/
├── __init__.py              # BlueprintRuntime entry point
├── state/
│   ├── manager.py           # StateManager: get/set/interpolate/copy
│   └── primitives.py        # get_nested, set_nested, interpolate, deep_copy, evaluate_expression
├── types/
│   ├── loader.py            # TypeLoader: YAML → TypeRegistry (mirrors resolution/type-loader.yaml)
│   └── registry.py          # TypeRegistry: lookup by name
├── workflow/
│   ├── loader.py            # WorkflowLoader: YAML → Workflow (mirrors resolution/workflow-loader.yaml)
│   └── validator.py         # Validates workflow against registry
├── engine/
│   ├── executor.py          # Main execution loop (mirrors execution/engine_execution.yaml phases)
│   ├── node_dispatch.py     # Dispatches to node executors by type
│   └── consequence_dispatch.py  # Dispatches to consequence handlers by type
├── nodes/
│   ├── action.py            # ActionNode: execute consequences, route on success/failure
│   ├── conditional.py       # ConditionalNode: evaluate precondition, route on true/false
│   ├── user_prompt.py       # UserPromptNode: server-side prompt handling
│   └── reference.py         # ReferenceNode: inline + spawn mode
├── consequences/
│   ├── __init__.py          # Handler registry
│   ├── control.py           # create_checkpoint, rollback_checkpoint, spawn_agent, invoke_skill, inline
│   ├── evaluation.py        # evaluate, compute
│   ├── intent.py            # evaluate_keywords, parse_intent_flags, match_3vl_rules, dynamic_route
│   ├── state.py             # set_flag, mutate_state
│   ├── logging.py           # init_log, log_node, log_entry, log_session_snapshot, finalize_log, write_log, ...
│   ├── interaction.py       # display
│   ├── utility.py           # set_timestamp, compute_hash
│   ├── filesystem.py        # local_file_ops
│   ├── git.py               # git_ops_local
│   ├── web.py               # web_ops
│   ├── scripting.py         # run_command
│   └── package.py           # install_tool
├── preconditions/
│   ├── __init__.py          # Evaluator registry
│   ├── composite.py         # all_of, any_of, none_of, xor_of
│   ├── expression.py        # evaluate_expression
│   ├── state.py             # state_check
│   ├── tools.py             # tool_check
│   ├── filesystem.py        # path_check
│   ├── logging.py           # log_state
│   ├── python.py            # python_module_available
│   ├── network.py           # network_available
│   ├── git.py               # source_check
│   └── web.py               # fetch_check
├── extensions/
│   └── loader.py            # Extension handler registry (load Python modules from extensions)
└── server/
    ├── app.py               # FastAPI wrapper
    └── mcp.py               # MCP server mode
```

### 3.4 State Primitives

The Python runtime implements the same state manipulation functions that the LLM uses conceptually:

```python
# state/primitives.py

def get_nested(state: dict, path: str) -> Any:
    """Get value from nested dict using dot notation.
    get_nested(state, "computed.intent_flags.is_new") → state["computed"]["intent_flags"]["is_new"]
    """

def set_nested(state: dict, path: str, value: Any) -> None:
    """Set value in nested dict using dot notation.
    Creates intermediate dicts as needed.
    """

def interpolate(template: str, state: dict) -> str:
    """Replace ${path} placeholders with values from state.
    interpolate("Hello ${user.name}", state) → "Hello Alice"
    Supports nested paths: ${computed.result.score}
    """

def deep_copy(state: dict) -> dict:
    """Create independent deep copy of state for spawn mode isolation."""

def evaluate_expression(expr: str, state: dict) -> Any:
    """Evaluate boolean/arithmetic expression with state context.
    Supports: ==, !=, >, <, >=, <=, &&, ||, !
    Functions: len(), contains(), startswith(), endswith()
    """
```

### 3.5 Node Executors

Each of the 5 node types becomes a Python executor that mirrors the pseudocode in `workflow_nodes.yaml`:

**ActionNode** (mirrors the `action` node type from `blueprint-types.md`):
```python
async def execute_action(node, state, dispatch_consequence):
    for action in node["actions"]:
        result = await dispatch_consequence(action, state)
        if result.failed:
            log_failure(action, result.error)
            return route_to(node["on_failure"])
        if action.get("store_as"):
            set_nested(state, f"computed.{action['store_as']}", result.value)
    return route_to(node["on_success"])
```

**ConditionalNode** (mirrors conditional executor with audit mode):
```python
async def execute_conditional(node, state, evaluate_precondition):
    if node.get("audit", {}).get("enabled"):
        # Audit mode: evaluate ALL conditions, no short-circuit
        audit_results = evaluate_all_conditions(node, state, evaluate_precondition)
        output_path = node["audit"].get("output", "computed.audit_results")
        set_nested(state, output_path, audit_results)
        branch = "on_true" if audit_results["passed"] else "on_false"
    else:
        # Normal mode: short-circuit
        result = await evaluate_precondition(node["condition"], state)
        branch = "on_true" if result else "on_false"
    return route_to(node["branches"][branch])
```

**ReferenceNode** (inline + spawn mode):
```python
async def execute_reference(node, state, runtime):
    workflow = await runtime.load_workflow(node["workflow"])
    inputs = resolve_inputs(node, state)
    mode = node.get("mode", "inline")

    if mode == "inline":
        # Shared state
        for key, value in inputs.items():
            state[key] = value
        await runtime.execute_workflow(workflow, state)
        return resolve_routing(node, state)
    else:
        # Spawn: isolated state
        isolated = deep_copy(state)
        for key, value in inputs.items():
            isolated[key] = value
        result = await runtime.execute_workflow_isolated(workflow, isolated)
        if result.success:
            apply_output_mapping(node, state, isolated)
            return route_to(node["transitions"]["on_success"])
        else:
            return route_to(node["transitions"]["on_failure"])
```

**UserPromptNode** (server-side mode for progressive/private execution):
```python
async def execute_user_prompt(node, state, prompt_handler):
    """In server mode, user_prompt becomes an API call rather than a tool invocation.
    The prompt_handler abstracts the delivery mechanism:
    - Public mode: calls AskUserQuestion tool
    - Progressive mode: sends step envelope via HTTP, awaits response
    - Private mode: returns prompt as API response, awaits next request
    """
    options = resolve_options(node, state)
    response = await prompt_handler.present(node["prompt"], options)
    return handle_response(node, options, response, state)
```

### 3.6 Extension Loading

Extensions (like the web3 identity/escrow types from the web3 analysis) register additional Python handlers:

```python
# Extension package structure:
# blueprint_web3_identity/
#   handlers/
#     consequences.py    # identity_ops, identity_trust_score, attestation_ops, store_immutable
#     preconditions.py   # identity_check, did_registered, attestation_check

# Registration in extension's __init__.py:
def register(registry):
    registry.add_consequence("identity_ops", identity_ops_handler)
    registry.add_consequence("identity_trust_score", trust_score_handler)
    registry.add_precondition("identity_check", identity_check_evaluator)
    # ... etc
```

This mirrors the YAML `definitions.extensions` pattern -- the same extension that provides YAML type definitions for the LLM runtime also provides Python handlers for the server runtime.

---

## 4. Blueprint-Runtime Package Design

### 4.1 Repository

**Repo**: `hiivmind/blueprint-runtime` (standalone, pip-installable)

This is a **new repository**, separate from both `blueprint-lib` (YAML definitions) and `spoon-core` (AI agent framework). The separation follows ADR-12 below -- the runtime is a consumer of blueprint-lib definitions, not an extension of either codebase.

### 4.2 Dependencies

| Package | Purpose | Required? |
|---------|---------|-----------|
| `pyyaml` | Parse YAML workflow and type definitions | Yes |
| `jsonschema` | Validate workflows against Blueprint schemas | Yes |
| `httpx` | Fetch remote type definitions, MCP calls | Yes |
| `fastapi` + `uvicorn` | HTTP server wrapper | Optional (server mode) |
| `mcp` | MCP server mode | Optional (MCP mode) |

Notably absent: no LLM SDK dependency. The Python runtime doesn't call an LLM -- it executes handlers directly.

### 4.3 Interface

```python
from blueprint_runtime import BlueprintRuntime

# Basic execution
runtime = BlueprintRuntime()
result = await runtime.execute(
    workflow_path="path/to/workflow.yaml",
    initial_state={"user_input": "analyze this code"},
)

# Result structure
# ExecutionResult:
#   success: bool
#   ending_id: str          # Which ending was reached
#   final_state: dict       # Complete state after execution
#   transition_log: list    # [{ node_id, action, state_delta, timestamp }]
#   duration_seconds: float
```

### 4.4 Server Integration

**FastAPI wrapper** for HTTP execution endpoint:

```python
from blueprint_runtime.server import create_app

app = create_app(
    workflows_dir="./workflows",
    type_source="hiivmind/hiivmind-blueprint-lib@v3.1.1",
    mode="progressive",  # or "private", "verified"
)

# Endpoints:
# POST /execute          -- start workflow execution
# POST /step/{session}   -- submit response for progressive mode
# GET  /status/{session} -- check execution status
# GET  /verify/{session} -- get verification report (verified mode)
```

**MCP server mode** for SpoonOS agent invocation:

```python
from blueprint_runtime.server import create_mcp_server

server = create_mcp_server(
    workflows_dir="./workflows",
    type_source="hiivmind/hiivmind-blueprint-lib@v3.1.1",
)

# Exposes as MCP tools:
# blueprint_execute(workflow, initial_state) → ExecutionResult
# blueprint_step(session_id, response) → StepEnvelope
# blueprint_status(session_id) → SessionStatus
```

### 4.5 Conceptual Package Structure

```
blueprint-runtime/
├── pyproject.toml           # Package metadata, dependencies
├── src/
│   └── blueprint_runtime/   # Core package (see §3.3 for module layout)
├── tests/
│   ├── test_state.py        # State primitive tests
│   ├── test_consequences/   # One test file per consequence handler
│   ├── test_preconditions/  # One test file per precondition evaluator
│   ├── test_nodes/          # Node executor tests
│   ├── test_engine.py       # Integration: full workflow execution
│   └── fixtures/            # YAML workflows for testing
└── examples/
    ├── basic_execution.py   # Minimal example
    ├── progressive_game.py  # Progressive disclosure example
    └── verified_workflow.py # Verification example
```

---

## 5. Progressive Disclosure Protocol

### 5.1 Step Envelope

The server reveals workflow steps incrementally via **step envelopes**. Each envelope contains only what the client needs to present the current step -- no future steps, no scoring logic, no game state.

```
Step Envelope Structure:
┌──────────────────────────────────────────┐
│  {                                        │
│    session_id: "abc123",                  │
│    step_id: "collect_tips",               │
│    step_number: 3,                        │
│    total_steps: null,  // hidden          │
│    prompt: {                              │
│      question: "Enter your tips...",      │
│      header: "Tips",                      │
│      options: [...],                      │
│    },                                     │
│    deadline: "2026-03-15T18:00:00Z",      │
│    metadata: {                            │
│      round: "round_15",                   │
│      display_content: "..."               │
│    }                                      │
│  }                                        │
└──────────────────────────────────────────┘
```

Key properties:
- `total_steps` is `null` -- the client doesn't know how many steps remain
- No `on_success` or `on_failure` targets are revealed
- No scoring rules, conditions, or future node references
- `deadline` enables time-bounded responses (tips must be in before kickoff)
- `metadata` carries display-only content the server chooses to reveal

### 5.2 Protocol Flow

```
Client                              Server
  │                                    │
  │  POST /execute                     │
  │  { workflow: "footy_tips",         │
  │    initial_state: { round: 15 } }  │
  │──────────────────────────────────→│
  │                                    │  Server loads workflow
  │                                    │  Executes until user_prompt node
  │  ◄─────── Step Envelope ──────────│
  │  { step_id: "verify_membership",  │
  │    prompt: "Enter your DID" }      │
  │                                    │
  │  POST /step/{session}              │
  │  { response: "did:erc8004:..." }   │
  │──────────────────────────────────→│
  │                                    │  Server validates DID
  │                                    │  Advances state
  │                                    │  Executes until next user_prompt
  │  ◄─────── Step Envelope ──────────│
  │  { step_id: "collect_tips",        │
  │    prompt: "Enter tips for R15",   │
  │    deadline: "2026-03-15T18:00Z" } │
  │                                    │
  │  POST /step/{session}              │
  │  { response: "Collingwood > ..." } │
  │──────────────────────────────────→│
  │                                    │  Server records submission
  │                                    │  Hashes content
  │                                    │  Stores in NeoFS
  │  ◄─────── Final Result ───────────│
  │  { status: "success",              │
  │    output: { content_hash: "..." } │
  │  }                                 │
```

### 5.3 Server-Side Execution Between Steps

Between client responses, the server executes all non-interactive nodes silently:

```python
async def execute_until_prompt(session):
    """Execute nodes until we hit a user_prompt node or an ending."""
    while True:
        node = get_current_node(session)

        if node["type"] == "user_prompt":
            # Stop and send envelope to client
            return build_step_envelope(node, session.state)

        elif is_ending(node):
            # Workflow complete
            return build_final_result(session)

        else:
            # Execute silently (action, conditional, reference)
            result = await execute_node(node, session.state)
            session.advance_to(result.next_node)
```

Action nodes, conditional nodes, and reference nodes execute entirely server-side. The client never sees their existence. This is the key insight: **the workflow graph topology is hidden from the client**.

### 5.4 Footy Tipping: Progressive Mode Walkthrough

The season resolution workflow (`footy_tipping_resolve_season` from the web3 analysis) in progressive mode:

1. **Server starts workflow** -- `init_log`, `verify_organizer` execute silently
2. **Step 1 sent to client**: "Confirm you are the organizer (sign challenge)" -- client signs
3. **Server verifies** -- `check_authority`, `fetch_all_results`, `score_all_rounds` execute silently
4. **Step 2 sent to client**: Final leaderboard + "Release prize pool to winner?" -- client confirms
5. **Server executes release** -- `release_prize` (spawn mode), `issue_winner_attestation` execute silently
6. **Final result sent**: winner DID, release tx hash, attestation URI

The client sees only 2 prompts. The server executes 8+ nodes, including escrow operations, attestation creation, and immutable storage -- all invisible to the client.

### 5.5 Game Example: Hidden Puzzle

```yaml
# Progressive disclosure hides the solution and hint logic
name: puzzle_game
nodes:
  present_puzzle:
    type: user_prompt
    prompt:
      question: "${computed.current_clue}"  # Server computes clue
      header: "Puzzle"
      options:
        - id: submit
          label: Submit answer
          description: Enter your answer

  check_answer:
    type: conditional
    # This logic is HIDDEN from client in progressive mode
    condition:
      type: evaluate_expression
      expression: "computed.user_answer == computed.solution"
    branches:
      on_true: award_points
      on_false: check_hints_remaining

  check_hints_remaining:
    type: conditional
    # Hidden: client doesn't know hint threshold
    condition:
      type: evaluate_expression
      expression: "computed.attempts >= 3"
    branches:
      on_true: reveal_hint
      on_false: present_puzzle  # Loop back
```

In progressive mode, the client sees only the puzzle prompt. The solution comparison, hint threshold, and scoring logic remain server-side.

---

## 6. Verification Protocol

### 6.1 State Transition Log

During public execution, the client LLM reports state transitions after each node:

```yaml
# Transition log entry
- node_id: "check_prerequisites"
  node_type: "conditional"
  timestamp: "2026-03-15T10:30:01Z"
  action: "evaluate_precondition"
  result: true
  branch_taken: "on_true"
  state_delta:
    set:
      computed.prereq_audit:
        passed: true
        total: 3
        passed_count: 3
    unchanged:
      - flags
      - user_responses
```

### 6.2 Server Re-Execution

The server receives the client's transition log and re-executes the same workflow with the same inputs:

```
Client Transition Log          Server Re-Execution
┌────────────────────┐         ┌────────────────────┐
│ Node: start        │         │ Node: start        │
│ Δ: log initialized │─compare─│ Δ: log initialized │  ✓ match
│                    │         │                    │
│ Node: check_prereq │         │ Node: check_prereq │
│ Result: true       │─compare─│ Result: true       │  ✓ match
│ Branch: on_true    │         │ Branch: on_true    │
│                    │         │                    │
│ Node: verify_id    │         │ Node: verify_id    │
│ Δ: challenge set   │─compare─│ Δ: challenge set   │  ✓ match
│ ...                │         │ ...                │
└────────────────────┘         └────────────────────┘
```

### 6.3 Divergence Detection

When the server's re-execution produces different results:

```yaml
# Divergence report
divergences:
  - step: 5
    node_id: "evaluate_intent"
    type: "soft"  # LLM non-determinism
    expected:
      action: "evaluate_keywords"
      result: "setup_wizard"
    actual:
      action: "evaluate_keywords"
      result: "configure"
    severity: "info"
    reason: "LLM keyword matching is non-deterministic"

  - step: 8
    node_id: "payment_step"
    type: "hard"  # Suspicious
    expected:
      action: "escrow_ops.deposit"
      result: { tx_hash: "0xabc..." }
    actual:
      action: null  # Step was skipped!
    severity: "critical"
    reason: "Payment step was not executed by client"
```

### 6.4 Tolerance Model

Not all divergences indicate tampering. The verification protocol classifies divergences:

| Category | Example | Tolerance | Action |
|----------|---------|-----------|--------|
| **Deterministic match** | `set_flag`, `mutate_state`, `compute` | Zero tolerance | Must be identical |
| **LLM-interpreted** | `evaluate_keywords`, `parse_intent_flags` | Soft tolerance | Log as info, don't flag |
| **Timing-dependent** | `set_timestamp`, log timestamps | Ignore | Timestamps will always differ |
| **Tool-dependent** | `git_ops_local.get-sha`, `web_ops.fetch` | Ignore | External state may change |
| **Security-critical** | Payment steps, escrow ops, identity verification | Zero tolerance | Flag as critical if skipped or altered |

```python
# Tolerance rules
TOLERANCE_RULES = {
    # Consequence types with LLM non-determinism
    "evaluate_keywords": Tolerance.SOFT,
    "parse_intent_flags": Tolerance.SOFT,

    # Always different
    "set_timestamp": Tolerance.IGNORE,
    "init_log": Tolerance.IGNORE_TIMESTAMPS,

    # External state may change
    "git_ops_local": Tolerance.IGNORE_VALUE,
    "web_ops": Tolerance.IGNORE_VALUE,

    # Must match exactly
    "set_flag": Tolerance.EXACT,
    "mutate_state": Tolerance.EXACT,
    "compute": Tolerance.EXACT,
    "escrow_ops": Tolerance.CRITICAL,
    "identity_ops": Tolerance.CRITICAL,
}
```

### 6.5 Attestation

When verification succeeds, the server issues a signed attestation:

```yaml
# Verification attestation
type: workflow_verification
workflow: "footy_tipping_register"
workflow_version: "1.0.0"
executor_did: "did:erc8004:0x1234..."
verifier_did: "did:erc8004:0xabcd..."
session_id: "abc123"
timestamp: "2026-03-15T10:35:00Z"
result:
  verified: true
  total_steps: 12
  matched_steps: 12
  soft_divergences: 1  # evaluate_keywords non-determinism
  hard_divergences: 0
  critical_divergences: 0
signature: "0x..."  # Signed by verifier DID
```

This attestation can be stored immutably (via `store_immutable` from the web3 extensions) as proof that the workflow was faithfully executed.

---

## 7. SpoonOS Alignment

### 7.1 SpoonOS = The Private Runtime for Blueprint Workflows

The spoon-core analysis identified two systems with complementary strengths:

| Blueprint | Spoon |
|-----------|-------|
| Declarative YAML workflows | Python async runtime |
| Schema validation | Payment infrastructure |
| Version-pinned types | Web3 identity |
| LLM-interpreted execution | Deterministic execution |

`blueprint-runtime` is the bridge. It lets Spoon's Python infrastructure execute Blueprint YAML deterministically, without an LLM in the loop.

### 7.2 Integration Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  SpoonOS Server                                               │
│                                                               │
│  ┌─────────────────┐  ┌──────────────────┐                   │
│  │  SpoonReactAI    │  │  BlueprintRuntime │                   │
│  │  (agent loops)   │  │  (YAML executor)  │                   │
│  │                  │  │                   │                   │
│  │  Uses Blueprint  │  │  Wraps as:        │                   │
│  │  workflows for   │──│  - StateGraph node│                   │
│  │  structured      │  │  - MCP tool       │                   │
│  │  multi-step work │  │  - FastAPI endpoint│                   │
│  └─────────────────┘  └──────────────────┘                   │
│           │                    │                              │
│           ▼                    ▼                              │
│  ┌──────────────────────────────────────┐                    │
│  │  Shared Infrastructure               │                    │
│  │  x402 service │ DID resolver │ NeoFS │                    │
│  └──────────────────────────────────────┘                    │
│                                                               │
│  x402 gates access to private workflow execution              │
└──────────────────────────────────────────────────────────────┘
```

### 7.3 Three Integration Modes

**As a StateGraph node**: BlueprintRuntime wraps as a callable node in Spoon's `StateGraph`:

```python
# Spoon StateGraph using Blueprint workflow as a node
graph = StateGraph(CompetitionState)

graph.add_node("registration", BlueprintRuntimeNode(
    workflow="hiivmind/blueprint-web3-escrow@v1.0.0:footy-register",
    mode="private",
))
graph.add_node("tip_collection", BlueprintRuntimeNode(
    workflow="hiivmind/blueprint-web3-escrow@v1.0.0:footy-tips",
    mode="progressive",
))
graph.add_edge("registration", "tip_collection")
```

**As an MCP tool**: Spoon agents can invoke Blueprint workflows via MCP:

```python
# Spoon agent calls Blueprint via MCP
result = await mcp_client.call_tool(
    "blueprint_execute",
    workflow="footy_tipping_resolve_season",
    initial_state={"pool_id": "abc123", "organizer_did": "did:erc8004:0x..."},
)
```

**As a standalone HTTP service**: FastAPI wrapper accessible by any client:

```
POST https://spoonos.example.com/blueprint/execute
X-PAYMENT: <x402 signed header>
Content-Type: application/json

{
  "workflow": "premium_code_analysis",
  "initial_state": { "code": "..." }
}
```

### 7.4 The Footy Tipping Example: End-to-End

The footy tipping competition (from the web3 analysis) maps perfectly to the dual execution model:

| Phase | Execution Mode | Why |
|-------|---------------|-----|
| Season creation | Private | Organizer-only, escrow contract deployment |
| Player registration | Verified | Public action, but server verifies DID + deposit |
| Weekly tips | Progressive | Player sees only current round, server hides scoring logic |
| Season resolution | Private | Scoring logic, winner determination, escrow release -- all server-side |

The resolution workflow is the perfect example: scoring logic is **private** (server), tips are **public** (client submitted), escrow release is **enforced** (contract). The server runs `outcome_ops.score_round` and `outcome_ops.determine_winner` in Python -- deterministic, auditable, not dependent on LLM interpretation.

### 7.5 x402 Gating for Private Execution

Per ADR-2 from the spoon-core analysis, server-side enforcement is the security boundary. Private mode execution is gated by x402:

```
Client                              Server (SpoonOS)
  │                                    │
  │  POST /blueprint/execute           │
  │  (no payment header)               │
  │──────────────────────────────────→│
  │                                    │
  │  ◄──── 402 Payment Required ──────│
  │  { payment_requirements: {         │
  │    amount: "0.01", currency: "USDC"│
  │  }}                                │
  │                                    │
  │  POST /blueprint/execute           │
  │  X-PAYMENT: <signed header>        │
  │──────────────────────────────────→│
  │                                    │  Verify payment
  │                                    │  Execute workflow
  │  ◄──── 200 ExecutionResult ───────│
```

### 7.6 Escrow Contract Uses Private Mode

The escrow contract operations (from the web3 analysis) naturally map to private mode because:

1. **Scoring logic is proprietary** -- the organizer's scoring rules shouldn't be visible to players
2. **Winner determination must be deterministic** -- Python runtime, not LLM interpretation
3. **Escrow release requires authority** -- only the server (with organizer's DID) can release funds
4. **Dispute resolution needs auditability** -- server's execution log is the authoritative record

---

## 8. What Changes in Blueprint-lib

### 8.1 Nothing Breaks

The YAML type definitions are **unchanged**. The Python runtime is a consumer of the existing definitions, not a modification of them. Workflows that run today via LLM interpretation continue to work identically.

### 8.2 Potential Annotations (Future)

New `payload` annotations could hint at server-side behavior:

```yaml
# Hypothetical future annotation
escrow_ops:
  payload:
    kind: tool_call
    requires:
      network: true
      private: true   # NEW: this type benefits from server-side execution
      deterministic: false  # NEW: involves external state (blockchain)
```

These annotations would be informational, not enforced by the YAML schema. They help the runtime (and workflow authors) understand which types benefit from which execution mode.

### 8.3 Extension Types Map to Private Mode

The web3 extension types naturally map to private mode:

| Extension Type | Why Private Mode |
|---------------|------------------|
| `escrow_ops` (release, refund) | Key signing, authority enforcement |
| `outcome_ops` (score, determine_winner) | Proprietary scoring logic |
| `oracle_feed` | Server-side data fetching, untrusted source handling |
| `identity_ops` (register) | Private key operations |

These types were designed with `spawn` mode mandatory (ADR-3). Private execution is the logical next step: instead of spawning an isolated sub-workflow on the client, execute the entire workflow server-side.

### 8.4 `effect` Pseudocode Becomes Dual-Purpose

The `effect` blocks in type definitions serve two purposes:

1. **LLM reads them** for public execution -- the LLM interprets the pseudocode directly
2. **Python handlers implement them** for private execution -- the pseudocode is the specification

This means `effect` blocks must remain clear, unambiguous, and complete. They are the single source of truth that both runtimes implement.

---

## 9. Architectural Decision Records

### ADR-11: Hardcoded Python Handlers, Not Pseudocode Parsing

**Decision:** The Python runtime implements each consequence/precondition type as a native Python function, rather than parsing and interpreting the `effect` pseudocode at runtime.

**Rationale:** Pseudocode parsing would require building an interpreter for a loosely-defined language. The pseudocode uses informal syntax (mix of Python, JavaScript, and plain English), includes LLM-specific instructions ("the LLM naturally performs this evaluation"), and references conceptual functions (`display_to_user`, `mcp_call`) that need concrete implementations. A parser would be fragile and would duplicate the LLM's interpretive capability poorly.

Hardcoded handlers are:
- Deterministic (no interpretation ambiguity)
- Testable (unit tests per handler)
- Debuggable (standard Python stack traces)
- Performant (no parsing overhead)

**Consequences:** Each new type definition requires a corresponding Python handler. The handler must be written to match the `effect` pseudocode semantics. This is manual work, but it's straightforward -- the `effect` block is the specification, the handler is the implementation.

**Relationship to prior ADRs:** Independent of ADRs 1-10. This is an implementation decision for the new runtime.

### ADR-12: blueprint-runtime as Standalone Package

**Decision:** The Python runtime ships as `hiivmind/blueprint-runtime`, a standalone pip-installable package. It is not embedded in `spoon-core` or `blueprint-lib`.

**Rationale:**
- **Not in blueprint-lib**: blueprint-lib is YAML-only, no Python runtime dependency. Adding Python code would change its nature from a definition library to a runtime.
- **Not in spoon-core**: spoon-core has its own agent framework, LLM management, and Web3 stack. Embedding Blueprint execution would create tight coupling and force spoon-core consumers to take a Blueprint dependency.
- **Standalone**: Can be consumed by SpoonOS, by standalone servers, or by any Python project that needs to execute Blueprint workflows.

**Consequences:** Three repos in the ecosystem: `blueprint-lib` (YAML definitions), `blueprint-runtime` (Python executor), `spoon-core` (agent framework). SpoonOS composes all three.

**Relationship to prior ADRs:** Extends ADR-5 (extension repos) to the runtime itself. Consistent with ADR-1 (MCP as bridge) -- the runtime can expose itself via MCP.

### ADR-13: Progressive Disclosure Uses Step Envelopes

**Decision:** Progressive mode reveals workflow steps via step envelopes containing only the current prompt, options, and deadline. No workflow graph, future steps, or scoring logic is sent to the client.

**Rationale:** The whole point of progressive disclosure is to hide future state. Sending the workflow graph (even encrypted) risks leakage. The step envelope pattern is:
- Minimal -- only what the client needs to render the current prompt
- Stateless on the client -- no workflow state to tamper with
- Familiar -- similar to multi-step form wizards in web applications

**Consequences:** The client LLM cannot reason about future steps or optimize its strategy. This is a feature, not a bug -- for games and competitions, this prevents cheating. For quizzes, this prevents looking ahead.

**Relationship to prior ADRs:** Builds on ADR-3 (spawn mode). Progressive mode is conceptually "the entire workflow runs in spawn mode on the server, with incremental output mapping."

### ADR-14: Verification Uses State Transition Logs with Tolerance

**Decision:** Verification compares client-reported state transition logs against server re-execution, with a tolerance model that accounts for LLM non-determinism.

**Rationale:** Strict byte-for-byte comparison would fail constantly because:
- `evaluate_keywords` may match different keywords for the same intent
- `parse_intent_flags` may assign different confidence levels
- Timestamps are always different
- External tool results may change between executions

The tolerance model classifies each consequence type's expected determinism and only flags divergences that exceed the tolerance for that type.

**Consequences:** Some LLM-interpreted types (`evaluate_keywords`, `parse_intent_flags`) cannot be verified to exact match. This is acceptable -- these types are routing helpers, not security-critical. Security-critical types (payments, escrow, identity) have zero tolerance.

**Relationship to prior ADRs:** Strengthens ADR-2 (server-side enforcement). Verification is defense-in-depth -- server-side enforcement remains the actual security boundary.

### ADR-15: Private Mode Workflows Require x402 or DID Authentication

**Decision:** Private mode execution (where the server runs the full workflow) requires either x402 payment or DID-authenticated access. Public and verified modes do not require authentication (the client already has the YAML).

**Rationale:** Private mode hides the workflow definition -- this is the value being protected. Without a payment/authentication gate, anyone could call the endpoint repeatedly to reverse-engineer the hidden workflow through observation. x402 gates access to each execution. DID authentication allows access-controlled execution for authorized users (e.g., competition organizers).

**Consequences:** Every private mode endpoint must have x402 or DID middleware. This aligns with the spoon-core analysis's existing x402 gateway pattern.

**Relationship to prior ADRs:** Direct application of ADR-2 (server-side enforcement) and ADR-4 (definitions free, execution metered) to the new execution modes.

---

## 10. Implementation Roadmap

### Phase 0: Core Interpreter

**Goal:** State management + node dispatch + 10 most-used consequence types.

| Component | What It Does | Effort |
|-----------|-------------|--------|
| `state/primitives.py` | `get_nested`, `set_nested`, `interpolate`, `deep_copy`, `evaluate_expression` | Small |
| `state/manager.py` | StateManager wrapping primitives | Small |
| `types/loader.py` | Load YAML type definitions (local path only) | Small |
| `engine/executor.py` | 3-phase execution loop (init → execute → complete) | Medium |
| `engine/node_dispatch.py` | Dispatch to action, conditional node executors | Small |
| `nodes/action.py` | Execute consequences, route on success/failure | Small |
| `nodes/conditional.py` | Evaluate precondition, route on true/false (including audit mode) | Medium |
| Consequence handlers (10) | `set_flag`, `mutate_state`, `compute`, `evaluate`, `set_timestamp`, `compute_hash`, `display`, `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules` | Medium |
| Precondition evaluators (5) | `all_of`, `any_of`, `none_of`, `state_check`, `evaluate_expression` | Small |

**Validation:** Execute the `intent-detection` reusable workflow end-to-end in Python.

### Phase 1: Full Type Coverage

**Goal:** All 43 consequences + 27 preconditions have Python handlers.

| Component | Count | Effort |
|-----------|-------|--------|
| Remaining consequence handlers | 33 | Medium-Large |
| Remaining precondition evaluators | 22 | Medium |
| `nodes/reference.py` (inline + spawn) | 1 | Medium |
| `nodes/user_prompt.py` (console mode) | 1 | Small |
| `types/loader.py` (remote GitHub fetch) | 1 | Medium |
| `workflow/loader.py` | 1 | Medium |
| Extension loading | 1 | Small |

**Validation:** Execute the footy tipping workflows (all 4 phases) from the web3 analysis.

### Phase 2: Server Wrapper

**Goal:** HTTP server + MCP server mode for remote execution.

| Component | What It Does | Effort |
|-----------|-------------|--------|
| `server/app.py` | FastAPI wrapper with session management | Medium |
| `server/mcp.py` | MCP tool definitions for BlueprintRuntime | Medium |
| Session management | Track active workflow sessions, state persistence | Medium |
| x402 middleware | Payment gating for private mode endpoints | Small (uses spoon-core) |
| DID middleware | DID authentication for authorized access | Small (uses spoon-core) |

**Validation:** Execute a workflow via HTTP POST and via MCP tool call.

### Phase 3: Progressive Disclosure Protocol

**Goal:** Server reveals steps incrementally, client responds.

| Component | What It Does | Effort |
|-----------|-------------|--------|
| Step envelope builder | Convert user_prompt nodes to step envelopes | Small |
| `execute_until_prompt` | Server-side execution between prompts | Medium |
| Deadline enforcement | Time-bounded responses (optional) | Small |
| Session state persistence | Store state between client requests | Medium |
| Client SDK (optional) | Python/JS client for step envelope protocol | Small |

**Validation:** Run the footy tipping weekly tips flow with a test client that only sees step envelopes.

### Phase 4: Verification Protocol

**Goal:** Server re-executes and compares against client transition logs.

| Component | What It Does | Effort |
|-----------|-------------|--------|
| Transition log schema | Define log entry format | Small |
| Client log collector | Instrument LLM runtime to produce transition logs | Medium |
| Server re-executor | Re-execute workflow with same inputs | Small (reuses Phase 0) |
| Divergence detector | Compare logs with tolerance rules | Medium |
| Tolerance configuration | Per-type tolerance classification | Small |
| Attestation generator | Issue signed verification attestation | Small (uses web3 extensions) |

**Validation:** Execute a workflow in Claude Code, capture transition log, submit to server, receive attestation.

### Phase 5: SpoonOS Integration

**Goal:** BlueprintRuntime as a first-class SpoonOS component.

| Component | What It Does | Effort |
|-----------|-------------|--------|
| `BlueprintRuntimeNode` | StateGraph node wrapper | Small |
| Spoon MCP server config | Register Blueprint tools in SpoonOS MCP server | Small |
| x402 gating integration | Wire x402 service into private mode | Small |
| Escrow workflow execution | Run footy tipping resolution end-to-end | Medium |
| Web3 extension handlers | Python handlers for identity/escrow/attestation types | Medium |

**Validation:** Run the complete footy tipping lifecycle (create → register → tip → resolve) through SpoonOS with escrow settlement.

### Phase Dependencies

```
Phase 0 ──→ Phase 1 ──→ Phase 2 ──┬──→ Phase 3
                                    │
                                    ├──→ Phase 4
                                    │
                                    └──→ Phase 5
```

Phases 3, 4, and 5 are independent of each other and can be developed in parallel after Phase 2.

---

## Key Reference Files

| File | Why It Matters |
|------|---------------|
| `execution/engine_execution.yaml` | The 3-phase execution model the interpreter must replicate |
| `consequences/consequences.yaml` | All 43 consequence types → Python handler functions |
| `preconditions/preconditions.yaml` | All 27 precondition types → Python evaluator functions |
| `blueprint-types.md` (Nodes section) | 3 node types → Python node executors |
| `resolution/type-loader.yaml` | Type loading protocol to replicate |
| `resolution/workflow-loader.yaml` | Workflow loading protocol to replicate |
| `docs/spoon-core-integration-analysis.md` | Direction B discussion, ADRs 1-5, token model |
| `docs/web3-extension-types-analysis.md` | Extension types that naturally map to private mode, ADRs 6-10 |
| `schema/config/output-config.json` | Output configuration the runtime must support |
| `spoon-core: spoon_ai/graph/engine.py` | Spoon's StateGraph for comparison |
| `spoon-core: spoon_ai/payments/x402_service.py` | x402 for gating private execution |

---

## Comparison: Blueprint Python Runtime vs Spoon StateGraph

| Aspect | BlueprintRuntime | Spoon StateGraph |
|--------|-----------------|-----------------|
| **Source format** | YAML workflow definitions | Python code |
| **Node definition** | YAML node objects | Python callables |
| **Routing** | Static (on_success/on_failure) + dynamic_route | Conditional edges + routing rules + LLM router |
| **State model** | Single mutable dict, dot-notation access | TypedDict with reducer merge |
| **Execution** | Sequential node loop | Async event loop with parallel groups |
| **Checkpointing** | `create_checkpoint`/`rollback_checkpoint` | `Checkpointer` interface (automatic per-step) |
| **Human-in-the-loop** | `user_prompt` node type | `interrupt_before`/`interrupt_after` |
| **Sub-workflows** | `reference` node (inline + spawn) | Nested graphs |
| **Type safety** | JSON Schema validation | Pydantic models |
| **Extensibility** | Extension handler registries | Custom node classes |
| **Portability** | YAML definitions work across runtimes | Python-only |

**Key difference:** BlueprintRuntime is declarative-first (YAML → execution). StateGraph is imperative-first (Python → execution). BlueprintRuntime's advantage is portability: the same YAML works with LLM interpretation (public mode) and Python execution (private mode). StateGraph's advantage is flexibility: any Python callable can be a node.

**They complement, not compete.** SpoonOS can use StateGraph for high-level orchestration and BlueprintRuntime for structured sub-workflows that need portability, verification, or progressive disclosure.

---

## Glossary (additions to previous analyses)

| Term | Definition |
|------|-----------|
| **BlueprintRuntime** | Python interpreter that executes Blueprint YAML workflows without an LLM |
| **Step envelope** | Minimal payload sent to client in progressive mode: prompt, options, deadline |
| **Transition log** | Record of `[node_id, action, state_delta]` produced during workflow execution |
| **Divergence** | Difference between client-reported and server-computed state transitions |
| **Tolerance model** | Classification of expected divergence per consequence type (exact, soft, ignore, critical) |
| **Handler** | Python function implementing a specific consequence type's `effect` semantics |
| **Evaluator** | Python function implementing a specific precondition type's `evaluation` semantics |
| **Public mode** | Client has full YAML, executes via LLM, no server involvement |
| **Verified mode** | Client executes, server re-executes and compares transition logs |
| **Progressive mode** | Server executes, reveals steps incrementally via step envelopes |
| **Private mode** | Server executes everything, client sees only inputs/outputs |
| **Dual execution** | The architectural pattern where the same YAML definitions have two runtimes (LLM + Python) |
| **Hardcoded handler** | Python function per type (as opposed to parsing `effect` pseudocode at runtime) |
