# Radical Simplification Audit: hiivmind-blueprint-lib

## Context

The blueprint-lib has grown to ~4,000 lines of YAML type definitions across 46 types, plus 15 JSON schemas and a 2,547-line execution engine. The library suffers from feature creep (logging/audit/CI baked into core), over-specification (pseudocode handling every edge case), environment coupling (Claude Code-specific logic), and a heavyweight loading chain. This audit recommends concrete cuts.

---

## Problem 1: Logging/Audit Bloat (10 types, ~500 lines)

**Current:** 10 logging consequence types: `init_log`, `log_node`, `log_entry`, `log_session_snapshot`, `finalize_log`, `write_log`, `apply_log_retention`, `output_ci_summary`, plus audit mode bolted onto `conditional` node.

**Issues:**
- `init_log` manages `.logs/.session-state.yaml`, invocation tracking, `BLUEPRINT_SESSION_ID` env vars — infrastructure, not workflow logic
- `apply_log_retention` implements file deletion by mtime/count — a sysadmin utility
- `output_ci_summary` hardcodes `GITHUB_STEP_SUMMARY` and `::error::` annotation syntax
- `conditional` node has 42 lines of audit pseudocode vs 5 lines of actual logic
- Logging auto-injection is wired into all 3 execution phases

**Recommendation: Cut to 2 types, move rest to extension**
| Keep (core) | Move to extension | Delete |
|---|---|---|
| `log_entry` (simplified) | `init_log`, `finalize_log`, `log_session_snapshot`, `write_log` | `apply_log_retention`, `output_ci_summary` |
| `log_node` (simplified) | `conditional` audit mode → separate `validation_gate` extension | |

- Remove auto-injection from execution engine — logging becomes opt-in per-node
- **Lines saved: ~350**

---

## Problem 2: Over-Specified Pseudocode

**Current examples of excess:**
- `match_3vl_rules`: 130 lines including legacy compatibility fields (`score`, `condition_count`), triple-branch winner determination, 5 result fields
- `user_prompt` node: 550 lines, 5 execution modes, dynamic option resolution, multi-turn pause/resume
- `reference` node: 344 lines, dual mode (inline/spawn), deprecated `context` vs `input` params, `next_node` vs `transitions`
- Execution engine `execute()` phase: batching logic, batch threshold checks, flush conditions

**Recommendation: Prose over pseudocode**
- Replace detailed pseudocode with concise behavioral descriptions
- Example: `match_3vl_rules` effect should be ~20 lines: "evaluate each rule against flags, count matches, return sorted candidates"
- Remove legacy compatibility fields — this is v3, break cleanly
- Remove `context` parameter from `reference` (use `input` only)
- Remove `next_node` from `reference` (use `transitions` only)
- **Target: 50% reduction in effect blocks across all types**

---

## Problem 3: Claude Code Environment Coupling

**Current:** Types assume Claude Code tooling:
- `interface_detection` checks `tool_available("AskUserQuestion")`
- `user_prompt` has 5 modes tied to interface: interactive (Claude Code), tabular, forms (web), structured, autonomous (agent)
- `run_command` has Claude Code-specific `interpreter: "auto"` with extension-based detection
- `capabilities` block lists Claude Code features explicitly

**Recommendation: Make environment-agnostic**
- Remove `interface_detection` and `capabilities` from execution engine
- `user_prompt` should define ONE prompt format; interface adaptation is the runtime's job, not the type definition's
- Remove multi-modal dispatch from type definitions entirely
- **Lines saved: ~200**

---

## Problem 4: Type Over-Consolidation (Swiss Army Knife types)

**Current:** Several types pack multiple operations behind an `operation` parameter:
- `local_file_ops`: read/write/mkdir/delete (different params needed per operation)
- `git_ops_local`: clone/pull/fetch/get-sha (`args` only meaningful for clone)
- `web_ops`: fetch/post/graphql (different parameter shapes)
- `mutate_state`: set/append/clear/merge (`value` ignored for clear)
- `tool_check`: available/version_gte/authenticated/daemon_ready (last 2 need hidden registry)

**These "consolidated" types are actually harder to understand** because parameter requirements change per operation.

**Recommendation: Split the worst offenders, keep the reasonable ones**
| Type | Action |
|---|---|
| `mutate_state` | Keep (operations are similar enough) |
| `local_file_ops` | Keep but document param requirements per operation clearly |
| `tool_check` | Remove `authenticated` and `daemon_ready` (move to extension) |
| `web_ops` | Keep |
| `git_ops_local` | Keep |

---

## Problem 5: Loading Chain Complexity

**Current loading sequence:**
1. Fetch `schema/authoring/workflow.json` → validate workflow structure
2. Fetch `schema/definitions/consequence-definition.json` (381 lines)
3. Fetch `schema/definitions/precondition-definition.json` (162 lines)
4. Fetch `schema/definitions/node-definition.json` (340 lines)
5. Fetch `consequences/index.yaml` → resolve to `consequences.yaml`
6. Fetch `preconditions/index.yaml` → resolve to `preconditions.yaml`
7. Fetch `nodes/index.yaml` → resolve to `workflow_nodes.yaml`
8. Fetch `execution/engine_execution.yaml` (2,547 lines!)

Plus `resolution/type-loader.yaml`, `workflow-loader.yaml`, `execution-loader.yaml`, `fetch-patterns.yaml`, `entrypoints.yaml`.

**That's 13+ files fetched before a workflow runs.**

**Recommendation: Flatten to 3 files**
| Current (13+ files) | Proposed (3 files) |
|---|---|
| 3 definition schemas | 1 unified `schema/type-definition.json` |
| 4 index.yaml files | Eliminate — inline registry into consolidated files |
| 5 resolution files | 1 `resolution.yaml` with fetch patterns |
| `engine_execution.yaml` (2,547 lines) | `execution.yaml` (~500 lines, prose-based) |
| 3 YAML type files | Keep as-is (already consolidated) |

**Loading path becomes:** workflow.json schema → 3 type YAML files → execution.yaml

---

## Problem 6: Execution Engine Over-Specification (2,547 lines)

**Current:** The execution engine specifies in exhaustive pseudocode:
- Batching logic with thresholds and flush conditions
- Multi-turn conversation pause/resume
- CI annotation emission (`::error::`)
- Interface detection with 6 priority levels
- Output level filtering (silent/quiet/normal/verbose/debug)
- Auto-injection of logging consequences at 3 points

**This is the single biggest bloat source.** The engine should describe *what* happens, not *how* in 2,547 lines of pseudocode.

**Recommendation: Rewrite as ~500 lines of behavioral description**
- Phase 1 (init): Load workflow, validate, initialize state. ~30 lines.
- Phase 2 (execute): Loop nodes, dispatch by type, route to next. ~30 lines.
- Phase 3 (complete): Display result. ~15 lines.
- Remove: batching, CI annotations, auto-log-injection, interface detection, multi-modal dispatch
- These become optional runtime concerns, not core engine specification

---

## Problem 7: Composite Precondition Duplication

**Current:** `all_of`, `any_of`, `none_of`, `xor_of` — 4 types with identical structure, only differing in boolean operator.

**Recommendation:** Single `composite` precondition with `operator: all|any|none|xor` parameter. **Lines saved: ~90.**

---

## Summary: Impact

| Area | Current | Proposed | Reduction |
|---|---|---|---|
| Consequence types | 28 | ~18 | -10 types |
| Precondition types | 13 | ~10 | -3 types |
| Node types | 5 | 5 | unchanged |
| Execution engine | 2,547 lines | ~500 lines | -80% |
| Schema files | 15 | ~8 | -7 files |
| Resolution files | 5 | 1 | -4 files |
| Total YAML lines | ~4,000 | ~2,000 | -50% |
| Files to load | 13+ | 5 | -60% |

## Implementation Order

1. **Execution engine rewrite** (biggest impact, unblocks other changes)
2. **Extract logging/audit/CI to extension** (removes 10 types from core)
3. **Consolidate composite preconditions** (quick win)
4. **Flatten loading chain** (merge schemas, remove index files)
5. **Simplify pseudocode** across remaining types (remove legacy fields, reduce verbosity)
6. **Remove environment coupling** (interface detection, multi-modal dispatch)

## Verification

- Validate remaining types against `schema/definitions/` after schema consolidation
- Check `examples/` still work with simplified types
- Verify `hiivmind-blueprint-author/references/` updated to match
- Test a real workflow end-to-end with simplified execution engine
