# Antfarm Comparative Analysis: Learnings for hiivmind-blueprint-lib

## Context

This analysis follows the [spoon-core integration analysis](spoon-core-integration-analysis.md) (ADRs 1-5), [web3 extension types analysis](web3-extension-types-analysis.md) (ADRs 6-10), [blueprint python runtime analysis](blueprint-python-runtime-analysis.md) (ADRs 11-15), and [OpenProse comparative analysis](prose-comparative-analysis.md) (ADRs 16-20). It examines Antfarm (`/home/nathanielramm/git/github/antfarm`), a multi-agent workflow orchestration system for software development, for practical learnings applicable to Blueprint-lib.

**This is a research deliverable. No code or schema changes are proposed here.**

## Executive Summary

Antfarm and Blueprint-lib approach workflow orchestration from different domains but share deep structural alignment:

- **Antfarm** is a *multi-agent pipeline system* for software development. Specialized agents (planner, developer, verifier, tester) execute deterministic pipelines coordinated through SQLite, cron polling, and file-based context passing. Agents run in isolated sessions with tool restrictions enforced by role.
- **Blueprint-lib** is a *type definition library* for general-purpose LLM workflows. A single LLM interprets typed consequence/precondition definitions. State flows through `state.computed` within a conversation context.

The key insight: Antfarm has solved practical problems that Blueprint will encounter as it moves toward multi-agent and iterative execution. Antfarm's story-based decomposition, verify-each quality gates, progress file memory, and role-based tool restrictions are battle-tested patterns that map cleanly to Blueprint's type system.

Five ADRs (21-25) propose adopting Antfarm's strongest patterns.

---

## 1. Antfarm Overview

### Architecture

Antfarm runs specialized AI agents autonomously on a single machine. Each workflow is a deterministic pipeline of steps, where each step is executed by a named agent with a specific role (analysis, coding, verification, testing, scanning, PR). Agents poll for work via cron (every 5 minutes, staggered), claim steps, execute in isolated OpenClaw sessions, and report results through structured KEY: value output.

| Component | Implementation |
|-----------|---------------|
| Runtime | TypeScript CLI (~3,000 lines) |
| Database | SQLite (WAL mode, foreign keys) |
| Orchestration | Cron-based polling (no message queue) |
| Agent runtime | OpenClaw (isolated sessions, tool access control) |
| Dashboard | Express.js (localhost:3333) |
| Configuration | YAML workflows + Markdown agent personas |

### Execution Model

```
Planner decomposes task into stories (max 20)
    ↓
Setup agent creates branch, discovers build commands
    ↓
Developer implements stories one at a time (fresh session each)
    ↓ ↑ (retry on failure)
Verifier checks each story against acceptance criteria
    ↓
Tester runs integration/E2E tests
    ↓
PR agent creates pull request
    ↓
Reviewer checks the PR
```

Each agent runs in a **fresh session** with:
- Clean context (no prior conversation history)
- File-based memory (`progress.txt` tracks completed work)
- Git history (commits are the durable record)
- Role-based tool restrictions (verifiers cannot write code)

### Three Bundled Workflows

| Workflow | Pipeline | Key Pattern |
|----------|----------|-------------|
| **feature-dev** | plan → setup → implement ⟳ verify → test → PR → review | Story-based decomposition with verify-each |
| **bug-fix** | triage → investigate → setup → fix → verify → PR | Root cause analysis before fix |
| **security-audit** | scan → prioritize → setup → fix ⟳ verify → test → PR | Vulnerability-as-story decomposition |

### Novel Patterns

**1. Story-Based Decomposition**

The planner agent breaks a task into 3-20 user stories, each sized to fit in one context window. Stories are first-class database entities with id, title, description, acceptance criteria, status, and retry count. The developer claims stories one at a time, works in a fresh session, commits, and moves on.

**2. Verify-Each Quality Gate**

After each story implementation, a separate verifier agent (with read-only + exec access, no write) checks:
- Do tests pass?
- Are acceptance criteria met?
- Does typecheck pass?
- Is there real code (not TODOs)?

If verification fails, the developer retries that story with the verifier's feedback injected into the prompt.

**3. Progress File Memory**

Agents write `progress.txt` to preserve knowledge across sessions:
```
## Codebase Patterns
- Uses Next.js with API routes
- Prisma for ORM

## Completed Stories
US-001: ✓ Database schema
US-002: ✓ API endpoint

## Key Commands
npm test — run tests (jest)
```

New sessions read this file to rebuild context without re-exploring the codebase.

**4. Role-Based Tool Restrictions**

| Role | Read | Write | Execute | Web | Purpose |
|------|------|-------|---------|-----|---------|
| analysis | ✓ | ✗ | ✗ | ✗ | Planning, investigation |
| coding | ✓ | ✓ | ✓ | ✗ | Implementation |
| verification | ✓ | ✗ | ✓ | ✗ | Quality checks (independence) |
| testing | ✓ | ✗ | ✓ | ✓ | E2E testing |
| scanning | ✓ | ✗ | ✓ | ✓ | Security scanning |
| pr | ✓ | ✗ | ✓ | ✗ | PR creation |

The critical insight: **verifiers cannot write code**. This prevents the common anti-pattern where a quality gate silently "fixes" issues instead of sending them back.

**5. Escalation on Exhausted Retries**

When retries are exhausted, the workflow pauses and escalates to a human rather than failing silently or continuing with broken state.

---

## 2. Comparative Analysis

| Aspect | Antfarm | Blueprint-lib | Winner |
|--------|---------|---------------|--------|
| **Domain** | Software development pipelines | General-purpose LLM workflows | Tie (different domains) |
| **Agent model** | Multiple specialized agents with role-based tool access | Single LLM interprets typed definitions | Antfarm (for multi-agent) |
| **Decomposition** | Story-based (planner → developer → verifier) | Node graph (sequential/parallel) | Antfarm (for complex tasks) |
| **Quality gates** | Verify-each with independent verifier agent | Preconditions (boolean checks before execution) | Antfarm |
| **Memory across steps** | Progress files + git history | `state.computed` in conversation context | Antfarm (survives context limits) |
| **Retry semantics** | Per-story retry with feedback injection | None (no retry mechanism) | Antfarm |
| **Type system** | Ad-hoc (KEY: value output parsing) | Formal (43 consequences, 27 preconditions, JSON schemas) | Blueprint |
| **Validation** | Runtime only (output must contain expected string) | Static (JSON Schema) + runtime (3-phase) | Blueprint |
| **Execution model** | Cron polling + SQLite coordination | LLM interprets effect pseudocode | Tie (different trade-offs) |
| **State semantics** | Context variables via template substitution | `state_reads`/`state_writes` declarations | Blueprint |
| **Versioning** | Workflow YAML version field (no pinned deps) | `@v3.1.1` pinned type resolution | Blueprint |
| **Extension model** | Custom workflows in `workflows/` directory | Namespaced extension repos | Blueprint |
| **Dual execution** | LLM-only (OpenClaw agents) | LLM + Python runtime (ADR-11) | Blueprint |
| **Offline operation** | Fully local (SQLite + cron) | Depends on GitHub raw URL fetch | Antfarm |
| **Escalation** | Pause + escalate to human on exhausted retries | None | Antfarm |
| **Dashboard** | Real-time web UI (run status, story progress) | None | Antfarm |

---

## 3. Learnings to Adopt

### ADR-21: Story-Based Decomposition Node Type

**Decision:** Add a `decompose` consequence type that breaks a task into sub-units (stories) with acceptance criteria, enabling loop-based execution over the resulting list.

**Rationale:** Antfarm's strongest pattern is story-based decomposition: a planner agent breaks a complex task into small, independently verifiable units, each sized to fit in one LLM context window. Blueprint has no equivalent. The `loop` node type can iterate, but there is no typed mechanism for:
1. Decomposing a task into structured sub-units
2. Tracking individual sub-unit status (pending/running/done/failed)
3. Injecting per-unit context into each loop iteration

Currently, a Blueprint workflow author would need to hand-code decomposition logic in effect pseudocode with no schema validation of the output structure.

```yaml
# Proposed consequence type
decompose:
  description:
    brief: "Decompose a task into structured sub-units with acceptance criteria"
    detailed: |
      Breaks a complex task into an ordered list of sub-units, each with
      an ID, title, description, and acceptance criteria. Sub-units are
      stored in state for iteration by loop nodes. The LLM determines
      the decomposition; the type enforces the output structure.
  category: workflow_control
  parameters:
    - name: task_description
      type: string
      required: true
      description: "The task to decompose"
    - name: max_units
      type: number
      required: false
      default: 20
      description: "Maximum number of sub-units"
    - name: store_as
      type: string
      required: true
      description: "State key for the sub-unit list"
    - name: constraints
      type: array
      required: false
      description: "Constraints for decomposition (e.g., 'each must fit in one context window')"
  payload:
    kind: composite
    effect: |
      units = **decompose task_description into ordered sub-units, each with:**
        **- id (string)**
        **- title (string)**
        **- description (string)**
        **- acceptance_criteria (array of strings)**
      **Enforce: max_units cap, dependency ordering, each unit independently verifiable**
      state.computed[params.store_as] = units
```

The `**...**` markers (ADR-19) indicate the decomposition itself requires LLM judgment, while the output structure is deterministic.

**Implementation sketch:**
- New consequence type in `consequences/consequences.yaml`
- Loop node iterates over `state.computed[store_as]`
- Each iteration receives `current_unit` in context (like Antfarm's `{{current_story}}`)
- Python runtime: LLM call for decomposition, schema validation of output structure

**Consequences:**
- Enables Antfarm-style story-based workflows in Blueprint
- Sub-unit status tracking requires state structure (array of objects with status field)
- Combines with ADR-18 (cross-run persistence) for multi-session decomposed workflows
- Does NOT replace the `loop` node type — `decompose` produces the list, `loop` iterates it

**Priority: P1** — Unlocks complex multi-step workflows. Medium effort.

---

### ADR-22: Verification Gate Precondition

**Decision:** Add a `verification_gate` precondition type that invokes an independent verification step before allowing a node to proceed.

**Rationale:** Antfarm's verify-each pattern is its strongest quality mechanism: after each story implementation, an independent agent (with read-only access) checks the work against acceptance criteria. If verification fails, the story is retried with specific feedback.

Blueprint's preconditions are boolean checks (`state_check`, `tool_check`, `path_check`). None of them can:
1. Invoke an LLM evaluation with custom criteria
2. Produce structured feedback on failure (not just pass/fail)
3. Route failure back to the producing node with the feedback

```yaml
# Proposed precondition type
verification_gate:
  description:
    brief: "Verify prior step output against acceptance criteria before proceeding"
    detailed: |
      Evaluates the output of a prior node against specified acceptance
      criteria. On failure, produces structured feedback that can be
      injected into a retry of the producing node. The verification
      is independent — it cannot modify the artifact being verified.
  category: quality
  parameters:
    - name: artifact
      type: string
      required: true
      description: "State key containing the output to verify"
    - name: criteria
      type: array
      required: true
      description: "List of acceptance criteria to check"
    - name: feedback_key
      type: string
      required: false
      description: "State key to store feedback on failure"
  evaluation:
    effect: |
      artifact_value = get_nested(state, params.artifact)
      result = **evaluate artifact_value against each criterion in params.criteria**
      **For each criterion: PASS, FAIL with specific reason**
      if all criteria pass:
        return T
      else:
        if params.feedback_key:
          state.computed[params.feedback_key] = result.failures
        return F
```

**Implementation sketch:**
- New precondition type in `preconditions/preconditions.yaml`
- On failure: stores structured feedback in `state.computed[feedback_key]`
- Loop nodes can use `feedback_key` to inject verification feedback into retry iterations
- Python runtime: LLM call for evaluation (judgment required), structured output parsing
- Key constraint: verification is **read-only** — it cannot modify the artifact

**Consequences:**
- Enables Antfarm's verify-each pattern in Blueprint workflows
- Feedback injection into retries requires loop node awareness of `feedback_key`
- The read-only constraint mirrors Antfarm's role separation (verifier cannot write)
- Combines with ADR-21 (decompose) for full story → implement → verify loops

**Priority: P1** — Quality gates are essential for reliable multi-step workflows. Medium effort.

---

### ADR-23: Retry Semantics with Feedback Injection

**Decision:** Add `retry` configuration to action nodes with feedback injection from failed preconditions or prior attempts.

**Rationale:** Antfarm handles failure gracefully: when a verifier rejects a story, the developer gets the specific failure feedback in its next attempt's prompt (`{{verify_feedback}}`). Blueprint has no retry mechanism — a failed node fails the workflow.

```yaml
# Proposed node-level retry configuration
nodes:
  - id: implement_story
    type: action
    retry:
      max_attempts: 3
      feedback_from: "verification_feedback"    # State key from verification_gate
      on_exhausted: pause                       # pause | fail | skip
    consequences:
      - type: run_command
        command: "implement the current story"
    preconditions:
      - type: verification_gate
        artifact: "current_implementation"
        criteria: ["tests pass", "acceptance criteria met"]
        feedback_key: "verification_feedback"
```

**Implementation sketch:**
- `retry` config block on action nodes (optional)
- `max_attempts`: integer (default 1, no retry)
- `feedback_from`: state key injected into the node's context on retry
- `on_exhausted`: `pause` (Antfarm-style escalation), `fail` (current behavior), `skip`
- Python runtime: loop with attempt counter, feedback injection into consequence parameters
- LLM runtime: execution semantics describe retry loop with feedback context

**Consequences:**
- `pause` introduces a new workflow state (paused, awaiting human input) — aligns with ADR-18 (persistence) for resumable workflows
- Feedback injection means action nodes must accept a `prior_feedback` context parameter
- Combines with ADR-22 (verification gate) for the full verify → feedback → retry loop
- Does NOT add automatic retry for transient failures (network errors, rate limits) — that's a runtime concern, not a type concern

**Priority: P1** — Retry with feedback is the minimum viable quality loop. Small-medium effort.

---

### ADR-24: Role-Based Capability Restrictions

**Decision:** Add a `capabilities` declaration to workflow node definitions that restricts which consequence types a node may execute.

**Rationale:** Antfarm's role system (analysis, coding, verification, testing, scanning, PR) enforces that agents can only use tools appropriate to their role. The critical insight: **verifiers cannot write code**. This prevents quality gates from silently "fixing" issues, preserving the separation between production and verification.

Blueprint has no equivalent. Any node can execute any consequence type. A verification node could invoke `mutate_state`, `run_command`, or `local_file_ops` with write operations — undermining the independence of the quality check.

```yaml
# Proposed capabilities declaration on nodes
nodes:
  - id: verify_implementation
    type: action
    capabilities:
      allow: [state_check, display, log_node]           # Whitelist
      deny: [mutate_state, run_command, local_file_ops]  # Or blacklist
      # One of allow/deny, not both
    consequences:
      - type: display
        format: text
        content: "Verification result: {{result}}"
```

**Implementation sketch:**
- `capabilities` config block on nodes (optional — no restriction if omitted)
- Either `allow` (whitelist) or `deny` (blacklist) list of consequence type names
- Validated during init phase (3-phase execution catches violations before runtime)
- Python runtime: type check before consequence dispatch
- LLM runtime: instruction in execution semantics to refuse restricted consequences

**Roles as capability presets** (convenience, not required):

```yaml
# Possible role presets (defined in execution semantics, not as types)
roles:
  analysis:
    allow: [display, log_node, state_check, evaluate_keywords]
  coding:
    allow: [mutate_state, run_command, local_file_ops, git_ops_local, display, log_node]
  verification:
    allow: [state_check, path_check, tool_check, display, log_node]
    deny: [mutate_state, local_file_ops, run_command]
```

**Consequences:**
- Static validation catches capability violations in init phase (before execution)
- Enables Antfarm-style role separation without requiring multiple agents
- A single LLM can play different "roles" at different nodes by restricting its available actions
- Presets are optional sugar — the raw allow/deny mechanism is the primitive

**Priority: P2** — Important for trust but requires careful design of the preset system. Medium effort.

---

### ADR-25: Progress Accumulator Pattern

**Decision:** Add an `accumulate` consequence type that appends structured entries to a growing state field, enabling Antfarm's progress file pattern within Blueprint's state system.

**Rationale:** Antfarm's `progress.txt` is a simple but powerful pattern: each agent session appends what it learned (codebase patterns, completed work, key commands) to a file that subsequent sessions read. This provides continuity across fresh sessions without carrying full conversation history.

Blueprint's `mutate_state` with `operation: set` overwrites. With `operation: append`, it adds to an array. Neither produces the structured, human-readable progress log that Antfarm's agents rely on for context reconstruction.

```yaml
# Proposed consequence type
accumulate:
  description:
    brief: "Append a structured entry to a growing progress log in state"
    detailed: |
      Adds a timestamped, categorized entry to a progress field in state.
      Designed for cross-iteration knowledge accumulation in loop workflows.
      Each entry has a category (pattern, completion, command, insight) and
      content. The accumulated log serves as context for subsequent iterations.
  category: state
  parameters:
    - name: field
      type: string
      required: true
      description: "State field to accumulate into"
    - name: category
      type: string
      required: true
      description: "Entry category (e.g., 'pattern', 'completed', 'command', 'insight')"
    - name: content
      type: string
      required: true
      description: "Entry content"
    - name: format
      type: string
      required: false
      default: "structured"
      description: "Output format: 'structured' (JSON entries) or 'markdown' (human-readable)"
  payload:
    kind: state_mutation
    effect: |
      entry = {
        category: params.category,
        content: params.content,
        timestamp: now(),
        iteration: state.loop_index  # if in a loop
      }
      if params.format == "markdown":
        state.computed[params.field] += render_markdown(entry)
      else:
        state.computed[params.field].entries.append(entry)
```

**Implementation sketch:**
- New consequence type in `consequences/consequences.yaml`
- Markdown format produces Antfarm-style progress output:
  ```
  ## Patterns
  - Uses Next.js with API routes (iteration 1)
  ## Completed
  - ✓ Database schema (iteration 1)
  - ✓ API endpoint (iteration 2)
  ```
- Structured format produces queryable JSON entries
- Python runtime: straightforward state append
- LLM runtime: state mutation with append semantics
- Combines with ADR-16 (reference storage) — large progress logs can use `store_mode: reference`

**Consequences:**
- Solves the "fresh session per iteration" memory problem for loop nodes
- Markdown format is immediately useful as LLM context (human-readable)
- Structured format enables programmatic querying in Python runtime
- Does NOT replace `mutate_state` (append) — `accumulate` is specifically for categorized progress logging

**Priority: P2** — Valuable for loop-heavy workflows. Small effort.

---

## 4. Where Blueprint Is Stronger

### Formal Type System

Antfarm's inter-agent communication is ad-hoc: agents output KEY: value lines, and downstream agents receive them via `{{placeholder}}` substitution. There is no schema for what keys an agent should produce or what types the values should be. A planner that outputs `STORIES_JSON` with a typo in the JSON structure causes a runtime failure with no static detection.

Blueprint's 43 consequence types and 27 precondition types with JSON schemas catch structural errors before execution. **Keep as-is.**

### Static Validation (3-Phase Execution)

Antfarm validates at runtime: if an agent's output doesn't contain the expected string, the step fails. Blueprint's init phase validates the entire workflow graph before any execution begins — missing types, invalid parameters, and broken edges are caught immediately. **Keep as-is.**

### Deterministic State Semantics

Antfarm's context is a flat key-value map with template substitution. Name collisions between agent outputs silently overwrite. Blueprint's `state_reads`/`state_writes` declarations enable the Python runtime to validate state flow at parse time and detect conflicts. **Keep as-is.**

### Version-Pinned Type Resolution

Antfarm workflows have a `version` field but no mechanism for pinning dependency versions. Blueprint's `@v3.1.1` resolution ensures reproducible execution. **Keep as-is.**

### Dual Execution Model

Antfarm is LLM-only — agents are OpenClaw sessions executing in real time. There is no path to deterministic execution without an LLM. Blueprint's dual execution (ADR-11) enables verified and private modes. **Keep as-is.**

### Extension Namespace Isolation

Antfarm's custom workflows live in a flat `workflows/` directory with no namespace isolation. Blueprint's extension repos (`blueprint-web3-identity`, `blueprint-web3-escrow`) prevent type name collisions across independent extension authors. **Keep as-is.**

---

## 5. What Not to Adopt

### Cron-Based Polling

Antfarm agents poll for work every 5 minutes via cron. This is appropriate for autonomous, long-running software development where latency tolerance is high. Blueprint workflows execute synchronously within a conversation — adding polling would introduce unnecessary latency and complexity for the interactive use case.

### Agent-Per-Step Model

Antfarm spawns a separate OpenClaw agent for each role. Blueprint uses a single LLM interpreting typed definitions. The multi-agent overhead (session setup, workspace provisioning, cron management) is justified for Antfarm's software development domain but excessive for Blueprint's general-purpose workflows. ADR-24 (role-based capabilities) achieves the key benefit (separation of concerns) without multi-agent overhead.

### SQLite Coordination

Antfarm uses SQLite as the coordination layer between agents. Blueprint's state management is in-memory (conversation context) or file-based (ADR-16, ADR-18). Adding a database would be over-engineering for Blueprint's execution model.

### KEY: value Output Parsing

Antfarm's output format (`STATUS: done\nREPO: /path`) is ad-hoc and fragile — multi-line values require special handling, and there's no schema validation. Blueprint's typed consequences with structured parameters are strictly superior.

### Fresh Session Per Step (as default)

Antfarm forces fresh sessions per step to prevent context window bloat. This makes sense when agents are long-running autonomous processes. Blueprint workflows typically execute within a single conversation where context continuity is valuable. ADR-16 (reference storage) and ADR-25 (progress accumulator) solve the context bloat problem without losing conversational continuity.

---

## 6. Priority and Sequencing

| Priority | ADR | Effort | Dependencies |
|----------|-----|--------|--------------|
| **P1** | ADR-21: Story-based decomposition | Medium | ADR-19 (judgment markers in decomposition logic) |
| **P1** | ADR-22: Verification gate | Medium | None |
| **P1** | ADR-23: Retry with feedback | Small-Medium | ADR-22 (feedback source) |
| **P2** | ADR-24: Role-based capabilities | Medium | None |
| **P2** | ADR-25: Progress accumulator | Small | ADR-16 (reference storage for large logs) |

**Recommended sequence:**

1. **ADR-22 + ADR-23** (sequential) — Verification gates first, then retry semantics that consume their feedback. Together they form the minimum viable quality loop.
2. **ADR-21** — Decomposition type. Combines with the verify/retry loop from step 1 for full Antfarm-style story workflows.
3. **ADR-25** — Progress accumulator. Enables loop iterations to build context for subsequent iterations.
4. **ADR-24** — Role-based capabilities. Important for trust but can be deferred until multi-step workflows are in production and the role presets are informed by real usage patterns.

**Combined with prior ADRs, the full implementation order across all analyses:**

| Phase | ADRs | Theme |
|-------|------|-------|
| Phase 1 | ADR-16 (reference state), ADR-19 (judgment markers) | Context efficiency |
| Phase 2 | ADR-22 (verification gate), ADR-23 (retry + feedback) | Quality loop |
| Phase 3 | ADR-17 (inline blocks), ADR-21 (decomposition) | Workflow structure |
| Phase 4 | ADR-25 (progress accumulator), ADR-18 (persistence) | Memory across runs |
| Phase 5 | ADR-24 (role capabilities), ADR-20 (embedded fallback) | Trust and resilience |

---

## 7. Relationship to Prior ADRs

| This ADR | Relates To | Relationship |
|----------|-----------|--------------|
| ADR-21 (decomposition) | ADR-19 (judgment markers) | Decomposition logic uses `**...**` markers — the task breakdown requires LLM judgment, the output structure is deterministic |
| ADR-21 (decomposition) | ADR-11 (Python runtime) | Python runtime calls LLM for decomposition, validates output structure against schema |
| ADR-22 (verification gate) | ADR-14 (verification tolerance) | Verification gate evaluation uses SOFT tolerance — acceptance criteria are semantic, not exact |
| ADR-22 (verification gate) | ADR-24 (role capabilities) | Verification nodes should use `deny: [mutate_state]` to enforce read-only verification |
| ADR-23 (retry + feedback) | ADR-18 (persistence) | `on_exhausted: pause` requires workflow state persistence for later human resumption |
| ADR-23 (retry + feedback) | ADR-22 (verification gate) | Retry consumes feedback from verification gate failures |
| ADR-24 (role capabilities) | ADR-3 (spawn mode) | Spawn mode provides process-level isolation; capabilities provide type-level restriction within a single process |
| ADR-24 (role capabilities) | ADR-15 (private mode) | Private mode workflows may require stricter capability restrictions (no display, no web_ops) |
| ADR-25 (progress accumulator) | ADR-16 (reference storage) | Large progress logs should use `store_mode: reference` to avoid context bloat |
| ADR-25 (progress accumulator) | ADR-18 (persistence) | Progress accumulation across runs requires cross-run persistence |

---

## 8. The Footy Tipping Thread

The AFL footy tipping competition (introduced in the web3 analysis) continues to serve as a grounding use case. With this analysis's ADRs:

**Weekly tip submission workflow (enhanced):**

```yaml
# With ADRs 21-25 applied
workflow:
  persistence:                              # ADR-18
    scope: project
    fields: [registered_users, round_state, tip_history]

  nodes:
    - id: decompose_round
      type: action
      consequences:
        - type: decompose                   # ADR-21
          task_description: "Process tips for round {{current_round}}"
          store_as: tip_tasks
          constraints:
            - "One task per registered user"
            - "Each task: validate tip, record, update leaderboard"

    - id: process_tips
      type: loop
      over: "computed.tip_tasks"
      retry:                                # ADR-23
        max_attempts: 2
        feedback_from: "tip_verification_feedback"
        on_exhausted: pause
      capabilities:                         # ADR-24
        deny: [web_ops, spawn_agent]        # Tips processing is local only
      consequences:
        - type: accumulate                  # ADR-25
          field: "round_progress"
          category: "completed"
          content: "Processed tip for {{current_unit.user_id}}"
      preconditions:
        - type: verification_gate           # ADR-22
          artifact: "current_tip_result"
          criteria:
            - "Tip is for a valid match in the current round"
            - "User has not already tipped for this match"
            - "Tip was submitted before lockout time"
          feedback_key: "tip_verification_feedback"
```

This combines story-based decomposition (one task per user), verification gates (tip validity), retry with feedback (re-validate on failure), role restrictions (no external web calls), and progress accumulation (track which users are processed).

---

## Glossary

| Term | Definition |
|------|-----------|
| **Antfarm** | Multi-agent workflow orchestration system for software development, built on OpenClaw |
| **OpenClaw** | Local AI agent runtime that manages agent sessions, tool access, and workspaces |
| **Story-based decomposition** | Breaking a complex task into small, independently verifiable sub-units sized for one context window |
| **Verify-each** | Quality gate pattern where each sub-unit is independently verified before proceeding to the next |
| **Progress file** | Append-only file tracking completed work, discovered patterns, and useful commands across agent sessions |
| **Role-based tool restriction** | Limiting which tools/actions an agent can use based on its role (analysis, coding, verification, etc.) |
| **Escalation** | Pausing a workflow and routing to a human when automated retries are exhausted |
| **Fresh session** | Starting each agent execution with a clean context window (no prior conversation history) |
| **Feedback injection** | Including specific failure reasons from a verification step in the prompt for a retry attempt |
| **Capability restriction** | Limiting which consequence types a Blueprint node may execute, analogous to Antfarm's role-based tool restrictions |
