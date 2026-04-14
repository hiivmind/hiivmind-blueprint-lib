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
