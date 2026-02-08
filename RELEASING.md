# Releasing hiivmind-blueprint-lib

This document describes the release process for hiivmind-blueprint-lib.

## Overview

Releases are fully automated via GitHub Actions. When a pull request is merged, a release is created automatically based on the target branch:

| PR Target | Source Branch | Release Type | Tag Format |
|-----------|-------------|--------------|------------|
| `main` | `release/*`, `hotfix/*` | Production | `v3.1.0` |
| `develop` | `feature/*`, `bugfix/*` | RC | `v3.1.0-rc.1` |
| `feature/*`, `bugfix/*` | topic branches | Beta | `v3.1.0-beta.my-feature.1` |

Pre-release numbers (rc.N, beta.NAME.N) auto-increment based on existing releases.

## Branch Model

```
main ─────────────────────────────── production releases only
  ↑                    ↑
  release/v3.1.0       hotfix/fix-name
  ↑
develop ─────────────────────────── RC releases on merge
  ↑              ↑
  feature/foo    bugfix/bar ──────── beta releases on merge
```

| Branch | Purpose | PRs From | Release Type |
|--------|---------|----------|--------------|
| `main` | Production only | `release/*`, `hotfix/*` | Production (`vX.Y.Z`) |
| `develop` | Integration | `feature/*`, `bugfix/*` | RC (`vX.Y.Z-rc.N`) |
| `feature/*`, `bugfix/*` | Development | topic branches | Beta (`vX.Y.Z-beta.NAME.N`) |

## Version Pinning Strategy

Workflows reference this library using version specifiers:

| Reference | Example | Use Case |
|-----------|---------|----------|
| `@vX.Y.Z` | `@v3.1.0` | Production - pinned and reproducible |
| `@vX.Y.Z-rc.N` | `@v3.1.0-rc.1` | Testing RC before production release |
| `@vX.Y.Z-beta.NAME.N` | `@v3.1.0-beta.new-types.1` | Testing a specific feature branch |
| `@main` | `@main` | Latest production commit (not recommended) |
| `@develop` | `@develop` | Latest integration commit (not recommended) |

**Recommendation:** Always use exact version pins (`@v3.1.0`) in production workflows.

## Release Workflows

### Production Release

Standard flow for releasing a new version:

1. **Develop on a feature branch:**
   ```bash
   git checkout develop
   git checkout -b feature/my-feature
   # ... make changes ...
   git push -u origin feature/my-feature
   ```

2. **Merge to develop** (creates RC release):
   - Open PR: `feature/my-feature` -> `develop`
   - On merge, GitHub Actions creates `v3.1.0-rc.1`
   - Test the RC in consuming workflows

3. **Prepare release branch:**
   ```bash
   git checkout develop
   git checkout -b release/v3.1.0
   ```
   - Update `package.yaml` version to `3.1.0`
   - Update `.claude-plugin/plugin.json` version to `3.1.0`
   - Update `CHANGELOG.md` with release notes
   - Commit: `chore: Prepare release v3.1.0`
   - Or use `/pr-version-bump` to automate these steps

4. **Merge to main** (creates production release):
   - Open PR: `release/v3.1.0` -> `main`
   - On merge, GitHub Actions creates `v3.1.0` tag and GitHub Release

5. **Verify:**
   ```bash
   curl -sf "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v3.1.0/package.yaml" | head -5
   ```

### Hotfix Release

For urgent fixes to production:

1. **Branch from main:**
   ```bash
   git checkout main
   git checkout -b hotfix/fix-critical-bug
   ```

2. **Fix, bump version, update changelog:**
   - Update `package.yaml` to `3.1.1`
   - Update `.claude-plugin/plugin.json` to `3.1.1`
   - Add `CHANGELOG.md` entry

3. **Merge to main:**
   - Open PR: `hotfix/fix-critical-bug` -> `main`
   - On merge, GitHub Actions creates `v3.1.1` tag and GitHub Release

4. **Back-merge to develop:**
   ```bash
   git checkout develop
   git merge main
   git push
   ```

### Manual Trigger

For cases where you need to create a release without a PR merge:

```bash
# Production release from a specific branch
gh workflow run release.yaml -f release_type=production -f source_branch=release/v3.1.0

# RC release
gh workflow run release.yaml -f release_type=rc -f source_branch=develop

# Beta release
gh workflow run release.yaml -f release_type=beta -f source_branch=feature/my-feature
```

## Prerequisites

- Version in `package.yaml` follows semver (`X.Y.Z`)
- For production releases: `CHANGELOG.md` has an entry for the version
- For production releases: `.claude-plugin/plugin.json` version matches `package.yaml`

## Emergency Manual Release

If GitHub Actions is unavailable, use the legacy release script:

```bash
# Preview what will happen
./scripts/release.sh --dry-run

# Create and push the tag
./scripts/release.sh
```

**Note:** `scripts/release.sh` is deprecated for normal use. Prefer the automated PR-merge workflow.

## Backfilling Historical Tags

To tag an older commit retroactively:

```bash
# Preview
./scripts/release.sh --dry-run --backfill v1.0.0 d3936fd

# Execute
./scripts/release.sh --backfill v1.0.0 d3936fd
```

## Troubleshooting

### Tag Already Exists

If a tag collision occurs:

```bash
# Delete local tag
git tag -d v3.1.0

# Delete remote tag
git push origin :v3.1.0

# Delete the GitHub release (if created)
gh release delete v3.1.0 --yes

# Re-trigger via manual dispatch or re-merge
```

### Only release/hotfix branches can target main

This error means a feature or bugfix branch PR was opened against `main`. Change the PR target to `develop` instead.

### Pre-Release Number Wrong

Pre-release numbers are auto-incremented by counting existing releases. If a release was deleted, the count may skip. This is harmless - semver pre-release ordering is correct regardless.

### Private Repository Considerations

If this repository is private, raw GitHub URLs will return 404 for unauthenticated requests. Options:

1. **Make the repo public** - Recommended for libraries meant to be referenced by external workflows
2. **Use authenticated fetches** - Workflows would need a GitHub token
3. **Bundle types** - Include type definitions directly in dependent projects

### CHANGELOG Entry Not Found (Production)

Production releases extract notes from `CHANGELOG.md`. Format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Changed
- ...
```

If no entry is found, the release is still created with a default message, but a warning is emitted.

## Semantic Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes to type definitions or schemas
- **MINOR** (0.X.0): New types, workflows, or backwards-compatible features
- **PATCH** (0.0.X): Bug fixes, documentation updates

### Breaking Change Examples

- Removing a consequence or precondition type
- Renaming a type (without alias)
- Changing required parameters for a type
- Changing schema structure incompatibly

### Non-Breaking Examples

- Adding new consequence or precondition types
- Adding optional parameters to existing types
- Adding new workflows
- Documentation updates
