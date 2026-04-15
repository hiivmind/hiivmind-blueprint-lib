# Design: Claude Code Skills & Slash-Commands in LMPL

**Date:** 2026-04-15
**Profile:** `@profile("agentic")`
**Intent:** `@intent("specify")`
**Status:** Draft — awaiting review
**Depends on:** [Core Agentic Loop](2026-04-15-claude-code-agentic-loop-design.md), [Tool Catalog](2026-04-15-claude-code-tool-catalog-design.md), [MCP](2026-04-15-claude-code-mcp-design.md)
**Referenced by:** Hooks (future), Plugin ecosystem (future)

---

## 1. Scope & Non-Goals

Skills and slash-commands are user-authored extensions that inject additional capabilities into a Claude Code session without writing TypeScript. They share file format, discovery, and packaging; they differ in how they are invoked. This spec treats them as two variants of one primitive.

**In scope:**
- File format: YAML frontmatter + markdown body
- Required and optional frontmatter fields
- Discovery from user, project, and plugin-provided locations (packaging opaque)
- Progressive disclosure: description in the system prompt, body loaded on invocation
- User invocation (`/name`) for both kinds
- Auto-invocation (skills only) via the `Skill` meta-tool
- System-prompt integration contract
- Integration with the core loop (prepending messages, tool_use blocks)

**Out of scope:**
- Plugin packaging internals (`plugin.json`, `marketplace.json`, `.claude-plugin/` layout) — future Plugin spec
- Hook system (skill-triggered hooks) — future Hooks spec
- Skill authoring guidance and prompt patterns — documentation, not spec
- Specific skill catalogs — ephemeral, user-dependent
- Versioning, update flows, and dependency resolution — Plugin spec

---

## 2. Background

A **skill** is a markdown file with YAML frontmatter declaring a `name`, a `description`, and (optionally) tool restrictions and example triggers. The body is the skill's instructions — loaded into the conversation only when the skill is invoked. A **slash-command** has the same file shape but no auto-invocation metadata: it runs exactly when the user types `/<name>`. Both are discovered at session start from user directories, project directories, and installed plugins; their descriptions (not bodies) are injected into the system prompt so Claude can recognize when to invoke them. This is **progressive disclosure**: the cheap summary sits in every turn's context; the full body loads only on invocation.

**Source grounding:** `src/tools/SkillTool`, `src/commands/*`, skill/command scanners in the entrypoint layer; skill frontmatter extraction via `filterInjectedMemoryFiles` and similar. See §12.

---

## 3. Types

### 3.1 Extension kind

```lmpl
type UserExtensionKind = "skill" | "slash_command"
```

### 3.2 Frontmatter

The shared contract. Every extension file must have this at the top, before the body.

```lmpl
type ExtensionFrontmatter = {
    name: string,
    description: string,                    -- the visible summary; trigger surface
    kind: UserExtensionKind,                -- inferred from path + frontmatter
    allowed_tools: option[list[ToolName]],  -- restrict tool use during expansion
    model: option[string],                  -- force a model for this extension
    disable_model_invocation: option[bool]  -- prevent auto-invocation even for skills
}
```

### 3.3 Skill

Skills carry auto-invocation metadata. The description is the trigger surface — Claude reads it every turn and uses it to decide whether to invoke.

```lmpl
type Skill = {
    frontmatter: ExtensionFrontmatter,
    body: string,                           -- markdown, loaded on invocation
    source_path: string,
    origin: ExtensionOrigin,
    auto_invocable: bool                    -- false if disable_model_invocation
}

invariant skill.frontmatter.kind == "skill"
```

### 3.4 Slash-command

```lmpl
type SlashCommand = {
    frontmatter: ExtensionFrontmatter,
    body: string,
    source_path: string,
    origin: ExtensionOrigin,
    argument_schema: option[JsonSchema]     -- declared in frontmatter; optional
}

invariant slash_command.frontmatter.kind == "slash_command"
invariant not auto_invocable(slash_command),
    "slash-commands are user-invoked only"
```

### 3.5 Origin and registry

```lmpl
type ExtensionOrigin =
    | "user"              -- ~/.claude/skills, ~/.claude/commands
    | "project"           -- <repo>/.claude/skills, <repo>/.claude/commands
    | {kind: "plugin", plugin: string}    -- bundled with a plugin

type ExtensionRegistry = {
    skills: map[string, Skill],                   -- keyed by name
    slash_commands: map[string, SlashCommand]
}
```

---

## 4. File Format & Frontmatter Contract

A skill or command file is YAML frontmatter delimited by `---`, followed by a markdown body:

```
---
name: commit
description: Create a git commit with a message following the repo's conventions
kind: slash_command
---

<body goes here — markdown, instructions, examples>
```

### 4.1 Parsing contract

```lmpl
define parse_extension(path: string, contents: string) -> Extension:
    @boundary(inputs: {path, contents}, outputs: Extension)

    require has_frontmatter_delimiters(contents),
        "file must begin with '---' and close the frontmatter with '---'"

    frontmatter <- parse_yaml(extract_between_delimiters(contents))
    body <- extract_after_closing_delimiter(contents)

    require valid_frontmatter(frontmatter), "frontmatter must satisfy the schema"
    require length(frontmatter.name) > 0, "name is required"
    require length(frontmatter.description) > 0, "description is required"
    require valid_identifier(frontmatter.name),
        "name must be a valid identifier (slash-safe, no spaces)"

    kind <- infer_kind(path, frontmatter)
    return assemble_extension(frontmatter, body, kind, path)

    ensure result.frontmatter.name == frontmatter.name,
        "parse is lossless on identity fields"
```

### 4.2 Required vs. optional fields

| Field                        | Required | Applies to            | Purpose                                   |
|------------------------------|----------|-----------------------|-------------------------------------------|
| `name`                       | yes      | both                  | Unique identifier, matches `/<name>`      |
| `description`                | yes      | both                  | Trigger surface and user-visible summary  |
| `allowed_tools`              | no       | both                  | Restrict tool catalog during expansion    |
| `model`                      | no       | both                  | Force a specific model for the extension  |
| `disable_model_invocation`   | no       | skills                | Opt out of auto-invocation                |
| `argument_schema`            | no       | slash-commands        | Declare expected arguments                |

---

## 5. Discovery

### 5.1 Scan locations

The client scans a fixed set of locations at session start. Loader mechanics are opaque; this spec asserts only the ordering and the uniqueness contract.

```lmpl
define discover_extensions() -> ExtensionRegistry:
    candidates <- []
    append_all(candidates, scan("user_skills_dir",       origin: "user"))
    append_all(candidates, scan("user_commands_dir",     origin: "user"))
    append_all(candidates, scan("project_skills_dir",    origin: "project"))
    append_all(candidates, scan("project_commands_dir",  origin: "project"))
    append_all(candidates, scan_all_installed_plugins(origin_template: plugin_origin))

    parsed <- map(candidates, parse_extension)
    return merge_with_precedence(parsed)

    ensure no_duplicates_by(result.skills, name), "skill names unique"
    ensure no_duplicates_by(result.slash_commands, name), "command names unique"
```

### 5.2 Uniqueness and precedence

If two sources define an extension with the same `name`, precedence is `project > user > plugin` (the opposite of enterprise-first in MCP — extensions are user authoring territory, so user overrides plugin-provided defaults). Collisions are resolved by discarding lower-precedence entries with a single reported warning.

```lmpl
define merge_with_precedence(exts: list[Extension]) -> ExtensionRegistry:
    grouped <- group_by(exts, name)
    winners <- map(grouped, g -> max_by(g, precedence))
    return build_registry(winners)

    invariant all(result, chosen -> precedence(chosen) >= precedence(other)
                 for other in grouped_with_same_name(chosen)),
        "resolved winner has maximum precedence"
```

### 5.3 Plugin packaging (opaque)

`scan_all_installed_plugins` is the extension point where plugins contribute skills and slash-commands. Packaging internals (`plugin.json`, `.claude-plugin/`) are deferred to a future Plugin spec. What matters here: plugin-sourced extensions carry their `plugin` identifier in `origin`, so the registry knows where each one came from.

---

## 6. Progressive Disclosure

### 6.1 Context budget contract

The system prompt contains every available skill's **name + description** — a few dozen to a few hundred tokens total. Bodies are *not* in the system prompt. A skill body can be thousands of tokens; loading all of them every turn would blow the context budget.

```lmpl
require total_skill_description_tokens(registry) <= skill_description_budget,
    "the sum of all skill descriptions must fit within the allocated budget"

invariant skill_bodies_not_in_system_prompt(registry),
    "bodies are loaded on invocation only; never preloaded"
```

### 6.2 Description is the trigger surface

Because the description is *all* Claude sees by default, its wording is what determines whether auto-invocation fires. This is structurally significant — the description is a **prompt contract**, not merely documentation.

```lmpl
ensure description_covers_auto_invocation_triggers(skill),
    "the description must enumerate enough triggers that the model can recognize applicability"
ensure description_unambiguous_within(registry),
    "descriptions should not overlap to the point of non-deterministic auto-invocation"
```

These are authoring obligations. Tooling can lint for overlap (gap §10.2).

### 6.3 Token-budget rationale

If progressive disclosure were abandoned (bodies inlined), a modest 20-skill installation would push the system prompt past the cache-friendly zone. The rationale is operational: keep the cacheable prefix small; pay the body cost only when the skill is used.

---

## 7. Invocation

### 7.1 User invocation

Both kinds accept `/<name>` from the user. The client expands the body into a sequence of messages and prepends them to the current turn's context — the same mechanism MCP prompts use (MCP spec §7.4).

```lmpl
define invoke_user_extension(name: string,
                            args: record,
                            registry: ExtensionRegistry,
                            state: State) -> State:
    extension <- lookup_extension(registry, name)
    require extension.some, "extension name must be registered"

    match extension.value:
        case skill:             messages <- expand_skill_body(skill, args)
        case slash_command:     messages <- expand_command_body(slash_command, args)

    return {
        ...state,
        messages: prepend_all(state.messages, messages),
        active_extension: some(extension.value.frontmatter.name)
    }

    ensure preserved_message_order(result.messages, state.messages),
        "prepend does not reorder existing history"
    ensure tool_scope_adjusted_if_declared(result, extension.value.allowed_tools),
        "allowed_tools narrows the tool catalog for the active invocation"
```

### 7.2 Auto-invocation — skills only

Auto-invocation happens through the **`Skill` meta-tool**. Claude emits a `tool_use` block with `{name: "Skill", arguments: {skill: "<name>"}}`; the tool implementation loads the skill's body and returns it as a `tool_result`, which is appended to the conversation like any other tool output. The next turn's model call sees the body as conversation content.

```lmpl
define tool Skill:
    name: "Skill"
    description: "Invoke a registered skill by name; returns the skill's body as context"
    category: "meta"
    source: {kind: "builtin"}
    requires_approval: false

    input_schema: {
        skill: string,
        args?: record
    }

    invoke(call, ctx) -> ToolResult:
        @boundary(
            inputs: {skill: string, args?: record},
            outputs: {content: string, frontmatter: ExtensionFrontmatter}
        )

        registry <- current_registry(ctx)
        skill <- lookup_skill(registry, call.arguments.skill)
        require skill.some, "skill must be registered at invocation time"
        require skill.value.auto_invocable,
            "skill must not have disable_model_invocation set"

        body <- render_body(skill.value, call.arguments.args otherwise empty_record)
        return success_result(body, frontmatter: skill.value.frontmatter)

    ensure result.status == "success" implies
           result.provenance.skill_name == call.arguments.skill,
        "provenance is attributable to the invoked skill"
```

### 7.3 Argument handling

Slash-commands may declare an `argument_schema`; when present, the client validates user-supplied arguments before expansion.

```lmpl
define expand_command_body(cmd: SlashCommand, args: record) -> list[Message]:
    if some(cmd.argument_schema):
        require validates_against(args, unwrap(cmd.argument_schema)),
            "arguments must match the declared schema"

    rendered <- render_template(cmd.body, args)
    return parse_body_into_messages(rendered)

    ensure all(result, m -> m.role in ["system", "user", "assistant"]),
        "expansion produces well-formed messages"
```

For skills, argument handling is looser: skills typically inline parameters into prose, and the body renderer is more permissive.

### 7.4 Tool-scope adjustment

If the active extension declares `allowed_tools`, the tool catalog is temporarily narrowed for the duration of the invocation. The narrowing lifts when the invocation concludes.

```lmpl
define narrow_tools_for_extension(catalog: ToolRegistry,
                                 allowed: option[list[ToolName]]) -> ToolRegistry:
    match allowed:
        case none:                return catalog     -- no restriction
        case some(list):          return filter_registry(catalog,
                                          def -> def.name in list)

    ensure length(result) <= length(catalog),
        "narrowing can only remove entries"
```

---

## 8. System-Prompt Integration

### 8.1 Injection format

Every auto-invocable skill contributes one line to a dedicated section of the system prompt:

```
- <name>: <description>
```

Plus a brief preamble instructing the model how to invoke them via the `Skill` tool.

```lmpl
define skills_section(registry: ExtensionRegistry) -> string:
    invocable <- filter(registry.skills, s -> s.auto_invocable)
    lines <- map(invocable, s -> "- " + s.frontmatter.name + ": "
                                     + s.frontmatter.description)
    return preamble() + "\n" + join(lines, "\n")

    ensure length(result) <= skill_description_budget,
        "section respects the description budget (§6.1)"
```

### 8.2 Invoke-before-respond contract (observed behavior)

The system prompt instructs: *"Invoke a skill BEFORE any response, even before clarifying questions, if it might apply"* (paraphrased from the observed prompt text). This is a prompt-level contract on model behavior — LMPL cannot enforce it, but can record it:

```lmpl
@model_contract
ensure when skill_may_apply(user_request):
    model_invokes_skill_before_other_output,
    "relevant skills are invoked before text response"
```

### 8.3 Discoverability vs. budget trade-off

The skills section grows linearly with registered skill count. Two levers prevent bloat:

- `disable_model_invocation: true` removes a skill from auto-invocation and therefore from the section (it remains user-invocable via `/`).
- Plugin authors typically keep descriptions tight (one line).

Beyond a threshold the section is paginated or auto-summarized — that's an implementation concern, not a spec obligation.

---

## 9. Interaction with the Core Loop

### 9.1 User-invoked extensions

As in MCP prompts (MCP spec §7.4): the expanded body is prepended to `state.messages` before the next turn. The core loop sees the result as normal conversation history — no new transition variant required.

### 9.2 Auto-invoked skills

The skill body arrives as a tool_result inside the normal tool-use cycle. The core loop's existing `transition: {reason: "tool_use"}` path handles it without modification.

```lmpl
-- In the core loop's `act` stage, the Skill tool's result:
tool_result {
    id: call.id,
    status: "success",
    content: skill.body,
    provenance: {source: "skill", skill_name: skill.frontmatter.name}
}
-- Flows through the standard append-and-continue path in continue_site.
```

### 9.3 Recursion

Skill bodies may themselves instruct the model to invoke other skills. A skill invoking a sub-skill produces another `Skill` tool_use in the next turn. Recursion depth is bounded by the core loop's `max_iterations`.

```lmpl
invariant recursion_depth(state) <= params.max_iterations,
    "nested skill invocations cannot outrun the iteration budget"
```

---

## 10. LMPL Gaps and Proposed Extensions

### 10.1 Frontmatter as a typed record

Every extension file declares a typed schema in its frontmatter; LMPL can express the schema as a record type (`ExtensionFrontmatter`), but the *source file* is untyped YAML. A `@from_file(schema, delimiter)` annotation would bind a typed record to its serialization format:

```lmpl
@from_file(schema: ExtensionFrontmatter, delimiter: "---")
define parse_extension(path: string) -> Extension
```

### 10.2 Prompt-contract linting

`description_unambiguous_within(registry)` is a semantic property of natural-language strings — checkable only by an LLM or heuristic. LMPL currently expresses this as a predicate; a `@prompt_lint("no_overlap")` annotation would make it an explicit authoring obligation and link it to a checker.

### 10.3 Scope-narrowing effects

`narrow_tools_for_extension` creates a scoped tool catalog for the duration of an invocation. LMPL can model this as returning a new registry, but the *scope lifetime* (tied to a specific invocation) is awkward. A `with_scope(narrowed_catalog) do: ...` block would express the lifetime structurally.

### 10.4 Multi-message template expansion

Slash-commands can expand into multiple messages of different roles. LMPL expresses this as a `list[Message]` return, which loses the template-authorship structure (which chunks came from which template section). A `message_template` type with named sections would preserve provenance.

### 10.5 Meta-tools as a kind

Both the `Task` tool (Tool catalog §6.5) and the `Skill` tool are meta-tools: they dispatch further execution rather than performing an effect. The `ToolCategory` tag `"meta"` is coarse. A subdivision (`"dispatch_subagent"`, `"dispatch_extension"`) would let the guardrail and concurrency layers distinguish them. Small but worth considering.

---

## 11. Cross-Spec References

| Reference                                | From                               | To                            |
|------------------------------------------|------------------------------------|-------------------------------|
| `ToolDefinition`, `ToolCategory`         | §7.2 (`Skill` tool), §7.4          | Tool catalog §3               |
| `can_use_tool` for narrowed catalogs     | §7.4                               | Guardrails §4                 |
| MCP prompts as parallel user extensions  | §7.1 (message-prepending pattern)  | MCP §7                        |
| Hook integration (pre-expansion / post-invocation) | (not modeled here)      | Hooks (future)                |
| Plugin packaging and `plugin.json`       | §5.3                               | Plugin ecosystem (future)     |
| Recursive `query()` via skill-triggered Task | §9.3                           | Core loop (#0), Sub-agents    |

---

## 12. References

- Varonis Threat Labs, "A Look Inside Claude's Leaked AI Coding Agent" — https://www.varonis.com/blog/claude-code-leak (skills and commands in the tool catalog; plugin-provided extensions)
- cablate, *claude-code-research* — https://github.com/cablate/claude-code-research (Skill tool, progressive disclosure, frontmatter patterns)
- Blake Crosley, "What the Claude Code Source Leak Reveals" — https://blakecrosley.com/blog/claude-code-source-leak (plugin ecosystem observations; skill discovery)
- FlorianBruniaux, *claude-code-ultimate-guide* — https://github.com/FlorianBruniaux/claude-code-ultimate-guide (skills, slash-commands, and hooks as user-authored extensions; observed frontmatter fields)

No source code is reproduced. All pseudocode is an independent LMPL expression of the documented extension model.
