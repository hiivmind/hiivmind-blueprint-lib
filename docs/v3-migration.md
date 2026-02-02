# Migrating to hiivmind-blueprint-lib v3.0

## Overview

v3.0 consolidates 38 specific types into 13 general-purpose types, reducing over-specification while maintaining full functionality.

**Consequences:** 19 specific types → 7 consolidated types
**Preconditions:** 19 specific types → 6 consolidated types (+ 3 eliminated via `evaluate_expression`)

This is a **breaking change**. Existing workflows using old type names will need to be updated.

---

## Consequences Migration

### Git Operations

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `clone_repo` | `git_ops_local` with `operation: "clone"` |
| `git_pull` | `git_ops_local` with `operation: "pull"` |
| `git_fetch` | `git_ops_local` with `operation: "fetch"` |
| `get_sha` | `git_ops_local` with `operation: "get-sha"` |

**Before (v2.x):**
```yaml
- type: clone_repo
  url: "${computed.repo_url}"
  dest: ".source/${computed.source_id}"
  store_as: clone_result
```

**After (v3.0):**
```yaml
- type: git_ops_local
  operation: clone
  args:
    url: "${computed.repo_url}"
    dest: ".source/${computed.source_id}"
  store_as: clone_result
```

**Before (v2.x):**
```yaml
- type: git_pull
  repo_path: ".source/${computed.source_id}"
```

**After (v3.0):**
```yaml
- type: git_ops_local
  operation: pull
  repo_path: ".source/${computed.source_id}"
```

**Before (v2.x):**
```yaml
- type: get_sha
  repo_path: ".source/${computed.source_id}"
  store_as: current_sha
```

**After (v3.0):**
```yaml
- type: git_ops_local
  operation: get-sha
  repo_path: ".source/${computed.source_id}"
  store_as: current_sha
```

---

### File Operations

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `read_file` | `local_file_ops` with `operation: "read"` |
| `write_file` | `local_file_ops` with `operation: "write"` |
| `create_directory` | `local_file_ops` with `operation: "mkdir"` |
| `delete_file` | `local_file_ops` with `operation: "delete"` |

**Before (v2.x):**
```yaml
- type: read_file
  path: "data/config.yaml"
  store_as: config
```

**After (v3.0):**
```yaml
- type: local_file_ops
  operation: read
  path: "data/config.yaml"
  store_as: config
```

**Before (v2.x):**
```yaml
- type: write_file
  path: "data/config.yaml"
  content: "${computed.new_config}"
```

**After (v3.0):**
```yaml
- type: local_file_ops
  operation: write
  path: "data/config.yaml"
  args:
    content: "${computed.new_config}"
```

**Before (v2.x):**
```yaml
- type: create_directory
  path: ".source/${computed.source_id}"
  recursive: true
```

**After (v3.0):**
```yaml
- type: local_file_ops
  operation: mkdir
  path: ".source/${computed.source_id}"
  args:
    recursive: true
```

---

### Script Execution

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `run_bash` | `run_command` with `interpreter: "bash"` |
| `run_python` | `run_command` with `interpreter: "python"` |
| `run_script` | `run_command` with appropriate `interpreter` |

**Before (v2.x):**
```yaml
- type: run_bash
  script: "echo 'Hello World'"
  store_as: output
```

**After (v3.0):**
```yaml
- type: run_command
  interpreter: bash
  script: "echo 'Hello World'"
  store_as: output
```

**Before (v2.x):**
```yaml
- type: run_python
  script: "print('Hello World')"
  store_as: output
```

**After (v3.0):**
```yaml
- type: run_command
  interpreter: python
  script: "print('Hello World')"
  store_as: output
```

---

### Logging

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `log_event` | `log_entry` with `level: "info"` |
| `log_warning` | `log_entry` with `level: "warning"` |
| `log_error` | `log_entry` with `level: "error"` |

**Before (v2.x):**
```yaml
- type: log_event
  message: "Processing started"
  context:
    source_id: "${computed.source_id}"
```

**After (v3.0):**
```yaml
- type: log_entry
  level: info
  message: "Processing started"
  context:
    source_id: "${computed.source_id}"
```

**Before (v2.x):**
```yaml
- type: log_warning
  message: "Rate limit approaching"
```

**After (v3.0):**
```yaml
- type: log_entry
  level: warning
  message: "Rate limit approaching"
```

**Before (v2.x):**
```yaml
- type: log_error
  message: "Clone failed"
  context:
    error: "${computed.error}"
```

**After (v3.0):**
```yaml
- type: log_entry
  level: error
  message: "Clone failed"
  context:
    error: "${computed.error}"
```

---

### State Mutation

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `set_state` | `mutate_state` with `operation: "set"` |
| `append_state` | `mutate_state` with `operation: "append"` |
| `clear_state` | `mutate_state` with `operation: "clear"` |
| `merge_state` | `mutate_state` with `operation: "merge"` |

**Before (v2.x):**
```yaml
- type: set_state
  field: computed.repo_url
  value: "https://github.com/pola-rs/polars"
```

**After (v3.0):**
```yaml
- type: mutate_state
  operation: set
  field: computed.repo_url
  value: "https://github.com/pola-rs/polars"
```

**Before (v2.x):**
```yaml
- type: append_state
  field: computed.sources
  value: "${computed.new_source}"
```

**After (v3.0):**
```yaml
- type: mutate_state
  operation: append
  field: computed.sources
  value: "${computed.new_source}"
```

**Before (v2.x):**
```yaml
- type: clear_state
  field: computed.temp_data
```

**After (v3.0):**
```yaml
- type: mutate_state
  operation: clear
  field: computed.temp_data
```

**Before (v2.x):**
```yaml
- type: merge_state
  field: computed.config
  value:
    new_key: "new_value"
```

**After (v3.0):**
```yaml
- type: mutate_state
  operation: merge
  field: computed.config
  value:
    new_key: "new_value"
```

---

### Display

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `display_message` | `display` with `format: "text"` |
| `display_table` | `display` with `format: "table"` |

**Before (v2.x):**
```yaml
- type: display_message
  message: "Operation completed successfully"
```

**After (v3.0):**
```yaml
- type: display
  format: text
  content: "Operation completed successfully"
```

**Before (v2.x):**
```yaml
- type: display_table
  data: "${computed.sources}"
  columns:
    - id
    - name
    - type
```

**After (v3.0):**
```yaml
- type: display
  format: table
  content: "${computed.sources}"
  args:
    columns:
      - id
      - name
      - type
```

---

### Web Operations

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `web_fetch` | `web_ops` with `operation: "fetch"` |
| `cache_web_content` | `web_ops` with `operation: "cache"` |

**Before (v2.x):**
```yaml
- type: web_fetch
  url: "https://api.github.com/repos/pola-rs/polars"
  store_as: repo_info
```

**After (v3.0):**
```yaml
- type: web_ops
  operation: fetch
  url: "https://api.github.com/repos/pola-rs/polars"
  store_as: repo_info
```

**Before (v2.x):**
```yaml
- type: cache_web_content
  url: "https://example.com/data.json"
  cache_path: ".cache/data.json"
  ttl: 3600
```

**After (v3.0):**
```yaml
- type: web_ops
  operation: cache
  url: "https://example.com/data.json"
  args:
    cache_path: ".cache/data.json"
    ttl: 3600
```

---

## Preconditions Migration

### State Checking

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `flag_set` | `state_check` with `operator: "true"` |
| `flag_not_set` | `state_check` with `operator: "false"` |
| `state_equals` | `state_check` with `operator: "equals"` |
| `state_not_null` | `state_check` with `operator: "not_null"` |
| `state_is_null` | `state_check` with `operator: "null"` |

**Before (v2.x):**
```yaml
condition:
  type: flag_set
  flag: config_loaded
```

**After (v3.0):**
```yaml
condition:
  type: state_check
  field: flags.config_loaded
  operator: "true"
```

**Before (v2.x):**
```yaml
condition:
  type: flag_not_set
  flag: error_occurred
```

**After (v3.0):**
```yaml
condition:
  type: state_check
  field: flags.error_occurred
  operator: "false"
```

**Before (v2.x):**
```yaml
condition:
  type: state_equals
  field: source_type
  value: git
```

**After (v3.0):**
```yaml
condition:
  type: state_check
  field: source_type
  operator: equals
  value: git
```

**Before (v2.x):**
```yaml
condition:
  type: state_not_null
  field: computed.repo_url
```

**After (v3.0):**
```yaml
condition:
  type: state_check
  field: computed.repo_url
  operator: not_null
```

**Before (v2.x):**
```yaml
condition:
  type: state_is_null
  field: computed.error
```

**After (v3.0):**
```yaml
condition:
  type: state_check
  field: computed.error
  operator: "null"
```

---

### Array Length (use evaluate_expression)

These types have been **eliminated**. Use `evaluate_expression` with `len()` instead.

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `count_equals` | `evaluate_expression` with `len(field) == value` |
| `count_above` | `evaluate_expression` with `len(field) > value` |
| `count_below` | `evaluate_expression` with `len(field) < value` |

**Before (v2.x):**
```yaml
condition:
  type: count_equals
  field: computed.sources
  count: 0
```

**After (v3.0):**
```yaml
condition:
  type: evaluate_expression
  expression: "len(computed.sources) == 0"
```

**Before (v2.x):**
```yaml
condition:
  type: count_above
  field: computed.sources
  min: 0
```

**After (v3.0):**
```yaml
condition:
  type: evaluate_expression
  expression: "len(computed.sources) > 0"
```

**Before (v2.x):**
```yaml
condition:
  type: count_below
  field: computed.items
  max: 100
```

**After (v3.0):**
```yaml
condition:
  type: evaluate_expression
  expression: "len(computed.items) < 100"
```

---

### Tool Checking

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `tool_available` | `tool_check` with `capability: "available"` |
| `tool_version_gte` | `tool_check` with `capability: "version_gte"` |
| `tool_authenticated` | `tool_check` with `capability: "authenticated"` |
| `tool_daemon_ready` | `tool_check` with `capability: "daemon_ready"` |

**Before (v2.x):**
```yaml
condition:
  type: tool_available
  tool: git
```

**After (v3.0):**
```yaml
condition:
  type: tool_check
  tool: git
  capability: available
```

**Before (v2.x):**
```yaml
condition:
  type: tool_version_gte
  tool: node
  min_version: "18.0"
```

**After (v3.0):**
```yaml
condition:
  type: tool_check
  tool: node
  capability: version_gte
  args:
    min_version: "18.0"
```

**Before (v2.x):**
```yaml
condition:
  type: tool_authenticated
  tool: gh
```

**After (v3.0):**
```yaml
condition:
  type: tool_check
  tool: gh
  capability: authenticated
```

**Before (v2.x):**
```yaml
condition:
  type: tool_daemon_ready
  tool: docker
```

**After (v3.0):**
```yaml
condition:
  type: tool_check
  tool: docker
  capability: daemon_ready
```

---

### Path Checking

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `config_exists` | `path_check` with `path: "data/config.yaml"` and `check: "is_file"` |
| `index_exists` | `path_check` with `path: "data/index.md"` and `check: "is_file"` |
| `index_is_placeholder` | `path_check` with `check: "contains_text"` |
| `file_exists` | `path_check` with `check: "is_file"` |
| `directory_exists` | `path_check` with `check: "is_directory"` |

**Before (v2.x):**
```yaml
condition:
  type: config_exists
```

**After (v3.0):**
```yaml
condition:
  type: path_check
  path: "data/config.yaml"
  check: is_file
```

**Before (v2.x):**
```yaml
condition:
  type: index_exists
```

**After (v3.0):**
```yaml
condition:
  type: path_check
  path: "data/index.md"
  check: is_file
```

**Before (v2.x):**
```yaml
condition:
  type: index_is_placeholder
```

**After (v3.0):**
```yaml
condition:
  type: path_check
  path: "data/index.md"
  check: contains_text
  args:
    pattern: "Run hiivmind-corpus-build"
```

**Before (v2.x):**
```yaml
condition:
  type: file_exists
  path: "data/config.yaml"
```

**After (v3.0):**
```yaml
condition:
  type: path_check
  path: "data/config.yaml"
  check: is_file
```

**Before (v2.x):**
```yaml
condition:
  type: directory_exists
  path: ".source/${computed.source_id}"
```

**After (v3.0):**
```yaml
condition:
  type: path_check
  path: ".source/${computed.source_id}"
  check: is_directory
```

---

### Source Checking

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `source_exists` | `source_check` with `aspect: "exists"` |
| `source_cloned` | `source_check` with `aspect: "cloned"` |
| `source_has_updates` | `source_check` with `aspect: "has_updates"` |

**Before (v2.x):**
```yaml
condition:
  type: source_exists
  id: polars
```

**After (v3.0):**
```yaml
condition:
  type: source_check
  source_id: polars
  aspect: exists
```

**Before (v2.x):**
```yaml
condition:
  type: source_cloned
  id: "${computed.source_id}"
```

**After (v3.0):**
```yaml
condition:
  type: source_check
  source_id: "${computed.source_id}"
  aspect: cloned
```

**Before (v2.x):**
```yaml
condition:
  type: source_has_updates
  id: "${computed.source_id}"
```

**After (v3.0):**
```yaml
condition:
  type: source_check
  source_id: "${computed.source_id}"
  aspect: has_updates
```

---

### Logging State

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `log_initialized` | `log_state` with `aspect: "initialized"` |
| `log_finalized` | `log_state` with `aspect: "finalized"` |
| `log_level_enabled` | `log_state` with `aspect: "level_enabled"` |

**Before (v2.x):**
```yaml
condition:
  type: log_initialized
```

**After (v3.0):**
```yaml
condition:
  type: log_state
  aspect: initialized
```

**Before (v2.x):**
```yaml
condition:
  type: log_finalized
```

**After (v3.0):**
```yaml
condition:
  type: log_state
  aspect: finalized
```

**Before (v2.x):**
```yaml
condition:
  type: log_level_enabled
  level: debug
```

**After (v3.0):**
```yaml
condition:
  type: log_state
  aspect: level_enabled
  args:
    level: debug
```

---

### Fetch Results

| v2.x Type | v3.0 Equivalent |
|-----------|-----------------|
| `fetch_succeeded` | `fetch_check` with `aspect: "succeeded"` |
| `fetch_returned_content` | `fetch_check` with `aspect: "has_content"` |

**Before (v2.x):**
```yaml
condition:
  type: fetch_succeeded
  from: computed.page_fetch
```

**After (v3.0):**
```yaml
condition:
  type: fetch_check
  from: computed.page_fetch
  aspect: succeeded
```

**Before (v2.x):**
```yaml
condition:
  type: fetch_returned_content
  from: computed.page_fetch
```

**After (v3.0):**
```yaml
condition:
  type: fetch_check
  from: computed.page_fetch
  aspect: has_content
```

---

## Types Unchanged

The following types remain the same in v3.0:

### Consequences (unchanged)
- `create_checkpoint`
- `rollback_checkpoint`
- `spawn_agent`
- `invoke_skill`
- `inline`
- `evaluate`
- `compute`
- `set_flag`
- `set_timestamp`
- `compute_hash`
- `evaluate_keywords`
- `parse_intent_flags`
- `match_3vl_rules`
- `dynamic_route`
- `init_log`
- `log_node`
- `log_session_snapshot`
- `finalize_log`
- `write_log`
- `apply_log_retention`
- `output_ci_summary`
- `install_tool`

### Preconditions (unchanged)
- `all_of`
- `any_of`
- `none_of`
- `xor_of`
- `evaluate_expression`
- `python_module_available`
- `network_available`

---

## Quick Reference

### Consequence Type Mapping

| v2.x | v3.0 | Operation/Format Parameter |
|------|------|---------------------------|
| `clone_repo` | `git_ops_local` | `operation: clone` |
| `git_pull` | `git_ops_local` | `operation: pull` |
| `git_fetch` | `git_ops_local` | `operation: fetch` |
| `get_sha` | `git_ops_local` | `operation: get-sha` |
| `read_file` | `local_file_ops` | `operation: read` |
| `write_file` | `local_file_ops` | `operation: write` |
| `create_directory` | `local_file_ops` | `operation: mkdir` |
| `delete_file` | `local_file_ops` | `operation: delete` |
| `run_bash` | `run_command` | `interpreter: bash` |
| `run_python` | `run_command` | `interpreter: python` |
| `run_script` | `run_command` | `interpreter: <any>` |
| `log_event` | `log_entry` | `level: info` |
| `log_warning` | `log_entry` | `level: warning` |
| `log_error` | `log_entry` | `level: error` |
| `set_state` | `mutate_state` | `operation: set` |
| `append_state` | `mutate_state` | `operation: append` |
| `clear_state` | `mutate_state` | `operation: clear` |
| `merge_state` | `mutate_state` | `operation: merge` |
| `display_message` | `display` | `format: text` |
| `display_table` | `display` | `format: table` |
| `web_fetch` | `web_ops` | `operation: fetch` |
| `cache_web_content` | `web_ops` | `operation: cache` |

### Precondition Type Mapping

| v2.x | v3.0 | Operator/Capability/Aspect |
|------|------|---------------------------|
| `flag_set` | `state_check` | `operator: "true"` |
| `flag_not_set` | `state_check` | `operator: "false"` |
| `state_equals` | `state_check` | `operator: equals` |
| `state_not_null` | `state_check` | `operator: not_null` |
| `state_is_null` | `state_check` | `operator: "null"` |
| `count_equals` | `evaluate_expression` | `len(field) == N` |
| `count_above` | `evaluate_expression` | `len(field) > N` |
| `count_below` | `evaluate_expression` | `len(field) < N` |
| `tool_available` | `tool_check` | `capability: available` |
| `tool_version_gte` | `tool_check` | `capability: version_gte` |
| `tool_authenticated` | `tool_check` | `capability: authenticated` |
| `tool_daemon_ready` | `tool_check` | `capability: daemon_ready` |
| `config_exists` | `path_check` | `check: is_file` (path: data/config.yaml) |
| `index_exists` | `path_check` | `check: is_file` (path: data/index.md) |
| `index_is_placeholder` | `path_check` | `check: contains_text` |
| `file_exists` | `path_check` | `check: is_file` |
| `directory_exists` | `path_check` | `check: is_directory` |
| `source_exists` | `source_check` | `aspect: exists` |
| `source_cloned` | `source_check` | `aspect: cloned` |
| `source_has_updates` | `source_check` | `aspect: has_updates` |
| `log_initialized` | `log_state` | `aspect: initialized` |
| `log_finalized` | `log_state` | `aspect: finalized` |
| `log_level_enabled` | `log_state` | `aspect: level_enabled` |
| `fetch_succeeded` | `fetch_check` | `aspect: succeeded` |
| `fetch_returned_content` | `fetch_check` | `aspect: has_content` |
