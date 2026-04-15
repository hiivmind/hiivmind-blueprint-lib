# Design: Claude Code Plugin Ecosystem in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Skills & Slash-Commands](2026-04-15-claude-code-skills-design.md), [Hooks](2026-04-15-claude-code-hooks-design.md), [Sub-agents](2026-04-15-claude-code-subagents-design.md), [MCP](2026-04-15-claude-code-mcp-design.md)
**Referenced by:** all authoring specs (as the packaging layer)

---

## 1. Scope & Non-Goals

A **plugin** is the distribution unit for user-authored extensions to Claude Code: a bundle that may contain skills, slash-commands, hooks, named sub-agents, and MCP server specs. A **marketplace** is a special plugin whose only purpose is to list other plugins. This spec covers the full ecosystem: manifest format, component contribution, marketplaces, activation lifecycle, version resolution, dependencies, update flows, and trust propagation.

**In scope:**
- `plugin.json` manifest and `.claude-plugin/` directory layout
- `${CLAUDE_PLUGIN_ROOT}` path interpolation contract
- Component contribution contracts (one per authored surface from the other specs)
- `marketplace.json` (a plugin that lists plugins) and trust propagation
- Activation lifecycle: install → resolve → register → activate → deactivate
- Version resolution, dependency graphs, conflict resolution
- Update flows with staging and rollback
- Trust tiers and security considerations

**Out of scope:**
- Specific hosting / distribution channels (git, tarball, registry URL) — operational
- Payment / licensing / attribution mechanics
- Telemetry collection from plugins
- Platform-specific packaging (signed macOS bundles, etc.)
- Authoring tutorials — documentation, not spec

---

## 2. Background

A plugin packages one or more **components** — each component is an instance of a surface defined by an earlier spec (a skill, a slash-command, a hook, a named sub-agent type, an MCP server spec). The package declares itself through `plugin.json` inside a top-level `.claude-plugin/` directory; the rest of the tree holds component files in conventional locations. Plugins can depend on other plugins by semver constraint, and the ecosystem tolerates multiple incompatible versions installed side-by-side only when no shared global namespace collides. A **marketplace** is a plugin that lists other plugins — the client adds a marketplace once, then browses and installs plugins from it. Trust flows from the marketplace tier down to the plugins it lists: a plugin's effective trust tier is the minimum of its own declared tier and its marketplace's tier.

**Source grounding:** `.claude-plugin/plugin.json` observed in the public Claude Code plugins (anthropic-official, community); `marketplace.json` in plugin marketplaces; `${CLAUDE_PLUGIN_ROOT}` string substitution observed in hook commands and MCP transport configs. See §13.

---

## 3. Types

### 3.1 Manifest

```lmpl
type PluginManifest = {
    name: string,                             -- unique within a marketplace
    version: SemVer,
    description: string,
    author: option[string],
    homepage: option[string],
    license: option[string],
    dependencies: map[string, SemVerConstraint],  -- plugin_name → constraint
    compatible_claude_code: SemVerConstraint, -- required client version
    components: PluginComponents,
    trust_tier: option[PluginTrustTier]       -- self-declared; bounded at install
}

type PluginComponents = {
    skills: list[string],              -- relative paths under CLAUDE_PLUGIN_ROOT
    commands: list[string],
    hooks: list[HookContribution],
    agents: list[AgentContribution],
    mcp_servers: list[string]          -- each is a path to an MCP config fragment
}
```

### 3.2 Versioning

```lmpl
type SemVer = {major: int, minor: int, patch: int, prerelease: option[string]}
type SemVerConstraint = string         -- e.g., "^1.2.0", ">=2.0.0 <3"

define satisfies(v: SemVer, c: SemVerConstraint) -> bool:
    -- Standard semver constraint satisfaction.
    ...
```

### 3.3 Trust tiers

```lmpl
type PluginTrustTier =
    | "official"      -- Anthropic-curated
    | "verified"      -- marketplace operator has vetted
    | "community"     -- self-declared; unverified
    | "local"         -- loaded from disk; user-authored

-- Ordering for trust comparison (higher = more trusted).
define trust_rank(t: PluginTrustTier) -> int:
    match t:
        case "official": 4
        case "verified": 3
        case "community": 2
        case "local":    1
```

### 3.4 Component contributions

Each contribution wraps a reference to a component defined by another spec, plus packaging-specific metadata.

```lmpl
type HookContribution = {
    config: HookConfig,                -- from Hooks spec §3.2
    enabled_by_default: bool
}

type AgentContribution = {
    name: string,                      -- becomes a SubagentType (Sub-agents spec §3.1)
    definition_path: string,           -- agent definition file under CLAUDE_PLUGIN_ROOT
    default_isolation: IsolationModel  -- from Sub-agents spec §3.1
}
```

### 3.5 Registry

```lmpl
type InstalledPlugin = {
    manifest: PluginManifest,
    install_path: string,              -- absolute; becomes CLAUDE_PLUGIN_ROOT
    marketplace: option[string],       -- provenance
    effective_trust: PluginTrustTier,  -- min(self, marketplace)
    active: bool
}

type PluginRegistry = map[string, InstalledPlugin]   -- name → installed

invariant all(result, p -> trust_rank(p.effective_trust)
                       <= trust_rank(p.manifest.trust_tier otherwise "community")),
    "effective trust cannot exceed declared"
```

---

## 4. Plugin Structure

### 4.1 Directory layout

```
<plugin_root>/
├── .claude-plugin/
│   └── plugin.json            -- manifest (§3.1)
├── skills/                    -- skills contributed by this plugin
│   └── <name>/SKILL.md
├── commands/                  -- slash-commands
│   └── <name>.md
├── hooks/                     -- hook scripts (shell, Python, etc.)
│   └── <name>.sh
├── agents/                    -- sub-agent definition files
│   └── <name>.md
├── .mcp.json                  -- MCP server specs contributed by this plugin
└── README.md                  -- authoring documentation (not consumed by client)
```

The layout above is a convention, not a hard requirement; the manifest's `components` field maps component kinds to explicit paths and overrides the convention when needed.

### 4.2 `${CLAUDE_PLUGIN_ROOT}` interpolation

String fields in manifests, hook commands, and MCP transport configs may reference `${CLAUDE_PLUGIN_ROOT}`. The client substitutes the plugin's absolute install path at load time. This is how a plugin's hook can refer to a script inside its own bundle portably.

```lmpl
define interpolate_plugin_root(s: string, plugin: InstalledPlugin) -> string:
    return replace(s, "${CLAUDE_PLUGIN_ROOT}", plugin.install_path)

    ensure not contains("${CLAUDE_PLUGIN_ROOT}", result) when
           interpolated(s, plugin),
        "all occurrences are substituted"
    ensure starts_with_path_or_unchanged(result, plugin.install_path),
        "substitution does not escape the plugin directory"
```

### 4.3 Component-type conventions

Each directory corresponds to a surface owned by another spec. The plugin is the *contributor*; the behavior of each surface is defined where it originates.

| Directory    | Maps to spec                                  | Registration call                                     |
|--------------|-----------------------------------------------|-------------------------------------------------------|
| `skills/`    | Skills §3.3                                   | `register_extension(kind: "skill", origin: plugin)`   |
| `commands/`  | Skills §3.4 (slash-commands)                  | `register_extension(kind: "slash_command", origin: plugin)` |
| `hooks/`     | Hooks §3.2                                    | `register_hook(config with origin: plugin)`           |
| `agents/`    | Sub-agents §3.1                               | adds a named `SubagentType`                           |
| `.mcp.json`  | MCP §3.2                                      | `register_mcp_server(spec with source: plugin)`       |

---

## 5. Component Contribution Contracts

Each contract is a thin wrapper. The details of what a skill *is*, what a hook *does*, etc., are owned by the respective spec; this spec only owns how plugins contribute them.

### 5.1 Skills and slash-commands

```lmpl
define contribute_extensions(plugin: InstalledPlugin,
                            registry: ExtensionRegistry) -> ExtensionRegistry:
    for skill_path in plugin.manifest.components.skills:
        ext <- parse_extension(join(plugin.install_path, skill_path))
        require ext.frontmatter.kind == "skill",
            "files under skills/ must declare kind: skill"
        registry <- add_extension(registry, ext, origin: plugin_origin(plugin))

    for cmd_path in plugin.manifest.components.commands:
        ext <- parse_extension(join(plugin.install_path, cmd_path))
        require ext.frontmatter.kind == "slash_command",
            "files under commands/ must declare kind: slash_command"
        registry <- add_extension(registry, ext, origin: plugin_origin(plugin))

    return registry
```

### 5.2 Hooks

```lmpl
define contribute_hooks(plugin: InstalledPlugin,
                       registry: HookRegistry) -> HookRegistry:
    for hc in plugin.manifest.components.hooks:
        interpolated_cmd <- interpolate_plugin_root(hc.config.command, plugin)
        config <- {...hc.config,
                   command: interpolated_cmd,
                   origin: {kind: "plugin", plugin: plugin.manifest.name}}

        if hc.enabled_by_default:
            registry <- register_hook(registry, config)

    return registry

    ensure all(registry[event], h -> h.origin.kind == "plugin" implies
              matches_installed(h, plugins)),
        "plugin-origin hooks require their plugin to be installed"
```

### 5.3 Sub-agents

```lmpl
define contribute_agents(plugin: InstalledPlugin,
                        agent_registry: SubagentRegistry) -> SubagentRegistry:
    for ac in plugin.manifest.components.agents:
        def <- parse_agent_definition(join(plugin.install_path, ac.definition_path))
        agent_registry <- register_agent_type(agent_registry, {
            name: ac.name,
            definition: def,
            default_isolation: ac.default_isolation,
            origin: plugin_origin(plugin)
        })

    return agent_registry
```

### 5.4 MCP server specs

Plugin-contributed `.mcp.json` files declare MCP server specs the client should connect to when the plugin activates. The client treats the plugin as a config source (MCP spec §3.2) with origin `"plugin"`.

```lmpl
define contribute_mcp_servers(plugin: InstalledPlugin) -> list[McpServerSpec]:
    raw <- read_file(join(plugin.install_path, ".mcp.json"))
    specs <- parse_mcp_specs(raw)

    return map(specs, s -> {
        ...s,
        source: "plugin",
        transport: interpolate_transport(s.transport, plugin)  -- §4.2
    })
```

---

## 6. Marketplaces

### 6.1 `marketplace.json`

A marketplace is a plugin whose manifest lists other plugins instead of (or in addition to) contributing components. Listed plugins are not installed — they are *offered* for installation.

```lmpl
type MarketplaceEntry = {
    name: string,
    version_range: SemVerConstraint,
    source: MarketplaceSource,           -- where to fetch the plugin from
    declared_trust: PluginTrustTier
}

type MarketplaceSource =
    | {kind: "git",  url: string, rev: option[string]}
    | {kind: "path", path: string}                         -- monorepo case
    | {kind: "url",  url: string}                          -- tarball / zip

type MarketplaceManifest = {
    plugin: PluginManifest,              -- marketplaces are also plugins
    marketplace: {
        plugins: list[MarketplaceEntry],
        own_trust_tier: PluginTrustTier
    }
}
```

### 6.2 Registration

```lmpl
define register_marketplace(client_state: ClientState,
                           marketplace: InstalledPlugin) -> ClientState:
    require has_marketplace_manifest(marketplace),
        "marketplace plugins must include the marketplace section"

    return {...client_state,
            marketplaces: append(client_state.marketplaces, marketplace)}

    ensure marketplace.effective_trust >= "local",
        "a registered marketplace is at least locally trusted"
```

### 6.3 Discovery

```lmpl
define list_available_plugins(client_state: ClientState) -> list[MarketplaceEntry]:
    return flatten(map(client_state.marketplaces, m -> m.marketplace_entries))

    ensure no_duplicates_by(result, name) or
           flagged_as_conflict(result),
        "duplicate entries across marketplaces are either deduplicated or flagged"
```

### 6.4 Trust propagation

A plugin installed from a marketplace has effective trust bounded by the marketplace's own tier.

```lmpl
define effective_trust_of(plugin_declared: PluginTrustTier,
                         marketplace_tier: PluginTrustTier) -> PluginTrustTier:
    return min_by_rank([plugin_declared, marketplace_tier])

    ensure trust_rank(result) <= trust_rank(plugin_declared),
        "trust cannot be elevated by the marketplace"
    ensure trust_rank(result) <= trust_rank(marketplace_tier),
        "a community marketplace cannot host verified plugins at full tier"
```

Users can override this locally (downgrade further), but cannot upgrade beyond the marketplace cap. An `"official"` plugin fetched from a `"community"` marketplace gets `"community"` trust — the same plugin from the official marketplace gets `"official"`.

---

## 7. Activation Lifecycle

### 7.1 Install sequence

```lmpl
define install_plugin(entry: MarketplaceEntry,
                     client_state: ClientState) -> ClientState:
    -- 1. Fetch
    package_path <- fetch_from(entry.source)

    -- 2. Validate manifest
    manifest <- read_manifest(package_path)
    require satisfies(client_version(), manifest.compatible_claude_code),
        "client must satisfy the plugin's client-version constraint"
    require valid_manifest(manifest), "manifest must pass schema validation"

    -- 3. Resolve dependencies (§8)
    resolved <- resolve_dependency_graph(manifest, client_state.registry)
    require resolved.ok, "all declared dependencies must resolve"

    -- 4. Install declared deps first
    client_state <- install_many(resolved.plan, client_state)

    -- 5. Register this plugin's components into all relevant registries
    installed <- {
        manifest: manifest,
        install_path: package_path,
        marketplace: some(entry.marketplace_name),
        effective_trust: effective_trust_of(manifest.trust_tier otherwise "community",
                                            entry.declared_trust),
        active: false
    }
    client_state <- {...client_state,
                     registry: insert(client_state.registry, manifest.name, installed)}

    -- 6. Activate (§7.2)
    return activate_plugin(manifest.name, client_state)

    ensure installed_and_registered_before_activation(result, manifest.name),
        "components are not exposed until activation completes"
```

### 7.2 Activation

Activation exposes a plugin's components to the running client. It is *reversible* — deactivation removes the components without uninstalling.

```lmpl
define activate_plugin(name: string, client_state: ClientState) -> ClientState:
    plugin <- lookup(client_state.registry, name)
    require plugin.some, "plugin must be installed"

    -- Register into each surface's registry.
    ext_registry   <- contribute_extensions(plugin.value, client_state.extensions)
    hook_registry  <- contribute_hooks(plugin.value, client_state.hooks)
    agent_registry <- contribute_agents(plugin.value, client_state.agents)
    mcp_specs      <- contribute_mcp_servers(plugin.value)

    return {...client_state,
            extensions: ext_registry,
            hooks: hook_registry,
            agents: agent_registry,
            pending_mcp_servers: concat(client_state.pending_mcp_servers, mcp_specs),
            registry: update(client_state.registry, name,
                             p -> {...p, active: true})}

    ensure plugin_components_visible_after_activation(name, result),
        "all contributed components are reachable via their registries"
```

### 7.3 Deactivation ordering

Deactivation removes contributions in **reverse dependency order**: a plugin depended on by another is deactivated *after* its dependents. A live sub-agent or in-flight hook invocation delays deactivation of its host plugin until it terminates.

```lmpl
define deactivate_plugin(name: string, client_state: ClientState) -> ClientState:
    require no_dependents_active(name, client_state),
        "a plugin depended on by active plugins cannot be deactivated first"
    require no_live_invocations(name, client_state),
        "live sub-agents / hooks from this plugin must complete first"

    return remove_all_contributions(name, client_state)

    ensure plugin_components_invisible_after_deactivation(name, result),
        "no registry retains an entry originating from this plugin"
```

### 7.4 Per-plugin settings and state

Plugins may read and write their own config at `.claude/plugin-name.local.md` (YAML-frontmatter doc in the user's project) and their own persistent state in `${CLAUDE_PLUGIN_ROOT}/.state/`. The client exposes a typed read/write API to prevent plugins from reaching into each other's state.

```lmpl
invariant plugin_cannot_read_other_state(plugin_a, plugin_b),
    "state files are scoped to their owning plugin by the client API"
```

---

## 8. Version Resolution & Dependencies

### 8.1 Dependency graph

```lmpl
type DependencyGraph = {
    nodes: list[string],                      -- plugin names
    edges: list[{from: string, to: string, constraint: SemVerConstraint}]
}

define build_graph(manifests: list[PluginManifest]) -> DependencyGraph:
    ...
    ensure acyclic(result), "dependency cycles are forbidden"
```

### 8.2 Cycle detection

```lmpl
invariant acyclic(graph), "a dependency cycle is a resolver error"

-- On cycle detection, the resolver fails with the specific cycle in the error.
```

### 8.3 Resolution strategy

The resolver picks the **highest version satisfying all constraints** for each plugin name. If no single version satisfies every dependent's constraint simultaneously, resolution fails.

```lmpl
define resolve(graph: DependencyGraph,
              available: map[string, list[SemVer]]) -> ResolutionResult:

    -- For each node, intersect all inbound constraints, pick the highest available.
    result <- map(graph.nodes, name -> {
        let constraints = collect_inbound_constraints(graph, name)
        let candidates = filter(available[name], v -> satisfies_all(v, constraints))
        return {name: name, chosen: max_version(candidates)}
    })

    if any(result, r -> r.chosen.none):
        return {ok: false, error: "no_version_satisfies_constraints", details: ...}

    return {ok: true, plan: result}

    ensure result.ok implies all(result.plan, p -> some(p.chosen)),
        "a successful plan has a chosen version for every node"
```

### 8.4 Conflict resolution

If a user has plugin `A v1` installed and installs plugin `B` that requires `A v2`, the resolver surfaces a conflict. Options:

| Option                        | Policy                                                    |
|-------------------------------|-----------------------------------------------------------|
| Upgrade A to v2               | Default; runs compatibility check first                   |
| Side-by-side install          | Only if `A v1` and `A v2` share no global identifiers     |
| Reject B                      | If neither upgrade nor side-by-side is safe               |

**Side-by-side is rare.** It requires that *every* component a plugin contributes is namespace-safe at both versions: no duplicate skill name, command name, agent type, MCP server name, or hook matcher collision. In practice this almost never holds; the common case is upgrade-or-reject.

```lmpl
define side_by_side_safe(a: PluginManifest, b: PluginManifest) -> bool:
    return no_overlap(skill_names(a), skill_names(b))
       and no_overlap(command_names(a), command_names(b))
       and no_overlap(agent_names(a), agent_names(b))
       and no_overlap(mcp_server_names(a), mcp_server_names(b))
       and no_overlap(hook_matchers(a), hook_matchers(b))
```

---

## 9. Update Flows

### 9.1 Discover updates

```lmpl
define discover_updates(client_state: ClientState) -> list[PluginUpdate]:
    candidates <- flatten(map(client_state.registry,
                              (name, installed) -> available_versions_for(name)))
    return filter(candidates, c ->
        semver_gt(c.version, installed_version(client_state, c.name)))
```

### 9.2 Apply

Updates follow **stage → verify → swap → reactivate**:

```lmpl
define apply_update(update: PluginUpdate, client_state: ClientState)
    -> ClientState:

    -- 1. Stage: install the new version in a side directory.
    staged <- fetch_to_staging(update.source)

    -- 2. Verify: the new manifest is valid and its deps resolve against current state.
    require valid_manifest(staged.manifest)
    resolved <- resolve_dependency_graph(staged.manifest,
                                         client_state.registry_minus(update.name))
    require resolved.ok, "new version's dependencies must resolve"

    -- 3. Swap: deactivate old → move staging into place → activate new.
    client_state <- deactivate_plugin(update.name, client_state)
    swap_directories(old: installed_path(update.name), new: staged.path)

    -- 4. Reactivate.
    return activate_plugin(update.name, client_state)

    ensure update_is_atomic(result, update),
        "the update either completed and activated, or rolled back entirely"
```

### 9.3 Rollback

If activation of the new version fails, the staged directory is reverted to the old version and the old plugin is reactivated. Rollback is *always* available until the next successful update replaces the old directory.

```lmpl
attempt:
    activated <- activate_plugin(update.name, client_state_after_swap)
on failure(err):
    restore_old_version(update.name)
    reactivate_old(update.name)
    raise UpdateFailed(update.name, err)
```

---

## 10. Trust & Security

### 10.1 Trust ladder

```
official > verified > community > local
```

- **Official**: Anthropic-curated; ships with or is promoted by the client.
- **Verified**: marketplace has vetted the plugin.
- **Community**: self-declared; trust is "the marketplace hosts it, nothing more."
- **Local**: user loaded from disk; trust derives entirely from the user's authorship.

### 10.2 Trust-gated behaviors

```lmpl
define requires_tier(behavior: string) -> PluginTrustTier:
    match behavior:
        case "autorun_session_start_hook":       return "verified"
        case "contribute_system_prompt":         return "official"
        case "disable_guardrail":                return "official"    -- rare; also opt-in per session
        case "contribute_skill":                 return "local"
        case "contribute_hook":                  return "local"
        case "contribute_mcp_server":            return "community"
```

A plugin that needs a behavior its tier does not permit is installable but the behavior is suppressed with a user-visible warning.

### 10.3 Hook-spawning plugins

The hook system (Hooks spec §9) is the highest-risk surface a plugin can contribute. The client enforces:

- `SessionStart` hooks from plugins **require explicit activation** on first encounter (not merely install).
- A plugin that has fired ≥ N `SessionStart` hooks whose exit code is "error" has its hook contributions disabled and surfaces a remediation prompt.
- Hooks from `community` plugins run with a forced timeout ceiling; plugins cannot override it.

### 10.4 Signing (aspirational)

Current plugins are not cryptographically signed; trust derives from marketplace curation and tier. A `@signed_by(public_key)` annotation is noted in §11.2 as a future extension.

---

## 11. LMPL Gaps and Proposed Extensions

### 11.1 Typed path interpolation

`interpolate_plugin_root` operates on strings. A `templated_path[T]` type parameterized on the allowed variable set would make interpolation safe: expressions like `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh` would carry a static guarantee that only declared substitutions occur, with no accidental command injection surface.

### 11.2 Signed-origin types

Trust tiers are string tags today. A `@signed_by(public_key)` annotation on types could let the client verify structural provenance rather than relying solely on manifest claims. This would convert some runtime checks in §10 into authoring-time obligations.

### 11.3 Dependency-resolution semantics

`resolve` is effectively a constraint solver. LMPL has no first-class support for expressing "solve this constraint system." Declaring the resolver's contract is doable (preconditions on inputs, postconditions on outputs), but specifying *behavior* relies on prose. A `@solver(objective, constraints)` annotation would let specs reason about the shape of the output without re-implementing the solver.

### 11.4 Reverse-order lifecycle

Deactivation-in-reverse-dependency-order is a common pattern (plugins, modules, services, DI frameworks). LMPL expresses it imperatively. A `lifecycle_graph` block with `activate` / `deactivate` hooks and automatic topological ordering would formalize the pattern.

### 11.5 Atomic external effects

§9.2 asserts `update_is_atomic`, which requires staging + rollback. LMPL has no primitive for "atomic file-system operation." A `@transactional(on: "filesystem")` annotation would document the staging contract explicitly.

### 11.6 Cross-plugin namespace isolation

§7.4's invariant `plugin_cannot_read_other_state` is a sandboxing contract that crosses the API boundary. LMPL has no "this function is scoped to a principal" construct. Related to the `@isolation(trust_level)` gap raised in the Sub-agents spec (§8.4 there) — worth unifying.

---

## 12. Cross-Spec References

| Reference                                | From           | To                                   |
|------------------------------------------|----------------|--------------------------------------|
| Skill contribution                       | §5.1           | Skills §3.3, §5                      |
| Slash-command contribution               | §5.1           | Skills §3.4, §5                      |
| Hook contribution                        | §5.2           | Hooks §3.2, §5.1                     |
| Sub-agent-type contribution              | §5.3           | Sub-agents §3.1                      |
| MCP server spec contribution             | §5.4           | MCP §3.2, §4.1                       |
| `${CLAUDE_PLUGIN_ROOT}` in hook commands | §4.2, §5.2     | Hooks §3.2                           |
| `${CLAUDE_PLUGIN_ROOT}` in MCP transport | §4.2, §5.4     | MCP §3.1                             |
| Trust tier influencing Guardrails defaults | §10.2        | Guardrails (per-MCP-source tightening, §8.3 there) |

---

## 13. References

- Blake Crosley, "What the Claude Code Source Leak Reveals" — https://blakecrosley.com/blog/claude-code-source-leak (plugin-provided hooks, skills, sub-agents; marketplace pattern)
- Redreamality, "Claude Code Leak: A Deep Dive into Anthropic's AI Coding Agent Architecture" — https://redreamality.com/blog/claude-code-source-leak-architecture-analysis/ (plugin marketplace layer; ecosystem structure)
- cablate, *claude-code-research* — https://github.com/cablate/claude-code-research (plugin discovery, plugin.json, .claude-plugin/ layout)
- Varonis Threat Labs, "A Look Inside Claude's Leaked AI Coding Agent" — https://www.varonis.com/blog/claude-code-leak (plugin surface as attack surface; hook-spawning plugins as risk)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented plugin ecosystem.
