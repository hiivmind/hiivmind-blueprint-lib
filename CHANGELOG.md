# Changelog

All notable changes to hiivmind-blueprint-types will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
