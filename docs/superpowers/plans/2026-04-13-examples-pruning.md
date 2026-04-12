# Examples Pruning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 6 isolated example files (1,846 lines, 118 snippets) with a single `examples.md` containing 3 composite workflows that collectively demonstrate all 34 types in context.

**Architecture:** One markdown file at the repo root with 3 fenced YAML workflow blocks. Each workflow is a realistic end-to-end flow. Types are demonstrated by usage, not explained — `blueprint-types.md` is the reference. Documentation cross-references updated to point at `examples.md`.

**Tech Stack:** Markdown, YAML, git. Verification is grep-based parity checking.

---

## File Structure

**Created:**
- `examples.md` — 3 composite workflow examples (Task 1)

**Deleted:**
- `examples/consequences.yaml`, `examples/preconditions.yaml`, `examples/nodes.yaml` (Task 2)
- `examples/endings.yaml`, `examples/execution.yaml`, `examples/index.yaml` (Task 2)
- `examples/` directory (Task 2)

**Modified:**
- `README.md` (Task 3)
- `CLAUDE.md` (Task 3)
- `package.yaml` (Task 3)

---

### Task 1: Create `examples.md`

**Files:**
- Create: `examples.md`

- [ ] **Step 1: Create the file**

Write the following content to `examples.md` at the repo root. This is the complete file — 3 workflows covering all 34 types.

```markdown
# hiivmind-blueprint Examples

Three composite workflows demonstrating all 34 types from `blueprint-types.md`
in realistic end-to-end context. Each workflow is valid Blueprint YAML.

---

## 1. Source Onboarding

Check prerequisites, prompt for source type, clone a git repo, checkpoint
state before risky operations.

**Types demonstrated:** `action`, `conditional`, `user_prompt`, `composite`,
`tool_check`, `path_check`, `state_check`, `network_available`, `set_flag`,
`mutate_state`, `display`, `log_node`, `log_entry`, `local_file_ops`,
`git_ops_local`, `set_timestamp`, `create_checkpoint`, `rollback_checkpoint`,
`install_tool`

```yaml
name: source-onboarding
version: "1.0.0"
description: Onboard a new git source — check tools, prompt for details, clone and configure.

start_node: check_prerequisites

initial_state:
  phase: setup
  flags: {}
  computed: {}
  output:
    level: normal

nodes:
  check_prerequisites:
    type: conditional
    description: Verify required tools and network
    condition:
      type: composite
      operator: all
      conditions:
        - type: tool_check
          tool: git
          capability: available
        - type: tool_check
          tool: yq
          capability: version_gte
          args:
            min_version: "4.0"
        - type: network_available
    branches:
      on_true: check_config
      on_false: install_missing_tools

  install_missing_tools:
    type: action
    description: Attempt to install yq if missing
    actions:
      - type: install_tool
        tool: yq
        install_command: "snap install yq"
      - type: log_entry
        level: info
        message: "Installed missing tool: yq"
    on_success: check_config
    on_failure: error_missing_tools

  check_config:
    type: conditional
    description: Check if config.yaml already exists
    condition:
      type: path_check
      path: "data/config.yaml"
      check: is_file
    branches:
      on_true: load_config
      on_false: ask_source_type

  load_config:
    type: action
    description: Read existing config and verify it has a sources array
    actions:
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
    branches:
      on_true: ask_source_type
      on_false: init_sources

  init_sources:
    type: action
    actions:
      - type: mutate_state
        operation: set
        field: computed.config.sources
        value: []
    on_success: ask_source_type
    on_failure: error_config_read

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
        consequence:
          - type: mutate_state
            operation: set
            field: source_type
            value: git
        next_node: checkpoint_before_clone
      local:
        consequence:
          - type: mutate_state
            operation: set
            field: source_type
            value: local
        next_node: done

  checkpoint_before_clone:
    type: action
    description: Save state before clone (risky network operation)
    actions:
      - type: create_checkpoint
        name: before_clone
      - type: set_timestamp
        store_as: computed.clone_started_at
      - type: display
        content: "Cloning repository..."
    on_success: clone_repo
    on_failure: error_checkpoint

  clone_repo:
    type: action
    description: Clone the git repository
    actions:
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
    actions:
      - type: rollback_checkpoint
        name: before_clone
      - type: log_entry
        level: error
        message: "Clone failed, state restored from checkpoint"
    on_success: error_clone_failed
    on_failure: error_clone_failed

endings:
  done:
    type: success
    message: "Source onboarded: ${computed.source_id}"
  error_missing_tools:
    type: error
    message: "Required tools not available"
  error_config_read:
    type: error
    message: "Failed to read config.yaml"
  error_checkpoint:
    type: error
    message: "Failed to create checkpoint"
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

```yaml
name: web-content-pipeline
version: "1.0.0"
description: Fetch web content, detect changes via hashing, process with Python.

start_node: verify_source

initial_state:
  phase: pipeline
  flags: {}
  computed: {}

nodes:
  verify_source:
    type: conditional
    description: Ensure source is configured and cloned
    condition:
      type: source_check
      source_id: "${computed.source_id}"
      aspect: cloned
    branches:
      on_true: check_python
      on_false: error_no_source

  check_python:
    type: conditional
    description: Verify Python yaml module is available for processing
    condition:
      type: python_module_available
      module: yaml
    branches:
      on_true: check_cache
      on_false: error_no_python

  check_cache:
    type: conditional
    description: Skip fetch if content is already cached
    condition:
      type: path_check
      path: ".cache/${computed.source_id}.md"
      check: is_file
    branches:
      on_true: done_cached
      on_false: fetch_content

  fetch_content:
    type: action
    description: Fetch web page and store result
    actions:
      - type: web_ops
        operation: fetch
        url: "${computed.page_url}"
        prompt: "Extract the main documentation content"
        allow_failure: true
        store_as: computed.fetch_result
    on_success: check_fetch
    on_failure: error_fetch

  check_fetch:
    type: conditional
    description: Verify fetch returned usable content
    condition:
      type: fetch_check
      from: computed.fetch_result
      aspect: has_content
    branches:
      on_true: hash_content
      on_false: error_empty_fetch

  hash_content:
    type: action
    description: Hash fetched content and check for changes
    actions:
      - type: compute_hash
        from: computed.fetch_result.content
        store_as: computed.new_hash
      - type: evaluate
        expression: "computed.new_hash != computed.previous_hash"
        set_flag: content_changed
    on_success: check_changed
    on_failure: error_hash

  check_changed:
    type: conditional
    description: Only process if content actually changed
    condition:
      type: evaluate_expression
      expression: "flags.content_changed == true"
    branches:
      on_true: process_content
      on_false: done_no_changes

  process_content:
    type: action
    description: Clean content, compute output path, run processing script
    actions:
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
    on_failure: error_process

  spawn_indexer:
    type: action
    description: Spawn parallel agent to update the index
    actions:
      - type: spawn_agent
        subagent_type: general-purpose
        prompt: "Update the index at data/index.md to include ${computed.source_id}"
        store_as: computed.index_result
        run_in_background: true
    on_success: cache_content
    on_failure: done_processed

  cache_content:
    type: action
    description: Cache fetched content locally for next run
    actions:
      - type: web_ops
        operation: cache
        from: computed.fetch_result
        dest: ".cache/${computed.source_id}.md"
    on_success: done_processed
    on_failure: done_processed

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
  error_no_source:
    type: error
    message: "Source not cloned: ${computed.source_id}"
  error_no_python:
    type: error
    message: "Python yaml module not available"
  error_fetch:
    type: error
    message: "Failed to fetch ${computed.page_url}"
  error_empty_fetch:
    type: failure
    message: "Fetch returned empty content"
  error_hash:
    type: error
    message: "Failed to hash content"
  error_process:
    type: error
    message: "Processing script failed"
```

---

## 3. Intent-Driven Router

Parse user input with 3VL keyword matching, match against intent rules,
display candidates if ambiguous, route to the winning skill.

**Types demonstrated:** `action`, `user_prompt`, `composite`, `state_check`,
`evaluate_expression`, `evaluate_keywords`, `parse_intent_flags`,
`match_3vl_rules`, `display`, `invoke_skill`, `mutate_state`, `log_entry`

```yaml
name: intent-router
version: "1.0.0"
description: Parse user input with 3VL intent detection and route to the matching skill.

start_node: get_input

initial_state:
  phase: routing
  flags: {}
  computed: {}

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
        consequence:
          - type: mutate_state
            operation: set
            field: computed.mode
            value: parse
        next_node: parse_keywords
      browse:
        consequence:
          - type: mutate_state
            operation: set
            field: computed.mode
            value: browse
        next_node: show_capabilities

  parse_keywords:
    type: action
    description: Quick keyword check before full 3VL parsing
    actions:
      - type: evaluate_keywords
        input: "${computed.user_input}"
        keyword_sets:
          build: [build, create, scaffold, generate]
          navigate: [find, search, look up, docs, documentation]
          maintain: [update, refresh, sync, check]
        store_as: computed.keyword_match
    on_success: check_keyword_match
    on_failure: error_parse

  check_keyword_match:
    type: conditional
    description: If keyword match is confident, skip full 3VL parse
    condition:
      type: composite
      operator: all
      conditions:
        - type: state_check
          field: computed.keyword_match
          operator: not_null
        - type: evaluate_expression
          expression: "computed.confidence > 0.8"
    branches:
      on_true: route_to_skill
      on_false: full_3vl_parse

  full_3vl_parse:
    type: action
    description: Parse intent flags and match against rule table
    actions:
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
    on_failure: error_parse

  check_clear_winner:
    type: conditional
    description: Check if 3VL produced a clear winner
    condition:
      type: state_check
      field: computed.match_result.clear_winner
      operator: "true"
    branches:
      on_true: route_to_skill
      on_false: show_candidates

  show_candidates:
    type: action
    description: Display top candidates for user to choose
    actions:
      - type: display
        format: table
        title: "Possible matches"
        headers: [Name, Score]
        content: "${computed.match_result.top_candidates}"
    on_success: get_input
    on_failure: error_display

  route_to_skill:
    type: action
    description: Invoke the matched skill
    actions:
      - type: mutate_state
        operation: set
        field: computed.routed_skill
        value: "${computed.match_result.winner}"
      - type: invoke_skill
        skill: "${computed.routed_skill}"
    on_success: done
    on_failure: error_skill

  show_capabilities:
    type: action
    description: List available skills
    actions:
      - type: display
        format: markdown
        content: |
          ## Available Skills
          - **build** — Create new workflows and skills
          - **navigate** — Search and browse documentation
          - **maintain** — Update, refresh, and check existing work
    on_success: get_input
    on_failure: error_display

endings:
  done:
    type: success
    message: "Routed to ${computed.routed_skill}"
    behavior:
      type: delegate
      skill: "${computed.routed_skill}"
  error_parse:
    type: error
    message: "Failed to parse intent"
  error_display:
    type: error
    message: "Display error"
  error_skill:
    type: error
    message: "Failed to invoke skill"
```
```

- [ ] **Step 2: Verify line count and type coverage**

Run:
```bash
wc -l examples.md
```

Expected: between 350 and 450 lines.

Run the parity check — every one of the 34 type names must appear at least once:
```bash
for t in create_checkpoint rollback_checkpoint spawn_agent invoke_skill inline \
         evaluate compute display log_node log_entry set_flag mutate_state set_timestamp \
         evaluate_keywords parse_intent_flags match_3vl_rules \
         local_file_ops git_ops_local web_ops run_command install_tool compute_hash \
         composite evaluate_expression state_check \
         tool_check path_check python_module_available network_available source_check fetch_check \
         action conditional user_prompt; do
  if ! grep -q "$t" examples.md; then
    echo "MISSING: $t"
  fi
done
echo "--- done ---"
```

Expected: only `--- done ---`. If any `MISSING:` lines appear, fix `examples.md` before committing.

- [ ] **Step 3: Commit**

```bash
git add examples.md
git commit -m "feat: add examples.md with 3 composite workflow examples

Replaces 118 isolated per-type snippets with 3 end-to-end workflows
that demonstrate all 34 types in realistic context:

1. Source Onboarding (19 types) — tools, prompts, git, checkpoints
2. Web Content Pipeline (14 types) — fetch, hash, process, spawn
3. Intent-Driven Router (12 types) — 3VL parsing, skill routing

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Delete old example files

**Files:**
- Delete: `examples/consequences.yaml`, `examples/preconditions.yaml`, `examples/nodes.yaml`
- Delete: `examples/endings.yaml`, `examples/execution.yaml`, `examples/index.yaml`
- Delete: `examples/` directory

- [ ] **Step 1: Remove all files**

```bash
git rm examples/consequences.yaml examples/preconditions.yaml examples/nodes.yaml \
       examples/endings.yaml examples/execution.yaml examples/index.yaml
```

Expected: six `rm 'path'` lines.

- [ ] **Step 2: Remove empty directory**

```bash
rmdir examples 2>/dev/null || true
ls examples/ 2>&1
```

Expected: "No such file or directory".

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor!: delete isolated example files (replaced by examples.md)

Removes 6 files totalling 1,846 lines and 118 per-type snippets.
All types are now demonstrated in context via the 3 composite
workflows in examples.md at the repo root.

BREAKING CHANGE: examples/ directory no longer exists.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Update documentation references

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `package.yaml`

- [ ] **Step 1: Update README.md**

There are 3 references to update. Read `README.md` first, then apply these edits:

**Edit A:** Find `See \`examples/endings.yaml\` for full patterns` (around line 116). Replace with:

```
See `examples.md` for full ending patterns in context.
```

**Edit B:** Find `See \`examples/\` for workflow call-site snippets` (around line 167). Replace with:

```
See `examples.md` for composite workflow examples.
```

**Edit C:** In the File Structure tree, find the `examples/` block:

```
├── examples/                     # Workflow call-site snippets
│   ├── consequences.yaml
│   ├── preconditions.yaml
│   ├── nodes.yaml
│   ├── endings.yaml
│   └── execution.yaml
```

Replace with:

```
├── examples.md                   # 3 composite workflow examples
```

Verify:
```bash
grep -n 'examples/' README.md
```

Expected: no output (no references to `examples/` as a directory).

- [ ] **Step 2: Update CLAUDE.md**

There are 6 references to update. Read `CLAUDE.md` first, then apply these edits:

**Edit A:** In the sync table, find:

```
| `examples/` (this repo) | Workflow call-site snippets must use current type names and enum variants |
```

Replace with:

```
| `examples.md` (this repo) | Composite workflow examples must use current type names and enum variants |
```

**Edit B:** In the sync checklist, find:

```
1. **Examples sync** — update `examples/*.yaml` if a type, parameter, or enum variant was renamed or removed.
```

Replace with:

```
1. **Examples sync** — update `examples.md` if a type, parameter, or enum variant was renamed or removed.
```

**Edit C:** Find:

```
Workflow YAML references types via `type: <name>` plus sibling keys for parameters. See `examples/` for concrete call-site snippets.
```

Replace with:

```
Workflow YAML references types via `type: <name>` plus sibling keys for parameters. See `examples.md` for composite workflow examples.
```

**Edit D:** Find:

```
5. Add a workflow call-site example in `examples/`.
```

Replace with:

```
5. Ensure the type is demonstrated in `examples.md` (add to an existing workflow or note if a new workflow is needed).
```

**Edit E:** Find:

```
- Are existing examples in `examples/` still consistent with the type?
```

Replace with:

```
- Are existing examples in `examples.md` still consistent with the type?
```

**Edit F:** Find:

```
4. Example coverage - Types should have usage examples
```

Replace with:

```
4. Example coverage - Types should appear in `examples.md` workflows
```

Verify:
```bash
grep -n 'examples/' CLAUDE.md
```

Expected: no output.

- [ ] **Step 3: Update package.yaml**

Read `package.yaml`. Find:

```
  - examples/           # Workflow call-site snippets
```

Replace with:

```
  - examples.md         # Composite workflow examples
```

Verify:
```bash
grep -n 'examples/' package.yaml
```

Expected: no output.

- [ ] **Step 4: Final verification**

Run:
```bash
grep -rn --include='*.md' --include='*.yaml' --include='*.json' \
  'examples/' . 2>/dev/null \
  | grep -v '^\./CHANGELOG\.md:' \
  | grep -v '^\./docs/superpowers/'
```

Expected: no output (zero references to `examples/` as a directory outside exempt files).

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md package.yaml
git commit -m "docs: update references from examples/ to examples.md

README.md, CLAUDE.md, and package.yaml now reference examples.md
at the repo root instead of the deleted examples/ directory.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**

| Spec requirement | Covered by |
|---|---|
| Replace 6 YAML files with `examples.md` | Task 1 (create), Task 2 (delete) |
| 3 composite workflows | Task 1 — source-onboarding, web-content-pipeline, intent-router |
| All 34 type names demonstrated | Task 1 Step 2 (parity grep) |
| Delete `examples/` directory | Task 2 |
| Update `README.md` references | Task 3 Step 1 |
| Update `CLAUDE.md` references | Task 3 Step 2 |
| Update `package.yaml` references | Task 3 Step 3 |
| No remaining `examples/` directory references | Task 3 Step 4 |

All requirements covered. ✓

**2. Placeholder scan:** Every task has concrete content — the full YAML for all 3 workflows is inline in Task 1, every edit in Task 3 has before/after text. No TBDs or "fill in later". ✓

**3. Type consistency:** The 34 type names used in the workflows match the names in `blueprint-types.md` exactly. The parity check in Task 1 Step 2 uses the same list as the catalog collapse plan's parity check. ✓
