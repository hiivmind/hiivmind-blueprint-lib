# Workflow Schema Compression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compress workflow YAML by ~30-40% through structural changes (consequences rename, default failure routing, ternary conditionals, condition/handler sugar) while maintaining deterministic Python-traversable structure.

**Architecture:** Six schema-level changes normalize sugar forms to canonical form at parse time. The JSON schemas accept both sugar and canonical forms. The type catalog (`blueprint-types.md`) and all examples update to use the compressed syntax. The real intent-detection workflow also updates.

**Tech Stack:** JSON Schema (draft 2020-12), YAML, Markdown

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `schema/authoring/node-types.json` | Modify | All node-level structural changes |
| `schema/authoring/workflow.json` | Modify | Add `default_error`, confirm `initial_state` optional |
| `blueprint-types.md` | Modify | Update node signatures and conventions |
| `examples.md` | Rewrite | 3 workflows using compressed syntax |
| `workflows/core/intent-detection.yaml` | Modify | Update to compressed format |
| `README.md` | Modify | Update workflow snippet and node types table |
| `CLAUDE.md` | Modify | Update conventions reference |
| `CHANGELOG.md` | Modify | Add compression entry under v7.0.0 |

---

### Task 1: Schema — node-types.json structural changes

**Files:**
- Modify: `schema/authoring/node-types.json`

This task covers: `consequences` rename, flatten branches, ternary conditionals, optional `on_failure`, condition sugar, response handler sugar. All changes are in one file.

- [ ] **Step 1: Update `$comment` version**

In `schema/authoring/node-types.json`, change line 4:

```json
"$comment": "Schema version 2.0 - Node type definitions. validation_gate deprecated in favor of conditional with audit.",
```

to:

```json
"$comment": "Schema version 3.0 - Workflow schema compression: consequences rename, ternary conditionals, condition/handler sugar.",
```

- [ ] **Step 2: Rename `actions` to `consequences` in action_node and remove `on_failure` from required**

In `schema/authoring/node-types.json`, replace the entire `action_node` definition (lines 38-58):

```json
    "action_node": {
      "type": "object",
      "required": ["actions", "on_success", "on_failure"],
      "properties": {
        "type": { "const": "action" },
        "description": { "type": "string" },
        "actions": {
          "type": "array",
          "items": { "$ref": "#/$defs/consequence" },
          "minItems": 1,
          "description": "Consequences to execute sequentially"
        },
        "on_success": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node or ending to transition to on success"
        },
        "on_failure": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node or ending to transition to on failure"
        }
      }
    },
```

with:

```json
    "action_node": {
      "type": "object",
      "required": ["consequences", "on_success"],
      "properties": {
        "type": { "const": "action" },
        "description": { "type": "string" },
        "consequences": {
          "type": "array",
          "items": { "$ref": "#/$defs/consequence" },
          "minItems": 1,
          "description": "Consequences to execute sequentially"
        },
        "on_success": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node or ending to transition to on success"
        },
        "on_failure": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node or ending to transition to on failure. When omitted, routes to workflow default_error."
        }
      }
    },
```

- [ ] **Step 3: Flatten branches and add ternary support in conditional_node**

Replace the entire `conditional_node` definition (lines 60-110):

```json
    "conditional_node": {
      "type": "object",
      "required": ["condition", "branches"],
      "properties": {
        "type": { "const": "conditional" },
        "description": { "type": "string" },
        "condition": {
          "$ref": "#/$defs/precondition",
          "description": "Condition to evaluate (often a composite like all_of, any_of, xor_of)"
        },
        "audit": {
          "type": "object",
          "description": "Enable audit mode for comprehensive condition evaluation without short-circuiting",
          "properties": {
            "enabled": {
              "type": "boolean",
              "default": false,
              "description": "Enable audit mode (evaluate all conditions, collect results)"
            },
            "output": {
              "type": "string",
              "default": "computed.audit_results",
              "description": "State path where audit results are written"
            },
            "messages": {
              "type": "object",
              "description": "Error messages keyed by precondition type name",
              "additionalProperties": {
                "type": "string"
              }
            }
          },
          "additionalProperties": false
        },
        "branches": {
          "type": "object",
          "description": "Branch targets for true/false conditions",
          "required": ["on_true", "on_false"],
          "properties": {
            "on_true": {
              "$ref": "../common.json#/$defs/node_reference",
              "description": "Node to transition to if condition is true"
            },
            "on_false": {
              "$ref": "../common.json#/$defs/node_reference",
              "description": "Node to transition to if condition is false"
            }
          },
          "additionalProperties": false
        }
      }
    },
```

with:

```json
    "conditional_node": {
      "type": "object",
      "required": ["condition", "on_true", "on_false"],
      "properties": {
        "type": { "const": "conditional" },
        "description": { "type": "string" },
        "condition": {
          "description": "Condition to evaluate. String = evaluate_expression shorthand. Object with all/any/none/xor key (no type key) = composite shorthand. Object with type key = canonical precondition.",
          "oneOf": [
            { "type": "string" },
            { "type": "object" }
          ]
        },
        "audit": {
          "type": "object",
          "description": "Enable audit mode for comprehensive condition evaluation without short-circuiting",
          "properties": {
            "enabled": {
              "type": "boolean",
              "default": false,
              "description": "Enable audit mode (evaluate all conditions, collect results)"
            },
            "output": {
              "type": "string",
              "default": "computed.audit_results",
              "description": "State path where audit results are written"
            },
            "messages": {
              "type": "object",
              "description": "Error messages keyed by precondition type name",
              "additionalProperties": {
                "type": "string"
              }
            }
          },
          "additionalProperties": false
        },
        "on_true": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node to transition to if condition is true"
        },
        "on_false": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node to transition to if condition is false"
        },
        "on_unknown": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node to transition to if condition evaluation fails. When omitted, routes to workflow default_error."
        }
      }
    },
```

- [ ] **Step 4: Update response handler — rename `consequence` to `consequences` and add string sugar**

Replace the `user_prompt_node` definition's `on_response` property (lines 123-129):

```json
        "on_response": {
          "type": "object",
          "description": "Map of option IDs to response handlers",
          "additionalProperties": {
            "$ref": "#/$defs/response_handler"
          }
        }
```

with:

```json
        "on_response": {
          "type": "object",
          "description": "Map of option IDs to response handlers. String value = shorthand for {next_node: value}.",
          "additionalProperties": {
            "oneOf": [
              { "type": "string" },
              { "$ref": "#/$defs/response_handler" }
            ]
          }
        }
```

Then replace the `response_handler` definition (lines 212-225):

```json
    "response_handler": {
      "type": "object",
      "properties": {
        "consequence": {
          "type": "array",
          "items": { "$ref": "#/$defs/consequence" },
          "description": "Consequences to apply when this option is selected"
        },
        "next_node": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node to transition to"
        }
      }
    },
```

with:

```json
    "response_handler": {
      "type": "object",
      "properties": {
        "consequences": {
          "type": "array",
          "items": { "$ref": "#/$defs/consequence" },
          "description": "Consequences to apply when this option is selected"
        },
        "next_node": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Node to transition to (supports ${} interpolation for dynamic routing)"
        }
      }
    },
```

- [ ] **Step 5: Commit**

```bash
git add schema/authoring/node-types.json
git commit -m "refactor: compress node-types schema — consequences rename, ternary conditionals, sugar"
```

---

### Task 2: Schema — workflow.json

**Files:**
- Modify: `schema/authoring/workflow.json`

- [ ] **Step 1: Add `default_error` to required fields and properties**

In `schema/authoring/workflow.json`, change the `required` array (line 8):

```json
  "required": ["name", "version", "start_node", "nodes", "endings"],
```

to:

```json
  "required": ["name", "version", "start_node", "default_error", "nodes", "endings"],
```

Then add the `default_error` property after `start_node` (after line 56):

```json
    "default_error": {
      "$ref": "../common.json#/$defs/node_reference",
      "description": "Default ending for unhandled failures. Action nodes without on_failure and conditional nodes without on_unknown route here. Must reference a valid ending."
    },
```

- [ ] **Step 2: Update `$comment`**

Change line 3:

```json
  "$comment": "Schema version 3.0 - Types defined in blueprint-types.md (skill-embedded, no per-repo definitions file)",
```

to:

```json
  "$comment": "Schema version 3.1 - Added default_error for implicit failure routing. Types defined in blueprint-types.md.",
```

- [ ] **Step 3: Commit**

```bash
git add schema/authoring/workflow.json
git commit -m "refactor: add default_error to workflow schema"
```

---

### Task 3: Type catalog — blueprint-types.md

**Files:**
- Modify: `blueprint-types.md`

- [ ] **Step 1: Update conventions section**

In `blueprint-types.md`, change line 16:

```
- Preconditions return boolean. Consequences mutate state or the world.
```

to:

```
- Preconditions return true, false, or unknown (when evaluation fails).
  Consequences mutate state or the world.
```

- [ ] **Step 2: Update action node signature**

Replace lines 22-24:

```
action(actions[], on_success, on_failure)
  actions = array of consequence objects, executed sequentially
  → route to on_success if all succeed; on_failure at first failure
```

with:

```
action(consequences[], on_success, on_failure?)
  consequences = array of consequence objects, executed sequentially
  on_failure defaults to workflow default_error when omitted
  → route to on_success if all succeed; on_failure at first failure
```

- [ ] **Step 3: Update conditional node signature**

Replace lines 26-29:

```
conditional(condition, branches{on_true, on_false}, audit?)
  condition = a single precondition object (often a `composite`)
  audit     = {enabled, output, messages} — evaluate without short-circuit
  → route to branches.on_true or branches.on_false
```

with:

```
conditional(condition, on_true, on_false, on_unknown?, audit?)
  condition = precondition object, OR string (evaluate_expression shorthand),
              OR {all|any|none|xor: [...]} (composite shorthand)
  on_unknown defaults to workflow default_error when omitted
  audit     = {enabled, output, messages} — evaluate without short-circuit
  → route to on_true, on_false, or on_unknown
```

- [ ] **Step 4: Commit**

```bash
git add blueprint-types.md
git commit -m "refactor: update node signatures for schema compression"
```

---

### Task 4: Examples — examples.md

**Files:**
- Rewrite: `examples.md`

This task replaces the entire file with all 3 workflows using compressed syntax. The workflows must collectively demonstrate all 34 types AND the 6 compression patterns:
1. `consequences:` instead of `actions:`/`consequence:`
2. Omitted `on_failure` (default routing)
3. Ternary conditional (`on_unknown`)
4. Condition string shorthand
5. Composite shorthand (`all:`)
6. Bare response handler (string) + dynamic `${}` routing

- [ ] **Step 1: Write compressed examples.md**

Replace the entire contents of `examples.md` with:

````markdown
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
````

- [ ] **Step 2: Verify all 34 types are present**

Run:
```bash
for type in action conditional user_prompt composite evaluate_expression state_check tool_check path_check python_module_available network_available source_check fetch_check create_checkpoint rollback_checkpoint spawn_agent invoke_skill inline evaluate compute display log_node log_entry set_flag mutate_state set_timestamp evaluate_keywords parse_intent_flags match_3vl_rules local_file_ops git_ops_local web_ops run_command install_tool compute_hash; do
  if ! grep -q "$type" examples.md; then
    echo "MISSING: $type"
  fi
done
```

Expected: no output (all 34 found).

- [ ] **Step 3: Commit**

```bash
git add examples.md
git commit -m "refactor: rewrite examples using compressed workflow syntax"
```

---

### Task 5: Intent-detection workflow

**Files:**
- Modify: `workflows/core/intent-detection.yaml`

The real reusable workflow needs the same structural updates. Also fixes a bug: it uses `set_state` (old v2 type name) instead of `mutate_state`.

- [ ] **Step 1: Replace `actions:` with `consequences:` throughout**

In `workflows/core/intent-detection.yaml`, replace all occurrences of `actions:` (used as the action node array key) with `consequences:`. There are 4 occurrences: in `parse_intent_flags` (line 61), `match_intent_rules` (line 72), `set_winner_action` (line 99), and `use_fallback` (line 152).

- [ ] **Step 2: Replace `consequence:` with `consequences:` in response handlers**

In the `show_disambiguation` node's `on_response`, replace `consequence:` with `consequences:` in both the `selected` handler (line 134) and the `other` handler (line 141).

- [ ] **Step 3: Fix `set_state` → `mutate_state`**

Replace the 3 occurrences of `type: set_state` with the correct v7 pattern:

In `set_winner_action` (around line 101):
```yaml
      - type: set_state
        field: computed.matched_action
        value: "${computed.intent_matches.winner.action}"
```
becomes:
```yaml
      - type: mutate_state
        operation: set
        field: computed.matched_action
        value: "${computed.intent_matches.winner.action}"
```

In `show_disambiguation` selected handler (around line 136):
```yaml
          - type: set_state
            field: computed.matched_action
            value: "${user_responses.show_disambiguation.selected.rule.action}"
```
becomes:
```yaml
          - type: mutate_state
            operation: set
            field: computed.matched_action
            value: "${user_responses.show_disambiguation.selected.rule.action}"
```

In `show_disambiguation` other handler (around line 143):
```yaml
          - type: set_state
            field: arguments
            value: "${user_responses.show_disambiguation.text}"
```
becomes:
```yaml
          - type: mutate_state
            operation: set
            field: arguments
            value: "${user_responses.show_disambiguation.text}"
```

- [ ] **Step 4: Flatten `branches:` on conditionals**

In `check_has_input` (lines 46-51), replace:
```yaml
    branches:
      on_true: parse_intent_flags
      on_false: use_fallback
```
with:
```yaml
    on_true: parse_intent_flags
    on_false: use_fallback
```

In `check_clear_winner` (lines 93-96), replace:
```yaml
    branches:
      on_true: set_winner_action
      on_false: check_has_candidates
```
with:
```yaml
    on_true: set_winner_action
    on_false: check_has_candidates
```

In `check_has_candidates` (lines 111-114), replace:
```yaml
    branches:
      on_true: show_disambiguation
      on_false: use_fallback
```
with:
```yaml
    on_true: show_disambiguation
    on_false: use_fallback
```

- [ ] **Step 5: Add `default_error` and make `on_failure` optional**

Add `default_error: success_resolved` after `start_node: check_has_input` (line 36). This workflow uses `success_resolved` as its catch-all since it's a sub-workflow that always resolves.

Then remove `on_failure` from nodes where it just points to `use_fallback` — specifically `parse_intent_flags` (line 66), `match_intent_rules` (line 81), and `set_winner_action` (line 104). Keep `on_failure: success_resolved` on `use_fallback` since that's explicit intentional routing.

Wait — `use_fallback` has `on_failure: success_resolved` which is the same as `on_success: success_resolved`. Since both routes go to the same place, keep them explicit for clarity. But the default_error approach here is different — this workflow routes failures to `use_fallback`, not to an error ending. Let's keep explicit `on_failure: use_fallback` on those nodes since it's intentional routing to a recovery node, not default error behavior.

Actually, this workflow doesn't benefit from default_error because its failure routing is intentional (fallback logic, not error endings). Add `default_error: success_resolved` for schema compliance but keep all explicit `on_failure` declarations.

- [ ] **Step 6: Commit**

```bash
git add workflows/core/intent-detection.yaml
git commit -m "refactor: update intent-detection workflow to compressed schema"
```

---

### Task 6: Documentation — README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Quick Start workflow snippet**

In `README.md`, replace the workflow snippet (lines 60-91):

```yaml
name: my-workflow
version: "1.0.0"

start_node: check_config

nodes:
  check_config:
    type: conditional
    condition:
      type: path_check
      path: "config.yaml"
      check: is_file
    branches:
      on_true: load_config
      on_false: create_config

  load_config:
    type: action
    actions:
      - type: local_file_ops
        operation: read
        path: "config.yaml"
        store_as: config
    on_success: done
    on_failure: error_reading

endings:
  done:
    type: success
    message: "Configuration loaded"
```

with:

```yaml
name: my-workflow
version: "1.0.0"

start_node: check_config
default_error: error_generic

nodes:
  check_config:
    type: conditional
    condition:
      type: path_check
      path: "config.yaml"
      check: is_file
    on_true: load_config
    on_false: create_config

  load_config:
    type: action
    consequences:
      - type: local_file_ops
        operation: read
        path: "config.yaml"
        store_as: config
    on_success: done

endings:
  done:
    type: success
    message: "Configuration loaded"
  error_generic:
    type: error
    message: "Unexpected failure at ${current_node}"
```

- [ ] **Step 2: Update the Node Types table**

In `README.md`, replace the Node Types table (lines 122-127):

```markdown
| Node Type | Purpose | Routing |
|-----------|---------|---------|
| `action` | Execute consequences (operations) | `on_success` / `on_failure` |
| `conditional` | Branch based on a precondition | `branches.on_true` / `branches.on_false` |
| `user_prompt` | Present structured prompt to user | Routes by `handler_id` from options |
```

with:

```markdown
| Node Type | Purpose | Routing |
|-----------|---------|---------|
| `action` | Execute consequences (operations) | `on_success` / `on_failure?` (defaults to `default_error`) |
| `conditional` | Branch on a precondition | `on_true` / `on_false` / `on_unknown?` (defaults to `default_error`) |
| `user_prompt` | Present structured prompt to user | Routes by `handler_id` from options |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README workflow snippet and node types for compressed schema"
```

---

### Task 7: Documentation — CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update conventions reference**

In `CLAUDE.md`, replace line 79:

```
- Preconditions return boolean. Consequences mutate state or the world.
```

with:

```
- Preconditions return true, false, or unknown. Consequences mutate state or the world.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md precondition convention for ternary"
```

---

### Task 8: CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add compression entry under the existing v7.0.0 section**

In `CHANGELOG.md`, after the `#### Universal \`${}\` interpolation` section (around line 43), add:

```markdown

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
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add workflow schema compression to CHANGELOG"
```

---

### Task 9: Schema validation

**Files:** None (verification only)

- [ ] **Step 1: Validate example workflows against updated schema**

Create a temporary validation script and run it:

```bash
python3 -c "
import json, yaml, sys
from jsonschema import validate, RefResolver
from pathlib import Path

schema_dir = Path('schema')
with open(schema_dir / 'authoring/workflow.json') as f:
    workflow_schema = json.load(f)

# Build resolver for \$ref
store = {}
for p in schema_dir.rglob('*.json'):
    with open(p) as f:
        s = json.load(f)
    if '\$id' in s:
        store[s['\$id']] = s

resolver = RefResolver.from_schema(workflow_schema, store=store)

# Extract YAML blocks from examples.md
import re
with open('examples.md') as f:
    content = f.read()

blocks = re.findall(r'\`\`\`yaml\n(.*?)\`\`\`', content, re.DOTALL)
print(f'Found {len(blocks)} YAML blocks')

for i, block in enumerate(blocks):
    try:
        doc = yaml.safe_load(block)
        validate(doc, workflow_schema, resolver=resolver)
        print(f'Block {i+1}: PASS')
    except Exception as e:
        print(f'Block {i+1}: FAIL - {e}')
        sys.exit(1)

print('All examples valid!')
"
```

Expected: 3 blocks, all PASS.

- [ ] **Step 2: Validate intent-detection workflow**

```bash
python3 -c "
import json, yaml
from jsonschema import validate, RefResolver
from pathlib import Path

schema_dir = Path('schema')
with open(schema_dir / 'authoring/workflow.json') as f:
    workflow_schema = json.load(f)

store = {}
for p in schema_dir.rglob('*.json'):
    with open(p) as f:
        s = json.load(f)
    if '\$id' in s:
        store[s['\$id']] = s

resolver = RefResolver.from_schema(workflow_schema, store=store)

with open('workflows/core/intent-detection.yaml') as f:
    doc = yaml.safe_load(f)

validate(doc, workflow_schema, resolver=resolver)
print('intent-detection.yaml: PASS')
"
```

Expected: PASS.

- [ ] **Step 3: Verify no remaining `actions:` or `branches:` in workflow-facing files**

```bash
# Check for old actions: key in workflow YAML (not in schema descriptions or docs/superpowers)
grep -rn "  actions:" examples.md workflows/ --include="*.yaml" --include="*.md" | grep -v "docs/superpowers" | grep -v "schema/"
```

Expected: no output.

```bash
# Check for old branches: key
grep -rn "  branches:" examples.md workflows/ --include="*.yaml" --include="*.md" | grep -v "docs/superpowers" | grep -v "schema/"
```

Expected: no output.

```bash
# Check for old singular consequence: key (should be consequences:)
grep -rn "  consequence:" examples.md workflows/ --include="*.yaml" --include="*.md" | grep -v "docs/superpowers" | grep -v "schema/" | grep -v "consequences:"
```

Expected: no output.

---

### Follow-up: Cross-repo pattern guide updates

**Not in scope for this plan** — requires a separate branch in `hiivmind-blueprint`.

The following files reference the old workflow structure and will need updating:
- `hiivmind-blueprint/lib/patterns/authoring-guide.md` — references `actions:`, `branches:`, old routing patterns
- `hiivmind-blueprint/lib/patterns/execution-guide.md` — references old node structure

Create a follow-up task after this plan completes.
