# hiivmind-blueprint Examples

Three composite workflows demonstrating all 34 types from `blueprint-types.md`
in realistic end-to-end context. Each workflow is valid Blueprint YAML using
the compressed schema (v3.0): `consequences:` everywhere, flattened
`on_true`/`on_false`, optional `on_failure`, condition shorthand, and
response handler string sugar.

---

## 1. Source Onboarding

Check prerequisites, prompt for source type, clone a git repo, checkpoint
state before risky operations.

**Types demonstrated:** `action`, `conditional`, `user_prompt`, `composite`,
`tool_check`, `path_check`, `state_check`, `network_available`, `set_flag`,
`mutate_state`, `display`, `log_node`, `log_entry`, `local_file_ops`,
`git_ops_local`, `set_timestamp`, `create_checkpoint`, `rollback_checkpoint`,
`install_tool`

**Compression patterns:** `consequences:` rename, composite `all:` shorthand,
default `on_failure` routing, bare response handler (`local: done`)

```yaml
name: source-onboarding
version: "1.0.0"
description: Onboard a new git source — check tools, prompt for details, clone and configure.

start_node: check_prerequisites
default_error: error_generic

initial_state:
  phase: setup
  output:
    level: normal

nodes:
  check_prerequisites:
    type: conditional
    description: Verify required tools and network
    condition:
      all:
        - type: tool_check
          tool: git
          capability: available
        - type: tool_check
          tool: yq
          capability: version_gte
          args:
            min_version: "4.0"
        - type: network_available
    on_true: check_config
    on_false: install_missing_tools

  install_missing_tools:
    type: action
    description: Attempt to install yq if missing
    consequences:
      - type: install_tool
        tool: yq
        install_command: "snap install yq"
      - type: log_entry
        level: info
        message: "Installed missing tool: yq"
    on_success: check_config

  check_config:
    type: conditional
    description: Check if config.yaml already exists
    condition:
      type: path_check
      path: "data/config.yaml"
      check: is_file
    on_true: load_config
    on_false: ask_source_type

  load_config:
    type: action
    description: Read existing config and verify it has a sources array
    consequences:
      - type: local_file_ops
        operation: read
        path: "data/config.yaml"
        store_as: computed.config
      - type: set_flag
        flag: config_loaded
        value: true
      - type: log_node
        node: load_config
        outcome: success
    on_success: verify_config
    on_failure: error_config_read

  verify_config:
    type: conditional
    description: Check config has a sources array
    condition:
      type: state_check
      field: computed.config.sources
      operator: not_null
    on_true: ask_source_type
    on_false: init_sources

  init_sources:
    type: action
    consequences:
      - type: mutate_state
        operation: set
        field: computed.config.sources
        value: []
    on_success: ask_source_type

  ask_source_type:
    type: user_prompt
    prompt:
      question: "What type of source do you want to add?"
      header: "Source"
      options:
        - id: git
          label: "Git repository"
          description: "Clone a git repo and index its contents"
        - id: local
          label: "Local directory"
          description: "Index files from a local path"
    on_response:
      git:
        consequences:
          - type: mutate_state
            operation: set
            field: source_type
            value: git
        next_node: checkpoint_before_clone
      local: done

  checkpoint_before_clone:
    type: action
    description: Save state before clone (risky network operation)
    consequences:
      - type: create_checkpoint
        name: before_clone
      - type: set_timestamp
        store_as: computed.clone_started_at
      - type: display
        content: "Cloning repository..."
    on_success: clone_repo

  clone_repo:
    type: action
    description: Clone the git repository
    consequences:
      - type: git_ops_local
        operation: clone
        args:
          url: "${computed.repo_url}"
          dest: ".source/${computed.source_id}"
          depth: 1
      - type: log_node
        node: clone_repo
        outcome: success
        details:
          url: "${computed.repo_url}"
    on_success: done
    on_failure: rollback_clone

  rollback_clone:
    type: action
    description: Restore state after failed clone
    consequences:
      - type: rollback_checkpoint
        name: before_clone
      - type: log_entry
        level: error
        message: "Clone failed, state restored from checkpoint"
    on_success: error_clone_failed

endings:
  done:
    type: success
    message: "Source onboarded: ${computed.source_id}"
  error_generic:
    type: error
    message: "Unexpected failure at ${current_node}"
  error_config_read:
    type: error
    message: "Failed to read config.yaml"
  error_clone_failed:
    type: failure
    message: "Clone failed for ${computed.repo_url}"
```

---

## 2. Web Content Pipeline

Verify a source exists, check for cached content, fetch a web page, hash for
change detection, process with a Python script, spawn a parallel indexing agent.

**Types demonstrated:** `action`, `conditional`, `evaluate_expression`,
`python_module_available`, `fetch_check`, `source_check`, `path_check`,
`web_ops`, `compute_hash`, `run_command`, `compute`, `evaluate`,
`spawn_agent`, `inline`

**Compression patterns:** condition string shorthand
(`"flags.content_changed == true"`), default `on_failure` routing

```yaml
name: web-content-pipeline
version: "1.0.0"
description: Fetch web content, detect changes via hashing, process with Python.

start_node: verify_source
default_error: error_generic

initial_state:
  phase: pipeline

nodes:
  verify_source:
    type: conditional
    description: Ensure source is configured and cloned
    condition:
      type: source_check
      source_id: "${computed.source_id}"
      aspect: cloned
    on_true: check_python
    on_false: error_no_source

  check_python:
    type: conditional
    description: Verify Python yaml module is available for processing
    condition:
      type: python_module_available
      module: yaml
    on_true: check_cache
    on_false: error_no_python

  check_cache:
    type: conditional
    description: Skip fetch if content is already cached
    condition:
      type: path_check
      path: ".cache/${computed.source_id}.md"
      check: is_file
    on_true: done_cached
    on_false: fetch_content

  fetch_content:
    type: action
    description: Fetch web page and store result
    consequences:
      - type: web_ops
        operation: fetch
        url: "${computed.page_url}"
        prompt: "Extract the main documentation content"
        allow_failure: true
        store_as: computed.fetch_result
    on_success: check_fetch

  check_fetch:
    type: conditional
    description: Verify fetch returned usable content
    condition:
      type: fetch_check
      from: computed.fetch_result
      aspect: has_content
    on_true: hash_content
    on_false: error_empty_fetch

  hash_content:
    type: action
    description: Hash fetched content and check for changes
    consequences:
      - type: compute_hash
        from: computed.fetch_result.content
        store_as: computed.new_hash
      - type: evaluate
        expression: "computed.new_hash != computed.previous_hash"
        set_flag: content_changed
    on_success: check_changed

  check_changed:
    type: conditional
    description: Only process if content actually changed
    condition: "flags.content_changed == true"
    on_true: process_content
    on_false: done_no_changes

  process_content:
    type: action
    description: Clean content, compute output path, run processing script
    consequences:
      - type: compute
        expression: "computed.output_dir + '/' + computed.source_id + '.md'"
        store_as: computed.output_path
      - type: inline
        description: "Normalize line endings and strip HTML comments"
        pseudocode: |
          content = state.computed.fetch_result.content
          content = content.replace("\r\n", "\n")
          content = regex_remove("<!--.*?-->", content)
          return content
        store_as: computed.cleaned_content
      - type: run_command
        script: "scripts/process.py"
        interpreter: python
        args:
          - "${computed.output_path}"
        store_as: computed.process_output
    on_success: spawn_indexer

  spawn_indexer:
    type: action
    description: Spawn parallel agent to update the index
    consequences:
      - type: spawn_agent
        subagent_type: general-purpose
        prompt: "Update the index at data/index.md to include ${computed.source_id}"
        store_as: computed.index_result
        run_in_background: true
    on_success: cache_content

  cache_content:
    type: action
    description: Cache fetched content locally for next run
    consequences:
      - type: web_ops
        operation: cache
        from: computed.fetch_result
        dest: ".cache/${computed.source_id}.md"
    on_success: done_processed

endings:
  done_processed:
    type: success
    message: "Content processed: ${computed.source_id}"
  done_no_changes:
    type: success
    message: "No changes detected for ${computed.source_id}"
  done_cached:
    type: success
    message: "Using cached content for ${computed.source_id}"
  error_generic:
    type: error
    message: "Unexpected failure at ${current_node}"
  error_no_source:
    type: error
    message: "Source not cloned: ${computed.source_id}"
  error_no_python:
    type: error
    message: "Python yaml module not available"
  error_empty_fetch:
    type: failure
    message: "Fetch returned empty content"
```

---

## 3. Intent-Driven Router

Parse user input with 3VL keyword matching, match against intent rules,
display candidates if ambiguous, route to the winning skill.

**Types demonstrated:** `action`, `user_prompt`, `composite`, `state_check`,
`evaluate_expression`, `evaluate_keywords`, `parse_intent_flags`,
`match_3vl_rules`, `display`, `invoke_skill`, `mutate_state`, `log_entry`

**Compression patterns:** composite `all:` shorthand, condition string
shorthand, bare response handler (`browse: show_capabilities`,
`done: exit_success`), dynamic `${}` routing
(`"${user_responses.show_candidates.action}"`), FSM loop pattern

```yaml
name: intent-router
version: "1.0.0"
description: Parse user input with 3VL intent detection and route to the matching skill.

start_node: get_input
default_error: error_generic

initial_state:
  phase: routing

nodes:
  get_input:
    type: user_prompt
    prompt:
      question: "What would you like to do?"
      header: "Intent"
      options:
        - id: typed
          label: "Type a request"
          description: "Describe what you need in your own words"
        - id: browse
          label: "Browse capabilities"
          description: "See a list of available skills"
    on_response:
      typed:
        consequences:
          - type: mutate_state
            operation: set
            field: computed.mode
            value: parse
        next_node: parse_keywords
      browse: show_capabilities

  parse_keywords:
    type: action
    description: Quick keyword check before full 3VL parsing
    consequences:
      - type: evaluate_keywords
        input: "${computed.user_input}"
        keyword_sets:
          build: [build, create, scaffold, generate]
          navigate: [find, search, look up, docs, documentation]
          maintain: [update, refresh, sync, check]
        store_as: computed.keyword_match
    on_success: check_keyword_match

  check_keyword_match:
    type: conditional
    description: If keyword match is confident, skip full 3VL parse
    condition:
      all:
        - type: state_check
          field: computed.keyword_match
          operator: not_null
        - type: evaluate_expression
          expression: "computed.confidence > 0.8"
    on_true: route_to_skill
    on_false: full_3vl_parse

  full_3vl_parse:
    type: action
    description: Parse intent flags and match against rule table
    consequences:
      - type: parse_intent_flags
        input: "${computed.user_input}"
        flag_definitions:
          wants_creation:
            keywords: [build, create, new, scaffold, generate]
            negative_keywords: [delete, remove, existing]
          wants_query:
            keywords: [find, search, look, show, list, docs]
            negative_keywords: [create, build, update]
          wants_maintenance:
            keywords: [update, refresh, sync, check, fix]
            negative_keywords: [create, new]
        store_as: computed.intent_flags
      - type: match_3vl_rules
        flags: "${computed.intent_flags}"
        rules:
          - name: build
            conditions: { wants_creation: T, wants_query: F }
            action: build_skill
          - name: navigate
            conditions: { wants_query: T }
            action: navigate_skill
          - name: maintain
            conditions: { wants_maintenance: T, wants_creation: F }
            action: maintain_skill
        store_as: computed.match_result
      - type: log_entry
        level: info
        message: "3VL match: ${computed.match_result.winner}"
        context:
          flags: "${computed.intent_flags}"
    on_success: check_clear_winner

  check_clear_winner:
    type: conditional
    description: Check if 3VL produced a clear winner
    condition: "computed.match_result.clear_winner == true"
    on_true: route_to_skill
    on_false: show_candidates

  show_candidates:
    type: user_prompt
    description: Present top candidates as dynamic options for user to choose
    prompt:
      question: "Multiple matches found. Which skill do you want?"
      header: "Choose"
      options_from_state: computed.match_result.top_candidates
      options:
        id: "candidate.action"
        label: "candidate.name"
        description: "candidate.score"
    on_response:
      selected: "${user_responses.show_candidates.action}"

  route_to_skill:
    type: action
    description: Invoke the matched skill
    consequences:
      - type: mutate_state
        operation: set
        field: computed.routed_skill
        value: "${computed.match_result.winner}"
      - type: invoke_skill
        skill: "${computed.routed_skill}"
      - type: mutate_state
        operation: append
        field: computed.completed_skills
        value: "${computed.routed_skill}"
    on_success: ask_continue

  ask_continue:
    type: user_prompt
    description: FSM loop — return to main menu or exit
    prompt:
      question: "Skill complete. What next?"
      header: "Continue?"
      options:
        - id: again
          label: "Do something else"
          description: "Return to the main menu"
        - id: done
          label: "I'm finished"
          description: "Exit the workflow"
    on_response:
      again:
        consequences:
          - type: mutate_state
            operation: clear
            field: computed.match_result
          - type: log_entry
            level: info
            message: "Looping back to main menu"
        next_node: get_input
      done: exit_success

  show_capabilities:
    type: action
    description: List available skills
    consequences:
      - type: display
        format: markdown
        content: |
          ## Available Skills
          - **build** — Create new workflows and skills
          - **navigate** — Search and browse documentation
          - **maintain** — Update, refresh, and check existing work
    on_success: get_input

endings:
  exit_success:
    type: success
    message: "Session complete. Skills used: ${computed.completed_skills}"
  error_generic:
    type: error
    message: "Unexpected failure at ${current_node}"
```
