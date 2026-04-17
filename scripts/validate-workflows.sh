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
SCHEMA_OUTPUT="$REPO_ROOT/schema/config/output-config.json"
SCHEMA_PROMPTS="$REPO_ROOT/schema/config/prompts-config.json"
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
      -r "$SCHEMA_OUTPUT" \
      -r "$SCHEMA_PROMPTS" \
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
