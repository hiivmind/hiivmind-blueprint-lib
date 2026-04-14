# Changelog

All notable changes to hiivmind-blueprint-lib will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [7.1.0] - 2026-04-14

### Added

#### Composite node types (authoring-time sugar)

Two new composite node types expand to primitive nodes via a walker implemented in `hiivmind-blueprint-mcp` (separate repo). The LLM at runtime still sees only the three primitive node types (`action`, `conditional`, `user_prompt`) — composites never reach runtime.

- **`confirm`** — yes/no prompt with structural state gating. Required fields: `prompt`, `store_as`, `on_confirmed`, `on_declined`. Expands to `user_prompt → mutate_state → conditional → (optional action)`. The `store_as` field is required and always written `true`/`false` before routing, per the [confirmations-as-explicit-state](https://github.com/hiivmind/hiivmind-blueprint-central/blob/main/02.principles/g.trust-governance/confirmations-as-explicit-state.md) principle.
- **`gated_action`** — multi-way CASE/WHEN dispatch. Required fields: `when[]` (minItems 1), `else`. Optional: `on_unknown` (defaults to workflow `default_error`). Expands to a chain of `conditional` nodes, each optionally followed by an intermediate `action` for per-branch consequences. First-match-wins, 3VL short-circuit on unknown.

#### New author-time catalog: `blueprint-composites.md`

Composite signatures and expansion shapes live in a new file at the repo root, separate from `blueprint-types.md`. The runtime LLM continues to read only `blueprint-types.md`; the composite catalog is consumed at authoring time.

#### Walker-expansion fixture corpus

`tests/fixtures/composites/` contains paired `input.yaml` / `expected.yaml` fixtures covering:

- `confirm/minimal`, `confirm/with_consequences`, `confirm/custom_labels`
- `gated_action/basic`, `gated_action/with_consequences`, `gated_action/default_on_unknown`
- `_negative/` cases: `confirm_missing_store_as`, `gated_action_missing_else`, `gated_action_empty_when`

These are the authoritative contract that future Python and TypeScript walker implementations in `hiivmind-blueprint-mcp` must satisfy (bit-identical expansion from each input).

### Changed

- `schema/authoring/node-types.json` — bumped `$comment` to Schema version 3.1. Adds `confirm` and `gated_action` to the `type` enum plus two new `$defs` (`confirm_node`, `gated_action_node`) with `allOf` dispatch. Existing primitive validation unchanged.

### Related principles

Two new principles codify the discipline governing this feature. Committed in `hiivmind-blueprint-central` on branch `principle/composite-primitive-canary`:

- [composite-primitive-canary](https://github.com/hiivmind/hiivmind-blueprint-central/blob/main/02.principles/c.type-system/composite-primitive-canary.md) — composites are sugar; awkward composites are diagnostic signals that primitives need extension.
- [confirmations-as-explicit-state](https://github.com/hiivmind/hiivmind-blueprint-central/blob/main/02.principles/g.trust-governance/confirmations-as-explicit-state.md) — confirmations decompose into classify → record → evaluate; structure is the policy.

### Migration

Purely additive. No existing workflow breaks. Authors who want to use the new composites can opt in; hand-written primitive patterns continue to work unchanged.

---

## [7.0.0] - 2026-04-13

### BREAKING CHANGES

#### Type catalog collapsed into a single markdown file

The six catalog YAML files are replaced by one file at the repo root: `blueprint-types.md`. All 34 type definitions (3 nodes + 9 preconditions + 22 consequences) are preserved verbatim — no type names, parameter names, or enum variants changed. The compression is pure: 2,218 lines → ~180 lines.

**Removed:**
- `consequences/core.yaml`, `consequences/intent.yaml`, `consequences/extensions.yaml`
- `preconditions/core.yaml`, `preconditions/extensions.yaml`
- `nodes/workflow_nodes.yaml`
- `consequences/`, `preconditions/`, `nodes/` directories

**Added:**
- `blueprint-types.md` at the repo root — single-file type catalog in signature-style prose

**Migration for workflow authors:** None required. Workflow YAML type names, parameter names, and enum variants are all unchanged. Existing workflows continue to work.

#### Obsolete schemas deleted

Three JSON schemas are removed because they no longer have validation targets:

- `schema/definitions/type-definition.json` — validated the catalog YAML files
- `schema/definitions/execution-definition.json` — orphaned since v6.0.0 when `execution/` was removed
- `schema/resolution/definitions.json` — validated per-repo `.hiivmind/blueprint/definitions.yaml`, which is eliminated

The `schema/definitions/` and `schema/resolution/` directories are removed. Authoring schemas (`schema/authoring/*`), common definitions, config schemas, and runtime schemas are unaffected.

#### Per-repo `definitions.yaml` eliminated

Previously, consuming repos copied catalog types into `.hiivmind/blueprint/definitions.yaml`. That concept is gone: the `hiivmind-blueprint` skill ships `blueprint-types.md` as skill-embedded reference at build time. Consuming repos should delete any existing `.hiivmind/blueprint/definitions.yaml` after upgrading.

#### Universal `${}` interpolation

String parameters are now uniformly interpolatable. The previous per-parameter `interpolatable: true/false` flags (inconsistent in the old catalog) are gone. Literal strings remain literal; `${...}` always expresses intent to interpolate. This is strictly more flexible than the old behavior.

#### Workflow schema compressed

Six structural changes reduce workflow YAML verbosity by ~30-40%:

1. **`consequences:` everywhere** — `actions:` (on action nodes) and `consequence:` (in response handlers) renamed to `consequences:` for consistency with endings and paralleling `preconditions`.
2. **Default failure routing** — New required `default_error` field on workflows. `on_failure` on action nodes and `on_unknown` on conditional nodes are now optional; when omitted, they route to `default_error`.
3. **Ternary conditionals** — Conditionals now support `on_true`, `on_false`, and `on_unknown` as direct keys (flattened from `branches:` wrapper). `on_unknown` handles evaluation failure, distinct from "condition is false."
4. **Condition shorthand** — `condition: "expression"` is sugar for `{type: evaluate_expression, expression: "..."}`. `condition: {all: [...]}` is sugar for `{type: composite, operator: all, conditions: [...]}`. Full object form still works.
5. **Response handler shorthand** — `option_id: "node_name"` is sugar for `{next_node: "node_name"}`. `next_node` supports `${}` interpolation for dynamic routing.
6. **Optional `initial_state`** — When omitted, walker initializes with empty defaults. When provided, no need for empty `flags: {}` or `computed: {}`.

**Renamed:**
- Action node: `actions:` → `consequences:`
- Response handler: `consequence:` → `consequences:`
- Conditional: `branches: {on_true, on_false}` → `on_true`, `on_false` (direct keys)

**Added:**
- `default_error` (required workflow field)
- `on_unknown` (optional on conditional nodes)
- Condition string shorthand and composite shorthand
- Response handler string shorthand and dynamic `${}` routing

### Changed

- Version: `6.1.0` → `7.0.0`
- `package.yaml` artifacts: drop `consequences/`, `preconditions/`, `nodes/`; add `blueprint-types.md`
- `package.yaml` schemas block: drop `definitions: "1.0"` entry
- `README.md`: File Structure, Type Inventory, Quick Start, How It Works sections updated
- `CLAUDE.md`: File Structure, Sync Checklist, Key Concepts, Common Tasks sections updated
- `examples/index.yaml`: removed `source_files:` mapping to deleted YAML files
- Cross-repo: `hiivmind-blueprint/lib/patterns/authoring-guide.md` and `execution-guide.md` updated to reference `blueprint-types.md`

## [5.0.0] - 2026-02-24

### BREAKING CHANGES

#### `reference` Node Removed

The `reference` node type has been removed entirely. It introduced complexity around remote workflow loading with security/prompt injection risks from loading remote documents and workflows.

**Migration:** Replace `reference` nodes with direct workflow composition or `action` nodes that handle the same logic inline.

**Removed from:**
- `nodes/workflow_nodes.yaml` — node definition deleted
- `schema/authoring/node-types.json` — schema definition deleted
- `schema/authoring/workflow.json` — `input_schema`, `output_schema`, ending `output`, and `schema_parameter` removed (only existed for spawn-mode reference)
- `execution/engine_execution.yaml` — dispatch case removed
- `resolution/loader.yaml` — `workflow_loading` section removed (section 4), section 5 renumbered to 4
- `schema/resolution/loader.json` — `workflowLoader` definition removed

#### `user_prompt` Node Simplified

1. **`option_mapping` merged into `options`**: The `options` field is now polymorphic:
   - **Array** (static): `options: [{id, label, description}, ...]` — unchanged
   - **Object** (dynamic mapping): `options: {id: "rule.name", label: "rule.name", ...}` — replaces `option_mapping`

   **Migration:** Rename `option_mapping:` to `options:` in any node that uses `options_from_state`. Remove the old `options:` field (which was absent when using dynamic options).

2. **`mode` renamed to `display`**: The prompt rendering configuration field is now `display` instead of `mode`.

3. **`interactive` renamed to `json`**: The default display mode is now `json` (structured data, client renders natively) instead of `interactive` (which was tied to `AskUserQuestion`).

   **Migration:** In `initial_state.prompts`, change `mode: interactive` to `display: json` and `mode: tabular` to `display: tabular`.

### Changed

- Node type count: 4 → 3 (reference removed)
- Total type count: 35 → 34
- `prompts-config.json` schema updated: `mode` → `display`, `interactive` → `json`
- Loader sections renumbered: 5 sections → 4 sections

## [4.0.0] - 2026-02-24

### BREAKING CHANGES

Radical simplification: 50 types reduced to 36 types, ~56% line reduction across the library. **Existing workflows using v3.x type names must be updated.**

#### Types Removed

| Removed Type | Category | Replacement |
|-------------|----------|-------------|
| `init_log` | consequence/logging | Removed (auto-injection eliminated) |
| `log_session_snapshot` | consequence/logging | Removed |
| `finalize_log` | consequence/logging | Removed (auto-injection eliminated) |
| `write_log` | consequence/logging | Removed (auto-injection eliminated) |
| `apply_log_retention` | consequence/logging | Removed |
| `output_ci_summary` | consequence/logging | Removed (CI coupling eliminated) |
| `log_state` | precondition/logging | Removed |
| `all_of` | precondition/composite | Use `composite` with `operator: all` |
| `any_of` | precondition/composite | Use `composite` with `operator: any` |
| `none_of` | precondition/composite | Use `composite` with `operator: none` |
| `xor_of` | precondition/composite | Use `composite` with `operator: xor` |

#### Parameter Changes

| Type | Change |
|------|--------|
| `tool_check` | Removed `authenticated` and `daemon_ready` capabilities |
| `reference` node | Removed `context` (use `input`), removed `next_node` (use `transitions`) |
| `user_prompt` node | Removed multi-modal support (voice, visual, autonomous modes) |
| `conditional` node | Removed `audit` mode |
| `log_entry` | Simplified to 3 params: `level`, `message`, `context` |
| `run_command` | Removed `venv` and `env` parameters |

### Changed

- **Execution engine**: Rewritten from 2,547 to 385 lines (-85%). Removed batching, CI annotations, auto-log-injection, interface detection, multi-modal dispatch
- **Composite preconditions**: 4 types consolidated into single `composite` type with `operator` parameter
- **Resolution chain**: 5 YAML files merged into `resolution/loader.yaml`. 3 JSON schemas merged into `schema/resolution/loader.json`
- **Definition schemas**: 3 JSON schemas merged into `schema/definitions/type-definition.json`
- **Logging schema**: Simplified to log_entry + log_node only (88 lines)
- **Output config schema**: Removed batch/CI properties (101 lines)
- **Prompts config schema**: Removed interface detection, multi-modal config (89 lines)
- **user_prompt node**: Simplified from 553 to ~155 lines, single prompt format
- **reference node**: Simplified from 344 to ~165 lines, uses `input` instead of `context`

### Removed

- All 4 content index files (`consequences/index.yaml`, `preconditions/index.yaml`, `nodes/index.yaml`, `execution/index.yaml`)
- 12 resolution/schema files replaced by 3 consolidated files
- `schema/_deprecated/` directory

## [3.1.1] - 2026-02-08

### Added

- **PR branch validation CI gate**: `.github/workflows/validate-pr-branch.yaml` blocks PRs to `main` unless from `release/*` or `hotfix/*` branches
- **`/prepare-release` skill**: Automates release branch creation, version bump, changelog, and PR to `main`
- **`/prepare-release` command**: Command gateway for the prepare-release skill

### Changed

- **RELEASING.md**: Added CI enforcement section and documented `/prepare-release` as recommended release flow
- **CLAUDE.md**: Updated Git Workflow section with branching requirement and release process reference

## [3.1.0] - 2026-02-08

### Added

- **Shared fetch patterns**: Extracted `resolution/fetch-patterns.yaml` with reusable `source_format`, `source_parsing`, `url_construction`, and `fetching` primitives
- **Claude Code plugin**: `.claude-plugin/plugin.json` manifest with `pr-version-bump` skill and command
- **Change classification patterns**: `lib/patterns/change-classification.md` and `lib/patterns/version-discovery.md`

### Changed

- **Bootstrap loaders simplified**: `type-loader.yaml`, `execution-loader.yaml`, and `workflow-loader.yaml` significantly reduced by extracting shared fetch logic
- **Release workflow overhauled**: `.github/workflows/release.yaml` now supports PR-merge-driven releases with production/rc/beta channels
- **Node definitions**: Removed embedded examples from `workflow_nodes.yaml` (examples live in `examples/`)
- **Examples updated**: Schema versions bumped to 3.0, type references updated to v3 consolidated names
- **Entrypoints**: Added `fetch_patterns` query entry, cleaned up documentation references

## [3.0.0] - 2026-02-02

### BREAKING CHANGES

This release consolidates 38 specific types into 13 general-purpose types, reducing over-specification while maintaining full functionality. **Existing workflows using v2.x type names must be updated.**

See [docs/v3-migration.md](docs/v3-migration.md) for complete migration guide with before/after examples.

#### Consequences Consolidated (19 types → 7 types)

| Removed Types | Consolidated Into |
|---------------|-------------------|
| `clone_repo`, `git_pull`, `git_fetch`, `get_sha` | `git_ops_local` |
| `read_file`, `write_file`, `create_directory`, `delete_file` | `local_file_ops` |
| `run_script`, `run_python`, `run_bash` | `run_command` |
| `log_event`, `log_warning`, `log_error` | `log_entry` |
| `set_state`, `append_state`, `clear_state`, `merge_state` | `mutate_state` |
| `display_message`, `display_table` | `display` |
| `web_fetch`, `cache_web_content` | `web_ops` |

#### Preconditions Consolidated (19 types → 6 types)

| Removed Types | Consolidated Into |
|---------------|-------------------|
| `flag_set`, `flag_not_set`, `state_equals`, `state_not_null`, `state_is_null` | `state_check` |
| `tool_available`, `tool_version_gte`, `tool_authenticated`, `tool_daemon_ready` | `tool_check` |
| `config_exists`, `index_exists`, `index_is_placeholder`, `file_exists`, `directory_exists` | `path_check` |
| `source_exists`, `source_cloned`, `source_has_updates` | `source_check` |
| `log_initialized`, `log_level_enabled`, `log_finalized` | `log_state` |
| `fetch_succeeded`, `fetch_returned_content` | `fetch_check` |

#### Preconditions Eliminated (use `evaluate_expression`)

| Removed Types | Use Instead |
|---------------|-------------|
| `count_equals` | `evaluate_expression` with `len(field) == N` |
| `count_above` | `evaluate_expression` with `len(field) > N` |
| `count_below` | `evaluate_expression` with `len(field) < N` |

### Added

- **Migration guide**: `docs/v3-migration.md` with complete type mapping tables and before/after examples

### Changed

- **Type count reduced**: 43 consequences → 31, 27 preconditions → 14
- **Consolidated types use operation/capability/aspect parameters** to specify behavior
- **Updated examples** to use new consolidated type syntax

## [2.1.0] - 2026-02-02

### Changed

- **`match_3vl_rules` upgraded with Kleene logic lessons**:
  - Rule `U` now means "don't care" (wildcard) - condition is skipped entirely
  - State `U` vs Rule `T/F` now counts as soft match (uncertain satisfaction)
  - New ranking: `(-hard_matches, +soft_matches, +effective_conditions)`
    - Prefers more definite matches
    - Penalizes uncertain matches
    - Prefers more specific rules (fewer effective conditions)
  - `effective_conditions` = non-U conditions in rule (replaces total `condition_count`)
  - Added legacy compatibility fields (`score`, `condition_count`) for backward compatibility
  - Candidate objects now include: `hard_matches`, `soft_matches`, `effective_conditions`

### Notes

This update aligns `match_3vl_rules` with proper Kleene 3-valued logic semantics:
- `U AND F = F` (definite exclusion)
- `U AND T = U` (soft match - uncertain)
- `F AND U = F` (definite exclusion)
- `U AND U = U` (both uncertain - fallback candidate)
- `T AND T = T` (hard match)
- `T AND F = F` (exclusion)

## [2.0.0] - 2026-01-28

### BREAKING CHANGES

- **Removed bundle.yaml**: Types are now fetched directly from raw GitHub URLs
  - Use `source: hiivmind/hiivmind-blueprint-lib@v2.0.0` in workflow definitions
  - Resolves to `https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/`
- **No caching**: Types are always fetched fresh (simplest approach)
- **No lock files**: Removed types.lock - use exact version pins for reproducibility
- **Directory structure simplified**: Removed redundant `definitions/` level
  - `consequences/definitions/core/` → `consequences/core/`
  - `consequences/definitions/extensions/` → `consequences/extensions/`
  - `preconditions/definitions/core/` → `preconditions/core/`
  - `preconditions/definitions/extensions/` → `preconditions/extensions/`
  - `nodes/definitions/core/` → `nodes/core/`
- Update your workflow references from `hiivmind/hiivmind-blueprint-lib@v1.x.x` to `hiivmind/hiivmind-blueprint-lib@v2.0.0`

### Added

- **Workflows support**: Reusable workflow definitions in `workflows/` directory
- **intent-detection workflow**: Reusable 3VL intent detection for dynamic routing
  - Parses user input into flags, matches against rules, sets `computed.matched_action`
  - Handles disambiguation when multiple intents match
  - Reference: `hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection`
- `workflows/index.yaml` registry for workflow definitions
- `workflow` schema version (1.0)
- `logging/defaults.yaml` for framework logging configuration defaults

### Changed

- Simplified file paths (removed `definitions/` nesting)
- Updated all URLs to use new package name

### Removed

- `bundle.yaml` - no longer needed with direct raw GitHub URL approach

## [1.0.0] - 2026-01-27

### Added

Initial release extracted from hiivmind-blueprint lib/ directory.

#### Consequences (43 types)

**Core (30 types):**
- `core/state`: set_flag, set_state, append_state, clear_state, merge_state
- `core/evaluation`: evaluate, compute
- `core/interaction`: display_message, display_table
- `core/control`: create_checkpoint, rollback_checkpoint, spawn_agent
- `core/skill`: invoke_pattern, invoke_skill
- `core/utility`: set_timestamp, compute_hash
- `core/intent`: evaluate_keywords, parse_intent_flags, match_3vl_rules, dynamic_route
- `core/logging`: init_log, log_node, log_event, log_warning, log_error, log_session_snapshot, finalize_log, write_log, apply_log_retention, output_ci_summary

**Extensions (13 types):**
- `extensions/file-system`: read_file, write_file, create_directory, delete_file
- `extensions/git`: clone_repo, get_sha, git_pull, git_fetch
- `extensions/web`: web_fetch, cache_web_content
- `extensions/scripting`: run_script, run_python, run_bash

#### Preconditions (27 types)

**Core (22 types):**
- `core/filesystem`: config_exists, index_exists, index_is_placeholder, file_exists, directory_exists
- `core/state`: flag_set, flag_not_set, state_equals, state_not_null, state_is_null, count_equals, count_above, count_below
- `core/tool`: tool_available, python_module_available
- `core/composite`: all_of, any_of, none_of
- `core/expression`: evaluate_expression
- `core/logging`: log_initialized, log_level_enabled, log_finalized

**Extensions (5 types):**
- `extensions/source`: source_exists, source_cloned, source_has_updates
- `extensions/web`: fetch_succeeded, fetch_returned_content

#### Schemas
- `consequence-definition.json` (v1.1)
- `precondition-definition.json` (v1.0)
- `workflow-definitions.json` (v1.0) - schema for the definitions block in workflows

### Notes

- Schema version 1.1 for consequences includes: requires, execution, provides, alternatives, script fields
- Schema version 1.0 for preconditions provides: parameters, evaluation, examples, related
- All types support `${variable}` interpolation for string parameters
