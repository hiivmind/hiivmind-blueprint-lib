---
name: pr-version-bump
description: Analyze PR changes and prepare a semantic version bump
arguments:
  - name: mode
    description: "Operation mode: prepare (default) or finalize"
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

# PR Version Bump Gateway

Route to the `pr-version-bump` skill based on the requested mode.

## Mode Detection

Parse the `mode` argument (or first word of natural language input):

| Input | Mode | Action |
|-------|------|--------|
| *(empty)* | Prepare | Bump version, draft changelog, commit |
| `prepare` | Prepare | Same as above |
| `bump` | Prepare | Same as above |
| `finalize` | Finalize | Verify version bump and changelog before merge |
| `verify` | Finalize | Same as above |
| `check` | Finalize | Same as above |

## Execution

Invoke the skill:

```
Skill: pr-version-bump
```

Pass the detected mode to Phase 1 (CONTEXT) of the skill.

## Examples

```
/pr-version-bump              → Prepare mode
/pr-version-bump prepare      → Prepare mode
/pr-version-bump bump         → Prepare mode
/pr-version-bump finalize     → Finalize mode
/pr-version-bump verify       → Finalize mode
/pr-version-bump check        → Finalize mode
```
