# Blueprint Type Catalog Collapse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace six catalog YAML files (2,218 lines) and three obsolete schema files with a single ~150-line `blueprint-types.md` at the repo root, while preserving 100% type/parameter/enum parity.

**Architecture:** One markdown file at the repo root becomes the sole source of type vocabulary. All workflow authoring remains unchanged (type names and parameters are unchanged). The `hiivmind-blueprint` skill ships `blueprint-types.md` as skill-embedded reference, eliminating the per-repo `.hiivmind/blueprint/definitions.yaml` concept.

**Tech Stack:** Markdown, YAML, JSON Schema, git. No code to build, no tests to run — verification is grep-based and parity-based. The design doc at `docs/superpowers/specs/2026-04-11-blueprint-type-catalog-collapse-design.md` is the canonical spec; read it before starting.

---

## Scope

**In scope:**
- Create `blueprint-types.md` at repo root
- Delete 6 catalog YAML files + 3 parent directories
- Delete 3 obsolete schema files + 2 parent directories
- Update `package.yaml` to v7.0.0
- Update `README.md`, `CLAUDE.md`, `CHANGELOG.md`
- Update `examples/index.yaml`, `examples/execution.yaml`
- Update `lib/patterns/change-classification.md` (if references exist)
- Remove or rewrite stale `docs/refactor/*` plans that reference old paths
- Cross-repo: update `hiivmind-blueprint/lib/patterns/authoring-guide.md` and `execution-guide.md`
- No-ghost-definitions audit returns zero actionable references in `hiivmind-blueprint-lib`

**Out of scope (documented as follow-ups in Task 15):**
- Cross-repo cleanup of the other ~17 files in `hiivmind-blueprint` that reference old catalog paths (templates, SKILL.md files, references/, etc.)
- `schema/_deprecated/` cleanup
- Pruning `examples/` to one example per type
- Any type name / parameter / enum changes

---

## File Structure

Files this plan touches, grouped by task:

**Created:**
- `blueprint-types.md` — the single-file type catalog (Task 2)

**Deleted:**
- `consequences/core.yaml`, `consequences/intent.yaml`, `consequences/extensions.yaml` (Task 4)
- `preconditions/core.yaml`, `preconditions/extensions.yaml` (Task 4)
- `nodes/workflow_nodes.yaml` (Task 4)
- `consequences/`, `preconditions/`, `nodes/` directories (Task 4)
- `schema/definitions/type-definition.json` (Task 5)
- `schema/definitions/execution-definition.json` (Task 5)
- `schema/definitions/` directory (Task 5)
- `schema/resolution/definitions.json` (Task 5)
- `schema/resolution/` directory (Task 5)

**Modified:**
- `package.yaml` (Task 6)
- `README.md` (Task 7)
- `CLAUDE.md` (Task 8)
- `CHANGELOG.md` (Task 9)
- `examples/index.yaml` (Task 10)
- `examples/execution.yaml` (Task 10)
- `lib/patterns/change-classification.md` (Task 11, if references exist)
- `docs/refactor/simplify.md`, `docs/refactor/swarm-simplify-plan.md` (Task 12)
- `../hiivmind-blueprint/lib/patterns/authoring-guide.md` (Task 13)
- `../hiivmind-blueprint/lib/patterns/execution-guide.md` (Task 13)

---

## Task 1: Create feature branch

**Files:**
- No file changes

- [ ] **Step 1: Verify starting state**

Run:
```bash
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib
git status
git branch --show-current
```

Expected:
- Working tree clean
- Current branch: `refactor/simpilfy`
- HEAD at `b9fa761` (the second spec commit) or later

If branch is not `refactor/simpilfy`, stop and ask — the spec doc was committed there.

- [ ] **Step 2: Create feature branch**

Run:
```bash
git checkout -b refactor/type-catalog-collapse
```

Expected: `Switched to a new branch 'refactor/type-catalog-collapse'`

- [ ] **Step 3: Confirm baseline grep count**

Run:
```bash
grep -rn -l --include='*.md' --include='*.yaml' --include='*.json' \
  -e 'consequences/core\.yaml' \
  -e 'consequences/intent\.yaml' \
  -e 'consequences/extensions\.yaml' \
  -e 'preconditions/core\.yaml' \
  -e 'preconditions/extensions\.yaml' \
  -e 'nodes/workflow_nodes\.yaml' \
  -e '\.hiivmind/blueprint/definitions\.yaml' \
  -e 'schema/definitions/' \
  -e 'schema/resolution/' \
  . 2>/dev/null | sort
```

Expected: 16 files (the baseline of ghost references before the refactor begins). This is what Task 14 must drive to a much smaller set (only the spec doc, this plan, and CHANGELOG — all exempt per the audit rules).

Note the exact list in a scratch file if helpful. Do NOT commit the scratch file.

---

## Task 2: Create `blueprint-types.md`

**Files:**
- Create: `blueprint-types.md`

- [ ] **Step 1: Read the draft from the spec**

Open `docs/superpowers/specs/2026-04-11-blueprint-type-catalog-collapse-design.md` and locate the **"Draft content (normative)"** section. The code block after that heading contains the full `blueprint-types.md` content — every one of the 34 types with signatures, enum variants, and one-line semantics.

- [ ] **Step 2: Create `blueprint-types.md` at the repo root**

Create the file with the exact content below. This content is the canonical draft from the spec; it MUST be copied without modification. Coverage: 3 nodes + 9 preconditions + 22 consequences = 34 types.

```markdown
# hiivmind-blueprint Types

Canonical type catalog for Blueprint workflows. Workflows reference every type
in this file by name (via `type: <name>` in YAML). An LLM — or code-with-LLM —
uses this document to interpret workflows deterministically. There is no other
type definition file.

## Conventions

- `name(param1, param2, optional?)` — reference signature. `?` marks optional
  params. The actual YAML call site uses sibling keys, not positional args.
- `X ∈ {a, b, c}` — enum variants on the line below the signature.
- `→` — outcome / return meaning.
- All string parameters support `${}` state interpolation. Literals are
  literal; `${...}` always expresses intent to interpolate.
- Preconditions return boolean. Consequences mutate state or the world.

---

## Nodes

action(actions[], on_success, on_failure)
  actions = array of consequence objects, executed sequentially
  → route to on_success if all succeed; on_failure at first failure

conditional(condition, branches{on_true, on_false}, audit?)
  condition = a single precondition object (often a `composite`)
  audit     = {enabled, output, messages} — evaluate without short-circuit
  → route to branches.on_true or branches.on_false

user_prompt(prompt{question, header, options|options_from_state+options}, on_response)
  header          ≤ 12 chars
  options (array) = 2–4 items of {id, label, description} (static form)
  options (object)= {id, label, description} as expressions (dynamic form;
                    requires options_from_state pointing at a state array)
  on_response     = map of option_id → {consequence?, next_node}
  → present prompt, store selection in state.user_responses, run handler
    consequences, route to handler.next_node

---

## Preconditions

### Core

composite(operator, conditions[])
  operator ∈ {all, any, none, xor}
  → combine nested preconditions with the operator

evaluate_expression(expression)
  expression supports ==, !=, >, <, >=, <=, &&, ||, !, len(), contains(),
             startswith(), endswith(); field access via dot notation
  → expression evaluates truthy against state

state_check(field, operator, value?)
  operator ∈ {equals, not_equals, null, not_null, true, false}
  field    = dot-notation path (e.g. `flags.initialized`, `computed.config.version`)
  value    required for equals / not_equals
  → inspect a state field

### Extensions

tool_check(tool, capability, args?)
  capability ∈ {available, version_gte}
  args = {min_version: "2.0"} when capability = version_gte
  → CLI tool in PATH, or installed version ≥ min_version

path_check(path, check, args?)
  check ∈ {exists, is_file, is_directory, contains_text}
  args  = {pattern: "text"} when check = contains_text
  → path satisfies the selected check

python_module_available(module)
  → `python3 -c "import <module>"` exits 0

network_available(target?)
  target defaults to https://github.com, 5s timeout
  → HTTP request to target succeeds

source_check(source_id, aspect)
  aspect ∈ {exists, cloned, has_updates}
    exists       → source_id listed in data/config.yaml
    cloned       → .source/<source_id>/ directory exists
    has_updates  → git fetch shows remote commits ahead (network op)

fetch_check(from, aspect)
  from   = state field holding a prior web_ops result
  aspect ∈ {succeeded, has_content}
    succeeded   → result.status in [200, 300)
    has_content → result.content non-empty

---

## Consequences

### Core — control

create_checkpoint(name)
  → deep copy state into state.checkpoints[name]

rollback_checkpoint(name)
  → restore state from state.checkpoints[name] (errors if missing)

spawn_agent(subagent_type, prompt, store_as, run_in_background?)
  run_in_background defaults to false
  → launch Claude Task agent; result stored at store_as

invoke_skill(skill, args?)
  → delegate via Skill tool; typically the last action before a success ending

inline(description, pseudocode, store_as?, state_reads?, state_writes?)
  → execute embedded workflow-specific pseudocode against state.
    Prefer a reusable consequence type when possible; state_reads / state_writes
    are documentary only.

### Core — evaluation

evaluate(expression, set_flag)
  → eval boolean expression, store result at state.flags[set_flag]

compute(expression, store_as)
  → eval expression (any type), store result at store_as

### Core — interaction

display(content, format?, title?, headers?)
  format ∈ {text, markdown, table, json}  (default: text; markdown = text)
  headers required when format = table; content must then be an array of rows
  → render content to user (side effect, no state change)

### Core — logging

log_node(node, outcome, details?)
  outcome ∈ {success, skipped, error, blocked}
  → append to state.log.node_history with ISO-8601 timestamp

log_entry(level, message, context?)
  level ∈ {debug, info, warning, error}
  → append structured entry to state.log.entries with ISO-8601 timestamp

### Core — state

set_flag(flag, value)
  value ∈ {true, false}
  → state.flags[flag] = value

mutate_state(operation, field, value?)
  operation ∈ {set, append, clear, merge}
    set    → field = value
    append → push value onto array at field
    clear  → field = null
    merge  → shallow merge object value into field
  → mutate state.<field>

### Core — utility

set_timestamp(store_as)
  → ISO-8601 UTC timestamp stored at store_as

### Core — intent (3VL)

3-Valued Logic: T=True, F=False, U=Unknown (wildcard / don't care in rules).

evaluate_keywords(input, keyword_sets, store_as)
  keyword_sets = map of intent_name → [keyword strings]
  → first matching intent name at store_as (case-insensitive), else null

parse_intent_flags(input, flag_definitions, store_as)
  flag_definitions = map of flag → {keywords, negative_keywords}
  → map of flag → T/F/U at store_as (default U; negative_keywords → F;
    keywords → T; case-insensitive)

match_3vl_rules(flags, rules, store_as)
  rules = array of intent rules with 3VL conditions (rule U = wildcard)
  → {clear_winner, winner, top_candidates, all_candidates} at store_as;
    ranked by (hard matches desc, soft matches asc, condition count asc)

### Extensions — file-system

local_file_ops(operation, path, content?, store_as?)
  operation ∈ {read, write, mkdir, delete}
    read   → content at path → store_as
    write  → write content to path, mkdir -p parent
    mkdir  → mkdir -p path
    delete → rm -f path

### Extensions — git

git_ops_local(operation, repo_path?, args?, store_as?)
  operation ∈ {clone, pull, fetch, get-sha}
    clone   → args = {url, dest, branch?, depth?}
    pull    → repo_path, fast-forward only
    fetch   → repo_path
    get-sha → HEAD sha at repo_path → store_as

### Extensions — web

web_ops(operation, url?, prompt?, allow_failure?, from?, dest?, store_as?)
  operation ∈ {fetch, cache}
    fetch → WebFetch url with prompt (default "Extract the main content");
            result {status, content, url} → store_as; non-2xx raises unless
            allow_failure = true
    cache → take result from `from` state field, write .content to dest
            (mkdir -p parent); optional store_as receives resolved dest path

### Extensions — scripting

run_command(script, interpreter?, args?, working_directory?, store_as?)
  interpreter ∈ {auto, bash, python, node, ruby}  (default: auto)
    auto dispatches by extension: .py→python3, .sh→bash, .js→node
  → run script; trimmed stdout at store_as if provided

### Extensions — package

install_tool(tool, install_command?, skip_if_available?)
  skip_if_available defaults to true
  → install CLI tool via custom command or tool-registry hint;
    skip if already present; verify presence after install

### Extensions — hashing

compute_hash(from, store_as)
  → sha256 of state.<from>; stored as `sha256:<hex>` at store_as
```

- [ ] **Step 3: Verify the file exists and is sized reasonably**

Run:
```bash
wc -l blueprint-types.md
grep -c '^[a-z_]*(' blueprint-types.md
```

Expected:
- Line count: between 150 and 200 (tight but not suspiciously small)
- Signature count: 34 (one per type name in `name(...)` form at the start of a line)

If signature count ≠ 34, stop and investigate — parity is broken.

- [ ] **Step 4: Commit**

```bash
git add blueprint-types.md
git commit -m "$(cat <<'EOF'
feat: add blueprint-types.md single-file type catalog

Collapses 34 types from 6 YAML files (2,218 lines) into one signature-
style markdown file at the repo root. Every type, parameter, and enum
variant from the current catalog is preserved verbatim. Subsequent
commits will delete the now-redundant YAML files, obsolete schemas,
and update all cross-references.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Parity verification

**Files:**
- No file changes (verification only)

Before deleting the old catalog, verify that every type name, parameter name, and enum variant in the old files appears in `blueprint-types.md`. If anything is missing, fix `blueprint-types.md` first and re-commit.

- [ ] **Step 1: Extract type names from old catalog**

Run:
```bash
# All top-level type keys in the six catalog files (two-space indent, then name, then colon)
for f in consequences/core.yaml consequences/intent.yaml consequences/extensions.yaml \
         preconditions/core.yaml preconditions/extensions.yaml nodes/workflow_nodes.yaml; do
  echo "--- $f ---"
  grep -E '^  [a-z_]+:$' "$f"
done
```

Expected count (across all six files): 34 type names — `create_checkpoint`, `rollback_checkpoint`, `spawn_agent`, `invoke_skill`, `inline`, `evaluate`, `compute`, `display`, `log_node`, `log_entry`, `set_flag`, `mutate_state`, `set_timestamp`, `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules`, `local_file_ops`, `git_ops_local`, `web_ops`, `run_command`, `install_tool`, `compute_hash`, `composite`, `evaluate_expression`, `state_check`, `tool_check`, `path_check`, `python_module_available`, `network_available`, `source_check`, `fetch_check`, `action`, `conditional`, `user_prompt`.

- [ ] **Step 2: Verify every type name appears in `blueprint-types.md`**

Run:
```bash
for t in create_checkpoint rollback_checkpoint spawn_agent invoke_skill inline \
         evaluate compute display log_node log_entry set_flag mutate_state set_timestamp \
         evaluate_keywords parse_intent_flags match_3vl_rules \
         local_file_ops git_ops_local web_ops run_command install_tool compute_hash \
         composite evaluate_expression state_check \
         tool_check path_check python_module_available network_available source_check fetch_check \
         action conditional user_prompt; do
  if ! grep -q "^$t(" blueprint-types.md; then
    echo "MISSING: $t"
  fi
done
echo "--- done ---"
```

Expected: only `--- done ---`. Any `MISSING:` line means that type is absent from `blueprint-types.md`.

- [ ] **Step 3: Verify every enum variant is preserved**

Run:
```bash
# Extract every enum block from old YAMLs
grep -rE '^\s+enum:|^\s+- [a-z_]' consequences/ preconditions/ nodes/ \
  | grep -v 'description\|interpolatable\|items\|type' > /tmp/old_enums.txt
wc -l /tmp/old_enums.txt
```

Then cross-reference the following enum variants (each must appear somewhere in `blueprint-types.md`):

| Type | Variants |
|---|---|
| `composite` | all, any, none, xor |
| `state_check` | equals, not_equals, null, not_null, true, false |
| `tool_check` | available, version_gte |
| `path_check` | exists, is_file, is_directory, contains_text |
| `source_check` | exists, cloned, has_updates |
| `fetch_check` | succeeded, has_content |
| `display` | text, markdown, table, json |
| `log_node` | success, skipped, error, blocked |
| `log_entry` | debug, info, warning, error |
| `mutate_state` | set, append, clear, merge |
| `local_file_ops` | read, write, mkdir, delete |
| `git_ops_local` | clone, pull, fetch, get-sha |
| `web_ops` | fetch, cache |
| `run_command` (interpreter) | auto, bash, python, node, ruby |

Spot-check command:
```bash
for v in all any none xor equals not_equals not_null available version_gte \
         exists is_file is_directory contains_text cloned has_updates succeeded has_content \
         text markdown table json success skipped blocked debug info warning \
         set append clear merge read write mkdir delete \
         clone pull fetch get-sha auto python node ruby; do
  if ! grep -q "\b$v\b" blueprint-types.md; then
    echo "MISSING VARIANT: $v"
  fi
done
echo "--- done ---"
```

Expected: only `--- done ---`. (Note: some variants like `fetch`, `error` appear in multiple types — the check is that they appear *somewhere*.)

- [ ] **Step 4: Verify parameter names are preserved**

Run:
```bash
# Extract every parameter name field from old YAMLs
grep -h 'name:' consequences/*.yaml preconditions/*.yaml nodes/*.yaml \
  | grep -E 'name: [a-z_]+' \
  | sed -E 's/.*name: ([a-z_]+).*/\1/' | sort -u
```

Confirm the resulting parameter names (e.g., `args`, `capability`, `check`, `condition`, `conditions`, `content`, etc.) all appear at least once in `blueprint-types.md`:
```bash
for p in $(grep -h 'name:' consequences/*.yaml preconditions/*.yaml nodes/*.yaml \
           | grep -E 'name: [a-z_]+' \
           | sed -E 's/.*name: ([a-z_]+).*/\1/' | sort -u); do
  if ! grep -q "\b$p\b" blueprint-types.md; then
    echo "MISSING PARAM: $p"
  fi
done
echo "--- done ---"
```

Expected: only `--- done ---`.

- [ ] **Step 5: If any MISSING reported, fix and amend Task 2's commit**

If Steps 2–4 report any missing items, stop. Open `blueprint-types.md`, add the missing type/variant/param, and amend the previous commit:
```bash
git add blueprint-types.md
git commit --amend --no-edit
```

Re-run Steps 2–4 until all three pass.

If no changes needed, Task 3 is complete without a new commit.

---

## Task 4: Delete catalog YAML files

**Files:**
- Delete: `consequences/core.yaml`, `consequences/intent.yaml`, `consequences/extensions.yaml`
- Delete: `preconditions/core.yaml`, `preconditions/extensions.yaml`
- Delete: `nodes/workflow_nodes.yaml`
- Delete: `consequences/`, `preconditions/`, `nodes/` directories (empty after file removals)

- [ ] **Step 1: Remove the six YAML files**

Run:
```bash
git rm consequences/core.yaml consequences/intent.yaml consequences/extensions.yaml
git rm preconditions/core.yaml preconditions/extensions.yaml
git rm nodes/workflow_nodes.yaml
```

Expected: six `rm 'path'` lines.

- [ ] **Step 2: Confirm directories are empty and remove them**

Run:
```bash
ls consequences/ preconditions/ nodes/ 2>&1
```

Expected: three "No such file or directory" OR three empty listings.

If empty directories remain (git doesn't track them but they may exist on disk):
```bash
rmdir consequences preconditions nodes 2>/dev/null || true
```

- [ ] **Step 3: Verify deletion**

Run:
```bash
ls consequences/ preconditions/ nodes/ 2>&1
```

Expected: all three return "No such file or directory".

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor!: delete catalog YAML files (v7.0.0 collapse)

Removes the six catalog YAML files and their parent directories. All 34
type definitions now live in blueprint-types.md at the repo root.

- consequences/{core,intent,extensions}.yaml
- preconditions/{core,extensions}.yaml
- nodes/workflow_nodes.yaml

Parity verified in the preceding commit: every type name, parameter,
and enum variant is present in blueprint-types.md.

BREAKING CHANGE: catalog YAML files no longer exist. Consumers that
parsed them must read blueprint-types.md instead.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Delete obsolete schemas

**Files:**
- Delete: `schema/definitions/type-definition.json`
- Delete: `schema/definitions/execution-definition.json`
- Delete: `schema/resolution/definitions.json`
- Delete: `schema/definitions/`, `schema/resolution/` directories

- [ ] **Step 1: Remove the three schema files**

Run:
```bash
git rm schema/definitions/type-definition.json
git rm schema/definitions/execution-definition.json
git rm schema/resolution/definitions.json
```

Expected: three `rm 'path'` lines.

- [ ] **Step 2: Remove empty parent directories**

Run:
```bash
ls schema/definitions/ schema/resolution/ 2>&1
rmdir schema/definitions schema/resolution 2>/dev/null || true
ls schema/definitions/ schema/resolution/ 2>&1
```

Expected: after `rmdir`, both return "No such file or directory".

- [ ] **Step 3: Confirm remaining schema tree is valid**

Run:
```bash
find schema -type f -name '*.json' | sort
```

Expected (exactly these 7 files):
```
schema/_deprecated/display-config.json
schema/_deprecated/logging-config.json
schema/authoring/intent-mapping.json
schema/authoring/node-types.json
schema/authoring/workflow.json
schema/common.json
schema/config/output-config.json
schema/config/prompts-config.json
schema/runtime/logging.json
```

(9 files total — the `_deprecated/` pair is intentionally kept per the spec's non-goals.)

- [ ] **Step 4: Verify authoring schemas don't reference deleted paths**

Run:
```bash
grep -rn '\$ref.*definitions/\|definitions\.json\|resolution/' schema/authoring/ schema/common.json schema/config/ schema/runtime/
```

Expected: no output. The authoring/common/config/runtime schemas never referenced the catalog or resolution schemas; confirm this holds.

If any `$ref` to deleted files is found, stop — there's a broken reference that must be fixed before continuing.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor!: delete obsolete definition schemas (v7.0.0 collapse)

Removes three schemas that no longer have validation targets:

- schema/definitions/type-definition.json — validated the catalog YAML
  files deleted in the previous commit.
- schema/definitions/execution-definition.json — orphaned since v6.0.0
  when the execution/ directory was removed.
- schema/resolution/definitions.json — validated per-repo
  .hiivmind/blueprint/definitions.yaml, which is eliminated in v7.0.0
  in favour of the skill-embedded blueprint-types.md.

Authoring schemas (workflow, node-types, intent-mapping) are
unaffected — they were already type-agnostic, deferring precondition
and consequence type validation to runtime.

BREAKING CHANGE: schema/definitions/ and schema/resolution/ no longer
exist. Any tooling that validated against them must migrate.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Update `package.yaml`

**Files:**
- Modify: `package.yaml`

- [ ] **Step 1: Read the current contents**

Run:
```bash
cat package.yaml
```

Current relevant lines (as of commit `b9fa761`):
- Line 5: `version: "6.1.0"`
- Lines 6–14: multi-line description referencing the old catalog layout
- Lines 19–24: `schemas:` block including `definitions: "1.0"`
- Lines 27–32: `stats:` block
- Lines 35–41: `artifacts:` block listing `consequences/`, `preconditions/`, `nodes/`
- Lines 44: `minimum_blueprint_version: "6.1.0"`
- Lines 47–50: `usage:` block mentioning `.hiivmind/blueprint/definitions.yaml`

- [ ] **Step 2: Rewrite `package.yaml`**

Replace the entire file contents with:

```yaml
# Blueprint Types Library Package Manifest
# Semantic type definitions for hiivmind-blueprint

name: hiivmind-blueprint-lib
version: "7.0.0"
description: |
  Single-file type catalog for hiivmind-blueprint. Defines 22 consequence
  types, 9 precondition types, and 3 node types in blueprint-types.md at
  the repo root.

  The hiivmind-blueprint skill ships blueprint-types.md as skill-embedded
  reference. There is no per-repo definitions file; all workflow
  authoring LLMs read this single canonical document.

repository: https://github.com/hiivmind/hiivmind-blueprint-lib
license: MIT

# Schema versions for each authoring system
schemas:
  workflow: "3.0"
  node: "2.0"

# Statistics
stats:
  total_types: 34
  consequence_types: 22
  precondition_types: 9
  node_types: 3
  workflows: 1

# Artifacts produced by releases
artifacts:
  - blueprint-types.md  # The canonical type catalog
  - workflows/          # Reusable workflow definitions
  - schema/             # Authoring, config, and runtime JSON schemas
  - examples/           # Workflow call-site snippets

# Compatibility
minimum_blueprint_version: "7.0.0"

# How to use this package
usage: |
  The hiivmind-blueprint skill ships blueprint-types.md at build time
  from a pinned version of this library. Workflow authors reference
  types by name in their workflow YAML; the skill (and its LLM) knows
  what each name means by loading blueprint-types.md. Consuming repos
  do not keep a local copy of the catalog.
```

Use Edit or Write to overwrite `package.yaml` with the above.

- [ ] **Step 3: Verify YAML parses**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('package.yaml'))" && echo OK
```

Expected: `OK`. If a YAML parse error appears, fix and retry.

- [ ] **Step 4: Commit**

```bash
git add package.yaml
git commit -m "$(cat <<'EOF'
chore(release): bump to v7.0.0 for type catalog collapse

- version: 6.1.0 → 7.0.0
- artifacts: drop consequences/, preconditions/, nodes/; add
  blueprint-types.md
- schemas: drop definitions: "1.0" (schema deleted); keep workflow
  and node schema versions
- usage: describe skill-embedded distribution; per-repo definitions
  file eliminated
- minimum_blueprint_version: 6.1.0 → 7.0.0

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Update `README.md`

**Files:**
- Modify: `README.md`

The current README extensively describes the old catalog structure. It needs targeted edits in six sections, not a full rewrite — sections unrelated to catalog layout (Overview intro, Endings, State Management, Variable Interpolation, Three-Valued Logic, Versioning Policy, License) are preserved.

- [ ] **Step 1: Update the "How It Works" example**

Open `README.md`. Find the code block starting with `# From consequences/core.yaml` (around line 24).

Replace it with:

```yaml
# From blueprint-types.md
set_flag(flag, value)
  value ∈ {true, false}
  → state.flags[flag] = value
```

- [ ] **Step 2: Update the "When executing a workflow" list**

Directly below the code block, the list reads:

```
1. Reads the local definitions file (`.hiivmind/blueprint/definitions.yaml`)
2. Reads the workflow YAML (nodes, consequences, preconditions)
3. Interprets the `effect` pseudocode to perform each operation
4. Naturally handles interpolation, error recovery, and tool calls
```

Replace with:

```
1. Reads `blueprint-types.md` (shipped by the hiivmind-blueprint skill)
2. Reads the workflow YAML (nodes, consequences, preconditions)
3. Interprets each type by its documented signature and semantics
4. Naturally handles `${}` interpolation, error recovery, and tool calls
```

- [ ] **Step 3: Replace the "Overview" section's copy-paste example**

Find the Overview section (starts with "This package provides semantic type definitions...", around line 48). It contains a long code block showing `.hiivmind/blueprint/definitions.yaml` contents with `action`, `mutate_state`, and `state_check` examples.

Replace the entire paragraph + code block (from "This package provides..." through the closing "```" of the code block, through "Workflows no longer need a `definitions` block — types are resolved from the local file by convention.") with:

```markdown
This package provides a single-file type catalog at `blueprint-types.md`. The `hiivmind-blueprint` skill ships this file at build time from a pinned version of the library. There is no per-repo definitions file.

Workflow authors reference types by name; the workflow-executing LLM reads `blueprint-types.md` to interpret each name. Every type is documented as a short function-style signature with parameters, enum variants, and a one-line semantic description. See `blueprint-types.md` for the full catalog.
```

- [ ] **Step 4: Update the "Skills vs Workflows" table**

In the table, the `Type` row reads:

```
| Type | Building block for workflows | This catalog (`consequences/`, `preconditions/`, `nodes/`) |
```

Replace with:

```
| Type | Building block for workflows | `blueprint-types.md` (this repo) |
```

- [ ] **Step 5: Update the "Quick Start" step 1**

In the Quick Start section, step 1 reads:

```
1. Copy needed type definitions from this catalog into `.hiivmind/blueprint/definitions.yaml`
```

Replace with:

```
1. Install the `hiivmind-blueprint` skill (ships `blueprint-types.md` automatically)
```

- [ ] **Step 6: Collapse the "Type Inventory" section**

The current "Type Inventory" section contains three verbose tables listing every type by category across the old files. Replace the entire section (from `## Type Inventory` through the end of the "Workflows (1 workflow)" subsection, but stopping BEFORE `## Three-Valued Logic (3VL) for Intent Detection`) with:

```markdown
## Type Inventory

All 34 types are defined in `blueprint-types.md` at the repo root:

- **3 node types** — `action`, `conditional`, `user_prompt`
- **9 precondition types** — 3 core + 6 extensions
- **22 consequence types** — 13 core + 3 intent (3VL) + 6 extensions

See `blueprint-types.md` for signatures, parameters, and enum variants. See `examples/` for workflow call-site snippets.

### Workflows (1 workflow)

| Workflow | Description |
|----------|-------------|
| intent-detection | Reusable 3VL intent detection for dynamic routing |
```

- [ ] **Step 7: Rewrite the "File Structure" section**

The current "File Structure" section (around line 298) shows a directory tree. Replace the entire section with:

```markdown
## File Structure

```
hiivmind-blueprint-lib/
├── blueprint-types.md            # Single-file type catalog (3 nodes,
│                                 # 9 preconditions, 22 consequences)
├── package.yaml                  # Package manifest
├── CHANGELOG.md                  # Version history
│
├── workflows/                    # Reusable workflow definitions
│   └── core/
│       └── intent-detection.yaml # 3VL intent detection workflow
│
├── examples/                     # Workflow call-site snippets
│   ├── consequences.yaml
│   ├── preconditions.yaml
│   ├── nodes.yaml
│   ├── endings.yaml
│   └── execution.yaml
│
└── schema/                       # JSON schemas
    ├── common.json               # Shared definitions
    ├── authoring/                # Workflow authoring validation
    │   ├── workflow.json
    │   ├── node-types.json
    │   └── intent-mapping.json
    ├── config/                   # Runtime configuration
    │   ├── output-config.json
    │   └── prompts-config.json
    └── runtime/                  # Runtime output validation
        └── logging.json
```

```

Note: the `examples/index.yaml` file is still present but will be updated in Task 10 to reflect the new catalog location.

- [ ] **Step 8: Verify no broken references remain in README.md**

Run:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' README.md
```

Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): update for v7.0.0 single-file catalog

Removes all references to the deleted catalog YAML files and
per-repo definitions.yaml. The Type Inventory section collapses
from three tables to a short summary pointing at blueprint-types.md.
File Structure diagram updated to reflect the new layout.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (repo-level instructions)

- [ ] **Step 1: Read current content**

Open `CLAUDE.md`. The relevant sections are:

- "Repository Overview" (mentions "22 consequence types, 9 precondition types, 3 node types, 1 reusable workflow")
- "File Structure" — lists old YAML paths
- "HARD REQUIREMENT: Cross-Repository Synchronization" — lists old YAML files and the sync checklist
- "Key Concepts → Type Definition Structure (Catalog Format)" — describes the verbose YAML structure
- "Slimmed-Down Format (definitions.yaml)" — describes the eliminated per-repo format
- "Common Tasks → Adding a New Type" — instructs editing old YAML files
- "Common Tasks → Validating Changes" — references deleted schemas

- [ ] **Step 2: Replace the "File Structure" section**

Find the code block under `## File Structure` (around lines 26–38). Replace:

```
consequences/core.yaml            # 13 core consequence types
consequences/intent.yaml          # 3 intent detection (3VL) types
consequences/extensions.yaml      # 6 extension consequence types
preconditions/core.yaml           # 3 core precondition types
preconditions/extensions.yaml     # 6 extension precondition types
nodes/workflow_nodes.yaml         # All 3 node types
```

With:

```
blueprint-types.md                # Single-file type catalog (all 34 types)
```

Also replace the "Schema Directory" tree block below it:

```
schema/
├── definitions/    # Type definition schemas (type-definition, execution-definition)
├── authoring/      # Workflow authoring schemas (workflow, node-types, intent-mapping)
├── runtime/        # Runtime schemas (logging)
├── config/         # Configuration schemas (output-config, prompts-config)
├── resolution/     # Definitions file schema (definitions.json)
└── common.json     # Shared definitions
```

With:

```
schema/
├── authoring/      # Workflow authoring schemas (workflow, node-types, intent-mapping)
├── runtime/        # Runtime schemas (logging)
├── config/         # Configuration schemas (output-config, prompts-config)
└── common.json     # Shared definitions
```

- [ ] **Step 3: Rewrite the "HARD REQUIREMENT: Cross-Repository Synchronization" section**

The current section begins with `**When modifying YAML type definitions, you MUST also update related files...**`. Replace the entire section (from the `## HARD REQUIREMENT` heading through the end of the "Analysis Scope" subsection, up to but NOT including `## Key Concepts`) with:

```markdown
## HARD REQUIREMENT: Cross-Repository Synchronization

**When modifying `blueprint-types.md`, you MUST also update related files to prevent divergence.**

Any change to `blueprint-types.md` MUST be synchronized with:

| Location | Purpose |
|----------|---------|
| `examples/` (this repo) | Workflow call-site snippets must use current type names and enum variants |
| `hiivmind-blueprint/lib/patterns/authoring-guide.md` | Authoring guidance referencing the catalog |
| `hiivmind-blueprint/lib/patterns/execution-guide.md` | Execution guidance referencing the catalog |
| `hiivmind-blueprint` skill bundle | The skill ships `blueprint-types.md` at build time; bundle must re-copy after changes |

### Synchronization Checklist

Before completing any change to `blueprint-types.md`:

1. **Examples sync** — update `examples/*.yaml` if a type, parameter, or enum variant was renamed or removed.
2. **Patterns sync** — update the two `hiivmind-blueprint/lib/patterns/*` files if the change affects authoring or execution guidance.
3. **Skill bundle** — ensure the next `hiivmind-blueprint` skill release re-ships the updated file.

### Analysis Scope

When analyzing or planning changes to `blueprint-types.md`, ALWAYS consider impact on:
- Existing workflow call sites (will `type: X` still resolve? Will required params still be present?)
- Examples (do they still work?)
- The two pattern guides in `hiivmind-blueprint` (are their references still accurate?)
```

- [ ] **Step 4: Replace the "Key Concepts" section**

The current section describes "Type Definition Structure (Catalog Format)" with a verbose YAML template, then "Slimmed-Down Format (definitions.yaml)". Replace everything from `## Key Concepts` through the end of the "Three-Valued Logic (3VL)" subsection (but keep the `### Three-Valued Logic (3VL)` subsection itself — it's still accurate) with:

```markdown
## Key Concepts

### Type Catalog Format

All types are defined in a single file: `blueprint-types.md`. Each type is a function-style signature:

```
type_name(required_param, optional?)
  param ∈ {enum, variants}   # if applicable
  → one-line outcome / return meaning
```

**Conventions:**
- `?` suffix marks optional parameters.
- `X ∈ {a, b, c}` lists enum variants.
- `→` marks the outcome.
- All string parameters support `${}` state interpolation.
- Preconditions return boolean. Consequences mutate state or the world.

Workflow YAML reference types via `type: <name>` plus sibling keys for parameters. See `examples/` for concrete call-site snippets.

### Three-Valued Logic (3VL)

The `intent` category uses Kleene 3-valued logic:
- `T` (True) - Definite match
- `F` (False) - Definite non-match
- `U` (Unknown) - Uncertain or "don't care" (in rules)

Key types: `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules`
```

- [ ] **Step 5: Replace the "Common Tasks → Adding a New Type" subsection**

Find the `### Adding a New Type` subsection under `## Common Tasks`. Replace with:

```markdown
### Adding a New Type

1. Open `blueprint-types.md` at the repo root.
2. Add the type to the appropriate section (`## Nodes`, `## Preconditions` → `### Core`/`### Extensions`, or `## Consequences` → the appropriate category).
3. Write the signature in the established format (`name(params) → meaning`, with enum variants indented below if applicable).
4. Update `package.yaml.stats` if counts changed.
5. Add a workflow call-site example in `examples/`.
6. Update the two pattern guides in `hiivmind-blueprint/lib/patterns/` if the new type affects authoring or execution guidance.
```

- [ ] **Step 6: Replace the "Common Tasks → Validating Changes" subsection**

Find the `### Validating Changes` subsection. Replace with:

```markdown
### Validating Changes

There is no JSON schema for `blueprint-types.md` — it is a human/LLM reference document, not structured data. Validation is by inspection:

- Does the signature format match the conventions in the file's header?
- Do the parameters and enum variants match the behavior documented in the `→` line?
- Are existing examples in `examples/` still consistent with the type?

Workflow authoring schemas (`schema/authoring/*`) are type-agnostic: they validate workflow structure but delegate type-specific validation to runtime (the LLM). Changes to `blueprint-types.md` never require schema changes.
```

- [ ] **Step 7: Verify no broken references remain**

Run:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' CLAUDE.md
```

Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(claude): update repo instructions for v7.0.0

Rewrites File Structure, Cross-Repo Sync Checklist, Key Concepts,
and Common Tasks sections to reference blueprint-types.md as the
single source of type vocabulary. Removes references to deleted
catalog YAML files, deleted schemas, and the eliminated per-repo
definitions.yaml.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Update `CHANGELOG.md`

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Read the top of the file**

Run:
```bash
head -20 CHANGELOG.md
```

The file uses Keep a Changelog format. Entries are in reverse chronological order, so the new v7.0.0 entry goes immediately after the header (after line 7).

- [ ] **Step 2: Add v7.0.0 entry**

Use Edit to insert the following AFTER line 7 (after the "adheres to Semantic Versioning" line and the blank line that follows it) and BEFORE the existing `## [5.0.0]` heading — but note that the highest existing entry may be higher than 5.0.0. Re-read to confirm the topmost entry, then insert before it.

New entry content:

```markdown
## [7.0.0] - 2026-04-11

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

### Changed

- Version: `6.1.0` → `7.0.0`
- `package.yaml` artifacts: drop `consequences/`, `preconditions/`, `nodes/`; add `blueprint-types.md`
- `package.yaml` schemas block: drop `definitions: "1.0"` entry
- `README.md`: File Structure, Type Inventory, Quick Start, How It Works sections updated
- `CLAUDE.md`: File Structure, Sync Checklist, Key Concepts, Common Tasks sections updated
- `examples/index.yaml`: removed `source_files:` mapping to deleted YAML files
- Cross-repo: `hiivmind-blueprint/lib/patterns/authoring-guide.md` and `execution-guide.md` updated to reference `blueprint-types.md`
```

- [ ] **Step 3: Verify the file parses as markdown and the entry is at the top**

Run:
```bash
head -80 CHANGELOG.md
```

Expected: after the file header, the first `## [X.Y.Z]` heading is `## [7.0.0] - 2026-04-11`.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(changelog): add v7.0.0 entry for type catalog collapse

Enumerates breaking changes: six catalog YAML files deleted, three
obsolete schemas deleted, per-repo definitions.yaml eliminated,
universal interpolation on string parameters. No workflow migration
required — type names, parameters, and enum variants are preserved.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Update `examples/`

**Files:**
- Modify: `examples/index.yaml`
- Modify: `examples/execution.yaml` (if it references deleted paths)

- [ ] **Step 1: Inspect the current state**

Run:
```bash
grep -l 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml' examples/
```

Expected: at least `examples/index.yaml` and likely `examples/execution.yaml`.

- [ ] **Step 2: Rewrite `examples/index.yaml`**

The current file has a `files:` block with a `source_files:` sub-map listing `core.yaml`, `intent.yaml`, `extensions.yaml` under `consequences` and `preconditions`. That sub-map must go — but the overall index structure (listing which example files exist and what categories they cover) is still useful.

Read the current content first:
```bash
cat examples/index.yaml
```

Then replace the `files:` block entirely. The new content for the whole file:

```yaml
# Examples Index
# Documentary reference for hiivmind-blueprint type usage patterns
# v7.0.0 - Type catalog collapsed into single blueprint-types.md
#
# These examples are for human reference, not for automated testing.
# They show how to use the various types from blueprint-types.md in workflows.

schema_version: "7.0"
description: |
  Example usage patterns for hiivmind-blueprint types. Documentary
  reference for workflow authors. Types themselves are defined in
  blueprint-types.md at the repo root.

  Examples are organized by domain. Each example includes a title,
  YAML snippet, and explanation.

files:
  consequences:
    description: Examples for consequence types (actions/effects)
    categories:
      - core/control
      - core/evaluation
      - core/interaction
      - core/logging
      - core/state
      - core/utility
      - core/intent
      - extensions/file-system
      - extensions/git
      - extensions/hashing
      - extensions/package
      - extensions/scripting
      - extensions/web

  preconditions:
    description: Examples for precondition types (conditions)
    categories:
      - core/composite
      - core/expression
      - core/state
      - extensions/filesystem
      - extensions/git
      - extensions/network
      - extensions/python
      - extensions/tools
      - extensions/web

  nodes:
    description: Examples for node types (workflow elements)
    categories:
      - action
      - conditional
      - user_prompt

  endings:
    description: Examples for ending definitions (outcome types, behaviors, consequences)
    categories:
      - display
      - delegate
      - restart
      - silent
      - error_with_consequences
      - indeterminate

  execution:
    description: Examples for execution patterns
    categories:
      - consequence-dispatch
      - precondition-dispatch
      - state
      - traversal

usage: |
  These examples are documentary only - they are snippets and fragments
  intended to illustrate usage patterns. They are not validated against
  JSON schemas and may be incomplete on their own.

  To use a pattern:
  1. Find the relevant type in blueprint-types.md (repo root)
  2. Find the relevant example in examples/<category>.yaml
  3. Adapt the YAML to your workflow context
  4. Ensure all required parameters are provided
  5. Validate your complete workflow against schema/authoring/workflow.json
```

Note: the old file had a `definitions:` section under `files:` describing "Example .hiivmind/blueprint/definitions.yaml format". That section is removed entirely since the per-repo file no longer exists.

- [ ] **Step 3: Verify YAML parses**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('examples/index.yaml'))" && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Inspect `examples/execution.yaml`**

Run:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' examples/execution.yaml
```

If output is non-empty: read the surrounding context for each match (`grep -n -C 3 '...' examples/execution.yaml`) and rewrite each affected block to reference `blueprint-types.md` instead. Most likely the references are in prose comments (`# From consequences/core.yaml` or similar) and can be replaced with `# From blueprint-types.md` or removed.

If output is empty: no changes needed — skip to Step 6.

- [ ] **Step 5: Verify `examples/execution.yaml` still parses**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('examples/execution.yaml'))" && echo OK
```

Expected: `OK`.

- [ ] **Step 6: Confirm no example file still references deleted paths**

Run:
```bash
grep -rn 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' examples/
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add examples/
git commit -m "$(cat <<'EOF'
docs(examples): update index for v7.0.0 single-file catalog

- examples/index.yaml: removed source_files mapping to deleted catalog
  YAMLs, removed the definitions example section (per-repo file is
  eliminated), updated usage instructions to point at blueprint-types.md
- examples/execution.yaml: updated prose references (if any)

Workflow snippets themselves are unchanged — type names, parameters,
and enum variants are preserved.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Update `lib/patterns/change-classification.md`

**Files:**
- Modify: `lib/patterns/change-classification.md` (if references exist)

This file was flagged by the baseline grep. It may reference the old catalog in its "Repository-Specific Rules" or classification examples.

- [ ] **Step 1: Inspect references**

Run:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' lib/patterns/change-classification.md
```

- [ ] **Step 2: For each match, read context and decide**

For each line reported, read 10 lines of context around it:
```bash
grep -n -C 5 '<pattern>' lib/patterns/change-classification.md
```

For each reference:

- **If the reference is in a change-classification example** (e.g., "adding a new type to `consequences/core.yaml` is a minor bump"): replace with an equivalent reference to `blueprint-types.md`. For example: "adding a new type to `blueprint-types.md` is a minor bump".
- **If the reference is in a file-path pattern used by an automated check** (e.g., a glob): replace with a pattern matching `blueprint-types.md`.
- **If the reference is historical prose** (describing what USED to be the case): leave it alone only if it clearly reads as past tense. Otherwise update.

- [ ] **Step 3: Apply edits and verify**

After edits:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' lib/patterns/change-classification.md
```

Expected: no output.

- [ ] **Step 4: Commit (only if edits were made)**

```bash
git add lib/patterns/change-classification.md
git commit -m "$(cat <<'EOF'
docs(lib): update change-classification for v7.0.0

Repository-specific classification rules now reference
blueprint-types.md instead of the deleted catalog YAML files.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

If no changes were needed, skip this commit.

---

## Task 12: Resolve `docs/refactor/` stale plans

**Files:**
- Modify or delete: `docs/refactor/simplify.md`
- Modify or delete: `docs/refactor/swarm-simplify-plan.md`
- Leave: `docs/refactor/test.txt` (not flagged by baseline grep)

These files are earlier simplification plans that reference the old catalog. The spec explicitly requires eliminating ghost definitions.

- [ ] **Step 1: Inspect each file**

Run:
```bash
head -40 docs/refactor/simplify.md
head -40 docs/refactor/swarm-simplify-plan.md
```

Read enough of each to decide: is this a historical plan document worth keeping (convert past-tense references into historical prose), or is it a stale work plan that should be deleted?

**Default recommendation:** If either file is a "plan to simplify" that is now *superseded by this v7.0.0 work*, delete it. Do not keep competing plans around.

- [ ] **Step 2: Delete or update**

For each file:

- **To delete:**
  ```bash
  git rm docs/refactor/simplify.md
  ```
  (repeat for the other file)

- **To update in place:** edit each reference to `consequences/...` / `preconditions/...` / `nodes/...` etc. to describe the historical catalog structure in past tense, OR add a top-of-file banner:
  ```markdown
  > **Superseded:** This document described a simplification plan that predates v7.0.0. See `blueprint-types.md` and `docs/superpowers/specs/2026-04-11-blueprint-type-catalog-collapse-design.md` for the current state.
  ```

- [ ] **Step 3: Verify no remaining ghost references**

Run:
```bash
grep -rn 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' docs/refactor/
```

Expected: no output (if files deleted) or only output inside prose that is clearly historical-tense.

- [ ] **Step 4: Commit**

```bash
git add -A docs/refactor/
git commit -m "$(cat <<'EOF'
docs(refactor): resolve stale simplification plans

Removes or marks superseded the pre-v7.0.0 simplification plans in
docs/refactor/. The type catalog collapse design in
docs/superpowers/specs/ is the current authoritative plan.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Cross-repo update (hiivmind-blueprint patterns)

**Files:**
- Modify: `../hiivmind-blueprint/lib/patterns/authoring-guide.md`
- Modify: `../hiivmind-blueprint/lib/patterns/execution-guide.md`

**Scope note:** The sibling `hiivmind-blueprint` repo has ~17 files that reference old catalog paths. Per the spec's non-goals, only these two pattern files are in scope for this plan. The others are tracked as follow-ups in Task 15.

- [ ] **Step 1: Switch to the sibling repo**

Run:
```bash
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint
git status
git branch --show-current
```

Expected: clean working tree. Note the current branch.

- [ ] **Step 2: Create a matching feature branch**

```bash
git checkout -b refactor/type-catalog-pointer-update
```

- [ ] **Step 3: Update `authoring-guide.md`**

Inspect:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml' lib/patterns/authoring-guide.md
```

For each match:

- **Type reference tables** — replace any table that enumerates types by category with a single pointer: `See [blueprint-types.md](https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md) in hiivmind-blueprint-lib for the complete type catalog.`
- **File path references** — replace `consequences/core.yaml` etc. with `blueprint-types.md`.
- **`.hiivmind/blueprint/definitions.yaml` references** — explain that the file is no longer needed; the skill loads `blueprint-types.md` automatically.

Verify:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml' lib/patterns/authoring-guide.md
```

Expected: no output.

- [ ] **Step 4: Update `execution-guide.md`**

Inspect:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml' lib/patterns/execution-guide.md
```

For each match:

- **Dispatch tables** — keep the high-level explanation of how the LLM dispatches on `type:`, but replace per-type enumerations with a pointer to `blueprint-types.md`.
- **File path references** — replace with `blueprint-types.md`.
- **Per-repo definitions references** — update to describe the skill-embedded distribution.

Verify:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml' lib/patterns/execution-guide.md
```

Expected: no output.

- [ ] **Step 5: Commit in hiivmind-blueprint**

```bash
git add lib/patterns/authoring-guide.md lib/patterns/execution-guide.md
git commit -m "$(cat <<'EOF'
docs(patterns): point to blueprint-types.md for v7.0.0

hiivmind-blueprint-lib v7.0.0 collapses the six catalog YAML files
into a single blueprint-types.md at the repo root. These two pattern
guides now reference the single-file catalog instead of enumerating
types in local tables.

Follow-up: other files in this repo (SKILL.md files, templates/,
references/, architecture.md) still reference old catalog paths
and will be updated in a subsequent pass.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Return to hiivmind-blueprint-lib**

```bash
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib
git branch --show-current
```

Expected: `refactor/type-catalog-collapse`.

Note: the cross-repo change is NOT merged into hiivmind-blueprint-lib; it lives on its own feature branch in its own repo and will be PR'd separately. This plan only requires that the branch exists and the commit lands.

---

## Task 14: No-ghost-definitions audit

**Files:**
- No file changes (verification only)

This is the spec's success criterion #10. The audit must return zero actionable references across `hiivmind-blueprint-lib`.

- [ ] **Step 1: Run the full ghost-definition grep**

```bash
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib
grep -rn --include='*.md' --include='*.yaml' --include='*.json' \
  -e 'consequences/core\.yaml' \
  -e 'consequences/intent\.yaml' \
  -e 'consequences/extensions\.yaml' \
  -e 'preconditions/core\.yaml' \
  -e 'preconditions/extensions\.yaml' \
  -e 'nodes/workflow_nodes\.yaml' \
  -e '\.hiivmind/blueprint/definitions\.yaml' \
  -e 'schema/definitions/' \
  -e 'schema/resolution/' \
  . 2>/dev/null
```

- [ ] **Step 2: Classify every match as exempt or actionable**

**Exempt matches (allowed to remain):**
- `docs/superpowers/specs/2026-04-11-blueprint-type-catalog-collapse-design.md` — the spec itself describes the removal
- `docs/superpowers/plans/2026-04-11-blueprint-type-catalog-collapse.md` — this plan describes the removal
- `CHANGELOG.md` — v7.0.0 entry legitimately lists what was removed, and older entries (5.0.0 and earlier) are historical

**Actionable matches (must be fixed):**
- Anything in `README.md`, `CLAUDE.md`, `blueprint-types.md`, `package.yaml`, `examples/`, `lib/`, `docs/refactor/`, `schema/` (remaining files), or `workflows/`
- Any prose in `docs/` analysis files (`prose-comparative-analysis.md`, `blueprint-python-runtime-analysis.md`, `spoon-core-integration-analysis.md`, etc.) that references the old paths as *current* rather than historical

- [ ] **Step 3: Check docs/ analysis files**

Run:
```bash
grep -n 'consequences/core\.yaml\|consequences/intent\.yaml\|consequences/extensions\.yaml\|preconditions/core\.yaml\|preconditions/extensions\.yaml\|nodes/workflow_nodes\.yaml\|\.hiivmind/blueprint/definitions\.yaml\|schema/definitions\|schema/resolution' docs/*.md
```

For each match, read context:
```bash
grep -n -C 3 '<pattern>' docs/<file>.md
```

If the reference is clearly historical prose (e.g., "The current catalog uses consequences/core.yaml..."), reword to past tense: "Before v7.0.0, the catalog used consequences/core.yaml...". If the reference is an ADR proposal or research doc that is explicitly not-implemented (these files are marked as such in the memory), it's fine — the memory confirms they are proposals.

If any match is actionable, fix it. If edits are made, commit with:

```bash
git add docs/
git commit -m "$(cat <<'EOF'
docs: reword historical references in analysis docs for v7.0.0

Updates analysis documents to refer to pre-v7.0.0 catalog structure
in past tense, removing them from the no-ghost-definitions audit.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Final audit — the "clean" version**

Run the audit one more time, this time excluding the exempt files:

```bash
grep -rn --include='*.md' --include='*.yaml' --include='*.json' \
  --exclude-dir=docs/superpowers \
  -e 'consequences/core\.yaml' \
  -e 'consequences/intent\.yaml' \
  -e 'consequences/extensions\.yaml' \
  -e 'preconditions/core\.yaml' \
  -e 'preconditions/extensions\.yaml' \
  -e 'nodes/workflow_nodes\.yaml' \
  -e '\.hiivmind/blueprint/definitions\.yaml' \
  -e 'schema/definitions/' \
  -e 'schema/resolution/' \
  . 2>/dev/null | grep -v '^\./CHANGELOG\.md:'
```

Expected: **zero lines of output**. This is the success criterion.

If any lines remain, they are actionable ghosts. Fix them in the appropriate file, commit, and re-run this exact grep until it produces zero output.

- [ ] **Step 5: Verify `definitions: "1.0"` is also gone from package.yaml**

Run:
```bash
grep -n 'definitions: "1\.0"' package.yaml
```

Expected: no output.

- [ ] **Step 6: Verify the `schema/` tree is in its final state**

Run:
```bash
find schema -type f -name '*.json' | sort
find schema -type d | sort
```

Expected files (9 total):
```
schema/_deprecated/display-config.json
schema/_deprecated/logging-config.json
schema/authoring/intent-mapping.json
schema/authoring/node-types.json
schema/authoring/workflow.json
schema/common.json
schema/config/output-config.json
schema/config/prompts-config.json
schema/runtime/logging.json
```

Expected directories: `schema`, `schema/_deprecated`, `schema/authoring`, `schema/config`, `schema/runtime`. (No `schema/definitions/`, no `schema/resolution/`.)

- [ ] **Step 7: Verify the top-level tree**

Run:
```bash
ls -la
```

Confirm:
- `blueprint-types.md` is present at the repo root
- `consequences/`, `preconditions/`, `nodes/` are NOT present
- Other top-level files (`README.md`, `CLAUDE.md`, `CHANGELOG.md`, `package.yaml`, `LICENSE`, etc.) are present

- [ ] **Step 8: Commit audit pass (if any files were touched)**

If Step 3 or other audit steps produced edits that haven't been committed yet, group them into a single "audit pass" commit:

```bash
git add -A
git status
git commit -m "$(cat <<'EOF'
chore: final no-ghost-definitions audit pass

Resolves any remaining actionable references to deleted catalog paths
found in the final audit. The audit now returns zero lines outside of
exempt historical documents (CHANGELOG.md, docs/superpowers/*).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

If nothing was changed in this task, no commit is needed.

---

## Task 15: Prepare for review

**Files:**
- No file changes

- [ ] **Step 1: Run `git log` to confirm the branch history**

Run:
```bash
git log --oneline refactor/simpilfy..refactor/type-catalog-collapse
```

Expected: a sequence of ~11 commits (one per task that committed):
```
<sha> chore: final no-ghost-definitions audit pass           (optional, only if Task 14 made edits)
<sha> docs(refactor): resolve stale simplification plans
<sha> docs(lib): update change-classification for v7.0.0     (optional, only if Task 11 made edits)
<sha> docs(examples): update index for v7.0.0 single-file catalog
<sha> docs(changelog): add v7.0.0 entry for type catalog collapse
<sha> docs(claude): update repo instructions for v7.0.0
<sha> docs(readme): update for v7.0.0 single-file catalog
<sha> chore(release): bump to v7.0.0 for type catalog collapse
<sha> refactor!: delete obsolete definition schemas (v7.0.0 collapse)
<sha> refactor!: delete catalog YAML files (v7.0.0 collapse)
<sha> feat: add blueprint-types.md single-file type catalog
```

If a commit is missing, go back and do the task it corresponds to.

- [ ] **Step 2: Diff-stat summary**

Run:
```bash
git diff --stat refactor/simpilfy..refactor/type-catalog-collapse
```

Expected rough shape:
- `blueprint-types.md` created (~170 lines added)
- `consequences/*.yaml`, `preconditions/*.yaml`, `nodes/workflow_nodes.yaml` all deleted (~2,218 lines removed)
- `schema/definitions/*.json`, `schema/resolution/*.json` all deleted
- `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `package.yaml`, `examples/index.yaml` all modified
- Net change: **large negative line delta** — this is a compression refactor

- [ ] **Step 3: List follow-up items not in scope for this plan**

Record the following as follow-ups (these are NOT blockers for merging this branch):

**In `hiivmind-blueprint` (sibling repo):**
The following ~17 files still reference old catalog paths and need updating in a separate pass:
```
skills/bp-maintain/SKILL.md
skills/bp-build/SKILL.md
.hiivmind/blueprint/execution-guide.md
templates/engine-entrypoint.md.template
.hiivmind/blueprint/engine_entrypoint.md
lib/patterns/node-mapping.md
skills/bp-extract/SKILL.md
templates/gateway-command.md.template
templates/workflow.yaml.template
templates/SKILL.md.template
references/node-features.md
references/preconditions-catalog.md
references/prompt-modes.md
references/consequences-catalog.md
docs/architecture.md
```
(Plus the `_archived/` SKILL.md files, which can be ignored.)

**In this repo (hiivmind-blueprint-lib):**
- Prune `examples/` to one example per type (deferred per spec non-goals)
- Clean up `schema/_deprecated/` directory (deferred per spec non-goals)

Add these to an issue tracker, a follow-up plan doc, or mention them in the PR description when the branch is opened for review.

- [ ] **Step 4: Announce completion**

The branch `refactor/type-catalog-collapse` is ready for human review. The canonical summary: **2,218 → ~180 lines**, 34 types preserved, 3 obsolete schemas deleted, zero actionable ghost references remaining.

---

## Self-Review Checklist (for the plan author, not the executor)

**1. Spec coverage:**

| Spec requirement | Covered by |
|---|---|
| Create `blueprint-types.md` with all 34 types | Task 2 |
| Delete 6 catalog YAML files + parent dirs | Task 4 |
| Delete 3 schema files + 2 parent dirs | Task 5 |
| Update `package.yaml` to v7.0.0 | Task 6 |
| Update `README.md` | Task 7 |
| Update `CLAUDE.md` | Task 8 |
| Update `CHANGELOG.md` | Task 9 |
| Preserve `examples/` with updates | Task 10 |
| Update `lib/patterns/change-classification.md` | Task 11 |
| Resolve stale `docs/refactor/` plans | Task 12 |
| Cross-repo: `hiivmind-blueprint/lib/patterns/*` | Task 13 |
| No-ghost-definitions audit returns zero | Task 14 |
| Feature branch `refactor/type-catalog-collapse` | Task 1 |
| 100% type/param/enum parity verified | Task 3 |

All spec requirements covered.

**2. Placeholder scan:** No TBDs, TODOs, "implement later", or "similar to Task N" references. Every step has concrete commands or code. ✓

**3. Type consistency:** Type names, parameter names, and enum variants used in `blueprint-types.md` (Task 2) match what's in the spec draft. The parity verification (Task 3) is explicitly designed to catch any drift. ✓
