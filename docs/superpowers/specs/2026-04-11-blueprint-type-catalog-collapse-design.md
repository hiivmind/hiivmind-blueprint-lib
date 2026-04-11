# Blueprint Type Catalog Collapse — Design

**Date:** 2026-04-11
**Status:** Proposed
**Target version:** v7.0.0 (major)

## Context

`hiivmind-blueprint-lib` currently defines 34 Blueprint types across six YAML
files totalling **2,218 lines**:

| File | Lines | Types |
|---|---|---|
| `consequences/core.yaml` | 687 | 13 |
| `consequences/intent.yaml` | 151 | 3 |
| `consequences/extensions.yaml` | 475 | 6 |
| `preconditions/core.yaml` | 199 | 3 |
| `preconditions/extensions.yaml` | 369 | 6 |
| `nodes/workflow_nodes.yaml` | 337 | 3 |

Each type carries extensive scaffolding: `category`, `since`, `replaces`,
`schema_version`, per-parameter `type`/`required`/`pattern`/`interpolatable`
flags, `payload.effect` pseudocode, `state_reads` / `state_writes` bookkeeping,
and duplicated `description.brief` + `description.detail` + `notes`.

None of this scaffolding is machine-enforced at workflow authoring time. A
direct audit of every schema file in `schema/` confirms:

> "The schema validates structure only - precondition type validation is
> delegated to runtime."
> — `schema/authoring/node-types.json:228`

Workflow schemas treat every precondition and consequence as
`{type: <identifier>, ...additionalProperties: true}`. Type existence, parameter
presence, enum variants, and parameter types are **not** validated anywhere —
they are interpreted at runtime by an LLM (or Python code cooperating with an
LLM) that reads the catalog as reference text. The structured YAML format is
therefore writing a lot of ceremony to produce text the LLM would have
understood from a single sentence.

Blueprint's core paradigm is **LLM-as-execution-engine**. The type catalog
should look the way an LLM actually needs to read it: a compact vocabulary of
function-style signatures with enum variants and one-line semantics.

## Goals

1. Replace six catalog YAML files with **one** markdown file at the repo
   root — `blueprint-types.md` — containing all 34 types in a compact,
   signature-style format.
2. Delete catalog schemas that become obsolete
   (`schema/definitions/type-definition.json`,
   `schema/definitions/execution-definition.json`,
   `schema/resolution/definitions.json`).
3. Eliminate the per-repo `.hiivmind/blueprint/definitions.yaml` concept. The
   canonical type vocabulary lives in exactly one place: the pinned version of
   `blueprint-types.md` inside `hiivmind-blueprint-lib`.
4. Reach parity: every type name, every parameter name, every enum variant
   present in the current catalog must appear in the compressed form. Nothing
   silently drops.
5. Preserve `examples/` as workflow call-site snippets (separate concern from
   the catalog).
6. Synchronize cross-repo references in `hiivmind-blueprint/patterns/*` to
   point at `blueprint-types.md`.

## Non-goals

- Changing any type name, parameter name, or enum variant.
- Changing the workflow schema (`schema/authoring/*`). Workflows are still
  validated structurally; the catalog compression has zero effect on workflow
  validation because the workflow schema was already type-agnostic.
- Introducing new types, removing existing types, or renaming categories.
- Changing runtime dispatch semantics.
- Redesigning `examples/` beyond removing anything that referenced deleted
  concepts.

## Design

### The single file

**Location:** `blueprint-types.md` at the repo root.

**Format:** Markdown with signature-style code blocks. Grouped top-level by
node / precondition / consequence. Consequences sub-grouped by category
(`core/control`, `core/evaluation`, ... `extensions/hashing`) using `###`
headings. Preconditions split into `### Core` and `### Extensions`.

**Conventions (documented once at the top of the file):**

- `name(param1, param2, optional?)` — reference signature. `?` suffix marks
  optional params. This is notation only; the actual YAML call site uses sibling
  keys, not positional arguments.
- `X ∈ {a, b, c}` — enum variants on the line below the signature, indented.
- `→` — marks the outcome / return meaning.
- Interpolation rule: string parameters that name *content* or *locations*
  (`path`, `url`, `content`, `message`, `prompt`) support `${}` state
  interpolation. Enum variants (`operation`, `check`, `aspect`) and identifier
  slots (field paths, flag names, `store_as`) are literal unless explicitly
  noted otherwise. This replaces the per-parameter `interpolatable: true/false`
  flag in the current catalog.
- Preconditions always return boolean. Consequences mutate state or the world.

**Expected size:** ~150 lines for all 34 types. From 2,218 → ~150 is a ~93%
reduction.

### Draft content (normative)

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
- String params that name content or locations (`path`, `url`, `content`,
  `message`, `prompt`) support `${}` state interpolation. Enum variants and
  identifier slots (field paths, flag names, `store_as`) are literal.
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

### What gets deleted

| Path | Reason |
|---|---|
| `consequences/core.yaml` | Folded into `blueprint-types.md` |
| `consequences/intent.yaml` | Folded into `blueprint-types.md` |
| `consequences/extensions.yaml` | Folded into `blueprint-types.md` |
| `preconditions/core.yaml` | Folded into `blueprint-types.md` |
| `preconditions/extensions.yaml` | Folded into `blueprint-types.md` |
| `nodes/workflow_nodes.yaml` | Folded into `blueprint-types.md` |
| `consequences/` directory | Empty after file deletions |
| `preconditions/` directory | Empty after file deletions |
| `nodes/` directory | Empty after file deletions |
| `schema/definitions/type-definition.json` | Nothing left to validate |
| `schema/definitions/execution-definition.json` | Orphaned since v6.0.0 (execution/ dir deleted) |
| `schema/definitions/` directory | Empty after file deletions |
| `schema/resolution/definitions.json` | Per-repo `definitions.yaml` is eliminated |
| `schema/resolution/` directory | Empty after file deletions |

### What is preserved

| Path | Reason |
|---|---|
| `schema/authoring/workflow.json` | Workflow validation is unaffected |
| `schema/authoring/node-types.json` | Node structural validation is unaffected |
| `schema/authoring/intent-mapping.json` | Intent mapping file validation is unaffected |
| `schema/common.json` | Shared fragments still used by authoring schemas |
| `schema/config/*` | Output and prompts configs still used |
| `schema/runtime/logging.json` | Log output schema still valid |
| `schema/_deprecated/*` | Not in scope for this change; handle in a separate cleanup |
| `examples/` | Kept as workflow call-site snippets. See note below. |
| `workflows/` | Reusable workflows unaffected |
| `package.yaml` | Updated with v7.0.0 stats |

### `examples/` preservation

`examples/consequences.yaml`, `examples/preconditions.yaml`,
`examples/workflow_nodes.yaml`, and similar files stay in place for now. They
document workflow *call-site* snippets (how `type: tool_check` looks in a real
workflow), which is a different concern from the type catalog. A follow-up pass
may prune them to one example per type but that is out of scope for v7.0.0.

**Required adjustment in this pass:** any example that references a type name,
enum variant, or parameter that no longer exists in the catalog (there should
be none, per the parity goal) must be fixed or removed.

### Per-repo consumption: skill-embedded

The `hiivmind-blueprint` skill (in the `hiivmind-blueprint` repo, separate from
this lib) ships `blueprint-types.md` as part of its skill bundle. Every
invocation of the skill loads the file into context automatically. Consuming
repos do not keep a local copy of the catalog; they reference types by name
from their workflow YAML and rely on the skill to know what each name means.

Version management is straightforward: each `hiivmind-blueprint` skill release
pins a specific version of `hiivmind-blueprint-lib` and copies the
`blueprint-types.md` from that pinned version at build time.

### Cross-repo sync obligations

`hiivmind-blueprint/patterns/authoring-guide.md` and
`hiivmind-blueprint/patterns/execution-guide.md` currently contain their own
type reference tables and dispatch descriptions. These must be updated in the
same release window:

- `authoring-guide.md` → type reference tables replaced by a pointer:
  *"See `blueprint-types.md` in hiivmind-blueprint-lib for the complete
  vocabulary."*
- `execution-guide.md` → dispatch descriptions keep their high-level
  explanation (how the LLM dispatches on `type:`) but drop any per-type
  enumeration; reference `blueprint-types.md` for the vocabulary.

The implementation plan will enumerate the specific sections that need edits
in the downstream repo.

### Versioning

This is a **major** version bump: **v7.0.0**.

Breaking changes (from a consumer perspective):

1. Catalog YAML files are deleted. Any tool that parsed them now fails.
2. `schema/resolution/definitions.json` is deleted. Any `.hiivmind/blueprint/definitions.yaml`
   file in a consuming repo is no longer the source of truth — it can be
   deleted.
3. `package.yaml.stats.total_types` stays at 34, but `consequence_types`,
   `precondition_types`, and `node_types` remain accurate. `artifacts` field
   updated to drop `consequences/`, `preconditions/`, `nodes/` and add
   `blueprint-types.md`.

`CHANGELOG.md` entry enumerates deletions and the new single-file location.
`RELEASING.md` is unchanged — the existing `/prepare-release` flow handles this.

### Migration notes

For a repo that previously used `.hiivmind/blueprint/definitions.yaml`:

1. Delete the file.
2. Upgrade `hiivmind-blueprint` skill to a version that pins
   `hiivmind-blueprint-lib` ≥ v7.0.0.
3. No workflow changes required — type names, parameter names, and enum
   variants are unchanged.

## Open questions

None at design time. All decisions locked in the brainstorm:

- Filename: `blueprint-types.md`.
- Per-repo consumption: skill-embedded (option A from brainstorm).
- `examples/` kept as-is for now.
- Cross-repo sync to `hiivmind-blueprint/patterns/*`: required, in scope.
- Version bump: v7.0.0.
- Concept name: "type catalog".

## Success criteria

1. `blueprint-types.md` exists at repo root with all 34 types.
2. All six catalog YAML files and their parent directories are deleted.
3. `schema/definitions/` and `schema/resolution/` directories are deleted.
4. `package.yaml` reflects v7.0.0 with updated `artifacts` list.
5. `README.md` and `CLAUDE.md` updated — every reference to
   `consequences/*.yaml`, `preconditions/*.yaml`, `nodes/*.yaml`, or
   `.hiivmind/blueprint/definitions.yaml` replaced with a pointer to
   `blueprint-types.md`.
6. `CHANGELOG.md` has a v7.0.0 entry enumerating the breaking changes.
7. Every existing example in `examples/` either still references valid type
   names / params / enum variants, or is removed.
8. `hiivmind-blueprint/patterns/authoring-guide.md` and
   `patterns/execution-guide.md` updated to reference `blueprint-types.md`.
9. No catalog content (type name, parameter name, enum variant) that existed
   pre-change is missing from `blueprint-types.md`.
