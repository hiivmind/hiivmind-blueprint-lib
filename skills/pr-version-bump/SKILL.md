---
name: pr-version-bump
version: 0.1.0
description: >
  Analyze PR changes and prepare semantic version bumps with changelog entries. Use this skill when:
  preparing a branch for PR creation, bumping version before merge, finalizing a PR for release,
  checking if version was bumped, verifying changelog entries. Trigger phrases: "bump version",
  "version bump", "prepare release", "prepare PR", "finalize PR", "check version", "verify bump",
  "semver", "changelog", "what version should this be", "ready to merge", "pre-merge check",
  "update version", "draft changelog", "release prep", "version check", "bump and PR".
---

# PR Version Bump

Analyze git changes since branching from main, recommend a semantic version bump, update version files, draft a changelog entry, and prepare the branch for PR creation.

## Path Convention

`{PLUGIN_ROOT}` = Plugin root directory (where `.claude-plugin/plugin.json` lives)

When this skill references files like `{PLUGIN_ROOT}/lib/patterns/version-discovery.md`, read from the plugin root, not relative to this skill folder.

## Scope

| Does | Does NOT |
|------|----------|
| Analyze changes since main | Run release scripts |
| Detect version files and changelog | Push tags |
| Recommend semver bump with evidence | Merge branches |
| Update version files and changelog | Deploy or publish |
| Commit version bump changes | |
| Push branch and create PR via `gh pr create` | |

## Modes

| Mode | Trigger | Purpose |
|------|---------|---------|
| **Prepare** (default) | `prepare`, `bump`, or no args | Bump version, draft changelog, commit, push, create PR |
| **Finalize** | `finalize`, `verify`, `check` | Verify version bump and changelog exist before merge |

---

## Phase 1: CONTEXT

Establish the working context.

### Steps

1. **Verify not on main branch:**
   ```bash
   git branch --show-current
   ```
   If on `main` or `master`, STOP with: "Switch to a feature branch first. Version bumps should not be done directly on main."

2. **Identify base branch:**
   ```bash
   git merge-base main HEAD
   ```
   This is the point where the current branch diverged from main.

3. **Detect mode** from user input:
   - Empty / "prepare" / "bump" → **Prepare mode**
   - "finalize" / "verify" / "check" → **Finalize mode**

4. **Report context:**
   ```
   Branch: feature/my-feature
   Base: main (diverged at abc1234)
   Mode: Prepare
   ```

### STOP: If on main branch

---

## Phase 2: DISCOVER

Scan the repository for version infrastructure.

### Steps

1. **Read pattern reference:**
   Read `{PLUGIN_ROOT}/lib/patterns/version-discovery.md` for the detection algorithm.

2. **Scan for version files** in priority order:
   - `package.yaml` → look for `version:` field
   - `package.json` → look for `"version":` field
   - `pyproject.toml` → look for `version =` field
   - `.claude-plugin/plugin.json` → look for `"version":` field
   - `Cargo.toml`, `setup.cfg`, `VERSION`

3. **Scan for changelog:**
   - `CHANGELOG.md`, `CHANGES.md`, `HISTORY.md`
   - Detect format (Keep a Changelog, conventional, other)

4. **Extract semver rules** from:
   - `CLAUDE.md` → look for `## Versioning` section
   - `RELEASING.md` → look for semantic versioning guidance
   - `CONTRIBUTING.md` → look for versioning section

5. **Detect release automation:**
   - `scripts/release.sh`
   - `.github/workflows/release.yaml`
   - `Makefile` or `Justfile` release targets

6. **Check for additional version files** that should stay in sync:
   - If `package.yaml` has version, also check `.claude-plugin/plugin.json`
   - Flag any mismatches

### STOP: Present discovery summary for confirmation

```
## Version Infrastructure

| Component | Found | Details |
|-----------|-------|---------|
| Version file | package.yaml | v3.0.0 |
| Changelog | CHANGELOG.md | Keep a Changelog format |
| Semver rules | CLAUDE.md | 5 rules extracted |
| Release script | scripts/release.sh | Tag-based release |
| Additional version files | .claude-plugin/plugin.json | v3.0.0 (in sync) |
```

---

## Phase 3: ANALYZE

Examine all changes since branching from main.

### Steps

1. **Read pattern reference:**
   Read `{PLUGIN_ROOT}/lib/patterns/change-classification.md` for the classification algorithm.

2. **Collect commit history:**
   ```bash
   git log main..HEAD --oneline --no-merges
   ```

3. **Collect diff summary:**
   ```bash
   git diff main...HEAD --stat
   git diff main...HEAD --name-status
   ```

4. **Classify changes** using the pipeline from `change-classification.md`:
   - Apply repository-specific rules (from Phase 2) first
   - Parse conventional commit prefixes
   - Apply file-level heuristics as fallback
   - Apply blueprint-lib-specific heuristics if type YAML files changed

5. **Build evidence table:**

   | Evidence | Source | Bump Signal |
   |----------|--------|-------------|
   | ... | ... | ... |

### STOP: Present change analysis summary

---

## Phase 4: RECOMMEND

Map classified changes to a semver recommendation.

### Steps

1. **Determine bump level:**
   - Take the highest signal from the evidence table
   - MAJOR > MINOR > PATCH

2. **Calculate new version:**
   - Current: `X.Y.Z` (from Phase 2)
   - MAJOR → `X+1.0.0`
   - MINOR → `X.Y+1.0`
   - PATCH → `X.Y.Z+1`

3. **Present recommendation:**
   ```
   ## Recommendation: MINOR bump

   Current: 3.0.0 → Recommended: 3.1.0

   ### Evidence
   | Evidence | Source | Signal |
   |----------|--------|--------|
   | New consequence type `foo` added | consequences.yaml diff | MINOR |
   | feat: Add foo consequence | commit abc1234 | MINOR |

   ### Reasoning
   New type added with no breaking changes. All existing types unchanged.
   ```

4. **Offer override:**
   - "Accept MINOR (3.1.0)"
   - "Override to MAJOR (4.0.0)"
   - "Override to PATCH (3.0.1)"
   - "Skip version bump"

### STOP: Wait for user to select bump level

---

## Phase 5: EXECUTE

Apply the version bump and draft changelog.

**Only runs in Prepare mode.** In Finalize mode, skip to Phase 6.

### Steps

1. **Update version file(s):**
   - Update the primary version file (e.g., `package.yaml`)
   - Update any additional version files found in Phase 2 (e.g., `.claude-plugin/plugin.json`)

2. **Draft changelog entry:**
   - Use the format detected in Phase 2
   - Place new entry after the changelog header, before existing entries
   - Include today's date
   - Categorize changes using Keep a Changelog sections:
     - `### Added` - New features
     - `### Changed` - Changes to existing functionality
     - `### Fixed` - Bug fixes
     - `### Removed` - Removed features
     - `### BREAKING CHANGES` - For MAJOR bumps

3. **Present draft for review:**
   Show the exact changes that will be made to each file.

4. **After user confirms, commit:**
   ```bash
   git add <version-files> <changelog>
   git commit -m "chore: Prepare release vX.Y.Z"
   ```

5. **Push branch to remote:**
   ```bash
   git push -u origin <branch-name>
   ```

6. **Create pull request:**
   Reference `{SKILL_ROOT}/resources/pull-requests.md` for `gh pr create` syntax.
   ```bash
   gh pr create --title "Release vX.Y.Z" --body "$(cat <<'EOF'
   ## Summary

   Version bump: A.B.C → X.Y.Z (MAJOR|MINOR|PATCH)

   ### Changelog

   <paste changelog entry from step 2>

   ---
   Prepared by `/pr-version-bump`
   EOF
   )"
   ```
   Capture and store the PR URL from the output.

### STOP: Confirm before making file mutations

---

## Phase 6: REPORT

Summarize what was done and offer next steps.

### Prepare Mode Report

```
## Version Bump Complete

- Version: 3.0.0 → 3.1.0
- Files updated: package.yaml, .claude-plugin/plugin.json
- Changelog: CHANGELOG.md updated with [3.1.0] entry
- Commit: abc1234 "chore: Prepare release v3.1.0"
- PR: https://github.com/hiivmind/hiivmind-blueprint-lib/pull/XX

### Next Steps

1. Review the PR and get approval
2. Merge the PR -- GitHub Actions will automatically create a tagged release
```

### Finalize Mode Report

In Finalize mode, Phase 6 checks instead of executes:

1. **Check version bumped:**
   - Compare version in HEAD vs main
   - PASS if version is higher, FAIL if unchanged

2. **Check changelog updated:**
   - Look for an entry matching the new version number
   - PASS if found with content, FAIL if missing

3. **Report results:**
   ```
   ## Pre-Merge Verification

   | Check | Status | Details |
   |-------|--------|---------|
   | Version bumped | PASS | 3.0.0 → 3.1.0 |
   | Changelog entry | PASS | [3.1.0] - 2026-02-07 with 3 items |
   | Version files in sync | PASS | package.yaml and plugin.json both 3.1.0 |

   Ready to merge.
   ```

   Or if checks fail:
   ```
   ## Pre-Merge Verification

   | Check | Status | Details |
   |-------|--------|---------|
   | Version bumped | FAIL | Still 3.0.0 - no bump detected |
   | Changelog entry | FAIL | No [3.1.0] entry found |

   Run `/pr-version-bump prepare` to fix.
   ```

---

## Error Handling

| Error | Action |
|-------|--------|
| Not a git repository | STOP: "This directory is not a git repository." |
| No `main` branch | Try `master`, then STOP if neither exists |
| No commits since main | STOP: "No changes to version. Branch is up to date with main." |
| No version file found | STOP: "No version file detected. Create a package.yaml, package.json, or pyproject.toml first." |
| Uncommitted changes | Warn: "You have uncommitted changes. Commit or stash them before bumping version." |
| Version already bumped | In Prepare mode, warn and offer to re-bump or skip |
