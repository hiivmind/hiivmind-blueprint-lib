# PR Version Bump Examples

## Example 1: MINOR Bump - New Type Added

**Scenario:** A branch adds a new `batch_execute` consequence type.

**Phase 2 Discovery:**
- Version file: `package.yaml` at v3.0.0
- Changelog: `CHANGELOG.md` (Keep a Changelog)
- Semver rules: extracted from `CLAUDE.md` ("Add new types" = MINOR)

**Phase 3 Analysis:**
```
Commits: 2 commits since main
  abc1234 feat: Add batch_execute consequence type
  def5678 docs: Add batch_execute examples

Files changed:
  M consequences/consequences.yaml  (+45 lines)
  A examples/batch-execute.yaml     (+30 lines)
```

**Phase 4 Recommendation:**
```
Recommendation: MINOR bump (3.0.0 → 3.1.0)
Evidence:
  - "Add new types" = MINOR (CLAUDE.md rules)
  - "feat:" prefix = MINOR (conventional commit)
  - New content in consequences.yaml = MINOR (blueprint heuristic)
```

---

## Example 2: MAJOR Bump - Type Removed

**Scenario:** A branch removes the deprecated `spawn_agent` consequence.

**Phase 3 Analysis:**
```
Commits: 1 commit since main
  abc1234 feat!: Remove deprecated spawn_agent consequence

Files changed:
  M consequences/consequences.yaml  (-35 lines)
  M examples/spawn-agent.yaml       (deleted)
```

**Phase 4 Recommendation:**
```
Recommendation: MAJOR bump (3.0.0 → 4.0.0)
Evidence:
  - "Remove type or required parameter" = MAJOR (CLAUDE.md rules)
  - "feat!:" prefix = MAJOR (conventional commit)
  - Type key removed from consequences.yaml = MAJOR (blueprint heuristic)
```

---

## Example 3: Finalize Mode - All Checks Pass

**Scenario:** Running `/pr-version-bump finalize` on a branch that already has a version bump.

**Phase 6 Report:**
```
## Pre-Merge Verification

| Check | Status | Details |
|-------|--------|---------|
| Version bumped | PASS | 3.0.0 → 3.1.0 |
| Changelog entry | PASS | [3.1.0] - 2026-02-07 with 2 items |
| Version files in sync | PASS | package.yaml and .claude-plugin/plugin.json both 3.1.0 |

Ready to merge.
```

---

## Example 4: Finalize Mode - Missing Changelog

**Scenario:** Version was bumped in `package.yaml` but changelog was not updated.

**Phase 6 Report:**
```
## Pre-Merge Verification

| Check | Status | Details |
|-------|--------|---------|
| Version bumped | PASS | 3.0.0 → 3.1.0 |
| Changelog entry | FAIL | No [3.1.0] entry found in CHANGELOG.md |
| Version files in sync | WARN | .claude-plugin/plugin.json still at 3.0.0 |

Action needed:
- Add a [3.1.0] entry to CHANGELOG.md
- Update .claude-plugin/plugin.json to 3.1.0
- Run `/pr-version-bump prepare` to fix automatically
```
