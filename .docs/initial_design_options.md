# Architectural Analysis: Externalized YAML Workflow Definitions

## Context

The `lib/` directory in hiivmind-blueprint contains a sophisticated two-tier type system:
- **43 consequence types** across 8 definition files (core + extensions)
- **27 precondition types** across 8 definition files (core + extensions)
- **Index files** providing type lookup registries
- **JSON Schemas** that validate structure only, delegating type semantics to YAML

The question: Can this be extracted into a standalone repo that workflows reference by URL, similar to GitHub Actions?

---

## The GitHub Actions Reference Model

GitHub Actions uses this pattern:

```yaml
jobs:
  build:
    steps:
      - uses: actions/checkout@v4        # org/repo@version
      - uses: docker/build-push-action@v5
```

**Key characteristics:**
1. **Namespace**: `org/repo` identifies the action
2. **Version pinning**: `@v4`, `@v5.1.0`, `@main`, `@sha`
3. **Immutable tags**: Once `v4` is released, it doesn't change
4. **Resolution**: GitHub fetches from `github.com/{org}/{repo}` at runtime
5. **Caching**: Actions are cached per-workflow-run

---

## Mapping to Workflow Definitions

### Current State (Embedded)

```yaml
# workflow.yaml
nodes:
  clone_source:
    type: action
    consequences:
      - type: clone_repo          # ← resolved via lib/consequences/definitions/index.yaml
        url: "${source.url}"
```

The `clone_repo` type is resolved locally from `lib/consequences/definitions/extensions/git.yaml`.

### Proposed State (External Reference)

```yaml
# workflow.yaml
definitions:
  consequences: hiivmind/hiivmind-blueprint-lib@v1    # ← External reference
  # or explicit URL:
  # consequences: https://github.com/hiivmind/hiivmind-blueprint-lib/releases/download/v1/consequences.yaml

nodes:
  clone_source:
    type: action
    consequences:
      - type: clone_repo          # ← resolved from external package
        url: "${source.url}"
```

---

## What Gets Externalized?

### Candidate: The Type Definition Layer

```
hiivmind/hiivmind-blueprint-lib/
├── consequences/
│   ├── definitions/
│   │   ├── core/
│   │   │   ├── state.yaml
│   │   │   ├── logging.yaml
│   │   │   └── ...
│   │   └── extensions/
│   │       ├── git.yaml
│   │       └── ...
│   └── index.yaml
├── preconditions/
│   ├── definitions/
│   │   ├── core/
│   │   └── extensions/
│   └── index.yaml
└── schema/
    ├── consequence-definition.json
    └── precondition-definition.json
```

### What Stays Local

- **workflow.yaml** files (the workflows themselves)
- **intent-mapping.yaml** (skill-specific routing)
- **SKILL.md** loaders (thin skill entry points)
- **lib/workflow/*.md** (execution semantics documentation)
- **lib/blueprint/patterns/*.md** (blueprint-specific patterns)

---

## Versioning Strategy

### Option A: Semantic Version Tags (GitHub Actions Model)

```
v1.0.0  →  First stable release
v1.1.0  →  New consequence types added (backwards compatible)
v1.2.0  →  New preconditions, parameter additions
v2.0.0  →  Breaking changes (renamed types, removed parameters)
```

**Major version aliases:**
- `@v1` → resolves to latest `v1.x.x`
- `@v2` → resolves to latest `v2.x.x`

**Workflow references:**
```yaml
definitions:
  consequences: hiivmind/hiivmind-blueprint-lib@v1     # Floating major
  consequences: hiivmind/hiivmind-blueprint-lib@v1.2  # Floating patch
  consequences: hiivmind/hiivmind-blueprint-lib@v1.2.3  # Pinned exact
```

### Option B: Schema Version as Contract

The definition files already have `schema_version: "1.1"`. This could be the compatibility contract:

```yaml
# workflow.yaml
requires:
  consequence_schema: ">=1.0 <2.0"
  precondition_schema: ">=1.0 <2.0"
```

The runtime resolves to any release satisfying the constraint.

### Option C: Content-Addressed (Immutable)

```yaml
definitions:
  consequences: sha256:a1b2c3d4...
```

Maximum reproducibility, but poor ergonomics. Better as an optional lock mechanism.

---

## Resolution Mechanisms

### 1. Direct URL Fetch (Simple)

```yaml
definitions:
  consequences: https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v1.2.0/consequences/index.yaml
```

**Pros:** Simple, works anywhere
**Cons:** Verbose, no version resolution, network required

### 2. Registry Resolution (GitHub Actions Style)

```yaml
definitions:
  consequences: hiivmind/hiivmind-blueprint-lib@v1
```

Resolution logic:
1. Parse `{owner}/{repo}@{version}`
2. Check local cache for `{owner}/{repo}/{version}`
3. If miss: fetch from `https://github.com/{owner}/{repo}/releases/download/{version}/bundle.yaml`
4. Validate against schema
5. Cache for future use

### 3. Plugin-Local Override

Allow plugins to bundle specific versions:

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
├── vendor/
│   └── hiivmind-blueprint-lib/       # ← vendored definitions
│       └── v1.2.0/
└── skills/
    └── my-skill/
        └── workflow.yaml
```

```yaml
# workflow.yaml
definitions:
  consequences: vendor://hiivmind-blueprint-lib/v1.2.0
```

---

## Caching Architecture

### Layer 1: Global Cache (User-Level)

```
~/.claude/cache/hiivmind-blueprint-lib/
├── hiivmind/
│   └── hiivmind-blueprint-lib/
│       ├── v1.2.0/
│       │   ├── consequences/
│       │   └── preconditions/
│       └── v1.3.0/
│           └── ...
```

Shared across all plugins. Fetched once per version.

### Layer 2: Lock File (Plugin-Level)

```yaml
# .hiivmind-blueprint-lib.lock
resolved:
  hiivmind/hiivmind-blueprint-lib:
    requested: "@v1"
    resolved: "v1.3.2"
    sha256: "a1b2c3d4..."
    fetched: "2026-01-27T05:30:00Z"
```

Ensures reproducible builds. Committed to repo.

### Layer 3: Offline Fallback

If network unavailable:
1. Check lock file for exact version
2. Use cached version if available
3. Error with clear message if truly missing

---

## Release Workflow

### For hiivmind-blueprint-lib Maintainers

```bash
# Tag release
git tag v1.3.0
git push origin v1.3.0

# GitHub Actions builds release artifacts
# - consequences/index.yaml (bundled)
# - preconditions/index.yaml (bundled)
# - bundle.yaml (single file with everything)
# - schema-checksums.txt
```

### Release Artifacts

```
v1.3.0/
├── bundle.yaml           # Everything in one file (for simple fetch)
├── consequences/         # Split files (for selective loading)
│   ├── index.yaml
│   └── definitions/
├── preconditions/
├── checksums.sha256
└── CHANGELOG.md
```

### Breaking Change Policy

- **Major version bump** required for:
  - Removing a consequence/precondition type
  - Removing a parameter from a type
  - Changing parameter semantics
  - Renaming types

- **Minor version** for:
  - Adding new types
  - Adding optional parameters
  - Deprecating (not removing) types

- **Patch version** for:
  - Documentation fixes
  - Example corrections
  - Non-semantic changes

---

## Extension Ecosystem

### First-Party Extensions

```yaml
definitions:
  consequences: hiivmind/hiivmind-blueprint-lib@v1
  extensions:
    - hiivmind/hiivmind-blueprint-lib-docker@v1
    - hiivmind/hiivmind-blueprint-lib-kubernetes@v1
```

### Third-Party Extensions

```yaml
definitions:
  consequences: hiivmind/hiivmind-blueprint-lib@v1
  extensions:
    - mycorp/internal-consequences@v2
    - community/ml-pipeline-types@v1
```

### Extension Registration

Extensions declare their types in their own `index.yaml`:

```yaml
# mycorp/internal-consequences index.yaml
schema_version: "1.0"
extends: hiivmind/hiivmind-blueprint-lib@v1
types:
  - deploy_to_staging
  - run_integration_tests
  - notify_slack
```

---

## Compatibility Considerations

### Forward Compatibility

Workflows should degrade gracefully when a type is unknown:

```yaml
nodes:
  maybe_notify:
    type: action
    consequences:
      - type: notify_slack
        fallback: skip           # ← if type unknown, skip
        channel: "#builds"
```

### Backward Compatibility

New versions should support old workflows:

```yaml
# Old workflow (v1.0 era)
- type: clone_repo
  url: "..."

# New definition (v1.3) adds optional params with defaults
- type: clone_repo
  url: "..."
  depth: 1        # ← new optional param, defaults to full clone
```

### Version Negotiation

Workflows can declare minimum requirements:

```yaml
workflow:
  requires:
    workflow_types: ">=1.2.0"

# At load time:
# 1. Check cached version
# 2. If < 1.2.0, fetch newer
# 3. If no internet and cached version insufficient, error
```

---

## Trade-offs

### Centralized Definitions

**Advantages:**
- Single source of truth for type semantics
- Version control and release management
- Community can contribute types
- Plugins stay lean (no bundled definitions)
- Breaking changes are explicit and versioned

**Disadvantages:**
- Network dependency for first fetch
- Version coordination across ecosystem
- Potential for "dependency hell" with extensions
- More complex tooling required

### Embedded Definitions (Current)

**Advantages:**
- Works offline always
- No external dependencies
- Simpler mental model
- Faster startup (no resolution step)

**Disadvantages:**
- Definitions duplicated across plugins
- Updates require copying files
- No version coordination
- Extension ecosystem harder to build

---

## Recommendation: Hybrid Model

### Phase 1: Establish the External Repo

1. Extract `lib/consequences/` and `lib/preconditions/` to `hiivmind/hiivmind-blueprint-lib`
2. Set up semantic versioning with GitHub releases
3. Publish `v1.0.0` as baseline

### Phase 2: Support Both Modes

```yaml
# External (default for new workflows)
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v1

# Embedded (for offline/airgapped)
definitions:
  source: local
  path: ./vendor/hiivmind-blueprint-lib
```

### Phase 3: Extension Registry

```yaml
# Multiple sources composed
definitions:
  base: hiivmind/hiivmind-blueprint-lib@v1
  extensions:
    - hiivmind/hiivmind-blueprint-lib-ci@v1
    - local:./custom-types
```

---

## Open Questions

1. **Resolution authority**: Should Claude Code have built-in resolution for `hiivmind/*` namespaces, or use generic GitHub URLs?

2. **Bundle format**: Single YAML file vs. directory structure? Single file is simpler to fetch; directory allows selective loading.

3. **Signature verification**: Should releases be signed? Would add trust but complexity.

4. **Private registries**: How do enterprises use private type definitions?

5. **Type collision**: What happens when two extensions define the same type name?

---

## Comparison: GitHub Actions vs. Proposed Model

| Aspect | GitHub Actions | Workflow Types |
|--------|---------------|----------------|
| **Unit** | Action (executable) | Type definition (schema) |
| **Resolution** | `actions/checkout@v4` | `hiivmind/hiivmind-blueprint-lib@v1` |
| **Granularity** | Per-action | Per-package (many types) |
| **Execution** | Actions run code | Types define structure |
| **Caching** | Per-workflow-run | Global + lockfile |
| **Offline** | Fails | Cached fallback |
| **Extensions** | Composite actions | Extension packages |

The key difference: GitHub Actions are **executable units**, while hiivmind-blueprint-lib are **semantic definitions**. This means hiivmind-blueprint-lib can be cached more aggressively and composed more freely.

---

## Next Steps (If Proceeding)

This analysis covers the architectural landscape. If this direction is approved:

1. Create `hiivmind/hiivmind-blueprint-lib` repo with extracted definitions
2. Design resolution protocol (URL scheme, caching)
3. Implement loader that supports both embedded and external
4. Establish release automation
5. Migrate hiivmind-blueprint to use external reference


● I've written a comprehensive architectural analysis exploring the externalization model. The document covers:

  Core Analysis:
  - GitHub Actions reference pattern and how it maps to workflow type definitions
  - What gets extracted (consequence/precondition definitions) vs what stays local (workflows, loaders)
  - Three versioning strategies (semver tags, schema version contracts, content-addressed)
  - Three resolution mechanisms (direct URL, registry resolution, plugin-local override)

  Infrastructure Design:
  - Three-layer caching architecture (global cache, lock files, offline fallback)
  - Release workflow with bundle artifacts
  - Breaking change policy aligned with semver

  Ecosystem Considerations:
  - Extension model for first-party and third-party type packages
  - Forward/backward compatibility patterns
  - Trade-offs between centralized vs embedded approaches

  Key Insight: Unlike GitHub Actions (executable units), workflow-types are semantic definitions - pure schema. This enables more aggressive caching and freer composition since
  there's no code execution at resolution time.

  The document ends with open questions for discussion rather than a task list.
  ⎿  Tool use rejected with user message: we will call this repo hiivmind-blueprint-lib
