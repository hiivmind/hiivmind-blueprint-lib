# Design: Claude Code Memory Tiers in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md), [Skills](2026-04-15-claude-code-skills-design.md)
**Referenced by:** Prompt Cache (future), Compaction (future)

---

## 1. Scope & Non-Goals

Claude Code runs three parallel memory systems: **CLAUDE.md** (user-authored instructions in a three-tier hierarchy), the **auto-memory** system (agent-maintained typed facts in `memdir/`), and **session persistence** (JSONL transcripts and resumption state). This spec captures all three, their distinct responsibilities, and how they compose with the core loop's context assembly.

**In scope:**
- CLAUDE.md three-tier hierarchy (global, project, subdirectory) and lazy loading
- `memdir/` auto-memory: `MEMORY.md` index, typed memory files (user / feedback / project / reference), save/recall contracts
- JSONL session transcripts, `.claude.json` state files, resumption flows
- Session quality monitoring (frustration detection, PR-request flags)
- `filterInjectedMemoryFiles` safety pass
- Per-tier token budget allocations
- Interaction points with system-prompt assembly

**Out of scope:**
- KAIROS / `/dream` / autonomous-agent memory (unreleased; gated)
- Plugin-contributed memory (plugins contribute via CLAUDE.md-equivalent files managed by the Plugin spec)
- Full prompt-cache boundary logic — future Prompt Cache spec owns that
- Specific compaction algorithms — future Compaction spec
- Memory across *different users* (there is no such thing by design)

---

## 2. Background

"Memory" in Claude Code is three distinct systems that happen to share the same instinct — keep something around so the next conversation is not starting from zero. **CLAUDE.md** is the authored surface: a developer writes conventions, constraints, and project context into plain-text markdown files, and the client injects them into the system prompt. **Auto-memory** is the agent-maintained surface: the model itself saves typed records (user preferences, feedback, project facts, external references) to files in `memdir/`, indexed by a short `MEMORY.md`, and recalls them on future sessions. **Session persistence** is the transactional surface: every turn's messages, tool calls, and tool results stream into a JSONL transcript, and `.claude.json` holds the cross-session state the client needs to resume. The three systems rarely touch each other; they coexist because each solves a problem the others do not.

**Source grounding:** `loadMemoryPrompt()`, `filterInjectedMemoryFiles()`, the `memdir/` directory layout, `.claude.json` storage incidents (a reported 3.1GB unmanaged-file issue), and community analyses of session quality monitoring. See §12.

---

## 3. Types

### 3.1 Unified source tag

```lmpl
type MemorySource =
    | {kind: "claude_md", tier: ClaudeMdTier, path: string}
    | {kind: "auto_memory", type: AutoMemoryType, path: string}
    | {kind: "session", session_id: string}
```

### 3.2 CLAUDE.md

```lmpl
type ClaudeMdTier =
    | "global"         -- ~/.claude/CLAUDE.md
    | "project"        -- <repo>/CLAUDE.md
    | "subdirectory"   -- <repo>/<sub>/CLAUDE.md, loaded on file access

type ClaudeMdFile = {
    tier: ClaudeMdTier,
    path: string,
    content: string,
    loaded_at: option[timestamp],      -- none for subdirectory until first access
    size_tokens: int
}
```

### 3.3 Auto-memory

```lmpl
type AutoMemoryType =
    | "user"           -- profile, preferences, knowledge
    | "feedback"       -- corrections and confirmations, with Why & How-to-apply
    | "project"        -- ongoing work, initiatives, incidents, with Why & How-to-apply
    | "reference"      -- pointers to external systems (Linear project X, Grafana dashboard Y)

type AutoMemoryFrontmatter = {
    name: string,
    description: string,               -- one-line, used for relevance matching
    type: AutoMemoryType
}

type AutoMemoryFile = {
    frontmatter: AutoMemoryFrontmatter,
    body: string,                      -- markdown; typed structure for feedback/project
    path: string
}

type MemoryIndex = {
    path: string,                      -- memdir/MEMORY.md
    entries: list[MemoryIndexEntry]
}

type MemoryIndexEntry = {
    title: string,
    file_path: string,                 -- relative to memdir/
    hook: string                       -- one-line description for relevance
}

-- Convention constraint (§5.2): MEMORY.md keeps entries to one line each,
-- under ~150 characters. Entries past line 200 are truncated from context.
```

### 3.4 Session persistence

```lmpl
type SessionMetadata = {
    session_id: string,
    created_at: timestamp,
    last_active: timestamp,
    working_directory: string,
    model: string,
    title: option[string],             -- auto-generated
    frustration_flags: int,            -- §6.4
    pr_request_flag: bool
}

type SessionTranscript = {
    metadata: SessionMetadata,
    jsonl_path: string,
    append_only: bool                  -- invariant, always true
}

type SessionLedger = map[string, SessionMetadata]  -- in .claude.json
```

### 3.5 Budget

```lmpl
type MemoryBudget = {
    global_claude_md: int,
    project_claude_md: int,
    subdirectory_claude_md: int,
    auto_memory_index: int,            -- the always-loaded index (MEMORY.md)
    auto_memory_on_demand: int         -- soft cap per loaded body, enforced by caller
}
```

---

## 4. CLAUDE.md Hierarchy

### 4.1 Three tiers

| Tier           | Location                              | When loaded                                                  |
|----------------|---------------------------------------|--------------------------------------------------------------|
| Global         | `~/.claude/CLAUDE.md`                 | Session start, every session                                  |
| Project        | `<cwd>/CLAUDE.md` (walking up)        | Session start, when a project root is detected                |
| Subdirectory   | `<cwd>/<sub>/CLAUDE.md`               | First time Claude accesses a file under `<sub>/`              |

All three tiers are appended to the **dynamic** section of the system prompt, after the static behavioral rules. They appear as authored instructions the model should follow.

### 4.2 Loading precedence and merge

Precedence is *additive*, not overriding — all three tiers contribute. When instructions conflict, the deeper (more specific) tier wins by convention, but this is a prose contract, not a resolver:

```lmpl
define load_claude_md_chain(cwd: string) -> list[ClaudeMdFile]:
    global <- read_if_exists("~/.claude/CLAUDE.md", tier: "global")
    project <- walk_up_and_find("CLAUDE.md", from: cwd, tier: "project")

    loaded <- filter([global, project], some)
    return loaded

    ensure all(result, f -> f.loaded_at != none),
        "every returned file has actually been loaded"
    ensure no_subdirectory_in(result),
        "this chain is session-start loading only; subdirectory tier is lazy"
```

### 4.3 Subdirectory lazy loading

Subdirectory CLAUDE.md files are loaded **on file access**. The Tool catalog's file-reading tools (Read, Edit, Write) check for a same-directory CLAUDE.md before their first read of a file under that directory; if present and not yet loaded, the file is read and appended to the running dynamic context.

```lmpl
define ensure_subdirectory_claude_md(file_path: string,
                                    state: State) -> State:
    parent <- parent_directory(file_path)
    candidate <- find_sibling("CLAUDE.md", parent)

    if candidate.some and not already_loaded(state, candidate.value):
        loaded <- read_claude_md(candidate.value, tier: "subdirectory")
        return {...state,
                dynamic_context: append(state.dynamic_context, loaded)}

    return state

    invariant no_duplicate_loads(state.dynamic_context),
        "the same CLAUDE.md is never loaded twice into a session"
```

### 4.4 Injection point

CLAUDE.md files appear in the **dynamic** section of the system prompt — below the static, cacheable prefix. This is deliberate: they change per session (via subdirectory lazy loads) and per project, so they cannot share the static cache.

```lmpl
invariant claude_md_in_dynamic_section(system_prompt),
    "CLAUDE.md content is never placed above SYSTEM_PROMPT_DYNAMIC_BOUNDARY"
```

See the future Prompt Cache spec for the boundary's formal semantics.

### 4.5 `filterInjectedMemoryFiles` safety pass

Before any CLAUDE.md content is injected, it passes a safety filter: detected secrets are redacted, obvious prompt-injection patterns are flagged, and files that exceed a reasonableness budget are truncated with a notice.

```lmpl
define filter_injected_memory(file: ClaudeMdFile) -> ClaudeMdFile:
    redacted <- redact_detected_secrets(file.content)
    flagged <- annotate_suspected_injection(redacted)
    bounded <- truncate_with_notice(flagged, cap: 100_000 chars)

    return {...file, content: bounded}

    ensure no_undetected_obvious_secret(result.content),
        "detected secrets are redacted before injection"
    ensure injection_hints_flagged(result.content) when
           contains_injection_pattern(file.content),
        "suspicious content is tagged, not silently injected"
```

---

## 5. Auto-Memory System

### 5.1 Directory layout

```
<auto_memory_root>/
├── MEMORY.md              -- the always-loaded index (§5.2)
├── user_<topic>.md        -- type: user
├── feedback_<topic>.md    -- type: feedback
├── project_<topic>.md     -- type: project
└── reference_<topic>.md   -- type: reference
```

The root location is client-managed; auto-memory is scoped per project (a file path derived from the working directory) so memory does not leak between unrelated projects.

### 5.2 `MEMORY.md` as always-loaded index

`MEMORY.md` is **always** injected into the system prompt's dynamic section. It is not the memory itself — it is the table of contents. Each entry is a one-line `- [Title](file.md) — one-line hook` pointer. Bodies are loaded on demand (§5.4).

```lmpl
invariant length_lines(memory_index) <= 200,
    "MEMORY.md entries past line 200 are truncated from context"
invariant all(memory_index.entries, e -> single_line(e)),
    "each index entry is one line; no body text in the index"
invariant total_tokens(memory_index) <= budget.auto_memory_index,
    "index fits the always-loaded budget"
```

### 5.3 Four types

Each type has a distinct when-to-save contract. This spec expresses the contract structurally; the authoring guidance belongs in documentation.

| Type          | Save when                                                                                      | Shape                                           |
|---------------|------------------------------------------------------------------------------------------------|-------------------------------------------------|
| `user`        | Learning about the user's role, preferences, responsibilities, knowledge                       | Free-form markdown                              |
| `feedback`    | User corrects an approach OR confirms a non-obvious approach worked                            | Rule + **Why** + **How to apply**               |
| `project`     | Learning who is doing what / why / by when; active state of work                               | Fact/decision + **Why** + **How to apply**      |
| `reference`   | Learning pointers into external systems (Linear project X, dashboard Y)                        | Free-form markdown                              |

### 5.4 Save and recall contracts

```lmpl
define save_memory(memory: AutoMemoryFile,
                  index: MemoryIndex) -> {file: AutoMemoryFile, index: MemoryIndex}:

    require unique_path(memory, index), "memory names do not collide"
    require type_appropriate(memory.frontmatter.type, memory.body),
        "body shape matches the frontmatter type contract"

    new_entry <- {
        title: memory.frontmatter.name,
        file_path: relative(memory.path, memdir_root),
        hook: memory.frontmatter.description
    }
    updated_index <- add_entry(index, new_entry)

    return {file: memory, index: updated_index}

    ensure entry_appears_in(updated_index, memory),
        "every saved file has a pointer in MEMORY.md"


define recall_memory(topic: string, index: MemoryIndex) -> list[AutoMemoryFile]:
    matching <- filter(index.entries, e -> relevant(topic, e))
    return map(matching, e -> read_memory_file(e.file_path))

    ensure all(result, f -> entry_exists(index, f)),
        "recall returns only files that the index references"
```

### 5.5 Staleness and verification

A memory saved at time T captures the state as of T. When the user asks about *current* state, the spec requires verification before citing recalled facts:

```lmpl
@model_contract
require before acting on recalled_memory:
    verify_still_current(recalled_memory)
      or flag_to_user("memory may be stale"),
    "recalled memory is a snapshot in time; verify before acting"
```

This is a model-behavior contract (LMPL cannot enforce the verification operationally).

### 5.6 Typed body structure

For `feedback` and `project` types, the body has a required structure:

```
<rule or fact — one paragraph>

**Why:** <reason, often a past incident or constraint>
**How to apply:** <when/where this guidance kicks in>
```

```lmpl
define type_appropriate(t: AutoMemoryType, body: string) -> bool:
    match t:
        case "feedback":  return has_section(body, "Why") and has_section(body, "How to apply")
        case "project":   return has_section(body, "Why") and has_section(body, "How to apply")
        case _:           return true
```

The rationale: for rules and facts, knowing *why* lets future recall judge edge cases instead of following blindly.

---

## 6. Session Persistence

### 6.1 JSONL transcripts

Every turn's structured messages (user input, assistant output, tool calls, tool results) are written to a per-session JSONL file. The file is **append-only** — a turn, once recorded, is never edited. This matters: the transcript is the authoritative log, not a display.

```lmpl
define append_turn(transcript: SessionTranscript,
                  records: list[JsonlRecord]) -> SessionTranscript:
    require transcript.append_only, "transcripts are append-only"
    write_lines(transcript.jsonl_path, records, mode: "append")

    ensure previous_content_unchanged(transcript),
        "append never mutates earlier lines"
```

### 6.2 `.claude.json` and state files

`.claude.json` is the client's cross-session state: a list of sessions, last-used session, model preferences, and a handful of per-project flags. The file has historically been unmanaged (the reported 3.1 GB incident stems from accumulated session records that were never pruned); a healthy implementation bounds its growth by aging-out session records after a retention window.

```lmpl
invariant bounded_growth(claude_json, retention_window),
    "session records older than the retention window are removed or archived"
```

### 6.3 Session creation and resumption

```lmpl
define create_session(cwd: string, client_state: ClientState) -> SessionTranscript:
    id <- generate_session_id()
    transcript <- {
        metadata: {
            session_id: id,
            created_at: now(),
            last_active: now(),
            working_directory: cwd,
            model: client_state.default_model,
            title: none,
            frustration_flags: 0,
            pr_request_flag: false
        },
        jsonl_path: session_jsonl_path(id),
        append_only: true
    }
    return transcript

define resume_session(session_id: string) -> option[SessionTranscript]:
    record <- lookup_in_claude_json(session_id)
    if record.none: return none

    messages <- replay_jsonl(record.jsonl_path)
    return some({metadata: record, jsonl_path: record.jsonl_path,
                 append_only: true})

    ensure resumed_messages_reflect_transcript(result, record.jsonl_path),
        "replay is a pure function of the JSONL"
```

### 6.4 Quality monitoring

The session metadata carries two live flags used by the client's session-quality logic:

- `frustration_flags` — incremented when the model (or a classifier) detects user frustration cues (repeated corrections, negative language). High counts surface a "take a break?" prompt or a mode downgrade.
- `pr_request_flag` — set when the user expresses intent to create a PR; used to remind the model to route through the configured GitHub automation.

These are observations, not enforcement. They inform the UI and the next turn's system prompt, but they do not block or redirect the loop.

```lmpl
define observe_session_quality(transcript: SessionTranscript,
                              latest_user_message: Message) -> SessionMetadata:
    meta <- transcript.metadata
    if frustration_detected(latest_user_message):
        meta <- {...meta, frustration_flags: meta.frustration_flags + 1}
    if pr_request_detected(latest_user_message):
        meta <- {...meta, pr_request_flag: true}
    return meta
```

---

## 7. Memory Budget and Prompt Integration

### 7.1 Per-source budget

The three systems share the dynamic-section budget. Defaults (indicative):

| Source                      | Budget      | Enforcement                                      |
|-----------------------------|-------------|--------------------------------------------------|
| Global CLAUDE.md            | ~2k tokens  | Truncate with notice                             |
| Project CLAUDE.md           | ~5k tokens  | Truncate with notice                             |
| Subdirectory CLAUDE.md      | ~2k tokens  | Hard reject; do not load past the cap            |
| `MEMORY.md` index           | ~1k tokens  | Hard; entries past line 200 dropped silently     |
| Auto-memory bodies (on-demand) | ~3k tokens per body | Caller enforces; larger bodies are split        |

### 7.2 Lazy-load thresholds

- `MEMORY.md` always loads (it is the index).
- Individual auto-memory bodies load only when a memory matches the current topic — recall is explicit, not ambient.
- Subdirectory CLAUDE.md loads only on first access to a file under that directory.

### 7.3 Cacheable vs. dynamic partition

Nothing in memory is cacheable across users, but **within** a user's session, the memory content is stable and *could* cache — except that subdirectory lazy loads invalidate the cache as soon as they fire. Future Prompt Cache spec will own the formal boundary and the sticky-latch invalidation rules; this spec only asserts the invariant:

```lmpl
invariant dynamic_memory_after_static_boundary,
    "memory-sourced content is placed strictly after the static cache boundary"
```

---

## 8. Safety and Privacy

### 8.1 PII in auto-memory

The auto-memory authoring guidance instructs the model to avoid saving PII and credentials. LMPL can express this as a save-time precondition:

```lmpl
require not contains_pii(memory.body),
    "auto-memory must not include PII"
require not contains_secret(memory.body),
    "auto-memory must not include secrets or credentials"
```

These are authoring-time obligations (static scan at save time). They are the last line of defense; the first is the model's training.

### 8.2 `.claude.json` growth incident

The reported 3.1 GB `.claude.json` storage incident is not a safety failure per se — but it is a privacy failure: every message, tool call, and tool result from every session sits unencrypted in that file. The spec obligation:

```lmpl
invariant claude_json_access_scoped_to_user,
    "the file is readable only by the owning OS user"
ensure bounded_growth(claude_json, retention_window),
    "old session records are pruned or archived to bound growth"
```

### 8.3 Filter on inject

The `filter_injected_memory` pass (§4.5) applies to CLAUDE.md. The same filter should apply to any auto-memory body at recall time:

```lmpl
require filter_injected_memory_applied(body) when injecting(body, to: system_prompt),
    "every memory-sourced string entering the prompt passes the filter"
```

---

## 9. Interactions With Other Specs

### 9.1 System-prompt assembly (Core Loop §5.1)

All three memory sources feed the *dynamic* section of the system prompt. The Core Loop's `gather_turn_context` calls into this spec's loader functions; the concrete assembly order is a Prompt Cache concern.

### 9.2 Skills vs. memory bodies

Skills (§6.1 in the Skills spec) and auto-memory entries both use progressive disclosure — description visible, body loaded on demand. They differ in *authorship* (skills are user-authored as extensions; memory is agent-authored during conversation) and in *lifecycle* (skill files are stable; memory files evolve). Functionally, the prompt-layer integration is similar; a future consolidation could unify them, but the spec currently treats them as distinct.

### 9.3 Plugins do not inject memory

Plugins contribute authored surfaces (skills, commands, hooks, agents, MCP specs). They do **not** contribute CLAUDE.md content directly — that is a per-project, per-user concern. A plugin that needs to inject project-wide instructions does so through its skills' descriptions, which appear in the system prompt via the Skills spec's mechanism.

### 9.4 Compaction (forward reference)

When the compaction spec lands, it will own decisions about *which* memory sources can be summarized or dropped when the context window pressures. A likely rule: session transcripts are compactable first, project CLAUDE.md last, global CLAUDE.md and `MEMORY.md` index never.

---

## 10. LMPL Gaps and Proposed Extensions

### 10.1 Always-loaded vs. on-demand classification

Every memory artifact falls into one of three classes: always-loaded (MEMORY.md index, global CLAUDE.md), eagerly-loaded-at-session-start (project CLAUDE.md), lazy (subdirectory CLAUDE.md, auto-memory bodies, skill bodies). An `@loading_policy(always | eager | lazy)` annotation on the data type would make the class structural.

### 10.2 Model-behavior contracts on recall

`require verify_still_current(recalled_memory)` is a contract on the *model* at recall time — not on a function the client runs. Same pattern as the injection-flagging contract in Guardrails (§7.1). LMPL's `@model_contract` helps document, but an enforcement story would need an LLM-predicate check (see Guardrails gap §9.2).

### 10.3 Typed bodies

Feedback and project memories have a structured body (§5.6). LMPL could express this with a tagged body type:

```lmpl
type FeedbackBody = {rule: string, why: string, how_to_apply: string}
type ProjectBody  = {fact: string, why: string, how_to_apply: string}
```

rather than a free-form string with a `has_section` predicate. A generalization of the skill-frontmatter pattern.

### 10.4 Append-only storage

`transcript.append_only` is a capability on the value. LMPL has no "append-only" modifier on collections. A `@append_only list[T]` type would elevate the invariant from a predicate to a type.

### 10.5 Budget allocation as a resource type

`MemoryBudget` is a passive record today. A `budget[T]` type with `allocate`/`release` semantics and invariants `sum(allocated) <= total` would make over-allocation a type error rather than a runtime check.

### 10.6 Retention windows

`.claude.json` retention is expressed as a prose invariant. A `@retention(window)` annotation on persisted types would document the obligation at the type level and help static tools find storage leaks.

---

## 11. Cross-Spec References

| Reference                              | From                             | To                                 |
|----------------------------------------|----------------------------------|------------------------------------|
| `load_memory_prompt` / context assembly | §4, §5                          | Core Loop §5.1                     |
| Dynamic section of system prompt       | §4.4, §7.3                       | Prompt Cache (future)              |
| Skills vs memory disclosure            | §9.2                             | Skills §6                          |
| Plugins contribute surfaces, not memory | §9.3                            | Plugin ecosystem §5                |
| Compaction candidate ordering          | §9.4                             | Compaction (future)                |
| `@model_contract` on recall            | §5.5, §10.2                      | Guardrails §9.3                    |

---

## 12. References

- Abhishek Ray, "Inside Claude Code's System Prompt" — https://www.claudecodecamp.com/p/inside-claude-code-s-system-prompt (CLAUDE.md three-tier hierarchy, dynamic-section placement, ~30k token budget)
- Siddhant Khare, "The plumbing behind Claude Code" — https://siddhantkhare.com/writing/the-plumbing-behind-claude-code (`src/memdir/memdir.ts`, `loadMemoryPrompt()`, three tiers)
- Varonis Threat Labs, "A Look Inside Claude's Leaked AI Coding Agent" — https://www.varonis.com/blog/claude-code-leak (`filterInjectedMemoryFiles()` safety pass)
- kolkov, "We Reverse-Engineered 12 Versions of Claude Code" — https://dev.to/kolkov/we-reverse-engineered-12-versions-of-claude-code-then-it-leaked-its-own-source-code-pij (`.claude.json` storage architecture, 3.1 GB incident, session records)
- FlorianBruniaux, *claude-code-ultimate-guide* — https://github.com/FlorianBruniaux/claude-code-ultimate-guide (memory hierarchy, session quality flags)
- Liran Baba, "Undercover mode, decoy tools, and a 3,167-line function" — https://liranbaba.dev/blog/claude-code-source-leak/ (session-state architecture; JSONL persistence)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented memory systems.
