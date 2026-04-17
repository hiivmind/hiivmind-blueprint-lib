# Blueprint-lib v8.0 — Type System Additions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship blueprint-lib v8.0.0 — five coordinated type-system additions (BL1–BL5): new `ending` node type retiring the top-level `endings:` block; `mcp_tool_call` consequence; `## Payload Types` catalog section + per-workflow `payload_types:` block; `trust_mode` and `data_mcps` workflow fields. Hard cutover, no deprecation.

**Architecture:** This repo is a type catalog + authoring schema — there is no runtime to test. "Tests" are JSON Schema validation (via `ajv-cli`) of positive/negative fixtures, plus repo-wide grep verification that the migration is complete. The consequence schema is type-agnostic by design (`node-types.json` L425); `mcp_tool_call` gets a catalog entry but no schema `$def`. The ending node gets both a schema `$def` (with transition-slot forbiddance) and a catalog entry; it is the fourth primitive node type.

**Tech Stack:** JSON Schema (Draft 2020-12), YAML, `yq` + `ajv-cli` via `scripts/validate-fixtures.sh` (existing) and a new `scripts/validate-workflows.sh` (this plan).

**Spec:** `docs/superpowers/specs/2026-04-17-v7-type-system-additions-design.md`

**Working branch:** continue on `feat/goal-seek-node` or create `feat/v8-type-additions` — either works. Subagent-driven development should land this in a dedicated worktree.

**Cross-repo scope:** Tasks 17–18 modify files in `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/patterns/`. Those commits land in *that* repo, not this one. Subagent drivers must switch repos for those tasks.

---

## File Map

### Create

**Fixtures (endings — schema-level):**
- `tests/fixtures/endings/minimal/input.yaml`
- `tests/fixtures/endings/with_consequences/input.yaml`
- `tests/fixtures/endings/with_behavior_silent/input.yaml`
- `tests/fixtures/endings/with_behavior_delegate/input.yaml`
- `tests/fixtures/endings/with_behavior_restart/input.yaml`
- `tests/fixtures/_negative/ending_with_on_success/input.yaml`
- `tests/fixtures/_negative/ending_missing_outcome/input.yaml`
- `tests/fixtures/_negative/ending_invalid_outcome/input.yaml`

**Fixtures (workflow-level — full workflows):**
- `tests/fixtures/workflows/v8_minimal/input.yaml`
- `tests/fixtures/workflows/v8_with_mcp/input.yaml`
- `tests/fixtures/workflows/_negative/endings_block_rejected/input.yaml`
- `tests/fixtures/workflows/_negative/default_error_not_ending/input.yaml`
- `tests/fixtures/workflows/_negative/payload_type_bad_name/input.yaml`

**Schema files:**
- `schema/authoring/payload-types.json`

**Scripts:**
- `scripts/validate-workflows.sh` — workflow-level JSON Schema validation

**Optional:**
- `scripts/migrate-v7-to-v8.sh` — YAML rewriter for the `endings:` → `nodes:` migration

### Modify

**In-repo:**
- `schema/authoring/node-types.json` — add `ending_node` `$def` + enum + dispatch
- `schema/authoring/workflow.json` — remove `endings:` property + `$def`; add `trust_mode`, `data_mcps`, `payload_types`
- `scripts/validate-fixtures.sh` — extend to cover `tests/fixtures/endings/`
- `blueprint-types.md` — add `ending` node + `mcp_tool_call` consequence + new `## Payload Types` section
- `examples.md` — migrate all 3 workflows + add 1 new using MCP features
- `workflows/core/intent-detection.yaml` — migrate `endings:` → `nodes:`
- `README.md` — migrate workflow snippets
- `CLAUDE.md` — update node primitive count (3 → 4)
- `package.yaml` — bump to 8.0.0; stats
- `CHANGELOG.md` — v8.0.0 entry

**Cross-repo (at `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/patterns/`):**
- `authoring-guide.md` — type tables + ending + payload types + mcp_tool_call sections
- `execution-guide.md` — dispatch semantics for ending + mcp_tool_call invocation topology

---

## Task 1: Positive fixtures for `ending` node

**Files:**
- Create: `tests/fixtures/endings/minimal/input.yaml`
- Create: `tests/fixtures/endings/with_consequences/input.yaml`
- Create: `tests/fixtures/endings/with_behavior_silent/input.yaml`
- Create: `tests/fixtures/endings/with_behavior_delegate/input.yaml`
- Create: `tests/fixtures/endings/with_behavior_restart/input.yaml`

- [ ] **Step 1: Write `minimal` fixture.**

```yaml
# tests/fixtures/endings/minimal/input.yaml
done:
  type: ending
  outcome: success
  message: "Goodbye."
```

- [ ] **Step 2: Write `with_consequences` fixture.**

```yaml
# tests/fixtures/endings/with_consequences/input.yaml
cleanup_done:
  type: ending
  outcome: success
  message: "Cleanup complete."
  consequences:
    - type: log_entry
      level: info
      message: "Workflow finished cleanly"
    - type: display
      content: "Done."
```

- [ ] **Step 3: Write `with_behavior_silent` fixture.**

```yaml
# tests/fixtures/endings/with_behavior_silent/input.yaml
silent_exit:
  type: ending
  outcome: cancelled
  behavior:
    type: silent
```

- [ ] **Step 4: Write `with_behavior_delegate` fixture.**

```yaml
# tests/fixtures/endings/with_behavior_delegate/input.yaml
handoff:
  type: ending
  outcome: success
  message: "Handing off to follow-up skill."
  behavior:
    type: delegate
    skill: "hiivmind-corpus-build"
    args: "${computed.source_id}"
    context:
      source: "${computed.source_id}"
```

- [ ] **Step 5: Write `with_behavior_restart` fixture.**

```yaml
# tests/fixtures/endings/with_behavior_restart/input.yaml
retry_from_ask:
  type: ending
  outcome: failure
  message: "Retrying."
  behavior:
    type: restart
    target_node: ask
    max_restarts: 3
    reset_state: false
```

- [ ] **Step 6: Commit fixtures.**

```bash
git add tests/fixtures/endings/
git commit -m "test: add positive fixtures for ending node type (BL5)"
```

---

## Task 2: Negative fixtures for `ending` node

**Files:**
- Create: `tests/fixtures/_negative/ending_with_on_success/input.yaml`
- Create: `tests/fixtures/_negative/ending_missing_outcome/input.yaml`
- Create: `tests/fixtures/_negative/ending_invalid_outcome/input.yaml`

- [ ] **Step 1: Write `ending_with_on_success` (ending forbids transition slots).**

```yaml
# tests/fixtures/_negative/ending_with_on_success/input.yaml
# NEGATIVE: an ending node may not declare on_success (or any transition slot).
bad:
  type: ending
  outcome: success
  message: "This should fail."
  on_success: somewhere
```

- [ ] **Step 2: Write `ending_missing_outcome` (outcome is required).**

```yaml
# tests/fixtures/_negative/ending_missing_outcome/input.yaml
# NEGATIVE: an ending node must declare an outcome.
bad:
  type: ending
  message: "No outcome — should fail."
```

- [ ] **Step 3: Write `ending_invalid_outcome` (outcome must match enum).**

```yaml
# tests/fixtures/_negative/ending_invalid_outcome/input.yaml
# NEGATIVE: `outcome` must be one of success/failure/error/cancelled/indeterminate.
bad:
  type: ending
  outcome: maybe
  message: "Unknown outcome — should fail."
```

- [ ] **Step 4: Commit negatives.**

```bash
git add tests/fixtures/_negative/ending_with_on_success/ \
        tests/fixtures/_negative/ending_missing_outcome/ \
        tests/fixtures/_negative/ending_invalid_outcome/
git commit -m "test: add negative fixtures for ending node type (BL5)"
```

---

## Task 3: Extend `validate-fixtures.sh` to cover `tests/fixtures/endings/`

**Files:**
- Modify: `scripts/validate-fixtures.sh`

The current script hard-codes `FIXTURES_DIR="$REPO_ROOT/tests/fixtures/composites"` and walks composite fixtures only. It needs to also walk `tests/fixtures/endings/` (positives) and include the new ending-specific negatives at `tests/fixtures/_negative/ending_*`.

- [ ] **Step 1: Read the current script to locate the two `find` calls.**

Run: `grep -n "find\|FIXTURES_DIR" scripts/validate-fixtures.sh`

Expected: the positive and negative `find` invocations around the end of the script.

- [ ] **Step 2: Add a second fixtures root and walk both.**

Replace the single-dir walk with a loop over both roots. Edit `scripts/validate-fixtures.sh`:

Find the block starting with `echo "=== Positive fixtures (must pass) ==="` and replace the two `while IFS= … find` blocks with:

```bash
# Positive roots
POS_ROOTS=(
  "$REPO_ROOT/tests/fixtures/composites"
  "$REPO_ROOT/tests/fixtures/endings"
)

# Negative root (single directory; filenames disambiguate fixture kind)
NEG_ROOT="$REPO_ROOT/tests/fixtures/_negative"
# The pre-existing composites _negative dir still applies:
NEG_COMPOSITES="$REPO_ROOT/tests/fixtures/composites/_negative"

echo "=== Positive fixtures (must pass) ==="
for root in "${POS_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r -d '' f; do
    validate_file "$f" "true"
  done < <(find "$root" -type f \( -name 'input.yaml' -o -name 'expected.yaml' \) \
           -not -path '*/_negative/*' -not -path '*/_walker_only/*' -print0)
done

echo ""
echo "=== Negative fixtures (must fail) ==="
for root in "$NEG_ROOT" "$NEG_COMPOSITES"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r -d '' f; do
    validate_file "$f" "false"
  done < <(find "$root" -type f -name 'input.yaml' -print0)
done
```

Keep the rest of the script unchanged (the old `FIXTURES_DIR` variable can remain; it's only used by the find commands being replaced).

- [ ] **Step 3: Run the validator and confirm the ending fixtures fail (schema doesn't know `ending` yet).**

Run: `bash scripts/validate-fixtures.sh`

Expected: existing composite fixtures pass; **new endings fixtures FAIL** (ajv rejects unknown `type: ending`). Output should include lines like:

```
FAIL  tests/fixtures/endings/minimal/input.yaml (node: done)
```

- [ ] **Step 4: Commit the script change.**

```bash
git add scripts/validate-fixtures.sh
git commit -m "build: extend validate-fixtures.sh to walk endings/ fixture tree"
```

---

## Task 4: Add `ending_node` `$def` to `node-types.json` (makes Task 1 & 2 fixtures validate)

**Files:**
- Modify: `schema/authoring/node-types.json`

- [ ] **Step 1: Add `"ending"` to the node type enum.**

In `schema/authoring/node-types.json`, find the `"type"` enum under `$defs.node.properties`:

```json
"enum": ["action", "conditional", "user_prompt", "confirm", "gated_action", "goal_seek"],
```

Replace with:

```json
"enum": ["action", "conditional", "user_prompt", "ending", "confirm", "gated_action", "goal_seek"],
```

(Place `ending` immediately after the three existing primitives; composites follow.)

- [ ] **Step 2: Add dispatch case for `ending` in the `allOf` list.**

Under `$defs.node.allOf`, after the `user_prompt` case and before the `confirm` case, insert:

```json
{
  "if": { "properties": { "type": { "const": "ending" } } },
  "then": { "$ref": "#/$defs/ending_node" }
},
```

- [ ] **Step 3: Add the `ending_node` `$def`.**

Add after `user_prompt_node` and before `confirm_node` in `$defs`:

```json
"ending_node": {
  "type": "object",
  "description": "Terminal node. Reaching an ending emits the declared outcome and stops the FSM. Behavior (silent/delegate/restart) governs post-termination handling.",
  "required": ["type", "outcome"],
  "properties": {
    "type": { "const": "ending" },
    "description": { "type": "string" },
    "outcome": {
      "type": "string",
      "enum": ["success", "failure", "error", "cancelled", "indeterminate"],
      "description": "Terminal outcome category."
    },
    "category": {
      "type": "string",
      "description": "Optional categorization for error outcomes (e.g., safety, validation, configuration, permission, external)."
    },
    "message": {
      "type": "string",
      "description": "Message to display at termination (supports ${} interpolation)."
    },
    "summary": {
      "type": "object",
      "description": "Structured summary data to display at termination.",
      "additionalProperties": true
    },
    "details": {
      "type": "string",
      "description": "Additional details for error outcomes."
    },
    "recovery": {
      "description": "Recovery guidance for error outcomes. Simple string or structured object.",
      "oneOf": [
        { "type": "string" },
        {
          "type": "object",
          "properties": {
            "suggestion":    { "type": "string" },
            "related_skill": { "type": "string" },
            "retry_node":    { "type": "string" }
          },
          "additionalProperties": false
        }
      ]
    },
    "consequences": {
      "type": "array",
      "description": "Consequences run at termination (best-effort; failures are logged but do not prevent completion).",
      "items": { "$ref": "#/$defs/consequence" }
    },
    "behavior": {
      "description": "Post-termination behavior. Defaults to display (show message/summary).",
      "oneOf": [
        {
          "type": "object",
          "description": "Delegate execution to another skill.",
          "required": ["type", "skill"],
          "properties": {
            "type":   { "const": "delegate" },
            "skill":  { "type": "string" },
            "args":   { "type": "string" },
            "context": { "type": "object", "additionalProperties": true }
          },
          "additionalProperties": false
        },
        {
          "type": "object",
          "description": "Restart the workflow from a target node.",
          "required": ["type"],
          "properties": {
            "type":         { "const": "restart" },
            "target_node":  { "$ref": "../common.json#/$defs/node_reference" },
            "reset_state":  { "type": "boolean", "default": false },
            "max_restarts": { "type": "integer", "minimum": 1, "default": 3 }
          },
          "additionalProperties": false
        },
        {
          "type": "object",
          "description": "Complete silently with no output.",
          "required": ["type"],
          "properties": {
            "type": { "const": "silent" }
          },
          "additionalProperties": false
        }
      ]
    }
  },
  "additionalProperties": false,
  "not": {
    "anyOf": [
      { "required": ["on_success"] },
      { "required": ["on_failure"] },
      { "required": ["on_true"] },
      { "required": ["on_false"] },
      { "required": ["on_unknown"] },
      { "required": ["on_response"] }
    ]
  }
}
```

- [ ] **Step 4: Update the `$comment` schema-version field at the top of the file.**

Change:

```json
"$comment": "Schema version 3.2 - Adds goal_seek composite (bounded dispatcher loop). Composites (confirm, gated_action, goal_seek) expand to primitives via walker in hiivmind-blueprint-mcp.",
```

To:

```json
"$comment": "Schema version 4.0 - Adds `ending` primitive node type (BL5). Node primitives: action, conditional, user_prompt, ending. Composites: confirm, gated_action, goal_seek.",
```

Also update the file-level `"description"` field to reflect the four primitives.

- [ ] **Step 5: Run the validator. All ending fixtures should now behave correctly.**

Run: `bash scripts/validate-fixtures.sh`

Expected:

```
=== Positive fixtures (must pass) ===
OK    tests/fixtures/endings/minimal/input.yaml
OK    tests/fixtures/endings/with_consequences/input.yaml
OK    tests/fixtures/endings/with_behavior_silent/input.yaml
OK    tests/fixtures/endings/with_behavior_delegate/input.yaml
OK    tests/fixtures/endings/with_behavior_restart/input.yaml
...all existing composite fixtures still OK...

=== Negative fixtures (must fail) ===
OK    tests/fixtures/_negative/ending_with_on_success/input.yaml (correctly rejected)
OK    tests/fixtures/_negative/ending_missing_outcome/input.yaml (correctly rejected)
OK    tests/fixtures/_negative/ending_invalid_outcome/input.yaml (correctly rejected)
...all existing negatives still correctly rejected...

All fixtures OK
```

- [ ] **Step 6: Commit schema.**

```bash
git add schema/authoring/node-types.json
git commit -m "feat(schema): add ending_node $def + enum + dispatch (BL5)"
```

---

## Task 5: Create `schema/authoring/payload-types.json` (BL2)

**Files:**
- Create: `schema/authoring/payload-types.json`

- [ ] **Step 1: Write the schema file.**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/main/schema/authoring/payload-types.json",
  "$comment": "Schema version 1.0 - Payload Types (BL2). Workflow-scoped data-shape declarations referenced by consequences via params_type.",
  "title": "Blueprint Payload Types Schema",
  "description": "Shape of a single payload type entry inside a workflow's payload_types: block.",
  "$defs": {
    "payload_type": {
      "type": "object",
      "description": "A map of field name to type descriptor. Field values may be scalar type strings or structured constraint objects.",
      "propertyNames": { "pattern": "^[a-z_][a-z0-9_]*$" },
      "additionalProperties": {
        "oneOf": [
          {
            "type": "string",
            "description": "Scalar type descriptor. Recognized forms: string, integer, boolean, object, array<T>, enum{a,b,c}. Whitespace-delimited constraints may follow (e.g. 'string (min_length=1, optional)').",
            "pattern": "^(string|integer|boolean|object|array<[a-zA-Z_][a-zA-Z0-9_]*>|enum\\{[^}]+\\})(\\s*\\([^)]*\\))?$"
          },
          {
            "type": "object",
            "description": "Structured field descriptor.",
            "required": ["type"],
            "properties": {
              "type":       { "type": "string" },
              "required":   { "type": "boolean", "default": true },
              "default":    {},
              "min":        { "type": "integer" },
              "max":        { "type": "integer" },
              "min_length": { "type": "integer" },
              "max_length": { "type": "integer" },
              "pattern":    { "type": "string" },
              "enum":       { "type": "array" },
              "items":      {}
            },
            "additionalProperties": false
          }
        ]
      }
    }
  }
}
```

- [ ] **Step 2: Commit.**

```bash
git add schema/authoring/payload-types.json
git commit -m "feat(schema): add payload-types.json (BL2)"
```

---

## Task 6: Add workflow-level fields (`trust_mode`, `data_mcps`, `payload_types`) to `workflow.json`

**Files:**
- Modify: `schema/authoring/workflow.json`

Add the three new optional properties. Keep `endings:` present in this task (removal is Task 7) so nothing breaks yet.

- [ ] **Step 1: Add `trust_mode` property.**

Inside `properties` in `schema/authoring/workflow.json`, after `"description"` and before `"entry_preconditions"`, add:

```json
"trust_mode": {
  "type": "string",
  "enum": ["stateless", "gated"],
  "default": "stateless",
  "description": "Workflow-level trust mode (BL3). Declarative metadata consumed by runtimes; blueprint-lib validates the enum only."
},
```

- [ ] **Step 2: Add `data_mcps` property.**

After `"trust_mode"`:

```json
"data_mcps": {
  "type": "object",
  "description": "Map of alias to MCP server name + semver range (e.g. 'eightball-tools@^1'). Aliases prefix mcp_tool_call tool references (BL4).",
  "propertyNames": { "pattern": "^[a-z_][a-z0-9_-]*$" },
  "additionalProperties": {
    "type": "string",
    "pattern": "^[\\w-]+@[\\w.\\-\\^~><=*|,\\s]+$"
  }
},
```

- [ ] **Step 3: Add `payload_types` property.**

After `"data_mcps"`:

```json
"payload_types": {
  "type": "object",
  "description": "Workflow-scoped payload type declarations (BL2). Keys are name@version; values are field maps. Referenced by consequences via params_type.",
  "propertyNames": { "pattern": "^[a-z_][a-z0-9_]*@\\d+$" },
  "additionalProperties": { "$ref": "payload-types.json#/$defs/payload_type" }
},
```

- [ ] **Step 4: Update schema-version comment at top of file.**

Change:

```json
"$comment": "Schema version 3.1 - Added default_error for implicit failure routing. Types defined in blueprint-types.md.",
```

To:

```json
"$comment": "Schema version 4.0 - Added trust_mode, data_mcps, payload_types (BL2/BL3/BL4); ending nodes live in nodes: (BL5).",
```

- [ ] **Step 5: Commit.**

```bash
git add schema/authoring/workflow.json
git commit -m "feat(schema): add trust_mode, data_mcps, payload_types workflow fields (BL2/3/4)"
```

---

## Task 7: Remove `endings:` block from `workflow.json` (breaking)

**Files:**
- Modify: `schema/authoring/workflow.json`

- [ ] **Step 1: Remove `"endings"` from `required`.**

Change:

```json
"required": ["name", "version", "start_node", "default_error", "nodes", "endings"],
```

To:

```json
"required": ["name", "version", "start_node", "default_error", "nodes"],
```

- [ ] **Step 2: Remove the `endings` property from `properties`.**

Delete the entire `"endings": { … }` block under `properties`.

- [ ] **Step 3: Remove the `ending` `$def` from `$defs`.**

Delete the entire `"ending": { … }` definition from the bottom of the file (it's the only entry in `$defs` today, so `$defs: {}` can also be removed if it becomes empty).

- [ ] **Step 4: Update the `default_error` description.**

Change its `"description"` to:

```
"Default node reference for unhandled failures. Must reference a node of type `ending`. Action nodes without on_failure and conditional nodes without on_unknown route here."
```

- [ ] **Step 5: Add `additionalProperties: false` at the workflow root (if not already present) to ensure a stray `endings:` key is rejected.**

Verify: the current `workflow.json` object may not have `additionalProperties`. Add `"additionalProperties": false` at the end of the root-level object (sibling of `properties`, `required`, `$defs`).

This is the load-time rule enforcing BL5's "top-level `endings:` is a hard error" invariant.

- [ ] **Step 6: Commit.**

```bash
git add schema/authoring/workflow.json
git commit -m "feat(schema)!: remove endings: block from workflow.json (BL5 breaking)

BREAKING CHANGE: workflows using the top-level endings: block fail to
validate. Migrate entries into nodes: with type: ending and outcome: field."
```

---

## Task 8: Create `scripts/validate-workflows.sh` (workflow-level schema validation)

**Files:**
- Create: `scripts/validate-workflows.sh`

The existing `validate-fixtures.sh` only validates node fragments. Workflow-level fixtures need a separate runner.

- [ ] **Step 1: Write the script.**

```bash
#!/usr/bin/env bash
#
# validate-workflows.sh — Validate full-workflow fixtures against workflow.json.
#
# Layout:
#   tests/fixtures/workflows/<name>/input.yaml           — positive
#   tests/fixtures/workflows/_negative/<name>/input.yaml — negative
#
# Exit codes mirror validate-fixtures.sh: 0 OK, 1 positive failed, 2 negative
# unexpectedly passed, 3 tool missing.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WF_ROOT="$REPO_ROOT/tests/fixtures/workflows"
SCHEMA_WF="$REPO_ROOT/schema/authoring/workflow.json"
SCHEMA_NODE="$REPO_ROOT/schema/authoring/node-types.json"
SCHEMA_PT="$REPO_ROOT/schema/authoring/payload-types.json"
SCHEMA_COMMON="$REPO_ROOT/schema/common.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WRAPPER_SCHEMA="$TMP_DIR/workflow-wrapper.json"
cat > "$WRAPPER_SCHEMA" <<'SCHEMA_EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$ref": "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/main/schema/authoring/workflow.json"
}
SCHEMA_EOF

command -v yq  >/dev/null 2>&1 || { echo -e "${RED}yq not found${NC}"; exit 3; }
command -v npx >/dev/null 2>&1 || { echo -e "${RED}npx not found${NC}"; exit 3; }

POS_PASS=0; POS_FAIL=0; NEG_PASS=0; NEG_FAIL=0

validate_file() {
  local yaml_file="$1" expect_pass="$2"
  local json_file="$TMP_DIR/$(basename "$(dirname "$yaml_file")").json"
  yq -o=json '.' "$yaml_file" > "$json_file"

  if npx --yes ajv-cli@5 validate --spec=draft2020 \
      -s "$WRAPPER_SCHEMA" \
      -r "$SCHEMA_WF" \
      -r "$SCHEMA_NODE" \
      -r "$SCHEMA_PT" \
      -r "$SCHEMA_COMMON" \
      -d "$json_file" \
      --strict=false \
      > "$TMP_DIR/ajv.log" 2>&1; then
    if [[ "$expect_pass" == "true" ]]; then
      echo -e "${GREEN}OK${NC}    $yaml_file"; POS_PASS=$((POS_PASS + 1))
    else
      echo -e "${YELLOW}UNEXPECTED PASS${NC}  $yaml_file"; NEG_FAIL=$((NEG_FAIL + 1))
    fi
  else
    if [[ "$expect_pass" == "true" ]]; then
      echo -e "${RED}FAIL${NC}  $yaml_file"; cat "$TMP_DIR/ajv.log"; POS_FAIL=$((POS_FAIL + 1))
    else
      echo -e "${GREEN}OK${NC}    $yaml_file (correctly rejected)"; NEG_PASS=$((NEG_PASS + 1))
    fi
  fi
}

echo "=== Positive workflow fixtures (must pass) ==="
while IFS= read -r -d '' f; do validate_file "$f" "true"; done \
  < <(find "$WF_ROOT" -type f -name 'input.yaml' -not -path '*/_negative/*' -print0 2>/dev/null || true)

echo ""
echo "=== Negative workflow fixtures (must fail) ==="
while IFS= read -r -d '' f; do validate_file "$f" "false"; done \
  < <(find "$WF_ROOT/_negative" -type f -name 'input.yaml' -print0 2>/dev/null || true)

echo ""
echo "=== Summary ==="
echo "Positive: $POS_PASS passed, $POS_FAIL failed"
echo "Negative: $NEG_PASS correctly rejected, $NEG_FAIL unexpectedly passed"

if [[ $POS_FAIL -gt 0 ]]; then exit 1; fi
if [[ $NEG_FAIL -gt 0 ]]; then exit 2; fi
echo -e "${GREEN}All workflow fixtures OK${NC}"
```

- [ ] **Step 2: Make it executable.**

Run: `chmod +x scripts/validate-workflows.sh`

- [ ] **Step 3: Commit.**

```bash
git add scripts/validate-workflows.sh
git commit -m "build: add validate-workflows.sh (workflow-level schema runner)"
```

---

## Task 9: Workflow-level fixtures (positive + negative)

**Files:**
- Create: `tests/fixtures/workflows/v8_minimal/input.yaml`
- Create: `tests/fixtures/workflows/v8_with_mcp/input.yaml`
- Create: `tests/fixtures/workflows/_negative/endings_block_rejected/input.yaml`
- Create: `tests/fixtures/workflows/_negative/default_error_not_ending/input.yaml`
- Create: `tests/fixtures/workflows/_negative/payload_type_bad_name/input.yaml`

- [ ] **Step 1: Positive — minimal v8 workflow.**

```yaml
# tests/fixtures/workflows/v8_minimal/input.yaml
name: v8-minimal
version: "1.0.0"
description: Minimal v8 workflow — a single action routing to an ending.

start_node: ack
default_error: error_generic

nodes:
  ack:
    type: action
    consequences:
      - type: display
        content: "Hello."
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

- [ ] **Step 2: Positive — v8 workflow exercising BL1/2/3/4 together.**

```yaml
# tests/fixtures/workflows/v8_with_mcp/input.yaml
name: v8-with-mcp
version: "1.0.0"
description: Workflow exercising trust_mode, data_mcps, payload_types, mcp_tool_call, ending.

trust_mode: stateless

data_mcps:
  eightball: "eightball-tools@^1"

payload_types:
  shake_params@1:
    question: "string (min_length=1)"
    context:  "string (optional)"

start_node: shake
default_error: error_generic

nodes:
  shake:
    type: action
    consequences:
      - type: mcp_tool_call
        tool: eightball.shake
        params_type: shake_params@1
        params:
          question: "${computed.question}"
        store_as: computed.answer
    on_success: done

  done:
    type: ending
    outcome: success
    message: "${computed.answer}"

  error_generic:
    type: ending
    outcome: error
    message: "Failed."
```

- [ ] **Step 3: Negative — top-level `endings:` block rejected.**

```yaml
# tests/fixtures/workflows/_negative/endings_block_rejected/input.yaml
# NEGATIVE: top-level endings: is forbidden in v8.
name: bad-endings-block
version: "1.0.0"
start_node: n1
default_error: done

nodes:
  n1:
    type: action
    consequences:
      - type: display
        content: "hi"
    on_success: done

endings:
  done:
    type: success
    message: "This should not be accepted."
```

- [ ] **Step 4: Negative — `default_error` pointing at a non-ending.**

Note: this negative relies on a cross-reference rule. The schema-level check cannot catch it (schema only checks that `default_error` is a node_reference string). This fixture is documented here for when a cross-reference validator is added; for now, it will *incorrectly pass* schema validation. Mark the dir with a README so Task 14 or a later plan can wire up cross-reference checking.

```yaml
# tests/fixtures/workflows/_negative/default_error_not_ending/input.yaml
# NEGATIVE (cross-reference only — not caught by current schema):
# default_error points at an action, not an ending.
name: bad-default-error
version: "1.0.0"
start_node: n1
default_error: n1  # <- should reference an ending, points at action

nodes:
  n1:
    type: action
    consequences:
      - type: display
        content: "hi"
    on_success: n1
```

```markdown
<!-- tests/fixtures/workflows/_negative/default_error_not_ending/README.md -->
# default_error_not_ending

Cross-reference-only negative. The schema alone does not enforce that `default_error`
points at a node of type `ending`. A future cross-reference validator (outside this
repo, likely in `hiivmind-blueprint-mcp`) should reject this fixture.

The `validate-workflows.sh` runner will currently report this as an UNEXPECTED PASS —
accept that for now; remove the fixture or add a cross-reference check later.
```

- [ ] **Step 5: Negative — payload type with bad name.**

```yaml
# tests/fixtures/workflows/_negative/payload_type_bad_name/input.yaml
# NEGATIVE: payload_types keys must match ^[a-z_][a-z0-9_]*@\d+$ — 'Foo@1' is wrong case.
name: bad-payload-type-name
version: "1.0.0"
start_node: done
default_error: done

payload_types:
  Foo@1:
    bar: string

nodes:
  done:
    type: ending
    outcome: success
```

- [ ] **Step 6: Run the workflow validator.**

Run: `bash scripts/validate-workflows.sh`

Expected:

```
=== Positive workflow fixtures (must pass) ===
OK    tests/fixtures/workflows/v8_minimal/input.yaml
OK    tests/fixtures/workflows/v8_with_mcp/input.yaml

=== Negative workflow fixtures (must fail) ===
OK    tests/fixtures/workflows/_negative/endings_block_rejected/input.yaml (correctly rejected)
UNEXPECTED PASS  tests/fixtures/workflows/_negative/default_error_not_ending/input.yaml
OK    tests/fixtures/workflows/_negative/payload_type_bad_name/input.yaml (correctly rejected)

Summary: 2 passed, 0 failed | 2 correctly rejected, 1 unexpectedly passed
```

Note: the script exits 2 because of the unexpected pass. That's expected per Step 4's README — we document the gap rather than hide it. Decide now whether to: (a) delete the cross-reference-only negative, (b) comment it out with a `# SKIP:` marker, or (c) add a `--skip-cross-ref` flag to the runner. Minimal disruption: **delete** the fixture + README (Step 4 above) and file an issue to add cross-reference checking later.

- [ ] **Step 7: Delete the cross-reference-only fixture and its README (to keep CI green).**

```bash
rm -r tests/fixtures/workflows/_negative/default_error_not_ending/
```

- [ ] **Step 8: Re-run validator. Expected: all pass.**

Run: `bash scripts/validate-workflows.sh`

Expected exit code 0, "All workflow fixtures OK".

- [ ] **Step 9: Commit.**

```bash
git add tests/fixtures/workflows/
git commit -m "test: workflow-level fixtures for v8 schema (BL2/3/4/5)

Cross-reference-only negative (default_error_not_ending) was prototyped
then removed; the schema alone cannot enforce that default_error targets
an ending. Track follow-up in issue for cross-reference validation."
```

---

## Task 10: Add `ending` catalog entry to `blueprint-types.md`

**Files:**
- Modify: `blueprint-types.md`

- [ ] **Step 1: Add the `ending` signature under `## Nodes`, after the `user_prompt` entry.**

Insert between `user_prompt(...)` and the `---` separator that precedes `## Preconditions`:

```
ending(outcome, message?, summary?, details?, category?,
       recovery?, behavior?, consequences?)
  outcome  ∈ {success, failure, error, cancelled, indeterminate}
  behavior = {type: silent | delegate | restart, …}  (optional; default: display message/summary)
  → terminate the workflow with the given outcome; run consequences
    (best-effort, logged on failure); then apply behavior.
    Schema forbids on_success/on_failure/on_true/on_false/on_unknown/on_response.
```

- [ ] **Step 2: Commit.**

```bash
git add blueprint-types.md
git commit -m "docs(catalog): add ending node type to blueprint-types.md (BL5)"
```

---

## Task 11: Add `mcp_tool_call` catalog entry

**Files:**
- Modify: `blueprint-types.md`

- [ ] **Step 1: Locate the `### Core — control` subsection under `## Consequences`.** It contains `create_checkpoint`, `rollback_checkpoint`, `spawn_agent`, `invoke_skill`, `inline`.

- [ ] **Step 2: Add `mcp_tool_call` entry between `invoke_skill` and `inline`.**

```
mcp_tool_call(tool, params, params_type?, store_as?)
  tool        = "<alias>.<tool_name>" — alias declared in workflow data_mcps:
  params      = map of literals + ${} state interpolation
  params_type = optional reference to a payload type declared in the workflow's
                payload_types: block (name@version)
  store_as    = optional state field to receive the tool result
  → invoke an MCP tool via the caller's MCP client; store the tool result at
    store_as if provided. The catalog describes the *effect*; whether the
    runtime calls the tool directly or emits a tool reference for the LLM's
    own MCP client to invoke is an execution-guide concern.
```

- [ ] **Step 3: Commit.**

```bash
git add blueprint-types.md
git commit -m "docs(catalog): add mcp_tool_call consequence to blueprint-types.md (BL1)"
```

---

## Task 12: Add `## Payload Types` section to `blueprint-types.md`

**Files:**
- Modify: `blueprint-types.md`

- [ ] **Step 1: Add a new `## Payload Types` section at the end of the file, after the last `---`.**

```markdown
---

## Payload Types

Workflows declare payload types at the top in a `payload_types:` block. References
from consequences use the form `<name>@<version>`. No central registry — instances
live per-workflow only. Blueprint-lib's catalog documents *how* to declare payload
types; instances travel with the workflow.

### Declaration syntax

    <name>@<version>:
      <field>: <type descriptor>

### Scalar type descriptors

    string                           — UTF-8 text
    integer                          — int64
    boolean                          — true/false
    object                           — arbitrary map
    array<T>                         — homogeneous array of T
    enum{a, b, c}                    — one of the listed literals

### Constraints (optional, parenthesised after the type)

    min_length=N, max_length=N       — string, array
    min=N, max=N                     — integer
    pattern="regex"                  — string
    required / optional              — modifier (default: required)

### Example

    shake_params@1:
      question: string (min_length=1)
      context:  string (optional)
      max_tokens: integer (min=1, max=4096, optional)

### Load-time contract (enforced by downstream runtimes/loaders)

- Every consequence `params_type` reference MUST resolve to a key in the current
  workflow's `payload_types:` block. Unresolvable reference → `unresolved_params_type`.
- Entry keys MUST match `^[a-z_][a-z0-9_]*@\d+$` (schema-enforced).
- Blueprint-lib does NOT validate that a consequence's `params` block conforms to the
  referenced payload type's field list — that is runtime concern. Blueprint-lib only
  validates that the reference resolves.
```

- [ ] **Step 2: Commit.**

```bash
git add blueprint-types.md
git commit -m "docs(catalog): add Payload Types section to blueprint-types.md (BL2)"
```

---

## Task 13: Migrate `workflows/core/intent-detection.yaml`

**Files:**
- Modify: `workflows/core/intent-detection.yaml`

The bundled workflow currently uses a top-level `endings:` block. Migrate every entry into `nodes:` with `type: ending` and renamed `outcome:` field.

- [ ] **Step 1: Read the file, note every `endings:` entry.**

Run: `grep -n "^endings:\|^  [a-z]" workflows/core/intent-detection.yaml`

Expected: identifies the `endings:` block and each entry underneath.

- [ ] **Step 2: For each `endings:` entry, add an equivalent `nodes:` entry with `type: ending` and `outcome: <original type>`.**

Pattern:

```yaml
# Before
endings:
  done_routed:
    type: success
    message: "Routed to skill"
    summary: { ... }

# After (add to nodes:)
nodes:
  # ... existing nodes ...
  done_routed:
    type: ending
    outcome: success
    message: "Routed to skill"
    summary: { ... }
```

Preserve `category`, `message`, `summary`, `details`, `recovery`, `consequences`, `behavior` fields unchanged.

- [ ] **Step 3: Delete the top-level `endings:` block.**

- [ ] **Step 4: Validate the migrated workflow.**

```bash
mkdir -p /tmp/v8-validate
yq -o=json '.' workflows/core/intent-detection.yaml > /tmp/v8-validate/intent.json
npx --yes ajv-cli@5 validate --spec=draft2020 \
  -s schema/authoring/workflow.json \
  -r schema/authoring/node-types.json \
  -r schema/authoring/payload-types.json \
  -r schema/common.json \
  -d /tmp/v8-validate/intent.json \
  --strict=false
```

Expected: `/tmp/v8-validate/intent.json valid`.

- [ ] **Step 5: Commit.**

```bash
git add workflows/core/intent-detection.yaml
git commit -m "refactor(workflows)!: migrate intent-detection endings: to nodes: (BL5)"
```

---

## Task 14: Migrate `examples.md` (3 existing workflows)

**Files:**
- Modify: `examples.md`

For each of the three composite examples (source-onboarding, web-content-pipeline, intent-router), convert the `endings:` block into `nodes:` entries with `type: ending` and renamed `outcome:`.

- [ ] **Step 1: Migrate workflow 1 — source-onboarding.**

Find the `endings:` block in `## 1. Source Onboarding`. Convert each of `done`, `error_generic`, `error_config_read`, `error_clone_failed` into `nodes:` entries:

```yaml
# Append to nodes: (just before the closing of the code fence)
  done:
    type: ending
    outcome: success
    message: "Source onboarded: ${computed.source_id}"

  error_generic:
    type: ending
    outcome: error
    message: "Unexpected failure at ${current_node}"

  error_config_read:
    type: ending
    outcome: error
    message: "Failed to read config.yaml"

  error_clone_failed:
    type: ending
    outcome: failure
    message: "Clone failed for ${computed.repo_url}"
```

Delete the `endings:` block.

- [ ] **Step 2: Migrate workflow 2 — web-content-pipeline.**

Apply the same conversion for each entry in its `endings:` block: `done_processed`, `done_no_changes`, `done_cached`, `error_generic`, `error_no_source`, `error_no_python`, `error_empty_fetch`.

- [ ] **Step 3: Migrate workflow 3 — intent-router.**

Apply the same conversion for `exit_success` and `error_generic`.

- [ ] **Step 4: Commit.**

```bash
git add examples.md
git commit -m "docs(examples)!: migrate three composite examples endings: to nodes: (BL5)"
```

---

## Task 15: Add new composite example using BL1/2/3/4 to `examples.md`

**Files:**
- Modify: `examples.md`

- [ ] **Step 1: Add a fourth `## 4. MCP-Delegated Query` example at the end of `examples.md` (before any trailing horizontal-rule).**

```yaml
## 4. MCP-Delegated Query

Ask the user for a question, invoke an external MCP tool, display the answer.

**Types demonstrated:** `action`, `user_prompt`, `ending`, `mcp_tool_call`,
`mutate_state`, `display`

**New in v8:** workflow-level `trust_mode`, `data_mcps`, `payload_types`.

```yaml
name: mcp-delegated-query
version: "1.0.0"
description: Ask a yes/no question; delegate to an external MCP tool; display the result.

trust_mode: stateless

data_mcps:
  eightball: "eightball-tools@^1"

payload_types:
  shake_params@1:
    question: string (min_length=1)
    context:  string (optional)

start_node: ask
default_error: error_generic

nodes:
  ask:
    type: user_prompt
    prompt:
      question: "What is your yes/no question?"
      header: "8-Ball"
      options:
        - id: asked
          label: "Ask"
        - id: declined
          label: "Cancel"
    on_response:
      asked:
        consequences:
          - type: mutate_state
            operation: set
            field: computed.question
            value: "${user_responses.ask}"
        next_node: shake
      declined: cancelled

  shake:
    type: action
    consequences:
      - type: mcp_tool_call
        tool: eightball.shake
        params_type: shake_params@1
        params:
          question: "${computed.question}"
        store_as: computed.answer
    on_success: reveal

  reveal:
    type: action
    consequences:
      - type: display
        format: markdown
        content: "**8-ball says:** ${computed.answer}"
    on_success: done

  done:
    type: ending
    outcome: success
    message: "Done."

  cancelled:
    type: ending
    outcome: cancelled
    message: "No question asked."

  error_generic:
    type: ending
    outcome: error
    message: "Unexpected failure at ${current_node}"
```
```

(Note: the fenced block above contains a fenced block inside — when you edit, replicate both fences carefully.)

- [ ] **Step 2: Commit.**

```bash
git add examples.md
git commit -m "docs(examples): add MCP-delegated query example using BL1/2/3/4"
```

---

## Task 16: Migrate `README.md` snippets

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Grep for `^endings:` blocks in `README.md`.**

Run: `grep -n "^endings:" README.md`

- [ ] **Step 2: For each snippet containing `endings:`, rewrite into the v8 form (ending entries inside `nodes:` with `type: ending` + `outcome:`).**

Apply the same conversion used in Tasks 13–14. If the snippet is illustrative-only (not a complete workflow), at minimum rename `type: success` → `type: ending` with `outcome: success` and move the key under `nodes:`.

- [ ] **Step 3: Commit.**

```bash
git add README.md
git commit -m "docs(readme): migrate workflow snippets to v8 ending shape (BL5)"
```

---

## Task 17: Update `CLAUDE.md` node-primitive count

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Grep for references to the count of node types.**

Run: `grep -n "3 node types\|three node types\|primitive\|1 reusable workflow" CLAUDE.md`

- [ ] **Step 2: Update the top-of-file bulleted summary:**

Change:

```
- **22 consequence types** - Operations that workflows can execute
- **9 precondition types** - Conditions workflows can check
- **3 node types** - Building blocks for workflow graphs
- **1 reusable workflow** - Intent detection with 3-valued logic
```

To:

```
- **23 consequence types** - Operations that workflows can execute (includes mcp_tool_call)
- **9 precondition types** - Conditions workflows can check
- **4 node types** - Building blocks for workflow graphs (action, conditional, user_prompt, ending)
- **1 reusable workflow** - Intent detection with 3-valued logic
- **Payload Types** - Per-workflow data-shape declarations
```

- [ ] **Step 3: Commit.**

```bash
git add CLAUDE.md
git commit -m "docs(claude): update type counts for v8 (4 node primitives, 23 consequences, payload types)"
```

---

## Task 18: Bump `package.yaml` to v8.0.0

**Files:**
- Modify: `package.yaml`

- [ ] **Step 1: Bump version.**

Change:

```yaml
version: "7.2.0"
```

To:

```yaml
version: "8.0.0"
```

- [ ] **Step 2: Update stats.**

Replace the `stats:` block with:

```yaml
stats:
  total_types: 36
  consequence_types: 23
  precondition_types: 9
  node_types: 4        # primitives: action, conditional, user_prompt, ending
  composite_types: 3   # confirm, gated_action, goal_seek (authoring-time sugar)
  payload_type_convention: true
  workflows: 1
```

- [ ] **Step 3: Update the schema versions under `schemas:`.**

Change:

```yaml
schemas:
  workflow: "3.0"
  node: "3.2"
```

To:

```yaml
schemas:
  workflow: "4.0"
  node: "4.0"
  payload_types: "1.0"
```

- [ ] **Step 4: Update `description` if it mentions type counts.**

The current description says `22 consequence types, 9 precondition types, and 3 node types`. Update to `23 consequence types, 9 precondition types, and 4 node types (action, conditional, user_prompt, ending)`.

- [ ] **Step 5: Update `minimum_blueprint_version`** if the spec or CHANGELOG mandates a new minimum — leave at `7.0.0` unless policy states otherwise.

- [ ] **Step 6: Commit.**

```bash
git add package.yaml
git commit -m "chore: bump package.yaml to v8.0.0 + update stats"
```

---

## Task 19: Add v8.0.0 entry to `CHANGELOG.md`

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Insert a new `## [8.0.0] - 2026-04-17` block above the existing `## [7.2.0]` entry.**

```markdown
## [8.0.0] - 2026-04-17

### Added
- `ending` node type (BL5). Fourth primitive; lives in `nodes:`. Retires the top-level `endings:` block. Signature: `ending(outcome, message?, summary?, details?, category?, recovery?, behavior?, consequences?)` with `outcome ∈ {success, failure, error, cancelled, indeterminate}` and optional `behavior: {silent | delegate | restart}`.
- `mcp_tool_call` consequence (BL1). Invokes a tool on a workflow-declared `data_mcps:` alias. Optional `params_type` references a per-workflow payload type declaration.
- `## Payload Types` section in `blueprint-types.md` (BL2). Documents the *convention* for per-workflow payload type declarations; no central registry of instances.
- `trust_mode` workflow field (BL3). Enum `{stateless, gated}`, default `stateless`.
- `data_mcps` workflow field (BL4). Map of alias to `"name@semver-range"`.
- `payload_types` workflow field (BL2). Map of `<name>@<version>` to field descriptors.
- `schema/authoring/payload-types.json` (new schema file).
- `scripts/validate-workflows.sh` — workflow-level schema validation runner.
- Fixture tree `tests/fixtures/endings/` and `tests/fixtures/workflows/` with positive + negative coverage.
- New composite example in `examples.md`: `MCP-Delegated Query` using `mcp_tool_call`, `payload_types`, `data_mcps`, `trust_mode`, `ending`.

### Changed (BREAKING)
- **Removed top-level `endings:` block.** All workflows must now place terminal states as `type: ending` entries under `nodes:`, with the old `type:` field renamed to `outcome:`. A top-level `endings:` key is rejected at load time.
- `schema/authoring/workflow.json` bumped to schema version 4.0.
- `schema/authoring/node-types.json` bumped to schema version 4.0 (adds `ending` to enum + dispatch + `ending_node` `$def`).
- `default_error`: description updated — target must resolve to a node of type `ending`. (Cross-reference enforcement left to consuming runtimes.)
- `workflows/core/intent-detection.yaml` migrated to v8 shape.
- `examples.md` migrated: all three composite examples restructured with ending nodes.
- `README.md` workflow snippets migrated.

### Migration

**No backwards compatibility.** Convert every workflow's `endings:` entries into `nodes:` entries:

```yaml
# Before (v7)
endings:
  done:
    type: success
    message: "OK"

# After (v8)
nodes:
  done:
    type: ending
    outcome: success
    message: "OK"
```

Transitions that previously named ending ids (`on_success: done`) are unchanged — they now resolve within the `nodes:` map. The optional helper `scripts/migrate-v7-to-v8.sh` (if shipped) automates the structural rewrite.

### Cross-repo

- `hiivmind-blueprint/lib/patterns/authoring-guide.md` — type tables updated; new sections for ending authoring, payload types, `mcp_tool_call`.
- `hiivmind-blueprint/lib/patterns/execution-guide.md` — dispatch semantics for ending (terminal logic) + `mcp_tool_call` invocation topology (runtime vs LLM-client).
- Downstream walker in `hiivmind-blueprint-mcp` requires a verification pass against new fixtures; no walker-contract changes expected.
```

- [ ] **Step 2: Commit.**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): add v8.0.0 entry (BL1–BL5)"
```

---

## Task 20: Cross-repo — update `hiivmind-blueprint/lib/patterns/authoring-guide.md`

**Files:**
- Modify (other repo): `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/patterns/authoring-guide.md`

This task's commit lands in the `hiivmind-blueprint` repo, NOT blueprint-lib.

- [ ] **Step 1: Change directory.**

Run: `cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint`

- [ ] **Step 2: Locate the primitive-node-types table in `lib/patterns/authoring-guide.md`.**

Run: `grep -n "action\|conditional\|user_prompt" lib/patterns/authoring-guide.md | head -20`

- [ ] **Step 3: Add an `ending` row to the primitive-node-types table.**

Add after the `user_prompt` row. Columns should mirror the existing columns (typically: Name, Purpose, Key fields, Terminality). For `ending`:

```
| `ending` | Terminal state. Emit outcome; run consequences; apply behavior. | `outcome`, `message?`, `behavior?` | Always terminal. |
```

- [ ] **Step 4: Add a short authoring section for `mcp_tool_call` under the Consequences authoring chapter.**

Include the signature, a minimal example, and a cross-link to the workflow-level `data_mcps:` declaration.

- [ ] **Step 5: Add a short authoring section for Payload Types.**

Cover: where they're declared (workflow-level `payload_types:` block), the `<name>@<version>` key pattern, the field descriptor syntax (string / integer / etc. with constraints), the `params_type` reference convention.

- [ ] **Step 6: Add a short section for `trust_mode` and `data_mcps` as workflow-level declarations.**

- [ ] **Step 7: Commit in the hiivmind-blueprint repo.**

```bash
git add lib/patterns/authoring-guide.md
git commit -m "docs(patterns): update authoring-guide for blueprint-lib v8.0 (BL1–BL5)

Adds ending node row to primitives table; new sections for mcp_tool_call,
Payload Types authoring, and trust_mode/data_mcps workflow fields."
```

- [ ] **Step 8: Return to blueprint-lib for subsequent tasks.**

Run: `cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib`

---

## Task 21: Cross-repo — update `hiivmind-blueprint/lib/patterns/execution-guide.md`

**Files:**
- Modify (other repo): `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/patterns/execution-guide.md`

This task's commit also lands in `hiivmind-blueprint`.

- [ ] **Step 1: Change directory.**

Run: `cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint`

- [ ] **Step 2: Locate the node dispatch / execution semantics section.**

Run: `grep -n "action\|conditional\|user_prompt\|terminal\|transition" lib/patterns/execution-guide.md | head -20`

- [ ] **Step 3: Add a subsection covering `ending` dispatch.**

Content:

- Reaching an `ending` node emits `terminal: true` (or runtime-equivalent) and stops the FSM.
- Execute `consequences` best-effort; errors are logged but do not prevent termination.
- Apply `behavior` after `consequences`: `silent` (no output), `delegate` (hand off to skill), `restart` (re-enter from `target_node` bounded by `max_restarts`).
- `restart` is NOT a new transition — it is a post-termination re-entry. Emit the outcome first, then the runtime re-enters.

- [ ] **Step 4: Add a subsection for `mcp_tool_call` invocation topology.**

Content:

- `mcp_tool_call` is a generic dispatcher. Two valid topologies:
  1. **Runtime-invokes:** the runtime has an MCP client and calls the tool directly; result stored at `store_as`.
  2. **LLM-invokes:** the runtime emits a tool reference in its response; the enclosing LLM agent invokes the tool via its own MCP client; the next FSM tick receives the result (details vary by runtime).
- Resolution: the workflow's `data_mcps:` alias is looked up; the alias's `"name@semver-range"` is matched against connected data-MCPs.
- `params_type` (if present) is resolved against the workflow's `payload_types:` block at load time; runtime-time shape validation of `params` against the payload type is the runtime's choice.

- [ ] **Step 5: Commit in hiivmind-blueprint.**

```bash
git add lib/patterns/execution-guide.md
git commit -m "docs(patterns): update execution-guide for blueprint-lib v8.0 (BL1, BL5)

Adds ending dispatch semantics (terminal + behavior) and mcp_tool_call
invocation-topology guidance (runtime-invokes vs LLM-invokes)."
```

- [ ] **Step 6: Return to blueprint-lib.**

Run: `cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib`

---

## Task 22: (Optional) Migration helper script

**Files:**
- Create: `scripts/migrate-v7-to-v8.sh`

Skip if time-boxed.

- [ ] **Step 1: Write the script.**

```bash
#!/usr/bin/env bash
#
# migrate-v7-to-v8.sh — Convert a v7 workflow.yaml's endings: block into nodes: entries.
#
# Usage: scripts/migrate-v7-to-v8.sh <workflow.yaml> [<workflow.yaml> ...]
#
# In-place edit. Requires yq v4+.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <workflow.yaml> [<workflow.yaml> ...]" >&2
  exit 2
fi

command -v yq >/dev/null 2>&1 || { echo "yq not found" >&2; exit 3; }

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    echo "skip: $file (not found)" >&2
    continue
  fi

  # Only run if there is a top-level endings: block.
  if ! yq -e '.endings' "$file" >/dev/null 2>&1; then
    echo "skip: $file (no endings: block)" >&2
    continue
  fi

  # For each endings.<id>, copy to nodes.<id> with type: ending and
  # rename the original .type field (success/failure/…) to .outcome.
  yq -i '
    (.endings | to_entries) as $endings
    | .nodes = (.nodes // {})
    | .nodes += (
        $endings
        | map(. as $e
              | .value
              | .outcome = .type
              | .type = "ending"
              | {($e.key): .})
        | add
      )
    | del(.endings)
  ' "$file"

  echo "migrated: $file"
done
```

- [ ] **Step 2: Make executable + commit.**

```bash
chmod +x scripts/migrate-v7-to-v8.sh
git add scripts/migrate-v7-to-v8.sh
git commit -m "build(scripts): add migrate-v7-to-v8.sh YAML rewriter"
```

---

## Task 23: Final repo-wide verification

**Files:** no new files.

- [ ] **Step 1: Repo-wide grep for any remaining `^endings:` in YAML or markdown.**

Run: `grep -rn "^endings:" . --include="*.yaml" --include="*.md" --exclude-dir=docs --exclude-dir=.git`

Expected: no output. (Intentionally exclude `docs/` because specs/plans reference the historical form.)

If output exists: investigate each site and either migrate or add an explicit comment indicating it's historical context.

- [ ] **Step 2: Run both validators.**

```bash
bash scripts/validate-fixtures.sh
bash scripts/validate-workflows.sh
```

Expected: both exit 0 with `All fixtures OK` / `All workflow fixtures OK`.

- [ ] **Step 3: Validate the bundled workflow against the new schema.**

```bash
mkdir -p /tmp/v8-final
yq -o=json '.' workflows/core/intent-detection.yaml > /tmp/v8-final/intent.json
npx --yes ajv-cli@5 validate --spec=draft2020 \
  -s schema/authoring/workflow.json \
  -r schema/authoring/node-types.json \
  -r schema/authoring/payload-types.json \
  -r schema/common.json \
  -d /tmp/v8-final/intent.json \
  --strict=false
```

Expected: `/tmp/v8-final/intent.json valid`.

- [ ] **Step 4: Skim the changelog entry, version bump, and README to confirm internal consistency.**

Visual review only — no automated check.

- [ ] **Step 5: Final commit (if any drift found and fixed, commit; otherwise skip).**

---

## Self-review notes

The plan completes when Task 23 reports clean validators + clean repo-wide grep. Version bump and CHANGELOG land in Tasks 18–19; they can be verified by inspection during Task 23 Step 4.

**Spec coverage verification:**

| Spec requirement | Task(s) |
|---|---|
| BL1 `mcp_tool_call` catalog entry | Task 11 |
| BL1 load-time contract rules | Catalog entry + documentation in CHANGELOG; no schema change (consequence-agnostic) |
| BL2 Payload Types catalog section | Task 12 |
| BL2 `payload-types.json` schema | Task 5 |
| BL2 `payload_types:` workflow field | Task 6 |
| BL3 `trust_mode` workflow field | Task 6 |
| BL4 `data_mcps` workflow field | Task 6 |
| BL5 `ending` node catalog entry | Task 10 |
| BL5 `ending_node` $def + enum + dispatch | Task 4 |
| BL5 `endings:` top-level block removed | Task 7 |
| BL5 fixtures (positive + negative) | Tasks 1, 2 |
| Examples migrated | Task 14 |
| New example using BL1/2/3/4 | Task 15 |
| Bundled workflow migrated | Task 13 |
| README migrated | Task 16 |
| CLAUDE.md stats updated | Task 17 |
| package.yaml bumped + stats | Task 18 |
| CHANGELOG entry | Task 19 |
| hiivmind-blueprint authoring-guide updated | Task 20 |
| hiivmind-blueprint execution-guide updated | Task 21 |
| Walker verification follow-up | Tracked in CHANGELOG (Task 19); executed in hiivmind-blueprint-mcp out-of-band |
| Migration script (optional) | Task 22 |
| Final verification | Task 23 |

All spec requirements mapped. No dangling "TBD" / "later" placeholders in the plan.
