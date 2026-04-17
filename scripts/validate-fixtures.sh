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

# Wrapper schema that targets the authoring node def via $ref. Required
# because ajv-cli's -s flag takes a schema file, not a JSON pointer. We
# point ajv at this wrapper; it follows the absolute $ref to the node
# def registered under node-types.json's $id.
#
# IMPORTANT: the $ref URL below MUST match node-types.json's $id exactly.
# ajv registers the schema (via -r $SCHEMA_NODE below) under its $id and
# resolves the wrapper's $ref against that registration — so no network
# call occurs during validation. If node-types.json's $id ever changes
# (branch rename, repo move), update this URL in lockstep or the wrapper
# will fail to resolve (or worse, silently fall back to a network fetch).
WRAPPER_SCHEMA="$TMP_DIR/node-wrapper.json"
cat > "$WRAPPER_SCHEMA" <<'SCHEMA_EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$ref": "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/main/schema/authoring/node-types.json#/$defs/node"
}
SCHEMA_EOF

command -v yq  >/dev/null 2>&1 || { echo -e "${RED}yq not found${NC}"; exit 3; }
command -v npx >/dev/null 2>&1 || { echo -e "${RED}npx not found (install Node.js)${NC}"; exit 3; }

POS_PASS=0
POS_FAIL=0
NEG_PASS=0
NEG_FAIL=0

validate_file() {
    local yaml_file="$1"
    local expect_pass="$2"  # "true" for positive, "false" for negative

    # Each fixture is a map of node_id -> node_dict. Validate each node
    # individually against #/$defs/node (node-type-aware via allOf dispatch).
    local node_ids
    node_ids="$(yq -r 'keys | .[]' "$yaml_file")"

    local any_fail=false
    for node_id in $node_ids; do
        local node_json="$TMP_DIR/${node_id}.json"
        yq -o=json ".\"$node_id\"" "$yaml_file" > "$node_json"

        if npx --yes ajv-cli@5 validate --spec=draft2020 \
            -s "$WRAPPER_SCHEMA" \
            -r "$SCHEMA_NODE" \
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

# Positive roots
POS_ROOTS=(
  "$REPO_ROOT/tests/fixtures/composites"
  "$REPO_ROOT/tests/fixtures/endings"
)

# Negative roots (fixtures living under composites/_negative vs the new top-level _negative)
NEG_ROOT="$REPO_ROOT/tests/fixtures/_negative"
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

echo ""
echo "=== Summary ==="
echo "Positive: $POS_PASS passed, $POS_FAIL failed"
echo "Negative: $NEG_PASS correctly rejected, $NEG_FAIL unexpectedly passed"

if [[ $POS_FAIL -gt 0 ]]; then exit 1; fi
if [[ $NEG_FAIL -gt 0 ]]; then exit 2; fi
echo -e "${GREEN}All fixtures OK${NC}"
