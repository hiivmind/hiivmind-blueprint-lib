# Changelog

All notable changes to hiivmind-blueprint-lib will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
