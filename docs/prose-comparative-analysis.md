# OpenProse Comparative Analysis: Learnings for hiivmind-blueprint-lib

## Context

This analysis follows the [spoon-core integration analysis](spoon-core-integration-analysis.md) (ADRs 1-5), [web3 extension types analysis](web3-extension-types-analysis.md) (ADRs 6-10), and [blueprint python runtime analysis](blueprint-python-runtime-analysis.md) (ADRs 11-15). It examines OpenProse (`/home/nathanielramm/git/github/prose`), an LLM-native workflow DSL, for practical learnings applicable to Blueprint-lib.

**This is a research deliverable. No code or schema changes are proposed here.**

## Executive Summary

OpenProse and Blueprint-lib solve the same problem — orchestrating LLM-powered workflows — from opposite ends:

- **OpenProse** is a *language specification* where "the LLM session IS the runtime." It defines a virtual machine via prose that, when read by a capable LLM system, causes that system to *become* the VM. No formal types, no schemas, no traditional runtime.
- **Blueprint-lib** is a *type definition library* with formal schemas, dual execution (LLM + Python), and version-pinned resolution. Structure enables static validation but adds overhead.

Neither approach dominates. OpenProse excels at keeping context windows lean (reference-based state), intra-workflow reuse (blocks), and marking where LLM judgment is needed (`**...**` syntax). Blueprint excels at validation, deterministic execution, versioned composition, and extension isolation.

Five ADRs (16-20) propose adopting OpenProse's strongest ideas without compromising Blueprint's type system.

---

## 1. OpenProse Overview

### Architecture

OpenProse defines a VM specification (`prose.md`) that transforms a "Prose Complete" system (Claude Code + Opus, OpenCode + Opus, Amp + Opus) into a workflow executor. The specification is detailed enough that reading it causes the LLM to simulate/embody the VM — "simulation with sufficient fidelity IS implementation."

| Traditional Component | OpenProse VM | Substrate |
|---|---|---|
| Instructions | `.prose` statements | Executed via Task tool calls |
| Program counter | Execution position | Tracked in `state.md` |
| Working memory | Conversation history | Context window |
| Persistent storage | `.prose/` directory | Files on disk |
| Variables | Named bindings | `bindings/{name}.md` files |

### Execution Model

Each `session` statement spawns a real subagent via the Task tool. Control flow (sequential, parallel, loops, choice) is explicit in the `.prose` syntax. State is passed **by reference** — file paths, not full content — keeping token usage bounded.

### Key Innovations

1. **Reference-based context**: Variables store file paths, not values. `context: research` passes a path to `bindings/research.md`, not the content itself.

2. **Block definitions**: Reusable intra-workflow functions that avoid the overhead of separate files or repos:
   ```prose
   block review(artifact):
     let feedback = session "Review {artifact}"
     session "Revise based on feedback"
       context: feedback
   do review("the API doc")
   ```

3. **Fourth-wall syntax** (`**...**`): Marks where the LLM should apply judgment vs. execute deterministically:
   ```prose
   loop until **the code is production ready** (max: 20):
     session "Fix the next failing test"
   ```

4. **Multi-scope persistence**: Agent memory persists at session, project, or user scope:
   ```prose
   agent captain:
     model: opus
     persist: true       # session scope
     persist: "project"  # project scope
     persist: "user"     # user scope (cross-project)
   ```

5. **Self-contained programs**: `.prose` files carry everything needed to execute — no external type resolution required.

### State Backends

OpenProse offers four pluggable state backends:

| Backend | Use Case | Trade-offs |
|---------|----------|------------|
| File-system (default) | Most workflows | Simple, portable, append-only |
| In-context (narration) | Small programs (<30 statements) | No disk I/O, limited by context window |
| SQLite (experimental) | Query-safe, transactional | Local only, single-writer |
| PostgreSQL (experimental) | Concurrent, networked | External dependency, setup overhead |

---

## 2. Comparative Analysis

| Aspect | OpenProse | Blueprint-lib | Winner |
|--------|-----------|---------------|--------|
| **Type system** | Implicit (duck typing) | 43 consequences, 27 preconditions, 5 node types, JSON schemas | Blueprint |
| **Static validation** | None — programs validated at runtime | JSON Schema validation before execution | Blueprint |
| **Context efficiency** | Reference-based (file paths, not values) | Full values stored in `state.computed` | OpenProse |
| **Intra-workflow reuse** | `block` definitions (inline functions) | `reference` node (requires separate file) | OpenProse |
| **Cross-run persistence** | 3-scope agent memory (session/project/user) | None — fresh state every run | OpenProse |
| **LLM judgment marking** | Explicit `**...**` syntax | Mixed into `effect` pseudocode, unmarked | OpenProse |
| **Offline resilience** | Self-contained `.prose` files | Depends on GitHub raw URL fetch | OpenProse |
| **Dual execution** | LLM-only | LLM + Python runtime (ADR-11) | Blueprint |
| **Deterministic semantics** | Append-only log, no `get_nested`/`set_nested` | `state_reads`/`state_writes` declarations | Blueprint |
| **Version pinning** | Registry has no versioning | `@v3.1.1` pinned resolution | Blueprint |
| **Execution phases** | Single-pass | 3-phase (init/execute/complete) | Blueprint |
| **Extension isolation** | Flat `use` imports | Namespaced extension repos | Blueprint |
| **Composition** | `use "alice/research"` (program imports) | `definitions` block with versioned URLs | Blueprint |
| **Error handling** | try/catch/finally, retry, backoff | Node-level `on_error` | Tie |
| **Parallel execution** | First-class `parallel` blocks | `parallel_group` node type | Tie |

---

## 3. Learnings to Adopt

### ADR-16: Reference-Based State Storage

**Decision:** Add `store_mode: reference` option to consequences that produce large outputs (`web_ops`, `local_file_ops`, `run_command`, `spawn_agent`).

**Rationale:** OpenProse passes file paths as context, not file contents. Blueprint stores full values in `state.computed`, which the LLM must carry in its context window. A 50KB web fetch result stored in state consumes ~12,500 tokens on every subsequent step — even if the result is only needed once.

With `store_mode: reference`, the consequence writes output to a working directory and stores the path in state. Downstream consequences that need the content use `local_file_ops` (operation: read) to retrieve it on demand.

```yaml
# Current behavior (store_mode: value, the default)
web_ops:
  operation: fetch
  url: "https://example.com/large-page"
  store_as: page_content    # Full HTML stored in state.computed.page_content

# New behavior (store_mode: reference)
web_ops:
  operation: fetch
  url: "https://example.com/large-page"
  store_as: page_content
  store_mode: reference      # Path stored: state.computed.page_content = ".blueprint/artifacts/page_content.md"
```

**Implementation sketch:**
- Add `store_mode` parameter (enum: `value` | `reference`, default: `value`) to consequence definition schema
- Applicable to: `web_ops`, `local_file_ops`, `run_command`, `spawn_agent`, `mcp_tool_call`
- Working directory: `.blueprint/artifacts/` (mirrors OpenProse's `.prose/runs/*/bindings/`)
- Python runtime: trivial — write to file, store path
- LLM runtime: `effect` pseudocode branches on `store_mode`

**Consequences:**
- Breaks no existing workflows (default remains `value`)
- Context window savings proportional to output size × downstream step count
- Requires `.blueprint/` directory convention (new)
- Aligns with Python runtime's file I/O capabilities (ADR-11)

**Priority: P0** — Directly improves LLM execution quality for existing workflows.

---

### ADR-17: Inline Block Definitions

**Decision:** Add `blocks` section to workflow definitions and a `block_invoke` node type (6th node type).

**Rationale:** OpenProse's `block` construct solves a real problem: reusable patterns within a single workflow. Blueprint's current options are:

1. **Duplicate the node sequence** — violates DRY, error-prone
2. **Extract to a separate workflow + `reference` node** — high overhead for small patterns (new file, new repo entry, version management)

A `blocks` section defines named node sequences inline. A `block_invoke` node calls them with parameter substitution.

```yaml
workflow:
  blocks:
    validate_and_store:
      parameters:
        - name: input_field
        - name: target_field
      nodes:
        - id: validate
          type: action
          consequences:
            - type: validate_input
              field: "{{input_field}}"
        - id: store
          type: action
          consequences:
            - type: mutate_state
              operation: set
              field: "{{target_field}}"
              value_from: "computed.validated"

  nodes:
    - id: validate_name
      type: block_invoke
      block: validate_and_store
      arguments:
        input_field: user.name
        target_field: validated_name

    - id: validate_email
      type: block_invoke
      block: validate_and_store
      arguments:
        input_field: user.email
        target_field: validated_email
```

**Implementation sketch:**
- `blocks` section at workflow top level (peer to `nodes`, `definitions`)
- `block_invoke` node type with `block` (name) and `arguments` (map) fields
- Blocks share parent workflow state (no isolation — unlike `reference` which uses `mode: spawn`)
- Python runtime: inline expansion at parse time (macro-style)
- LLM runtime: described in execution semantics as "execute the named block's nodes in sequence"

**Consequences:**
- 6th node type (alongside action, decision, parallel_group, loop, reference)
- Schema additions: `block-definition.json`, `block-invoke-node.json`
- No impact on existing workflows (purely additive)
- Blocks are NOT independently versionable — that's what `reference` is for

**Priority: P1** — Reduces duplication in complex workflows.

---

### ADR-18: Cross-Run State Persistence

**Decision:** Add `persistence` configuration to workflows with scope (session/project/user) and field whitelist.

**Rationale:** OpenProse agents can persist memory across runs at three scopes. Blueprint starts from scratch every execution, which breaks iterative use cases:

- **Footy tipping**: Weekly tip submissions must remember registered users, previous tips, and round state
- **Onboarding**: Multi-session onboarding must remember completed steps
- **Learning workflows**: Spaced repetition requires cross-session progress tracking

```yaml
workflow:
  persistence:
    scope: project                    # session | project | user
    fields:                           # Whitelist — only these fields persist
      - registered_users
      - previous_tips
      - current_round
    storage: ".blueprint/state/"      # Default location
    ttl: "30d"                        # Optional expiry
```

**Implementation sketch:**
- `persistence` config block in workflow definition
- On workflow start: load persisted fields into `state.computed` (before init phase)
- On workflow complete: write whitelisted fields to storage
- Python runtime: JSON files in `.blueprint/state/{workflow_name}/`
- LLM runtime: instruction in execution semantics to check for prior state
- Field whitelist prevents accidental persistence of transient data

**Consequences:**
- New schema: `persistence-config.json`
- Security consideration: persisted state must not leak across trust boundaries (per ADR-3, financial ops use spawn mode)
- Aligns with OpenProse's 3-scope model but starts with project scope only
- Enables the footy tipping weekly-tips use case (web3 analysis, Section 4)

**Priority: P2** — Large effort, but unlocks iterative workflow patterns.

---

### ADR-19: Judgment Markers in Effect Pseudocode

**Decision:** Adopt `**...**` convention in `effect` pseudocode blocks to mark where LLM reasoning/judgment is required vs. deterministic operations.

**Rationale:** OpenProse's "fourth wall" syntax explicitly separates structured execution from LLM discretion. Blueprint's `effect` blocks mix both without distinction:

```yaml
# Current: no distinction between deterministic and judgment operations
effect: |
  parsed = extract_entities(params.text)          # Deterministic
  relevant = filter_by_relevance(parsed, context)  # Judgment needed — but how would Python runtime know?
  state.computed[params.store_as] = relevant

# Proposed: judgment markers
effect: |
  parsed = extract_entities(params.text)
  relevant = **filter by relevance to the current context**
  state.computed[params.store_as] = relevant
```

This distinction is critical for the Python runtime (ADR-11): judgment-marked operations route to LLM calls, while unmarked operations map to deterministic Python handlers.

**Implementation sketch:**
- Convention only — no schema change required
- `**text**` in effect blocks = "LLM evaluates this semantically"
- Unmarked operations = deterministic (Python handler or direct execution)
- Document in execution semantics (`execution/engine_execution.yaml`)
- Gradually adopt across existing type definitions

**Consequences:**
- Zero breaking changes (existing effect blocks work as-is — all-unmarked = all-LLM, current behavior)
- Enables Python runtime to auto-detect which operations need LLM fallback
- Makes effect blocks more readable for human authors
- Aligns with OpenProse's proven pattern

**Priority: P1** — Small effort, high impact on Python runtime handler mapping.

---

### ADR-20: Embedded Type Fallback

**Decision:** Allow `definitions.embedded_types` as an offline fallback when remote type resolution fails.

**Rationale:** Blueprint workflows resolve types from versioned GitHub raw URLs:

```yaml
definitions:
  source: "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v3.1.1/"
```

This creates a single point of failure — GitHub outages, rate limiting, or air-gapped environments prevent workflow execution. OpenProse programs are fully self-contained: the `.prose` file carries everything needed.

Full self-containment would sacrifice Blueprint's versioned resolution and deduplication. Instead, allow an optional `embedded_types` fallback:

```yaml
definitions:
  source: "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v3.1.1/"
  embedded_types:                          # Optional fallback
    web_ops:
      description:
        brief: "Perform web operations"
      parameters:
        - name: operation
          type: string
          required: true
      payload:
        kind: tool_call
        effect: |
          # ... full effect block
```

Resolution order: remote source → embedded fallback → error.

**Implementation sketch:**
- `embedded_types` key in `definitions` block (optional)
- Schema addition (pre-v7.0.0: was `schema/resolution/`, now eliminated)
- Python runtime: try remote fetch, fall back to embedded
- LLM runtime: instruction in execution semantics for fallback order
- Tooling: `blueprint pack` command could auto-generate `embedded_types` from a resolved workflow

**Consequences:**
- Workflows remain functional during GitHub outages
- Air-gapped and CI/CD environments can use Blueprint without network access
- File size increases for workflows with embedded types
- Version drift risk if embedded types are not kept in sync (mitigated by `blueprint pack` tooling)

**Priority: P2** — Medium effort, important for production resilience.

---

## 4. Where Blueprint Is Stronger

### Formal Type System

Blueprint's 43 consequence types, 27 precondition types, and JSON schemas enable **static validation before execution**. OpenProse validates nothing until runtime — a typo in a session prompt is only caught when that session executes, potentially after expensive prior steps. Blueprint catches structural errors in the init phase.

**Keep as-is.** The type system is Blueprint's core differentiator.

### Dual Execution Model

Per ADR-11, Blueprint workflows can execute in LLM mode (public) or Python mode (private/verified). OpenProse is LLM-only — there is no path to deterministic execution, no verified mode, no way to run workflows without an LLM. For the footy tipping use case, round resolution MUST be deterministic (real money is involved).

**Keep as-is.** Dual execution enables trust levels that OpenProse cannot provide.

### Deterministic State Semantics

Blueprint type definitions declare `state_reads` and `state_writes`, enabling the Python runtime to validate state flow at parse time. OpenProse uses implicit filesystem conventions — variables exist when a binding file exists. There is no way to statically analyze data flow in an OpenProse program.

**Keep as-is.** Explicit state semantics enable the Python runtime's handler mapping.

### Version-Pinned Type Resolution

Blueprint workflows pin to specific versions (`@v3.1.1`). OpenProse's `p.prose.md` registry has no versioning — `use "alice/research"` always fetches latest. This means a program that worked yesterday may break today because a dependency changed.

**Keep as-is.** Versioning is essential for reproducible workflows.

### Three-Phase Execution

Blueprint's init/execute/complete model validates workflow structure before execution. OpenProse runs statements sequentially with no pre-validation — invalid control flow is discovered mid-execution.

**Keep as-is.** Pre-validation prevents wasted compute on invalid workflows.

### Extension Namespace Isolation

Blueprint extensions use namespaced repos (`blueprint-web3-identity`, `blueprint-web3-escrow`). OpenProse uses flat `use` imports with no namespace isolation. In a typed system with 50+ types across multiple extension repos, flat imports would cause name collisions.

**Keep as-is.** Namespacing scales; flat imports don't.

---

## 5. What Not to Adopt

### Imperative English DSL

OpenProse programs read like structured English:
```prose
session "Review the code for security issues"
  context: codebase
```

This is elegant for LLM-only execution but **breaks Python runtime parseability** (ADR-11). Blueprint's YAML + pseudocode structure is machine-parseable by both LLM and Python runtimes. Adopting prose-style syntax would require a natural language parser — solving a harder problem than the one Blueprint already solves.

### No Type System

OpenProse's lack of types means programs are only validated by execution. For Blueprint, removing the type system would eliminate static validation (the core value proposition), break JSON Schema compliance checks, prevent the Python runtime from mapping types to handlers, and remove version-pinned resolution.

### Session-as-VM Pattern

OpenProse's entire execution model relies on the LLM faithfully simulating a virtual machine from a specification. This is fragile with smaller models (the spec requires Opus-class capability) and impossible in the Python runtime. Blueprint's declarative approach works with any model that can interpret simple pseudocode.

### Append-Only State Replacement

OpenProse's file-system state is append-only — execution logs grow monotonically. Blueprint's `state.computed` uses `get_nested`/`set_nested` for structured state mutations. Replacing this with append-only semantics would break the Python runtime's state management and the `mutate_state` consequence type.

### Flat Namespace Imports

OpenProse's `use "alice/research"` provides no namespace isolation. In Blueprint's ecosystem with core types (43), web3 identity types, web3 escrow types, and future extensions, flat imports would create collision risks. The namespaced extension repo pattern (ADR-7) scales better.

---

## 6. Priority and Sequencing

| Priority | ADR | Effort | Dependencies |
|----------|-----|--------|--------------|
| **P0** | ADR-16: Reference-based state | Medium | None — can implement immediately |
| **P1** | ADR-19: Judgment markers | Small | None — convention, no schema change |
| **P1** | ADR-17: Inline blocks | Medium | Schema additions required |
| **P2** | ADR-18: Cross-run persistence | Large | ADR-16 (uses `.blueprint/` directory convention) |
| **P2** | ADR-20: Embedded type fallback | Medium | Schema additions to resolution |

**Recommended sequence:**

1. **ADR-16 + ADR-19** (parallel) — Immediate wins. Reference storage reduces context bloat; judgment markers clarify effect blocks for human authors and the Python runtime.
2. **ADR-17** — After schema work for block definitions. Unlocks workflow DRY patterns.
3. **ADR-18** — After ADR-16 establishes `.blueprint/` convention. Largest effort, deferred until iterative use cases demand it.
4. **ADR-20** — When production deployments encounter GitHub availability issues.

---

## 7. Relationship to Prior ADRs

| This ADR | Relates To | Relationship |
|----------|-----------|--------------|
| ADR-16 (reference state) | ADR-11 (Python runtime) | Python runtime benefits from file-based state — trivial to implement `store_mode: reference` as file I/O |
| ADR-16 (reference state) | ADR-3 (spawn mode isolation) | Reference storage aligns with spawn mode's file-based inter-workflow communication |
| ADR-17 (inline blocks) | ADR-7 (extension repos) | Blocks are for *intra*-workflow reuse; extension repos remain for *inter*-workflow reuse |
| ADR-18 (persistence) | ADR-3 (spawn mode) | Persisted state must respect spawn mode boundaries — financial workflows must not leak state |
| ADR-18 (persistence) | Web3 footy tipping | Directly enables weekly tip submission use case from web3 analysis |
| ADR-19 (judgment markers) | ADR-11 (Python runtime) | Markers tell the Python runtime which operations need LLM fallback vs. deterministic handlers |
| ADR-19 (judgment markers) | ADR-14 (verification) | Judgment-marked operations use SOFT tolerance; unmarked use EXACT tolerance |
| ADR-20 (embedded fallback) | ADR-12 (pip package) | The pip package could bundle core types as embedded fallback |
| ADR-20 (embedded fallback) | ADR-15 (private mode) | Private mode workflows in air-gapped environments need embedded types |

---

## Glossary

| Term | Definition |
|------|-----------|
| **Prose Complete** | An LLM system capable of running OpenProse programs (Claude Code + Opus, OpenCode + Opus, Amp + Opus) |
| **Fourth wall** | OpenProse's `**...**` syntax marking where the LLM applies judgment rather than executing deterministically |
| **Block** | A named, reusable sequence of operations within a single workflow (OpenProse) or proposed for Blueprint (ADR-17) |
| **Reference-based state** | Storing file paths in state instead of full content values, reducing context window consumption |
| **Store mode** | Proposed Blueprint parameter controlling whether consequence output is stored as a value or a file reference (ADR-16) |
| **Embedded types** | Type definitions included directly in a workflow file as a fallback for offline/air-gapped execution (ADR-20) |
| **Judgment marker** | `**text**` convention in effect pseudocode indicating LLM reasoning is required (ADR-19) |
