---
name: prepare-release
version: 0.1.0
description: >
  Create a release branch, bump version, update changelog, and open a PR to main.
  Automates the documented release workflow in RELEASING.md. Use this skill when:
  preparing a production release, creating a release branch, cutting a release,
  shipping a new version. Trigger phrases: "prepare release", "cut release",
  "release branch", "ship version", "create release", "start release",
  "new release", "release to main", "production release", "prepare for release".
---

# Prepare Release

Automate the full release workflow: create a `release/*` branch, bump version files, draft changelog, commit, push, and open a PR targeting `main`.

## Path Convention

`{PLUGIN_ROOT}` = Plugin root directory (where `.claude-plugin/plugin.json` lives)

When this skill references files like `{PLUGIN_ROOT}/lib/patterns/version-discovery.md`, read from the plugin root, not relative to this skill folder.

## Scope

| Does | Does NOT |
|------|----------|
| Create `release/vX.Y.Z` branch | Merge PRs |
| Analyze changes and recommend semver bump | Push tags (release workflow does this) |
| Update version files and changelog | Create GitHub Releases (release workflow does this) |
| Commit and push the release branch | Deploy or publish |
| Create PR to `main` via `gh pr create` | |

## Relationship to pr-version-bump

This skill reuses the same version analysis logic (Phases 2-4 of `pr-version-bump`) but adds release branch creation and enforces the `release/*` branching convention required by `RELEASING.md`.

| Skill | When to Use |
|-------|-------------|
| `/pr-version-bump` | Already on the correct branch, just need to bump + PR |
| `/prepare-release` | Starting from any branch, need the full release flow |

---

## Phase 1: CONTEXT

Establish the working context and validate preconditions.

### Steps

1. **Check for dirty working tree:**
   ```bash
   git status --porcelain
   ```
   If output is non-empty, STOP with: "You have uncommitted changes. Commit or stash them before preparing a release."

2. **Get current branch:**
   ```bash
   git branch --show-current
   ```

3. **Check if already on a release branch:**
   - If current branch matches `release/*`: note this — skip Phase 3 (branch creation)
   - Otherwise: will create a new release branch in Phase 3

4. **Ensure main is up to date:**
   ```bash
   git fetch origin main
   ```

5. **Identify merge base:**
   ```bash
   git merge-base origin/main HEAD
   ```

6. **Report context:**
   ```
   Branch: feature/simplify_bootstrap
   Base: origin/main (diverged at abc1234)
   Action: Will create release branch
   ```

### STOP: If working tree is dirty

---

## Phase 2: VERSION

Determine the target version for this release.

### If explicit version provided

If the user passed a version argument (e.g., `/prepare-release 4.0.0`):
- Validate it is valid semver (`X.Y.Z`)
- Strip leading `v` if present
- Skip to Phase 2 confirmation
- No change analysis needed

### If no explicit version (auto-detect)

Reuse the analysis logic from `pr-version-bump`:

1. **Read pattern references:**
   - `{PLUGIN_ROOT}/lib/patterns/version-discovery.md`
   - `{PLUGIN_ROOT}/lib/patterns/change-classification.md`

2. **Discover version infrastructure** (pr-version-bump Phase 2):
   - Scan for version files: `package.yaml`, `.claude-plugin/plugin.json`
   - Extract current version
   - Detect changelog format

3. **Analyze changes** (pr-version-bump Phase 3):
   ```bash
   git log origin/main..HEAD --oneline --no-merges
   git diff origin/main...HEAD --stat
   git diff origin/main...HEAD --name-status
   ```
   - Classify changes using `change-classification.md`
   - Build evidence table

4. **Recommend version** (pr-version-bump Phase 4):
   - Determine bump level (MAJOR > MINOR > PATCH)
   - Calculate new version

### STOP: Present version recommendation and wait for confirmation

```
## Version Recommendation

Current: 3.1.0 → Recommended: 3.2.0 (MINOR)

### Evidence
| Evidence | Source | Signal |
|----------|--------|--------|
| New workflow added | workflows/ diff | MINOR |

Accept 3.2.0, override, or cancel?
```

Offer choices:
- "Accept MINOR (3.2.0)" (or whatever was recommended)
- "Override to MAJOR (4.0.0)"
- "Override to PATCH (3.1.1)"
- "Cancel"

---

## Phase 3: BRANCH

Create the release branch. **Skip this phase if already on a `release/*` branch.**

### Steps

1. **Create release branch from current HEAD:**
   ```bash
   git checkout -b release/vX.Y.Z
   ```

2. **Push with tracking:**
   ```bash
   git push -u origin release/vX.Y.Z
   ```

3. **Confirm:**
   ```
   Created and pushed branch: release/vX.Y.Z
   ```

---

## Phase 4: BUMP

Update version files and changelog, then commit.

### Steps

1. **Update version file(s):**
   - `package.yaml`: update `version:` field
   - `.claude-plugin/plugin.json`: update `"version":` field
   - Any other version files discovered in Phase 2

2. **Draft changelog entry:**
   - Use Keep a Changelog format (matching existing `CHANGELOG.md`)
   - Place new entry after the header, before existing entries
   - Include today's date
   - Categorize changes:
     - `### Added` - New features
     - `### Changed` - Changes to existing functionality
     - `### Fixed` - Bug fixes
     - `### Removed` - Removed features
     - `### BREAKING CHANGES` - For MAJOR bumps

3. **Present draft for review:**
   Show the exact changes to each file.

### STOP: Confirm before making file mutations

4. **After user confirms, commit:**
   ```bash
   git add <version-files> CHANGELOG.md
   git commit -m "chore: Prepare release vX.Y.Z"
   ```

5. **Push:**
   ```bash
   git push
   ```

---

## Phase 5: PR

Create a pull request targeting `main`.

### Steps

1. **Create PR:**
   ```bash
   gh pr create --base main --title "Release vX.Y.Z" --body "$(cat <<'EOF'
   ## Summary

   Version bump: A.B.C → X.Y.Z (MAJOR|MINOR|PATCH)

   ### Changelog

   <paste changelog entry from Phase 4>

   ---
   Prepared by `/prepare-release`
   EOF
   )"
   ```

2. **Capture PR URL** from output.

---

## Phase 6: REPORT

Summarize the release preparation.

```
## Release Prepared

- Branch: release/vX.Y.Z
- Version: A.B.C → X.Y.Z
- Files updated: package.yaml, .claude-plugin/plugin.json, CHANGELOG.md
- Commit: abc1234 "chore: Prepare release vX.Y.Z"
- PR: https://github.com/hiivmind/hiivmind-blueprint-lib/pull/XX

### Next Steps

1. Review the PR and get approval
2. Merge the PR — GitHub Actions will automatically create a tagged release
3. After merge, configure "Validate PR Source Branch" as a required status check on main (first time only)
```

---

## Error Handling

| Error | Action |
|-------|--------|
| Not a git repository | STOP: "This directory is not a git repository." |
| Dirty working tree | STOP: "Commit or stash changes first." |
| No `main` branch | Try `master`, then STOP if neither exists |
| No commits since main | STOP: "No changes to release. Branch is up to date with main." |
| No version file found | STOP: "No version file detected." |
| Release branch already exists on remote | STOP: "Branch release/vX.Y.Z already exists. Delete it first or use a different version." |
| Tag already exists | STOP: "Tag vX.Y.Z already exists. Choose a different version." |
| On main branch | STOP: "Cannot prepare release from main. Switch to a feature or develop branch first." |
