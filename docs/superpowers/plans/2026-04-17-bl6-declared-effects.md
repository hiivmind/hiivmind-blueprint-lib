# BL6 `declared_effects` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the optional top-level `declared_effects:` block to the blueprint-lib workflow schema, shipped as v8.1.0.

**Architecture:** Purely additive change. One new optional property on `workflow.json`; catalog documentation in `blueprint-types.md`; extended worked example in `examples.md`; three positive + three negative fixtures; cross-repo sync to `hiivmind-blueprint` authoring/execution guides.

**Tech Stack:** JSON Schema Draft 2020-12 (`ajv-cli@5` validator), YAML fixtures (`yq`), Bash test runners (`scripts/validate-workflows.sh`).

---

## Spec

`docs/superpowers/specs/2026-04-17-bl6-declared-effects-design.md`

## Working branch

`feat/bl6-declared-effects` (already created off `develop`, spec already committed as `41a6ee7`).

## Target

`develop` (blueprint-lib follows `develop → release/* → main` flow).

## File structure

| File | Responsibility |
|---|---|
| `schema/authoring/workflow.json` | New optional property `declared_effects`; bump `$comment` schema-version note. |
| `blueprint-types.md` | New `## Declared Effects` top-level section (parallel to `## Payload Types`). |
| `examples.md` | Extend `## 4. MCP-Delegated Query` worked example with a `declared_effects:` block. |
| `tests/fixtures/workflows/v8_declared_effects_narrow/input.yaml` | Positive: narrowed envelope with `tools` + `max_call_count`. |
| `tests/fixtures/workflows/v8_declared_effects_forbidden/input.yaml` | Positive: `alias: forbidden` literal (declared + undeclared aliases). |
| `tests/fixtures/workflows/v8_declared_effects_unknown_key/input.yaml` | Positive: forward-compat extension keys under alias object. |
| `tests/fixtures/workflows/_negative/declared_effects_bad_value/input.yaml` | Negative: alias value neither object nor `"forbidden"`. |
| `tests/fixtures/workflows/_negative/declared_effects_bad_alias_name/input.yaml` | Negative: alias fails `propertyNames` pattern. |
| `tests/fixtures/workflows/_negative/declared_effects_negative_max_count/input.yaml` | Negative: `max_call_count: -1`. |
| `package.yaml` | Version bump 8.0.0 → 8.1.0; `schemas.workflow: "4.0"` → `"4.1"`. |
| `CHANGELOG.md` | New `[8.1.0] - 2026-04-17` entry. |
| `../hiivmind-blueprint/lib/patterns/authoring-guide.md` | New `declared_effects` subsection. |
| `../hiivmind-blueprint/lib/patterns/execution-guide.md` | One-paragraph note delegating envelope enforcement to the consuming runtime. |

---

## Task 1: Write the first positive fixture and confirm baseline rejection

Before touching the schema, write a positive fixture that exercises the new key. Because `workflow.json` currently has `additionalProperties: false` at its root, the validator MUST reject it today — that's the baseline for TDD.

**Files:**
- Create: `tests/fixtures/workflows/v8_declared_effects_narrow/input.yaml`

- [ ] **Step 1: Create the positive fixture**

Create `tests/fixtures/workflows/v8_declared_effects_narrow/input.yaml`:

```yaml
name: declared-effects-narrow
version: "1.0.0"
description: Workflow with a narrowed effect envelope — tools subset plus call count cap.

data_mcps:
  crm: "internal-crm@^2.1"
  billing: "stripe-mcp@~3"

declared_effects:
  crm:
    tools: [search_customers, get_account]
  billing:
    tools: [create_invoice]
    max_call_count: 1

start_node: search
default_error: error_generic

nodes:
  search:
    type: action
    consequences:
      - type: mcp_tool_call
        tool: crm.search_customers
        params:
          q: "${computed.query}"
        store_as: computed.hits
    on_success: done

  done:
    type: ending
    outcome: success
    message: "Done."

  error_generic:
    type: ending
    outcome: error
    message: "Error."
```

- [ ] **Step 2: Run validator to verify it FAILS at baseline**

Run: `bash scripts/validate-workflows.sh`

Expected: `FAIL  tests/fixtures/workflows/v8_declared_effects_narrow/input.yaml` with an `additionalProperties` error naming `declared_effects`. Exit code `1`.

This confirms the schema currently rejects the key — exactly what we expect before the schema change.

- [ ] **Step 3: Commit the fixture (without schema change)**

```bash
git add tests/fixtures/workflows/v8_declared_effects_narrow/input.yaml
git commit -m "test(bl6): positive fixture for narrowed declared_effects envelope"
```

The commit intentionally leaves the suite failing — Task 2 fixes it.

---

## Task 2: Add `declared_effects` to workflow.json schema

**Files:**
- Modify: `schema/authoring/workflow.json`

- [ ] **Step 1: Add the property and bump the `$comment`**

Edit `schema/authoring/workflow.json`. Change line 4:

```json
"$comment": "Schema version 4.0 - Added trust_mode, data_mcps, payload_types (BL2/BL3/BL4); ending nodes live in nodes: (BL5).",
```

to:

```json
"$comment": "Schema version 4.1 - BL6: added optional top-level declared_effects block (effect envelope narrowing).",
```

Then, inside `#/properties`, insert the following property between `payload_types` (ends around line 42 with `}`) and `entry_preconditions`:

```json
    "declared_effects": {
      "type": "object",
      "description": "Optional per-alias effect envelope narrowing the inferred default from data_mcps (BL6). Keys are aliases declared in data_mcps (or unused aliases used as forbidden documentation). Values are either the string literal 'forbidden' or an object with optional 'tools' and 'max_call_count'. Cross-alias validation (tools subset, alias-in-data_mcps) is delegated to the consuming runtime.",
      "propertyNames": { "pattern": "^[a-z_][a-z0-9_-]*$" },
      "additionalProperties": {
        "oneOf": [
          { "const": "forbidden" },
          {
            "type": "object",
            "properties": {
              "tools": {
                "type": "array",
                "items": { "type": "string", "pattern": "^[a-z_][a-z0-9_]*$" },
                "uniqueItems": true,
                "description": "Allowed tool names on this alias. Subset of the data-MCP's published tools (runtime-checked)."
              },
              "max_call_count": {
                "type": "integer",
                "minimum": 0,
                "description": "Hard cap on invocations of this alias per workflow run (static upper bound)."
              }
            },
            "additionalProperties": true
          }
        ]
      }
    },
```

- [ ] **Step 2: Verify the schema is still valid JSON**

Run: `jq . schema/authoring/workflow.json > /dev/null`

Expected: no output, exit code `0`. (Any parse error prints a message.)

- [ ] **Step 3: Run validator to verify the positive fixture now PASSES**

Run: `bash scripts/validate-workflows.sh`

Expected: `OK    tests/fixtures/workflows/v8_declared_effects_narrow/input.yaml`. Positive count increases by one compared to Task 1's baseline; all previously-passing fixtures still pass. Exit code `0` (assuming no other failures).

- [ ] **Step 4: Commit the schema change**

```bash
git add schema/authoring/workflow.json
git commit -m "feat(bl6): add declared_effects property to workflow schema"
```

---

## Task 3: Add remaining positive fixtures

**Files:**
- Create: `tests/fixtures/workflows/v8_declared_effects_forbidden/input.yaml`
- Create: `tests/fixtures/workflows/v8_declared_effects_unknown_key/input.yaml`

- [ ] **Step 1: Create the `forbidden` fixture**

Create `tests/fixtures/workflows/v8_declared_effects_forbidden/input.yaml`:

```yaml
name: declared-effects-forbidden
version: "1.0.0"
description: Workflow explicitly forbidding two aliases — one declared in data_mcps, one documentation-only.

data_mcps:
  crm: "internal-crm@^2"

declared_effects:
  crm: forbidden
  shell: forbidden

start_node: done
default_error: done

nodes:
  done:
    type: ending
    outcome: success
    message: "Done."
```

- [ ] **Step 2: Create the `unknown_key` fixture**

Create `tests/fixtures/workflows/v8_declared_effects_unknown_key/input.yaml`:

```yaml
name: declared-effects-unknown-key
version: "1.0.0"
description: Forward-compat — unknown keys under an alias object are accepted (reserved for future vocabulary).

data_mcps:
  crm: "internal-crm@^2"

declared_effects:
  crm:
    tools: [search_customers]
    data_volume_cap_mb: 100
    time_window_sec: 60

start_node: done
default_error: done

nodes:
  done:
    type: ending
    outcome: success
    message: "Done."
```

- [ ] **Step 3: Run validator to verify both PASS**

Run: `bash scripts/validate-workflows.sh`

Expected: Both new fixtures appear as `OK`. Positive count increases by two. Exit code `0`.

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/workflows/v8_declared_effects_forbidden/input.yaml \
        tests/fixtures/workflows/v8_declared_effects_unknown_key/input.yaml
git commit -m "test(bl6): positive fixtures for forbidden literal and unknown-key forward-compat"
```

---

## Task 4: Add negative fixtures

**Files:**
- Create: `tests/fixtures/workflows/_negative/declared_effects_bad_value/input.yaml`
- Create: `tests/fixtures/workflows/_negative/declared_effects_bad_alias_name/input.yaml`
- Create: `tests/fixtures/workflows/_negative/declared_effects_negative_max_count/input.yaml`

- [ ] **Step 1: Create the bad-value fixture**

Create `tests/fixtures/workflows/_negative/declared_effects_bad_value/input.yaml`:

```yaml
# NEGATIVE: declared_effects value must be either "forbidden" string or an object.
name: bad-declared-effect-value
version: "1.0.0"
start_node: done
default_error: done

declared_effects:
  crm: true

nodes:
  done:
    type: ending
    outcome: success
```

- [ ] **Step 2: Create the bad-alias-name fixture**

Create `tests/fixtures/workflows/_negative/declared_effects_bad_alias_name/input.yaml`:

```yaml
# NEGATIVE: declared_effects alias names must match ^[a-z_][a-z0-9_-]*$ — 'CRM' is uppercase.
name: bad-declared-effect-alias
version: "1.0.0"
start_node: done
default_error: done

declared_effects:
  CRM:
    tools: [search_customers]

nodes:
  done:
    type: ending
    outcome: success
```

- [ ] **Step 3: Create the negative-max-count fixture**

Create `tests/fixtures/workflows/_negative/declared_effects_negative_max_count/input.yaml`:

```yaml
# NEGATIVE: max_call_count must be >= 0.
name: bad-declared-effect-max-count
version: "1.0.0"
start_node: done
default_error: done

data_mcps:
  crm: "internal-crm@^2"

declared_effects:
  crm:
    max_call_count: -1

nodes:
  done:
    type: ending
    outcome: success
```

- [ ] **Step 4: Run validator to verify all three are correctly rejected**

Run: `bash scripts/validate-workflows.sh`

Expected: Each of the three appears as `OK ... (correctly rejected)` in the negative section. Exit code `0`. Final summary line: "All workflow fixtures OK".

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/workflows/_negative/declared_effects_bad_value/input.yaml \
        tests/fixtures/workflows/_negative/declared_effects_bad_alias_name/input.yaml \
        tests/fixtures/workflows/_negative/declared_effects_negative_max_count/input.yaml
git commit -m "test(bl6): negative fixtures for bad value, bad alias name, negative max_call_count"
```

---

## Task 5: Add `## Declared Effects` section to `blueprint-types.md`

**Files:**
- Modify: `blueprint-types.md` (append a new top-level section immediately after `## Payload Types`, which ends around line 293)

- [ ] **Step 1: Add the new section**

Open `blueprint-types.md`. The existing `## Payload Types` section ends at line 293 (`- Blueprint-lib does NOT validate...runtime concern...`). Immediately after that line, add a blank line then the following new section:

```markdown

## Declared Effects

Optional workflow-level block narrowing the default inferred effect envelope
from `data_mcps`. Workflows that omit the block accept any tool exposed by any
declared alias, invoked arbitrarily many times. Authors who want fine-grained
control add a `declared_effects:` block at the top level of the workflow YAML.

Each key is an alias (same naming rules as `data_mcps`); each value is either:

| Value form | Meaning |
|---|---|
| `forbidden` | Explicit deny — alias MUST NOT be invoked from this workflow. Readable documentation even when the alias is absent from `data_mcps`. |
| `{ tools: [...] }` | Restrict to a subset of the MCP's tools. Unlisted tools are forbidden. |
| `{ tools: [...], max_call_count: N }` | As above, with a hard cap on total invocations of this alias across a workflow run. |
| `{ max_call_count: N }` | Cap invocations without narrowing the tool list. |

### Example

    data_mcps:
      crm:     "internal-crm@^2.1"
      billing: "stripe-mcp@~3"

    declared_effects:
      crm:
        tools: [search_customers, get_account]
      billing:
        tools: [create_invoice]
        max_call_count: 1
      shell: forbidden

### Load-time contract (enforced by downstream runtimes)

- Aliases that appear in `declared_effects` with an object value MUST also appear in `data_mcps`.
- Each entry in `tools` MUST be a tool exported by the aliased MCP server.
- `max_call_count` is interpreted as a static upper bound across all reachable paths through the workflow DAG.
- Unknown keys under an alias object are reserved for future vocabulary (data volume caps, time windows, resource classes) and are accepted today without effect.
- Blueprint-lib validates only the syntactic shape of the block; cross-alias and cross-server checks are the consuming runtime's concern.
```

- [ ] **Step 2: Verify no Markdown structure damage**

Run: `grep -n '^## ' blueprint-types.md`

Expected output includes (in order): `## Conventions`, `## Nodes`, `## Preconditions`, `## Consequences`, `## Payload Types`, `## Declared Effects`.

- [ ] **Step 3: Commit**

```bash
git add blueprint-types.md
git commit -m "docs(bl6): add '## Declared Effects' section to blueprint-types.md"
```

---

## Task 6: Extend `## 4. MCP-Delegated Query` example in `examples.md`

**Files:**
- Modify: `examples.md:573-584` (update the "New in v8" note and add a `declared_effects:` block to the embedded YAML)

- [ ] **Step 1: Update the "New in v8" hint and add the block**

Open `examples.md`. Find the section starting at line 566. Replace the single line at 573:

```markdown
**New in v8:** workflow-level `trust_mode`, `data_mcps`, `payload_types`.
```

with:

```markdown
**New in v8:** workflow-level `trust_mode`, `data_mcps`, `payload_types`, `declared_effects`.
```

Then, inside the YAML code fence that starts at line 575, insert a `declared_effects:` block directly after the `data_mcps:` block. The existing `data_mcps:` block is:

```yaml
data_mcps:
  eightball: "eightball-tools@^1"
```

Change the sequence from `data_mcps → payload_types` to `data_mcps → declared_effects → payload_types`. The inserted block (and one trailing blank line) is:

```yaml
declared_effects:
  eightball:
    tools: [shake]
    max_call_count: 1
```

The surrounding YAML becomes:

```yaml
data_mcps:
  eightball: "eightball-tools@^1"

declared_effects:
  eightball:
    tools: [shake]
    max_call_count: 1

payload_types:
  shake_params@1:
    question: string (min_length=1)
    context:  string (optional)
```

- [ ] **Step 2: Verify example YAML still parses**

Run: `awk '/^````yaml$/,/^````$/' examples.md | sed '1d;$d' | yq -o=json '.' > /dev/null`

Expected: no output, exit code `0`. (Only the first fenced YAML block is extracted; if the file has multiple, this check only covers the first. The §4 example is the last, so for full coverage run the extraction per section manually or rely on `validate-workflows.sh` for fixture coverage. The schema-level check happens in Task 7.)

If the command above does not target §4, use this targeted extraction instead:

```bash
sed -n '/^## 4. MCP-Delegated Query/,$p' examples.md | awk '/^````yaml$/,/^````$/' | sed '1d;$d' | yq -o=json '.' > /dev/null
```

Expected: no output, exit code `0`.

- [ ] **Step 3: Commit**

```bash
git add examples.md
git commit -m "docs(bl6): extend MCP-Delegated Query example with declared_effects"
```

---

## Task 7: Bump version and add CHANGELOG entry

**Files:**
- Modify: `package.yaml:5` (version) and `package.yaml:23` (schemas.workflow)
- Modify: `CHANGELOG.md` (insert new entry at the top)

- [ ] **Step 1: Bump version in `package.yaml`**

Edit `package.yaml`. Change line 5:

```yaml
version: "8.0.0"
```

to:

```yaml
version: "8.1.0"
```

And change line 23:

```yaml
  workflow: "4.0"
```

to:

```yaml
  workflow: "4.1"
```

Stats lines (27-33) remain unchanged — BL6 adds no new types.

- [ ] **Step 2: Verify `package.yaml` still parses**

Run: `yq -o=json '.' package.yaml > /dev/null`

Expected: no output, exit code `0`.

- [ ] **Step 3: Insert the `[8.1.0]` changelog entry**

Open `CHANGELOG.md`. Locate the line `## [8.0.0] - 2026-04-17`. Insert the following block immediately before it (leaving the `[8.0.0]` section intact):

```markdown
## [8.1.0] - 2026-04-17

### Added
- `declared_effects:` optional workflow-level block (BL6). Per-alias narrowing of the default inferred effect envelope from `data_mcps`. Each alias value is either the string literal `forbidden` or an object with optional `tools: [...]` and `max_call_count: N`. Unknown keys under the alias object are reserved for future vocabulary and accepted today without effect. Cross-alias validation (tools subset, alias ∈ `data_mcps`) is delegated to the consuming runtime.
- New `## Declared Effects` top-level section in `blueprint-types.md`.
- Fixtures: `tests/fixtures/workflows/v8_declared_effects_{narrow,forbidden,unknown_key}/` (positive); `tests/fixtures/workflows/_negative/declared_effects_{bad_value,bad_alias_name,negative_max_count}/` (negative).

### Changed
- `schema/authoring/workflow.json` bumped to schema version 4.1 (purely additive — omitting the new block preserves 8.0.0 behavior exactly).
- `examples.md` example §4 (`MCP-Delegated Query`) extended with a `declared_effects:` block.

### Cross-repo sync
- `hiivmind-blueprint/lib/patterns/authoring-guide.md` documents the new block.
- `hiivmind-blueprint/lib/patterns/execution-guide.md` notes that load-time envelope enforcement is the consuming runtime's responsibility.

### Migration
- None. v8.0.0 workflows remain valid under v8.1.0 unchanged.

```

- [ ] **Step 4: Commit**

```bash
git add package.yaml CHANGELOG.md
git commit -m "chore(bl6): bump version to 8.1.0 and document in CHANGELOG"
```

---

## Task 8: Cross-repo sync — `hiivmind-blueprint` pattern guides

**Files:**
- Modify: `../hiivmind-blueprint/lib/patterns/authoring-guide.md` (append new subsection in the "Workflow-level declarations (v8)" area, around line 557-575)
- Modify: `../hiivmind-blueprint/lib/patterns/execution-guide.md` (append one-paragraph note near the `mcp_tool_call` execution section, around line 396-412)

- [ ] **Step 1: Add authoring subsection to `authoring-guide.md`**

Open `../hiivmind-blueprint/lib/patterns/authoring-guide.md`. Locate line 563:

```markdown
- **`payload_types`** (BL2) — see Payload Types section above.
```

Insert this new bullet immediately after it:

```markdown
- **`declared_effects`** (BL6, v8.1+) — optional per-alias effect envelope narrowing. Each alias maps to either the string literal `forbidden` or an object with optional `tools: [...]` and `max_call_count: N`. Cross-alias enforcement (tools-subset, alias-declared-in-`data_mcps`) is the consuming runtime's job; blueprint-lib validates only the syntactic shape.
```

Then, after the existing "Example front-matter" block (which ends at line 575 with ` }`), insert a new `####` heading and an extended example:

```markdown

#### Narrowing the effect envelope (`declared_effects`)

Workflows that declare `data_mcps` accept any exported tool on any declared
alias by default. To narrow that envelope — useful for sensitive workflows or
for producing a machine-readable "effect manifest" — add a `declared_effects:`
block:

```yaml
data_mcps:
  crm:     "internal-crm@^2.1"
  billing: "stripe-mcp@~3"

declared_effects:
  crm:
    tools: [search_customers, get_account]   # read-only subset
  billing:
    tools: [create_invoice]
    max_call_count: 1                        # hard cap across workflow run
  shell: forbidden                           # explicit deny (documentation)
```

Over-declaration (listing tools the workflow never calls) is a warning from the
consuming runtime, not an error — authors can narrow progressively during
hardening.
```

- [ ] **Step 2: Add execution note to `execution-guide.md`**

Open `../hiivmind-blueprint/lib/patterns/execution-guide.md`. Locate the `### Executing mcp_tool_call consequences` section (around line 396). After that section's last paragraph (before the next `###` heading), add:

```markdown

#### Effect-envelope enforcement

Workflows may declare an explicit `declared_effects:` block (BL6, v8.1+) to
narrow the default envelope inferred from `data_mcps`. Enforcement is a
load-time static check, the consuming runtime's responsibility:

- Reject any `mcp_tool_call` whose `tool` is not in the narrowed allowlist
  (`tool_outside_envelope`).
- Reject workflows whose reachable invocation count for an alias exceeds a
  declared `max_call_count` (`count_exceeds_envelope`).
- Warn on over-declaration (declared tools never invoked); not an error.

Blueprint-lib validates only the block's syntactic shape. `declared_effects`
narrows the envelope but does not widen it — cross-referencing against the
aliased MCP server's published tools happens at the runtime boundary.
```

- [ ] **Step 3: Commit in the blueprint repo**

```bash
cd ../hiivmind-blueprint
git checkout -b sync/bl6-declared-effects
git add lib/patterns/authoring-guide.md lib/patterns/execution-guide.md
git commit -m "docs(bl6): document declared_effects block in authoring + execution guides

Cross-repo sync for hiivmind-blueprint-lib v8.1.0 BL6 addition. Authoring
guide gets a new declared_effects subsection under 'Workflow-level
declarations (v8)'; execution guide gets an 'Effect-envelope enforcement'
subsection under the mcp_tool_call executor notes.

Cross-ref: hiivmind-blueprint-lib spec
docs/superpowers/specs/2026-04-17-bl6-declared-effects-design.md"
cd ../hiivmind-blueprint-lib
```

(The blueprint repo PR is opened separately after the lib PR merges and tags v8.1.0.)

---

## Self-review results

**1. Spec coverage:**
- Schema property addition → Task 2 ✓
- Schema shape with three value forms + `additionalProperties: true` on alias object → Task 2 ✓
- Catalog entry (`## Declared Effects` new top-level section) → Task 5 ✓
- `examples.md` §4 extension → Task 6 ✓
- CHANGELOG entry → Task 7 ✓
- package.yaml version bump → Task 7 ✓
- 3 positive fixtures → Tasks 1 + 3 ✓
- 3 negative fixtures → Task 4 ✓
- Cross-repo sync (authoring + execution guides) → Task 8 ✓
- `$comment` schema-version bump → Task 2 ✓

No gaps.

**2. Placeholder scan:** No TBDs, TODOs, "add appropriate X", "handle edge cases", or "similar to Task N" references. Every step has concrete code, paths, and commands.

**3. Type consistency:**
- Property name `declared_effects` — consistent across schema, catalog, example, CHANGELOG, authoring guide, execution guide, all fixtures.
- Value-form enumeration — `forbidden` literal + `{tools}` / `{tools, max_call_count}` / `{max_call_count}` — consistent across Task 2 schema, Task 5 catalog, Task 7 CHANGELOG, Task 8 authoring guide.
- Alias naming pattern `^[a-z_][a-z0-9_-]*$` — present in Task 2 schema, referenced in Task 5 catalog ("same naming rules as `data_mcps`"), asserted by Task 4's `bad_alias_name` fixture.
- Tool naming pattern `^[a-z_][a-z0-9_]*$` — present in Task 2 schema only; fixtures use conforming names.

---

## Execution notes

- `scripts/validate-workflows.sh` requires `npx` and `yq`; first run may download `ajv-cli@5` (a few seconds) via `npx --yes`. Pre-warm by running the validator once before dispatching implementer subagents if network latency is a concern.
- Commits 1–7 run in blueprint-lib on `feat/bl6-declared-effects`. Commit 8 runs in `../hiivmind-blueprint` on a new branch `sync/bl6-declared-effects`. Both branches open independent PRs; lib PR merges first and tags v8.1.0, blueprint PR follows.
- After the lib PR merges and v8.1.0 is tagged, open a small follow-up commit in `hiivmind-blueprint-central` flipping BL6's `Status: PROPOSED` to `SHIPPED` in the S1 addendum (lines 290 and 352–357). Not included in this plan; listed under "Sequencing" step 3 of the spec.
