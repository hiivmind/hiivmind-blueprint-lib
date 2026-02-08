# Version Discovery Pattern

How to locate and parse version information in any repository.

## Version File Detection

Search in priority order. Stop at the first match.

| Priority | File | Field | Parse Method |
|----------|------|-------|-------------|
| 1 | `package.yaml` | `version:` | YAML scalar |
| 2 | `package.json` | `"version":` | JSON string |
| 3 | `pyproject.toml` | `version =` under `[project]` or `[tool.poetry]` | TOML string |
| 4 | `.claude-plugin/plugin.json` | `"version":` | JSON string |
| 5 | `Cargo.toml` | `version =` under `[package]` | TOML string |
| 6 | `setup.cfg` | `version =` under `[metadata]` | INI value |
| 7 | `VERSION` | Entire file content (trimmed) | Plain text |

### Multi-Version Repositories

Some repos track version in multiple files (e.g., `package.yaml` + `.claude-plugin/plugin.json`). When multiple version files exist:

1. Use the highest-priority file as the **source of truth**
2. List all discovered files so the skill can update them in sync
3. Flag any version mismatches as warnings

## Changelog Detection

| File | Format | Section Pattern |
|------|--------|----------------|
| `CHANGELOG.md` | Keep a Changelog | `## [X.Y.Z] - YYYY-MM-DD` |
| `CHANGES.md` | Keep a Changelog | `## [X.Y.Z] - YYYY-MM-DD` |
| `HISTORY.md` | Varies | `## X.Y.Z` or `# X.Y.Z` |

### Changelog Validation

A valid changelog entry for version `X.Y.Z` must have:
- A heading matching `## [X.Y.Z]` (with or without date)
- At least one subsection (`### Added`, `### Changed`, `### Fixed`, etc.)
- Non-empty content under at least one subsection

## Semver Rule Extraction

Check these files for repository-specific versioning rules:

| File | Section to Search |
|------|-------------------|
| `CLAUDE.md` | `## Versioning` or `## Semantic Versioning` |
| `RELEASING.md` | `## Semantic Versioning` or `## Version Bumping` |
| `CONTRIBUTING.md` | `## Versioning` |

### Rule Extraction Algorithm

1. Look for tables mapping change types to version bumps
2. Look for bullet lists with "MAJOR:", "MINOR:", "PATCH:" prefixes
3. Look for "Breaking Change Examples" sections
4. Extract rules as structured pairs: `(change_description, bump_level)`

Example extracted rules from `CLAUDE.md`:
```
("Remove type or required parameter", MAJOR)
("Change parameter semantics", MAJOR)
("Add new types", MINOR)
("Add optional parameters", MINOR)
("Documentation fixes", PATCH)
```

## Release Script Detection

Check for release automation:

| Path | Indicates |
|------|-----------|
| `scripts/release.sh` | Shell-based release process |
| `.github/workflows/release.yaml` | CI-driven release |
| `Makefile` (target: `release`) | Make-based release |
| `Justfile` (recipe: `release`) | Just-based release |

The presence of a release script means the version bump skill should **only update files and commit** - not run the release process itself. Report the release mechanism so the user can trigger it after merging.
