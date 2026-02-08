---
name: prepare-release
description: Create a release branch, bump version, and open PR to main
arguments:
  - name: version
    description: "Explicit version to release (e.g. 4.0.0). If omitted, version is auto-detected."
    required: false
allowed_tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Edit
  - Write
  - AskUserQuestion
---

# Prepare Release Gateway

Route to the `prepare-release` skill to automate the release branch workflow.

## Argument Handling

| Input | Behavior |
|-------|----------|
| *(empty)* | Auto-detect version via change analysis (reuses pr-version-bump logic) |
| `4.0.0` | Use explicit version, skip analysis |
| `v4.0.0` | Strip leading `v`, use `4.0.0` |

## Execution

Invoke the skill:

```
Skill: prepare-release
```

Pass any version argument to Phase 2 (VERSION) of the skill.

## Examples

```
/prepare-release              → Auto-detect version from changes
/prepare-release 4.0.0        → Release as v4.0.0
/prepare-release v3.2.0       → Release as v3.2.0
```
