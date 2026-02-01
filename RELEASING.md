# Releasing hiivmind-blueprint-lib

This document describes the release process for hiivmind-blueprint-lib.

## Overview

Releases are managed through git tags. When a tag is pushed, GitHub Actions automatically creates a GitHub Release with notes extracted from CHANGELOG.md.

## Version Pinning Strategy

Workflows reference this library using version specifiers:

| Reference | Resolves To | Use Case |
|-----------|-------------|----------|
| `@v2.0.0` | Exact version | Production - pinned and reproducible |
| `@v2.0` | Latest patch in v2.0.x | Auto-patch updates (not yet supported) |
| `@v2` | Latest minor in v2.x.x | Development - tracks latest features |
| `@main` | Latest commit | Testing only - not recommended |

**Recommendation:** Always use exact version pins (`@v2.0.0`) in production workflows.

## Prerequisites

- Git access to the repository
- `yq` installed (for parsing package.yaml)
- GitHub CLI (`gh`) for workflow dispatch (optional)

## Release Workflow

### 1. Update Version and Changelog

1. Update `package.yaml` with the new version:
   ```yaml
   version: "2.1.0"
   ```

2. Add a changelog entry to `CHANGELOG.md`:
   ```markdown
   ## [2.1.0] - 2026-01-30

   ### Added
   - New feature X

   ### Changed
   - Improved Y
   ```

3. Commit these changes:
   ```bash
   git add package.yaml CHANGELOG.md
   git commit -m "chore: Prepare release v2.1.0"
   git push origin main
   ```

### 2. Create and Push Tag

Use the release script:

```bash
# Preview what will happen
./scripts/release.sh --dry-run

# Create and push the tag
./scripts/release.sh
```

Or manually:

```bash
git tag -a v2.1.0 -m "Release v2.1.0 - Brief description"
git push origin v2.1.0
```

### 3. Verify Release

1. Check GitHub for the new release: https://github.com/hiivmind/hiivmind-blueprint-lib/releases

2. Verify raw URLs work (for public repos):
   ```bash
   curl -sf "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/package.yaml" | head -5
   ```

3. Test in a workflow that uses this library

## Backfilling Historical Tags

To tag an older commit retroactively:

```bash
# Preview
./scripts/release.sh --dry-run --backfill v1.0.0 d3936fd

# Execute
./scripts/release.sh --backfill v1.0.0 d3936fd
```

## Release Script Reference

```bash
./scripts/release.sh [OPTIONS]

Options:
    --dry-run           Preview without making changes
    --backfill VERSION COMMIT
                        Tag a historical commit
    -h, --help          Show help
```

The script:
- Reads version from `package.yaml`
- Validates CHANGELOG.md has an entry for that version
- Checks the tag doesn't already exist
- Creates an annotated tag with changelog notes
- Pushes to origin

## GitHub Actions Workflow

The `.github/workflows/release.yaml` workflow:

- **Triggers:** On tag push (`v*`) or manual dispatch
- **Actions:**
  1. Validates tag format (semver)
  2. Verifies package.yaml version matches tag
  3. Extracts changelog notes
  4. Creates GitHub Release

### Manual Trigger

```bash
gh workflow run release.yaml -f tag=v2.1.0
```

## Troubleshooting

### Tag Already Exists

If you need to re-release the same version:

```bash
# Delete local tag
git tag -d v2.1.0

# Delete remote tag
git push origin :v2.1.0

# Re-create
./scripts/release.sh
```

### Private Repository Considerations

If this repository is private, raw GitHub URLs will return 404 for unauthenticated requests. Options:

1. **Make the repo public** - Recommended for libraries meant to be referenced by external workflows
2. **Use authenticated fetches** - Workflows would need a GitHub token
3. **Bundle types** - Include type definitions directly in dependent projects

### CHANGELOG Entry Not Found

The release script requires a changelog entry. Format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Changed
- ...
```

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
