# Change Classification Pattern

How to analyze git changes and recommend a semantic version bump.

## Input Collection

Gather these inputs before classification:

```bash
# All commits since branching from main
git log main..HEAD --oneline --no-merges

# Full diff summary (files changed, insertions, deletions)
git diff main...HEAD --stat

# Detailed diff for classification
git diff main...HEAD --name-status
```

## Classification Pipeline

Apply these classifiers in order. The highest bump level wins.

### 1. Repository-Specific Rules (Highest Priority)

If semver rules were extracted from `CLAUDE.md` or `RELEASING.md` (see `version-discovery.md`), apply them first:

1. For each rule `(change_description, bump_level)`:
   - Check if the diff or commit messages match the description
   - Record matches with the rule text as evidence
2. The highest matched bump level from repo rules takes priority

### 2. Conventional Commit Analysis

Parse commit messages for conventional commit prefixes:

| Prefix | Bump | Notes |
|--------|------|-------|
| `feat!:` or `BREAKING CHANGE` in body | MAJOR | Explicit breaking change |
| `fix!:` or any `type!:` | MAJOR | Breaking fix or change |
| `feat:` | MINOR | New feature |
| `fix:` | PATCH | Bug fix |
| `docs:` | PATCH | Documentation only |
| `chore:` | PATCH | Maintenance |
| `refactor:` | PATCH | Code restructuring |
| `test:` | PATCH | Test changes |
| `ci:` | PATCH | CI/CD changes |
| `style:` | PATCH | Formatting only |
| `perf:` | PATCH | Performance improvement |

### 3. File-Level Heuristics (Fallback)

When commits lack conventional prefixes, analyze the diff by file:

| Signal | Files Affected | Bump |
|--------|---------------|------|
| Deletions in source directories | `*.yaml`, `*.json`, `*.py`, `*.ts` (not tests/docs) | MAJOR signal |
| Renamed source files | Any source file | MAJOR signal |
| New source files added | Any source directory | MINOR signal |
| Modified source files | Any source file | MINOR signal |
| Only docs/config changed | `*.md`, `*.txt`, config files | PATCH |
| Only tests changed | `test/`, `tests/`, `*_test.*`, `*.spec.*` | PATCH |

**Signal vs certainty:** File-level heuristics produce *signals*, not definitive classifications. Present them as evidence alongside a recommendation, not as absolute determinations.

### 4. Blueprint-Lib-Specific Heuristics

Activate when type definition YAML files are detected in the diff (e.g., `consequences/consequences.yaml`, `preconditions/preconditions.yaml`).

| Change | Bump | Detection |
|--------|------|-----------|
| Type removed from YAML | MAJOR | Key present in base, absent in HEAD |
| Required parameter removed | MAJOR | Parameter list shortened with `required: true` entry gone |
| Parameter renamed | MAJOR | Old name gone, new name added in same type |
| New type added | MINOR | New top-level key in type YAML |
| Optional parameter added | MINOR | New entry with `required: false` or `default:` present |
| Effect pseudocode changed | MINOR | `effect:` block differs |
| Description or docs changed | PATCH | Only `description:`, `brief:`, `detailed:` differ |
| Example changed | PATCH | Only `examples/` files differ |

## Output Format

Present classification results as:

```
## Change Analysis

**Commits analyzed:** N commits since branching from main
**Files changed:** N files (N insertions, N deletions)

### Classification Evidence

| Evidence | Source | Bump Signal |
|----------|--------|-------------|
| "Added new `foo_bar` type" | consequences.yaml diff | MINOR |
| "feat: Add foo_bar consequence" | commit abc1234 | MINOR |
| "Documentation fixes only" | CLAUDE.md rules | PATCH |

### Recommendation: MINOR bump

**Reasoning:** New type added (`foo_bar` consequence) with no breaking changes detected.
Current: 3.0.0 → Recommended: 3.1.0
```

## Edge Cases

- **No source changes:** If only CI, docs, or test files changed, recommend PATCH
- **Mixed signals:** If both MAJOR and MINOR signals exist, recommend MAJOR with full evidence
- **Empty diff:** If `git diff main...HEAD` is empty, abort - nothing to release
- **Squash merges:** When analyzing squash-merged PRs, use the PR diff rather than commit history since individual commits are lost
