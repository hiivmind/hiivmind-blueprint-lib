# Composite Nodes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add composite node catalog + schema support (`confirm`, `gated_action`) to `hiivmind-blueprint-lib`, plus fixture corpus for downstream walker implementations to test against. No Python, no runtime code — `hiivmind-blueprint-lib` stays catalog + schemas only.

**Architecture:** Composites are authoring-time syntactic sugar documented in a new `blueprint-composites.md` (separate from `blueprint-types.md`, which stays runtime-facing). `schema/authoring/node-types.json` gains two new node-type sub-schemas and composite names in its `type` enum. Fixture pairs under `tests/fixtures/composites/` define the walker-expansion contract. A shell script + GitHub Action validates fixtures against the schema using `ajv-cli` via `npx` (no persistent Node/Python deps).

**Tech Stack:** Markdown (catalog docs), JSON Schema Draft 2020-12 (validation), YAML (fixtures and authored workflows), bash + `ajv-cli` (via `npx`, no install) + `yq` (already present) for validation, GitHub Actions.

**Branch:** `feat/composite-nodes` in `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib`. Already exists with spec doc committed.

**Reference spec:** `docs/superpowers/specs/2026-04-14-composite-nodes-design.md`

**Related principles (already committed on branch `principle/composite-primitive-canary` in sibling repo `hiivmind-blueprint-central`, DO NOT modify):**
- `02.principles/c.type-system/composite-primitive-canary.md`
- `02.principles/g.trust-governance/confirmations-as-explicit-state.md`

---

## File Structure

**New files (created in this plan):**
- `blueprint-composites.md` — authoring-time composite catalog
- `scripts/validate-fixtures.sh` — schema validation driver
- `.github/workflows/validate-fixtures.yaml` — CI workflow
- `tests/fixtures/composites/confirm/minimal/input.yaml` — call site
- `tests/fixtures/composites/confirm/minimal/expected.yaml` — walker-expansion contract
- `tests/fixtures/composites/confirm/with_consequences/input.yaml`
- `tests/fixtures/composites/confirm/with_consequences/expected.yaml`
- `tests/fixtures/composites/confirm/custom_labels/input.yaml`
- `tests/fixtures/composites/confirm/custom_labels/expected.yaml`
- `tests/fixtures/composites/gated_action/basic/input.yaml`
- `tests/fixtures/composites/gated_action/basic/expected.yaml`
- `tests/fixtures/composites/gated_action/with_consequences/input.yaml`
- `tests/fixtures/composites/gated_action/with_consequences/expected.yaml`
- `tests/fixtures/composites/gated_action/default_on_unknown/input.yaml`
- `tests/fixtures/composites/gated_action/default_on_unknown/expected.yaml`
- `tests/fixtures/composites/_negative/confirm_missing_store_as/input.yaml`
- `tests/fixtures/composites/_negative/confirm_missing_store_as/reason.md`
- `tests/fixtures/composites/_negative/gated_action_missing_else/input.yaml`
- `tests/fixtures/composites/_negative/gated_action_missing_else/reason.md`
- `tests/fixtures/composites/_negative/gated_action_empty_when/input.yaml`
- `tests/fixtures/composites/_negative/gated_action_empty_when/reason.md`
- `tests/fixtures/composites/README.md` — explains fixture layout

**Modified files:**
- `schema/authoring/node-types.json` — add composite sub-schemas and type-enum entries; bump `$comment` to Schema version 3.1
- `package.yaml` — bump version to 7.1.0; update `stats.node_types` count
- `CHANGELOG.md` — add 7.1.0 entry
- `README.md` — mention `blueprint-composites.md`
- `CLAUDE.md` — composite authoring note; walker pointer

**Not touched (belong to future work):**
- Any Python — none in this plan
- `hiivmind-blueprint-mcp` — separate future repo, separate spec, walker implementation
- Principles in `hiivmind-blueprint-central` — already committed

---

## Task 1: Scaffold fixture directory and validation script

**Files:**
- Create: `tests/fixtures/composites/README.md`
- Create: `scripts/validate-fixtures.sh`

This task lands the infrastructure — an empty fixture tree, a validation runner, and a README that documents the layout. Subsequent tasks add schema changes, then populate fixtures. We build the validator FIRST so each later task can verify its fixture against the evolving schema.

- [ ] **Step 1: Create the fixtures directory tree**

Run:
```bash
mkdir -p tests/fixtures/composites/_negative
```

- [ ] **Step 2: Write the fixtures README**

Create `tests/fixtures/composites/README.md`:

````markdown
# Composite Fixtures

Test fixtures for composite node types. Each composite (`confirm`, `gated_action`) has a directory with one or more case subdirectories. Each case contains an `input.yaml` (composite call site) and an `expected.yaml` (walker-expansion contract — the primitive subgraph a correct walker MUST emit).

## Layout

```
tests/fixtures/composites/
├── confirm/
│   └── <case_name>/
│       ├── input.yaml       # composite call site — validates against authoring schema
│       └── expected.yaml    # walker expansion — also validates against authoring schema
├── gated_action/
│   └── <case_name>/
│       ├── input.yaml
│       └── expected.yaml
└── _negative/
    └── <case_name>/
        ├── input.yaml       # schema-invalid call site — MUST fail validation
        └── reason.md        # human-readable explanation of what's wrong
```

## Validation

`scripts/validate-fixtures.sh` validates every `input.yaml` and `expected.yaml` against `schema/authoring/node-types.json`. Positive fixtures (outside `_negative/`) must pass; negative fixtures must fail. CI runs this on every PR.

## Walker parity

The **input → expected** relationship is NOT tested in this repo — `hiivmind-blueprint-lib` has no walker. That relationship is tested by `hiivmind-blueprint-mcp`'s Python and TypeScript walker implementations, which consume this fixture corpus as their authoritative contract. Both walkers must produce `expected.yaml` bit-for-bit from the corresponding `input.yaml`.

## Adding a fixture

1. Pick the composite directory (or `_negative/` for schema-failure cases).
2. Create a case subdirectory with a descriptive name (`minimal`, `with_consequences`, `default_on_unknown`, etc.).
3. Add `input.yaml` (and `expected.yaml` for positive cases, `reason.md` for negative cases).
4. Run `scripts/validate-fixtures.sh`. Positive cases should validate; negative cases should fail.
5. Commit.
````

- [ ] **Step 3: Write the validator script**

Create `scripts/validate-fixtures.sh`:

```bash
#!/usr/bin/env bash
#
# validate-fixtures.sh — Validate composite fixtures against authoring schema.
#
# Requirements:
#   - yq     (already required by the repo; parses YAML)
#   - npx    (bundled with Node.js; runs ajv-cli without persistent install)
#
# Exit codes:
#   0 — all positive fixtures validate; all negative fixtures fail as expected
#   1 — a positive fixture failed schema validation
#   2 — a negative fixture unexpectedly passed validation
#   3 — tool missing (yq or npx)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures/composites"
SCHEMA_NODE="$REPO_ROOT/schema/authoring/node-types.json"
SCHEMA_COMMON="$REPO_ROOT/schema/common.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

command -v yq  >/dev/null 2>&1 || { echo -e "${RED}yq not found${NC}"; exit 3; }
command -v npx >/dev/null 2>&1 || { echo -e "${RED}npx not found (install Node.js)${NC}"; exit 3; }

POS_PASS=0
POS_FAIL=0
NEG_PASS=0
NEG_FAIL=0

validate_file() {
    local yaml_file="$1"
    local expect_pass="$2"  # "true" for positive, "false" for negative
    local json_file="$TMP_DIR/$(basename "$yaml_file" .yaml).json"

    # Wrap the fixture in the node-reference shape the schema defs/node expects.
    # Each input.yaml/expected.yaml is a map of node_id -> node_dict.
    # We validate EACH node in the map individually against #/$defs/node.
    yq -o=json '.' "$yaml_file" > "$json_file"

    # Iterate over each top-level key (node_id); validate its value against node def.
    local node_ids
    node_ids="$(yq -r 'keys | .[]' "$yaml_file")"

    local any_fail=false
    for node_id in $node_ids; do
        local node_json="$TMP_DIR/${node_id}.json"
        yq -o=json ".\"$node_id\"" "$yaml_file" > "$node_json"

        if npx --yes ajv-cli@5 validate \
            -s "$SCHEMA_NODE#/\$defs/node" \
            -r "$SCHEMA_COMMON" \
            -d "$node_json" \
            --strict=false \
            > "$TMP_DIR/ajv.log" 2>&1; then
            :
        else
            any_fail=true
            if [[ "$expect_pass" == "true" ]]; then
                echo -e "${RED}FAIL${NC}  $yaml_file (node: $node_id)"
                cat "$TMP_DIR/ajv.log"
            fi
        fi
    done

    if [[ "$expect_pass" == "true" ]]; then
        if [[ "$any_fail" == "false" ]]; then
            echo -e "${GREEN}OK${NC}    $yaml_file"
            POS_PASS=$((POS_PASS + 1))
        else
            POS_FAIL=$((POS_FAIL + 1))
        fi
    else
        if [[ "$any_fail" == "true" ]]; then
            echo -e "${GREEN}OK${NC}    $yaml_file (correctly rejected)"
            NEG_PASS=$((NEG_PASS + 1))
        else
            echo -e "${YELLOW}UNEXPECTED PASS${NC}  $yaml_file (should have failed)"
            NEG_FAIL=$((NEG_FAIL + 1))
        fi
    fi
}

echo "=== Positive fixtures (must pass) ==="
while IFS= read -r -d '' f; do
    validate_file "$f" "true"
done < <(find "$FIXTURES_DIR" -type f \( -name 'input.yaml' -o -name 'expected.yaml' \) -not -path '*/_negative/*' -print0)

echo ""
echo "=== Negative fixtures (must fail) ==="
while IFS= read -r -d '' f; do
    validate_file "$f" "false"
done < <(find "$FIXTURES_DIR/_negative" -type f -name 'input.yaml' -print0 2>/dev/null || true)

echo ""
echo "=== Summary ==="
echo "Positive: $POS_PASS passed, $POS_FAIL failed"
echo "Negative: $NEG_PASS correctly rejected, $NEG_FAIL unexpectedly passed"

if [[ $POS_FAIL -gt 0 ]]; then exit 1; fi
if [[ $NEG_FAIL -gt 0 ]]; then exit 2; fi
echo -e "${GREEN}All fixtures OK${NC}"
```

- [ ] **Step 4: Make script executable and run once to verify it handles an empty fixture tree cleanly**

Run:
```bash
chmod +x scripts/validate-fixtures.sh
./scripts/validate-fixtures.sh
```

Expected output:
```
=== Positive fixtures (must pass) ===

=== Negative fixtures (must fail) ===

=== Summary ===
Positive: 0 passed, 0 failed
Negative: 0 correctly rejected, 0 unexpectedly passed
All fixtures OK
```
Exit code: 0. (No fixtures exist yet; script handles the empty case without erroring.)

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/composites/README.md scripts/validate-fixtures.sh
git commit -m "$(cat <<'EOF'
test: scaffold composite fixtures directory and validator script

Fixtures will live at tests/fixtures/composites/<composite>/<case>/ with
input.yaml and expected.yaml pairs. _negative/ subdirectory holds
schema-failure cases.

validate-fixtures.sh uses yq + ajv-cli (via npx, no persistent install)
to validate every fixture's nodes against schema/authoring/node-types.json.
Positive fixtures must validate; negative fixtures must fail.

Walker-expansion-equivalence (input → expected) is NOT tested here — that
belongs to hiivmind-blueprint-mcp. This repo only checks that each
fixture individually conforms to the authoring schema.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add composite type names to the node-type enum

**Files:**
- Modify: `schema/authoring/node-types.json:12-16` (the `type` enum inside `#/$defs/node`)

The enum currently lists `"action"`, `"conditional"`, `"user_prompt"`. Add `"confirm"` and `"gated_action"`. This is the minimum schema change that lets `type: confirm` and `type: gated_action` parse as valid node kinds — full validation of their specific fields comes in Tasks 3-4.

- [ ] **Step 1: Add a negative fixture that should currently pass (will fail after Task 4)**

Create `tests/fixtures/composites/_negative/confirm_unknown_pre_task2/input.yaml`:
```yaml
# Placeholder: before Task 2, 'type: confirm' isn't in the enum at all.
# This fixture exists only to prove the task 2 enum change takes effect.
# It will be deleted at the end of this task.
destroy_branch:
  type: confirm
  prompt: "Delete the branch?"
  store_as: confirmations.delete_x
  on_confirmed: { next_node: do_delete }
  on_declined:  { next_node: cancelled }
```

Create `tests/fixtures/composites/_negative/confirm_unknown_pre_task2/reason.md`:
```markdown
TEMPORARY fixture — `type: confirm` was not yet in the enum before Task 2 of
the composite nodes plan. This fixture was used to verify Task 2 took effect
(it passed as a negative case before Task 2, failed after). It is deleted at
the end of Task 2.
```

- [ ] **Step 2: Run validator; confirm the temp negative fixture correctly fails (since `confirm` isn't in the enum yet)**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected: the `confirm_unknown_pre_task2` case appears under negatives and is "correctly rejected" (because `type: confirm` isn't a recognized enum value yet).

- [ ] **Step 3: Update the type enum in node-types.json**

Modify `schema/authoring/node-types.json` lines 12-16:

OLD:
```json
        "type": {
          "type": "string",
          "enum": ["action", "conditional", "user_prompt"],
          "description": "Node type"
        },
```

NEW:
```json
        "type": {
          "type": "string",
          "enum": ["action", "conditional", "user_prompt", "confirm", "gated_action"],
          "description": "Node type (primitive: action/conditional/user_prompt; composite: confirm/gated_action)"
        },
```

- [ ] **Step 4: Run validator; confirm the temp negative fixture now passes validation (schema accepts `type: confirm`)**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected: `confirm_unknown_pre_task2` appears under negatives and is now "unexpectedly passed" — script exits with code 2. This is the intended signal that the enum change took effect.

- [ ] **Step 5: Delete the temporary negative fixture**

Run:
```bash
rm -rf tests/fixtures/composites/_negative/confirm_unknown_pre_task2
```

- [ ] **Step 6: Run validator; confirm clean exit**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected output:
```
=== Positive fixtures (must pass) ===

=== Negative fixtures (must fail) ===

=== Summary ===
Positive: 0 passed, 0 failed
Negative: 0 correctly rejected, 0 unexpectedly passed
All fixtures OK
```

- [ ] **Step 7: Commit**

```bash
git add schema/authoring/node-types.json
git commit -m "$(cat <<'EOF'
schema: add confirm and gated_action to node-type enum

First half of composite node schema support: extends the type enum in
node-types.json so 'type: confirm' and 'type: gated_action' parse as
valid node kinds. Field-level validation lands in the next commits
(confirm_node, gated_action_node $defs, and allOf dispatch).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `confirm_node` $def to the schema

**Files:**
- Modify: `schema/authoring/node-types.json` — add new `$defs` entry `confirm_node` plus a new `allOf` branch under `#/$defs/node`

The `confirm` composite requires `prompt`, `store_as`, `on_confirmed`, `on_declined`; accepts optional `header`. `on_confirmed` has `next_node` required + optional `consequences` and `label`. `on_declined` has `next_node` required + optional `label`.

- [ ] **Step 1: Write the positive fixture `confirm/minimal/input.yaml`**

Create `tests/fixtures/composites/confirm/minimal/input.yaml`:
```yaml
destroy_branch:
  type: confirm
  prompt: "Delete the branch '${branch_name}'?"
  store_as: confirmations.delete_branch_x
  on_confirmed:
    next_node: branch_gone
  on_declined:
    next_node: cancelled
```

Create `tests/fixtures/composites/confirm/minimal/expected.yaml` (walker expansion — 2 nodes because `on_confirmed.consequences` is absent, so no intermediate `__act` node is needed):
```yaml
destroy_branch__ask:
  type: user_prompt
  prompt:
    question: "Delete the branch '${branch_name}'?"
    header: "CONFIRM"
    options:
      - { id: "yes", label: "Yes" }
      - { id: "no",  label: "No"  }
  on_response:
    "yes":
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.delete_branch_x
          value: true
      next_node: destroy_branch__gate
    "no":
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.delete_branch_x
          value: false
      next_node: destroy_branch__gate

destroy_branch__gate:
  type: conditional
  condition: "confirmations.delete_branch_x == true"
  on_true: branch_gone
  on_false: cancelled
```

- [ ] **Step 2: Write the negative fixture `_negative/confirm_missing_store_as`**

Create `tests/fixtures/composites/_negative/confirm_missing_store_as/input.yaml`:
```yaml
destroy_branch:
  type: confirm
  prompt: "Delete the branch?"
  # store_as intentionally omitted — must fail validation
  on_confirmed:
    next_node: do_delete
  on_declined:
    next_node: cancelled
```

Create `tests/fixtures/composites/_negative/confirm_missing_store_as/reason.md`:
```markdown
`confirm` requires `store_as`. The `confirmations-as-explicit-state` principle
requires every confirmation to leave explicit named state evidence —
`store_as` IS that contract. Schema must reject calls that omit it.
```

- [ ] **Step 3: Run the validator; confirm the positive fixture FAILS (because `confirm_node` $def doesn't exist yet — the generic `node` schema passes `type: confirm` after Task 2 but doesn't enforce the required fields)**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected: both the positive AND the negative fixtures pass schema validation (neither fails), because today's schema has no shape check for `confirm`. The positive case passes as expected (exit-code-wise not a failure); the negative case **unexpectedly passes** — script exits 2. This is the failing-test signal: we need the `confirm_node` $def.

- [ ] **Step 4: Add `confirm_node` $def and wire it into the `allOf` dispatch**

Modify `schema/authoring/node-types.json`.

Inside `#/$defs/node`, extend the `allOf` array (currently has three branches for action/conditional/user_prompt). Add a fourth:

OLD (the closing bracket of the `allOf` array inside `#/$defs/node`):
```json
        {
          "if": { "properties": { "type": { "const": "user_prompt" } } },
          "then": { "$ref": "#/$defs/user_prompt_node" }
        }
      ]
    },
```

NEW:
```json
        {
          "if": { "properties": { "type": { "const": "user_prompt" } } },
          "then": { "$ref": "#/$defs/user_prompt_node" }
        },
        {
          "if": { "properties": { "type": { "const": "confirm" } } },
          "then": { "$ref": "#/$defs/confirm_node" }
        }
      ]
    },
```

Then add a new entry under `$defs` (place it AFTER `user_prompt_node` and BEFORE `prompt`):

```json
    "confirm_node": {
      "type": "object",
      "description": "Confirmation composite — yes/no prompt with structural state gating. Expands to user_prompt → mutate_state → conditional → (optional action). See principle: confirmations-as-explicit-state.",
      "required": ["prompt", "store_as", "on_confirmed", "on_declined"],
      "properties": {
        "type": { "const": "confirm" },
        "description": { "type": "string" },
        "prompt": {
          "type": "string",
          "description": "Question to ask the user"
        },
        "header": {
          "type": "string",
          "maxLength": 12,
          "default": "CONFIRM",
          "description": "Short header/tag (max 12 chars). Defaults to CONFIRM if omitted."
        },
        "store_as": {
          "$ref": "../common.json#/$defs/state_path",
          "description": "Dot-notation state field to hold the boolean decision (convention: confirmations.<name>). REQUIRED — the confirm composite always writes this field true|false before routing."
        },
        "on_confirmed": {
          "type": "object",
          "required": ["next_node"],
          "properties": {
            "label": {
              "type": "string",
              "default": "Yes",
              "description": "Label for the yes option. Defaults to 'Yes'."
            },
            "consequences": {
              "type": "array",
              "items": { "$ref": "#/$defs/consequence" },
              "description": "Optional consequences to run AFTER the conditional gate, before routing to next_node."
            },
            "next_node": {
              "$ref": "../common.json#/$defs/node_reference",
              "description": "Node to transition to when the user confirms."
            }
          },
          "additionalProperties": false
        },
        "on_declined": {
          "type": "object",
          "required": ["next_node"],
          "properties": {
            "label": {
              "type": "string",
              "default": "No",
              "description": "Label for the no option. Defaults to 'No'."
            },
            "next_node": {
              "$ref": "../common.json#/$defs/node_reference",
              "description": "Node to transition to when the user declines."
            }
          },
          "additionalProperties": false
        }
      },
      "additionalProperties": false
    },
```

- [ ] **Step 5: Run the validator; confirm the positive case passes AND the negative case is correctly rejected**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected output (abbreviated):
```
=== Positive fixtures (must pass) ===
OK    tests/fixtures/composites/confirm/minimal/input.yaml
OK    tests/fixtures/composites/confirm/minimal/expected.yaml

=== Negative fixtures (must fail) ===
OK    tests/fixtures/composites/_negative/confirm_missing_store_as/input.yaml (correctly rejected)

=== Summary ===
Positive: 2 passed, 0 failed
Negative: 1 correctly rejected, 0 unexpectedly passed
All fixtures OK
```
Exit 0.

- [ ] **Step 6: Commit**

```bash
git add schema/authoring/node-types.json tests/fixtures/composites/
git commit -m "$(cat <<'EOF'
schema: add confirm_node $def with confirmations-as-explicit-state invariant

confirm_node requires prompt, store_as, on_confirmed, on_declined.
on_confirmed supports optional consequences (ran after the conditional
gate, per the confirmations-as-explicit-state principle — consequences
are gated structurally, not via the prompt handler directly).

First fixtures land: confirm/minimal (positive) and _negative/
confirm_missing_store_as. Schema now correctly rejects confirm
calls without store_as.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add `gated_action_node` $def to the schema

**Files:**
- Modify: `schema/authoring/node-types.json` — add `gated_action_node` $def + allOf dispatch branch

`gated_action` requires `when` (minItems 1) and `else`. Each `when[]` item has `condition` + `next_node` required, `consequences` optional. `on_unknown` is optional (defaults to workflow `default_error`).

- [ ] **Step 1: Write positive fixture `gated_action/basic/input.yaml`**

Create `tests/fixtures/composites/gated_action/basic/input.yaml`:
```yaml
review_decision:
  type: gated_action
  when:
    - condition: "flags.status == 'approved'"
      next_node: publish
    - condition: "flags.status == 'rejected'"
      next_node: notify_author
  else: needs_review
  on_unknown: halt_for_audit
```

Create `tests/fixtures/composites/gated_action/basic/expected.yaml`:
```yaml
review_decision__case_0:
  type: conditional
  condition: "flags.status == 'approved'"
  on_true: publish
  on_false: review_decision__case_1
  on_unknown: halt_for_audit

review_decision__case_1:
  type: conditional
  condition: "flags.status == 'rejected'"
  on_true: notify_author
  on_false: needs_review
  on_unknown: halt_for_audit
```

- [ ] **Step 2: Write negative fixture `_negative/gated_action_missing_else`**

Create `tests/fixtures/composites/_negative/gated_action_missing_else/input.yaml`:
```yaml
review_decision:
  type: gated_action
  when:
    - condition: "flags.status == 'approved'"
      next_node: publish
  # else intentionally omitted — must fail validation
  on_unknown: halt_for_audit
```

Create `tests/fixtures/composites/_negative/gated_action_missing_else/reason.md`:
```markdown
`gated_action` requires `else`. No silent fall-through — the composite must
state explicitly what happens when no `when` clause matches. Schema rejects
omission.
```

- [ ] **Step 3: Write negative fixture `_negative/gated_action_empty_when`**

Create `tests/fixtures/composites/_negative/gated_action_empty_when/input.yaml`:
```yaml
review_decision:
  type: gated_action
  when: []   # empty — must fail validation (minItems 1)
  else: needs_review
```

Create `tests/fixtures/composites/_negative/gated_action_empty_when/reason.md`:
```markdown
`gated_action.when` must have at least one entry. An empty CASE/WHEN has no
meaning — authors should just route to `else` directly if they have no
conditions. Schema requires minItems: 1.
```

- [ ] **Step 4: Run validator; expect both negatives to unexpectedly pass (because `gated_action_node` doesn't exist yet)**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected: both negative fixtures unexpectedly pass (exit code 2). Positive fixture passes as expected. This is the failing-test signal: we need `gated_action_node`.

- [ ] **Step 5: Add `gated_action_node` $def and wire `allOf` dispatch**

Modify `schema/authoring/node-types.json`.

Extend the `allOf` array inside `#/$defs/node`:

OLD (after the confirm branch added in Task 3):
```json
        {
          "if": { "properties": { "type": { "const": "confirm" } } },
          "then": { "$ref": "#/$defs/confirm_node" }
        }
      ]
    },
```

NEW:
```json
        {
          "if": { "properties": { "type": { "const": "confirm" } } },
          "then": { "$ref": "#/$defs/confirm_node" }
        },
        {
          "if": { "properties": { "type": { "const": "gated_action" } } },
          "then": { "$ref": "#/$defs/gated_action_node" }
        }
      ]
    },
```

Add a new entry under `$defs` (place it AFTER `confirm_node`, BEFORE `prompt`):

```json
    "gated_action_node": {
      "type": "object",
      "description": "Multi-way CASE/WHEN dispatch composite. First-match-wins over an ordered list of conditions, each with optional consequences and a routing target. Expands to a chain of conditional nodes, each optionally followed by an action.",
      "required": ["when", "else"],
      "properties": {
        "type": { "const": "gated_action" },
        "description": { "type": "string" },
        "when": {
          "type": "array",
          "minItems": 1,
          "items": {
            "type": "object",
            "required": ["condition", "next_node"],
            "properties": {
              "condition": {
                "oneOf": [
                  { "type": "string" },
                  { "type": "object" }
                ],
                "description": "Condition to evaluate. Same polymorphism as conditional nodes: string = evaluate_expression shorthand; object with all/any/none/xor key = composite shorthand; object with type key = canonical precondition."
              },
              "consequences": {
                "type": "array",
                "items": { "$ref": "#/$defs/consequence" },
                "description": "Optional consequences to run when this branch is taken, before routing to next_node."
              },
              "next_node": {
                "$ref": "../common.json#/$defs/node_reference",
                "description": "Node to transition to when this condition matches."
              }
            },
            "additionalProperties": false
          }
        },
        "else": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Fallthrough destination when no when-clause matches. Required — no silent fall-through."
        },
        "on_unknown": {
          "$ref": "../common.json#/$defs/node_reference",
          "description": "Destination when any condition returns unknown (3VL short-circuit). Optional — defaults to workflow default_error."
        }
      },
      "additionalProperties": false
    },
```

- [ ] **Step 6: Run validator; confirm positives pass and negatives are correctly rejected**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected (abbreviated):
```
=== Positive fixtures (must pass) ===
OK    tests/fixtures/composites/confirm/minimal/input.yaml
OK    tests/fixtures/composites/confirm/minimal/expected.yaml
OK    tests/fixtures/composites/gated_action/basic/input.yaml
OK    tests/fixtures/composites/gated_action/basic/expected.yaml

=== Negative fixtures (must fail) ===
OK    .../_negative/confirm_missing_store_as/input.yaml (correctly rejected)
OK    .../_negative/gated_action_missing_else/input.yaml (correctly rejected)
OK    .../_negative/gated_action_empty_when/input.yaml (correctly rejected)

=== Summary ===
Positive: 4 passed, 0 failed
Negative: 3 correctly rejected, 0 unexpectedly passed
All fixtures OK
```
Exit 0.

- [ ] **Step 7: Commit**

```bash
git add schema/authoring/node-types.json tests/fixtures/composites/
git commit -m "$(cat <<'EOF'
schema: add gated_action_node $def with required when[] and else

gated_action_node requires when (minItems 1) and else. Each when[] item
requires condition + next_node, with optional consequences. on_unknown
is optional and defaults to workflow default_error per spec.

Adds gated_action/basic positive fixture and two negative fixtures:
gated_action_missing_else and gated_action_empty_when. All validate
correctly against the updated schema.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Bump schema `$comment` version to 3.1

**Files:**
- Modify: `schema/authoring/node-types.json:4` (the `$comment` line)

Signals the schema change to consumers.

- [ ] **Step 1: Update the $comment**

Modify `schema/authoring/node-types.json`.

OLD (line 4):
```json
  "$comment": "Schema version 3.0 - Workflow schema compression: consequences rename, ternary conditionals, condition/handler sugar.",
```

NEW:
```json
  "$comment": "Schema version 3.1 - Composite node support: confirm and gated_action sugar expand to primitives via walker in hiivmind-blueprint-mcp.",
```

- [ ] **Step 2: Run validator; confirm no regression (the comment change is purely textual)**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected: Same clean output as end of Task 4. Exit 0.

- [ ] **Step 3: Commit**

```bash
git add schema/authoring/node-types.json
git commit -m "$(cat <<'EOF'
schema: bump node-types.json \$comment to version 3.1

Signals composite support in node-types.json. Purely textual — all
validation behavior already lands in earlier commits on this branch.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Fill out `confirm` fixture corpus

**Files:**
- Create: `tests/fixtures/composites/confirm/with_consequences/input.yaml`
- Create: `tests/fixtures/composites/confirm/with_consequences/expected.yaml`
- Create: `tests/fixtures/composites/confirm/custom_labels/input.yaml`
- Create: `tests/fixtures/composites/confirm/custom_labels/expected.yaml`

Two additional positive cases that cover the optional fields: `consequences` on `on_confirmed`, and custom `label` on both branches.

- [ ] **Step 1: Write the `with_consequences` input**

Create `tests/fixtures/composites/confirm/with_consequences/input.yaml`:
```yaml
destroy_branch:
  type: confirm
  prompt: "Delete the branch '${branch_name}'?"
  header: "DELETE"
  store_as: confirmations.delete_branch_x
  on_confirmed:
    consequences:
      - type: git_ops_local
        operation: delete_branch
        args: { name: "${branch_name}" }
    next_node: branch_gone
  on_declined:
    next_node: cancelled
```

- [ ] **Step 2: Write the `with_consequences` expected expansion (3 nodes because `on_confirmed.consequences` is present, forcing an intermediate `__act` action node)**

Create `tests/fixtures/composites/confirm/with_consequences/expected.yaml`:
```yaml
destroy_branch__ask:
  type: user_prompt
  prompt:
    question: "Delete the branch '${branch_name}'?"
    header: "DELETE"
    options:
      - { id: "yes", label: "Yes" }
      - { id: "no",  label: "No"  }
  on_response:
    "yes":
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.delete_branch_x
          value: true
      next_node: destroy_branch__gate
    "no":
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.delete_branch_x
          value: false
      next_node: destroy_branch__gate

destroy_branch__gate:
  type: conditional
  condition: "confirmations.delete_branch_x == true"
  on_true: destroy_branch__act
  on_false: cancelled

destroy_branch__act:
  type: action
  consequences:
    - type: git_ops_local
      operation: delete_branch
      args: { name: "${branch_name}" }
  on_success: branch_gone
```

- [ ] **Step 3: Write the `custom_labels` input**

Create `tests/fixtures/composites/confirm/custom_labels/input.yaml`:
```yaml
accept_offer:
  type: confirm
  prompt: "Accept the offer?"
  header: "OFFER"
  store_as: confirmations.offer_accepted
  on_confirmed:
    label: "Accept it"
    next_node: finalize
  on_declined:
    label: "Walk away"
    next_node: closed_nothanks
```

- [ ] **Step 4: Write the `custom_labels` expected expansion**

Create `tests/fixtures/composites/confirm/custom_labels/expected.yaml`:
```yaml
accept_offer__ask:
  type: user_prompt
  prompt:
    question: "Accept the offer?"
    header: "OFFER"
    options:
      - { id: "yes", label: "Accept it"   }
      - { id: "no",  label: "Walk away"   }
  on_response:
    "yes":
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.offer_accepted
          value: true
      next_node: accept_offer__gate
    "no":
      consequences:
        - type: mutate_state
          operation: set
          field: confirmations.offer_accepted
          value: false
      next_node: accept_offer__gate

accept_offer__gate:
  type: conditional
  condition: "confirmations.offer_accepted == true"
  on_true: finalize
  on_false: closed_nothanks
```

- [ ] **Step 5: Run validator; all four new files (2 input.yaml + 2 expected.yaml) should validate**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected summary:
```
Positive: 8 passed, 0 failed
Negative: 3 correctly rejected, 0 unexpectedly passed
All fixtures OK
```

- [ ] **Step 6: Commit**

```bash
git add tests/fixtures/composites/confirm/
git commit -m "$(cat <<'EOF'
test: expand confirm fixture corpus with consequences + custom labels

with_consequences case covers on_confirmed.consequences (produces the
optional __act action node in expected expansion). custom_labels case
covers overriding the default Yes/No labels. All fixtures conform to
the authoring schema.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Fill out `gated_action` fixture corpus

**Files:**
- Create: `tests/fixtures/composites/gated_action/with_consequences/input.yaml`
- Create: `tests/fixtures/composites/gated_action/with_consequences/expected.yaml`
- Create: `tests/fixtures/composites/gated_action/default_on_unknown/input.yaml`
- Create: `tests/fixtures/composites/gated_action/default_on_unknown/expected.yaml`

Two additional cases: one `when` with `consequences` (exercising the optional intermediate action), and one case omitting `on_unknown` to verify the default-to-workflow-default_error behavior.

- [ ] **Step 1: Write the `with_consequences` input**

Create `tests/fixtures/composites/gated_action/with_consequences/input.yaml`:
```yaml
review_decision:
  type: gated_action
  when:
    - condition: "flags.status == 'approved'"
      consequences:
        - type: mutate_state
          operation: set
          field: approval_ts
          value: "${now}"
      next_node: publish
    - condition: { all: [{ type: state_check, field: flags.merge_ok, operator: "true" }] }
      next_node: merge_upstream
    - condition: "flags.status == 'rejected'"
      next_node: notify_author
  else: needs_review
  on_unknown: halt_for_audit
```

- [ ] **Step 2: Write the `with_consequences` expected expansion**

Create `tests/fixtures/composites/gated_action/with_consequences/expected.yaml`:
```yaml
review_decision__case_0:
  type: conditional
  condition: "flags.status == 'approved'"
  on_true: review_decision__case_0__act
  on_false: review_decision__case_1
  on_unknown: halt_for_audit

review_decision__case_0__act:
  type: action
  consequences:
    - type: mutate_state
      operation: set
      field: approval_ts
      value: "${now}"
  on_success: publish

review_decision__case_1:
  type: conditional
  condition: { all: [{ type: state_check, field: flags.merge_ok, operator: "true" }] }
  on_true: merge_upstream
  on_false: review_decision__case_2
  on_unknown: halt_for_audit

review_decision__case_2:
  type: conditional
  condition: "flags.status == 'rejected'"
  on_true: notify_author
  on_false: needs_review
  on_unknown: halt_for_audit
```

- [ ] **Step 3: Write the `default_on_unknown` input (omits `on_unknown`)**

Create `tests/fixtures/composites/gated_action/default_on_unknown/input.yaml`:
```yaml
route_on_env:
  type: gated_action
  when:
    - condition: "env.stage == 'production'"
      next_node: prod_flow
    - condition: "env.stage == 'staging'"
      next_node: stage_flow
  else: dev_flow
  # on_unknown intentionally omitted — walker must default to workflow default_error
```

- [ ] **Step 4: Write the `default_on_unknown` expected expansion (omits `on_unknown` on every conditional — walker must not inject a value; runtime uses workflow `default_error`)**

Create `tests/fixtures/composites/gated_action/default_on_unknown/expected.yaml`:
```yaml
route_on_env__case_0:
  type: conditional
  condition: "env.stage == 'production'"
  on_true: prod_flow
  on_false: route_on_env__case_1

route_on_env__case_1:
  type: conditional
  condition: "env.stage == 'staging'"
  on_true: stage_flow
  on_false: dev_flow
```

- [ ] **Step 5: Run validator; all four new files should validate**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected summary:
```
Positive: 12 passed, 0 failed
Negative: 3 correctly rejected, 0 unexpectedly passed
All fixtures OK
```

- [ ] **Step 6: Commit**

```bash
git add tests/fixtures/composites/gated_action/
git commit -m "$(cat <<'EOF'
test: expand gated_action fixture corpus with consequences + default on_unknown

with_consequences case exercises per-branch consequences (producing the
optional intermediate action node). default_on_unknown case verifies
that omitting on_unknown causes the walker to leave it unset on expanded
conditionals (runtime falls back to workflow default_error).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Write `blueprint-composites.md`

**Files:**
- Create: `blueprint-composites.md` (at repo root, alongside `blueprint-types.md`)

This is the authoritative author-time catalog. Terse signatures + expansion shape. Behavioral invariants live in the two principle files (referenced).

- [ ] **Step 1: Create `blueprint-composites.md`**

Create `blueprint-composites.md`:

````markdown
# hiivmind-blueprint Composites

Author-time composite catalog. Composites are syntactic sugar that the walker
expands deterministically into primitive nodes before the LLM interprets
anything at runtime.

**The LLM at runtime does NOT read this file.** It reads `blueprint-types.md`
and the expanded primitive graph. Composite definitions never reach runtime.

Walker implementations (Python and TypeScript) live in `hiivmind-blueprint-mcp`.
Both must produce identical primitive subgraphs from the fixture corpus in
`tests/fixtures/composites/`.

Behavioral invariants and rationale for each composite live in principle
documents:

- `composite-primitive-canary` (c.type-system) — composites are sugar; awkward
  composites are diagnostic signals that primitives need extension.
- `confirmations-as-explicit-state` (g.trust-governance) — the `confirm`
  composite's structural decomposition is the policy; the walker expansion is
  the enforcement.

## Conventions

- `name(param1, param2, optional?)` — reference signature. `?` marks optional
  parameters. The actual YAML call site uses sibling keys, not positional args.
- `X ∈ {a, b, c}` — enum variants on the line below the signature.
- `→` describes the expansion outcome (primitive subgraph shape), not runtime
  semantics.
- All string parameters support `${}` state interpolation (same as primitives).

---

## Composites

confirm(prompt, store_as, on_confirmed, on_declined, header?)
  store_as      = dot-notation state field (convention: confirmations.<name>)
  header        defaults to "CONFIRM"
  on_confirmed  = {next_node, consequences?, label?}
  on_declined   = {next_node, label?}
  → Expands to: user_prompt → mutate_state → conditional → (optional action).
    The conditional structurally gates routing on store_as == true.
    See principle: confirmations-as-explicit-state.

gated_action(when[], else, on_unknown?)
  when          = [{condition, consequences?, next_node}]
    condition   = string (evaluate_expression shorthand) |
                  {all|any|none|xor: [...]} (composite shorthand) |
                  object (canonical precondition)
  on_unknown    defaults to workflow default_error
  → First-match-wins CASE/WHEN dispatch. Expansion: chain of conditional
    nodes, each optionally followed by an action for per-branch
    consequences. 3VL short-circuit on unknown.
````

- [ ] **Step 2: Commit**

```bash
git add blueprint-composites.md
git commit -m "$(cat <<'EOF'
docs: add blueprint-composites.md — author-time composite catalog

Separate from blueprint-types.md (runtime catalog). Documents the two v1
composites (confirm, gated_action) with terse signatures and expansion
shapes. Behavioral invariants live in the two principles committed on
branch principle/composite-primitive-canary in hiivmind-blueprint-central.

Walker implementations are out of scope for this repo — they live in
the future hiivmind-blueprint-mcp package.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Wire CI workflow for fixture validation

**Files:**
- Create: `.github/workflows/validate-fixtures.yaml`

GitHub Action that runs `scripts/validate-fixtures.sh` on pull requests, so fixture drift can't land silently.

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/validate-fixtures.yaml`:

```yaml
name: Validate Composite Fixtures

on:
  pull_request:
    branches:
      - main
      - develop
      - "release/**"
      - "feature/**"
      - "hotfix/**"
    paths:
      - "schema/**"
      - "tests/fixtures/composites/**"
      - "scripts/validate-fixtures.sh"
      - ".github/workflows/validate-fixtures.yaml"
  workflow_dispatch:

jobs:
  validate:
    name: Validate fixtures against authoring schema
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Setup Node.js (for npx / ajv-cli)
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Run validator
        run: ./scripts/validate-fixtures.sh
```

- [ ] **Step 2: Sanity-check the shell script locally before CI lands**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected: clean exit (Positive: 12 passed, Negative: 3 correctly rejected).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/validate-fixtures.yaml
git commit -m "$(cat <<'EOF'
ci: run composite fixture validation on PRs

GitHub Action runs scripts/validate-fixtures.sh whenever schema files,
fixtures, or the validator itself change. Uses yq + ajv-cli via npx
(no persistent installs, matches the validator's local behavior).
Triggers on all non-main branches so authors see failures before
merging.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Update `package.yaml` and `CHANGELOG.md`

**Files:**
- Modify: `package.yaml` — bump version to 7.1.0; update stats
- Modify: `CHANGELOG.md` — add 7.1.0 entry

- [ ] **Step 1: Bump version in `package.yaml`**

Modify `package.yaml`.

OLD:
```yaml
name: hiivmind-blueprint-lib
version: "7.0.0"
```

NEW:
```yaml
name: hiivmind-blueprint-lib
version: "7.1.0"
```

- [ ] **Step 2: Update the `stats` block**

OLD (the stats section):
```yaml
# Statistics
stats:
  total_types: 34
  consequence_types: 22
  precondition_types: 9
  node_types: 3
  workflows: 1
```

NEW:
```yaml
# Statistics
stats:
  total_types: 34
  consequence_types: 22
  precondition_types: 9
  node_types: 3        # primitives only (action, conditional, user_prompt)
  composite_types: 2   # confirm, gated_action (authoring-time sugar)
  workflows: 1
```

- [ ] **Step 3: Update the `artifacts` block to include `blueprint-composites.md`**

OLD:
```yaml
# Artifacts produced by releases
artifacts:
  - blueprint-types.md  # The canonical type catalog
  - workflows/          # Reusable workflow definitions
  - schema/             # Authoring, config, and runtime JSON schemas
  - examples.md         # Composite workflow examples
```

NEW:
```yaml
# Artifacts produced by releases
artifacts:
  - blueprint-types.md       # Runtime type catalog (primitives)
  - blueprint-composites.md  # Authoring-time composite catalog (walker-expanded before runtime)
  - workflows/               # Reusable workflow definitions
  - schema/                  # Authoring, config, and runtime JSON schemas
  - examples.md              # Composite workflow examples
```

- [ ] **Step 4: Add CHANGELOG entry**

Modify `CHANGELOG.md` — insert a new 7.1.0 section directly AFTER the `# Changelog` / intro paragraphs and BEFORE the existing `## [7.0.0]` section.

Insert this block:

```markdown
## [7.1.0] - 2026-04-14

### Added

#### Composite node types (authoring-time sugar)

Two new composite node types expand to primitive nodes via a walker implemented in `hiivmind-blueprint-mcp` (separate repo). The LLM at runtime still sees only the three primitive node types (`action`, `conditional`, `user_prompt`) — composites never reach runtime.

- **`confirm`** — yes/no prompt with structural state gating. Required fields: `prompt`, `store_as`, `on_confirmed`, `on_declined`. Expands to `user_prompt → mutate_state → conditional → (optional action)`. The `store_as` field is required and always written `true`/`false` before routing, per the [confirmations-as-explicit-state](https://github.com/hiivmind/hiivmind-blueprint-central/blob/main/02.principles/g.trust-governance/confirmations-as-explicit-state.md) principle.
- **`gated_action`** — multi-way CASE/WHEN dispatch. Required fields: `when[]` (minItems 1), `else`. Optional: `on_unknown` (defaults to workflow `default_error`). Expands to a chain of `conditional` nodes, each optionally followed by an intermediate `action` for per-branch consequences. First-match-wins, 3VL short-circuit on unknown.

#### New author-time catalog: `blueprint-composites.md`

Composite signatures and expansion shapes live in a new file at the repo root, separate from `blueprint-types.md`. The runtime LLM continues to read only `blueprint-types.md`; the composite catalog is consumed at authoring time.

#### Walker-expansion fixture corpus

`tests/fixtures/composites/` contains paired `input.yaml` / `expected.yaml` fixtures covering:

- `confirm/minimal`, `confirm/with_consequences`, `confirm/custom_labels`
- `gated_action/basic`, `gated_action/with_consequences`, `gated_action/default_on_unknown`
- `_negative/` cases: `confirm_missing_store_as`, `gated_action_missing_else`, `gated_action_empty_when`

These are the authoritative contract that future Python and TypeScript walker implementations in `hiivmind-blueprint-mcp` must satisfy (bit-identical expansion from each input).

### Changed

- `schema/authoring/node-types.json` — bumped `$comment` to Schema version 3.1. Adds `confirm` and `gated_action` to the `type` enum plus two new `$defs` (`confirm_node`, `gated_action_node`) with `allOf` dispatch. Existing primitive validation unchanged.

### Related principles

Two new principles codify the discipline governing this feature. Committed in `hiivmind-blueprint-central` on branch `principle/composite-primitive-canary`:

- [composite-primitive-canary](https://github.com/hiivmind/hiivmind-blueprint-central/blob/main/02.principles/c.type-system/composite-primitive-canary.md) — composites are sugar; awkward composites are diagnostic signals that primitives need extension.
- [confirmations-as-explicit-state](https://github.com/hiivmind/hiivmind-blueprint-central/blob/main/02.principles/g.trust-governance/confirmations-as-explicit-state.md) — confirmations decompose into classify → record → evaluate; structure is the policy.

### Migration

Purely additive. No existing workflow breaks. Authors who want to use the new composites can opt in; hand-written primitive patterns continue to work unchanged.

---
```

- [ ] **Step 5: Run validator for final sanity check**

Run:
```bash
./scripts/validate-fixtures.sh
```

Expected: clean exit.

- [ ] **Step 6: Commit**

```bash
git add package.yaml CHANGELOG.md
git commit -m "$(cat <<'EOF'
release: v7.1.0 — composite node types (confirm, gated_action)

Minor release introducing the composite node mechanism: authoring-time
syntactic sugar that expands to primitive nodes via a walker in the
future hiivmind-blueprint-mcp package. Runtime LLM sees only primitives.

Purely additive. No existing workflow breaks.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Update `README.md` and `CLAUDE.md`

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

Point readers at `blueprint-composites.md` and clarify that walker implementation lives elsewhere.

- [ ] **Step 1: Read the current README top to find the right insertion point**

Run:
```bash
head -60 README.md
```

- [ ] **Step 2: Update README.md — add a composite section next to the type-catalog mention**

Find the section that describes the repo's contents (likely near the top, describing `blueprint-types.md`). Insert a new block immediately after the `blueprint-types.md` description:

Insert this block in `README.md`, AFTER the paragraph or list item that describes `blueprint-types.md`:

```markdown
### Composite Node Catalog — `blueprint-composites.md`

Alongside the runtime type catalog, `blueprint-composites.md` documents **composite node types** — authoring-time syntactic sugar that expands to primitive nodes before the LLM interprets anything. v1 ships `confirm` and `gated_action`.

The runtime LLM does not read `blueprint-composites.md`. Composite definitions are stripped by the walker (implemented in the `hiivmind-blueprint-mcp` package — Python and TypeScript flavors) before execution begins.

Behavioral invariants governing each composite live in principle documents in `hiivmind-blueprint-central`:

- `composite-primitive-canary` (c.type-system)
- `confirmations-as-explicit-state` (g.trust-governance)

Walker-expansion fixtures live under `tests/fixtures/composites/` and serve as the cross-language contract for walker implementations.
```

- [ ] **Step 3: Read the current CLAUDE.md to find the right insertion point**

Run:
```bash
head -80 CLAUDE.md
```

- [ ] **Step 4: Update CLAUDE.md — add a composite-authoring note**

Find the "Key Concepts" section in `CLAUDE.md`. Add a new subsection AFTER the "Type Catalog Format" subsection:

```markdown
### Composite Node Types (Authoring Sugar)

In addition to the three primitive node types, blueprint supports **composite nodes** — author-time syntactic sugar documented in `blueprint-composites.md` (separate from `blueprint-types.md`). v1 composites:

- `confirm` — yes/no prompt with structural state gating
- `gated_action` — multi-way CASE/WHEN dispatch

Composites are walker-expanded into primitive nodes before execution. The walker implementation lives in `hiivmind-blueprint-mcp` (separate repo). **This repo contains only the catalog, schema, and fixture corpus** — no walker code, no Python runtime.

When modifying composite definitions, also update:

1. `schema/authoring/node-types.json` — composite sub-schemas
2. `blueprint-composites.md` — author-facing signature
3. `tests/fixtures/composites/` — expansion contract fixtures (the authoritative walker target)

When modifying primitives in a way that could affect composite expansion, notify `hiivmind-blueprint-mcp` maintainers — walker expanders may need updates to stay contract-valid.
```

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: point README and CLAUDE.md at blueprint-composites.md

Adds composite-catalog section to README and composite-authoring note to
CLAUDE.md. Explains the two v1 composites, points at the companion
principles, and clarifies that walker implementation is out of scope
for this repo (lives in hiivmind-blueprint-mcp).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Final verification

After Task 11, run one end-to-end sanity pass:

```bash
# Fixture validation
./scripts/validate-fixtures.sh

# Expected: Positive: 12 passed, 0 failed; Negative: 3 correctly rejected, 0 unexpectedly passed; exit 0.

# Git log sanity
git log --oneline feat/composite-nodes ^refactor/type-catalog-collapse
```

Expected commit list on the branch (newest first, not counting the pre-existing spec commits):

1. `docs: point README and CLAUDE.md at blueprint-composites.md`
2. `release: v7.1.0 — composite node types (confirm, gated_action)`
3. `ci: run composite fixture validation on PRs`
4. `docs: add blueprint-composites.md — author-time composite catalog`
5. `test: expand gated_action fixture corpus with consequences + default on_unknown`
6. `test: expand confirm fixture corpus with consequences + custom labels`
7. `schema: bump node-types.json $comment to version 3.1`
8. `schema: add gated_action_node $def with required when[] and else`
9. `schema: add confirm_node $def with confirmations-as-explicit-state invariant`
10. `schema: add confirm and gated_action to node-type enum`
11. `test: scaffold composite fixtures directory and validator script`

Plus two earlier spec/principle-ref commits already on the branch.

Plan complete — feature branch ready for PR review to `main`.
