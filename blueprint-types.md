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
