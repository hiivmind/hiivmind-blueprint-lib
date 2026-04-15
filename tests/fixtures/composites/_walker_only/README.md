# Walker-contract-only fixtures

Fixtures in this directory are **structurally valid YAML** that the authoring
JSON schema cannot reject. They represent authoring errors that only the
walker (in `hiivmind-blueprint-mcp`) can catch at expansion time via graph-level
analysis (reachability, return-edge tracing, etc.).

This directory is **excluded from `scripts/validate-fixtures.sh`**. It exists
as a cross-repo contract: walker test suites should consume these fixtures
and assert rejection with a clear diagnostic.

## Index

- `goal_terminal_escapes_loop/` — a `goal_seek` sub-process whose terminal
  routes to a node outside the loop. The walker must reject with an error
  identifying the offending goal and terminal node.
