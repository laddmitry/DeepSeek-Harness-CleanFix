---
description: "The shared dsh core: model access, tools, durable sessions, and safety defaults for every dsh --profile surface, for users composing or customizing a profile."
kind: "package-bundle"
---

# @deepseek-ai/dsh-base

The cleaned composition preserves local history, filesystem tools, skills, instructions, settings, permission presets and in-process subagents. Model configuration comes from `DSH_LOCAL_MODEL_BASE_URL`, `DSH_LOCAL_MODEL_NAME` (default `qwen3:0.6b`), `DSH_LOCAL_MODEL_CONTEXT_WINDOW` (8192) and `DSH_LOCAL_MODEL_MAX_TOKENS` (2048). `LOCAL_MODEL_API_KEY` overrides the synthetic local key. Windows worker credentials use `DSH_WORKER_CREDENTIAL_FILE`, defaulting to `C:/DSH/data/worker-credentials.json`. Subprocess, sandbox and model-provider activation failures reject startup. Cloud exporters and arbitrary execution remain disabled.

English | [中文](README.zh.md)

For the default Qwen3 model the profile declares its reasoning capability and defaults `DSH_LOCAL_MODEL_REASONING` to `off`, which maps to OpenAI-compatible `reasoning_effort: none`. This avoids spending the output budget on thinking before producing tool calls. Other model names default to non-reasoning metadata; deployments with reasoning models must supply their supported levels.

## Summary

Every base-backed `dsh --profile` surface runs on `dsh-base`, so those surfaces share a model connection, the full tool set, durable session history, and workspace safety defaults. The shipped `sdk-minimal` profile deliberately uses a complete standalone tree instead. You rarely touch this bundle directly — shipped base-backed profiles already include it, and a custom base-backed profile names it first. When you need different defaults, change your profile patch or add a later bundle; this package is not a library you import.

## Table of Contents

- [Use this package](#use-this-package)
- [Understand the implementation](#understand-the-implementation)
- [Further Exploration](#further-exploration)
- [Model Experience](#model-experience)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)
- [Dev Note](#dev-note)

-----

<a id="use-this-package"></a>
## Use this package

You get the dsh core automatically: the shipped `web`, `headless`, `sdk`, and `acp` profiles already include it, and a custom profile names it as its first bundle. After that, everything works with no further configuration.

### A minimal custom profile

To build a profile on the shared core, create a profile with a `package.json` that names `@deepseek-ai/dsh-base` first:

```json
{
  "name": "my-profile",
  "private": true,
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base"]
    }
  }
}
```

Run `dsh --profile my-profile "your task"` and you get a working agent with model access, tools, persistence, and the default permission policy. The shipped `web`, `headless`, `sdk`, and `acp` profiles are created for you on first use. To add more bundles, run `dsh plugin --profile <name> add <package>`; in-box bundles resolve from the dsh installation. The profile contract is documented in the [app-boot profile section](../../boot/app-boot/README.md).

### What you get

Out of the box, every profile built on this core provides: a DeepSeek model connection (the provider and model are configurable, and you can enable extra providers from your settings), the full tool set — file editing, shell commands, web search, public HTTP(S) fetch, subagents, task and goal tracking — durable sessions that survive restarts, and the default permission policy that confines file writes to your workspace and asks before risky actions. Web fetch runs without per-call approval; its provider rejects non-public destinations. Feedback stays in the Session log. [OTel session upload](../../session/session-telemetry-otel/README.md) defaults to `FEEDBACK_ONLY` for all users, including `deepseek-official`: new text feedback, message ratings, edits, and withdrawals release the complete canonical prefix through that event, including context. Later records wait for the next explicit feedback; sending an authorized batch needs no further interaction or model call. `DISABLED` prevents OTel capture. The default-on [DeepSeek session-log contributor](../../session/session-log-deepseek/README.md) remains a separate request path.

Default file editing uses `read`, `write`, and `edit`. The `str_replace_editor` tool remains available as an explicit opt-in. To add it to a base-backed profile, put this entry in the profile, home, or invocation patch:

```yaml
- insert:
    - id: tool-str-replace-editor
      name: '@deepseek-ai/dsh-tool-str-replace-editor'
      config:
        maxOutputChars: 16000
```

The bundle mounts [MCP resources](../../mcp/mcp-resources/README.md) once. Configure only [MCP client entries](../../mcp/mcp-client/README.md) for the servers you need. Clients mounted by another provider also count as configured in their scope. Callers with no configured server in scope receive no MCP tools or prompt text.

### Shell tools per platform

The cleaned LOCAL_ONLY web/headless profiles expose filesystem tools instead of arbitrary shell, persistent-terminal, PTC, or workflow execution on every platform. Windows write-restricted tokens retain unrestricted reads, so this composition removes the execution route rather than claiming OS read isolation. The permission selector requires a shell provider and is disabled; the installation keeps its fixed workspace-write filesystem policy. Trusted operator commands run separately.

### Changing the defaults

To change what a profile built on this core provides — a different default model, a stricter permission mode, extra or fewer tools — edit your profile's `cordis.patch.yml` or add a later bundle. Each patch entry replaces the target's whole configuration, so restate every setting you want to keep. Keep the sandboxed filesystem provider as the single file-write path: adding the plain filesystem provider on top of it makes the profile fail to load.

-----

<a id="understand-the-implementation"></a>
## Understand the implementation

<details>
<summary>Implementation internals — click to expand</summary>

The bundle is a static patch document: one `insert` list applied over the empty profile root. It mounts no service, emits no events, and holds no mutable state; each inserted row's package owns that row's behavior and invariants.

### Composition mechanics

A patch replaces the targeted row's whole `config` rather than merging into it. Later bundle layers and the user's profile `cordis.patch.yml` override rows by id, with the last write winning per row. Rows whose value differs by mode do not live here: each mode bundle restates its complete configuration, keeping any single row down to one bundle layer plus the user's. The full row set and its rationale are documented inline in [`cordis.patch.yml`](cordis.patch.yml); the [generated composition graph](../../../apps/cli/composition.md) renders it.

### Platform gating

The cleaned installation sets shell providers and consumers, persistent terminals, PTC, and workflow rows to disabled: true. Profile and preset preflight refuses the corresponding resolved package names before import, including aliases and nested groups. These rows cannot be restored through the excluded user/home/CLI patch layers. Filesystem tools retain the sandboxed filesystem provider.

### Source map

| File | Role |
|---|---|
| [`cordis.patch.yml`](cordis.patch.yml) | The bundle substance: the base plugin rows, with per-row rationale as inline comments |
| [`src/index.ts`](src/index.ts) | Package entry; carries no runtime API |
| — | No runtime invariant companion is published; the package is a static patch-list carrier (a YAML document of loader rows owned by other packages); it mounts no service, emits no events, and owns no mutable relation to check. Each inserted row's own package carries that row's invariants. |
| [`tests/base.spec.ts`](tests/base.spec.ts) | Manifest declaration and platform-gating checks |

### Invariant ownership

No invariant companion is published because the package is a static patch-list carrier: each inserted row's package owns that row's invariants, and the bundle owns no mutable relation to check.

</details>

-----

<a id="further-exploration"></a>
## Further Exploration

Read these pages when you want to go deeper into profiles, the surfaces built on this core, or the exact composition.

- [app-boot profile section](../../boot/app-boot/README.md) — how profiles are resolved, layered, and customized.
- [Bundle package map](../README.md) — the surfaces built on this core.
- [Generated composition graph](../../../apps/cli/composition.md) — the exact plugin set each shipped profile uses.
- [Profile plugin bundles note](../../../.agents/notes/implemented/architecture/2026-08-05-profile-plugin-bundles.md) — the profile and bundle composition design.
- [Codex and Claude Code provider bundles](../../subagent/README.md) — optional provider bundles you can install on top.

-----

<a id="model-experience"></a>
## Model Experience

Indirectly, through each inserted row's package, which owns that row's model-facing behavior.

#### KV Cache effect

The bundle itself adds no request prefix; each inserted row's package owns any cache effect.

## Known Limitations and Deferred Work

The cleaned LOCAL_ONLY installation disables arbitrary shell, persistent-terminal, PTC, and workflow execution. Model-facing filesystem tools remain available. Windows write-restricted tokens do not restrict reads; this composition removes the arbitrary execution route instead of claiming OS read isolation. The installation preflight refuses these providers and consumers in preset trees before module import, including compatibility exemptions and package aliases.

<a id="known-limitations-and-deferred-work"></a>


These limits tell you when the core needs extra care or where an override must go. They are current package constraints, not a general comparison or a task backlog.

- **Overrides replace whole settings blocks** — a patch entry replaces the target's entire configuration, so your override must restate every setting you want to keep; nothing merges automatically.
- **Per-surface settings belong to the surface's bundle** — a default that differs between the web GUI and headless mode lives in that surface's bundle, not in the shared core.
- **Windows temp grants are private per-session subdirectories** — `workspace-write` confines writes to the workspace plus the session's own temp subdirectory (`<temp>\dsh-<hash>`, TMP/TEMP rewritten for confined children); `read-only` grants nothing. See `@deepseek-ai/dsh-sandbox-windows-acl`.
- **Adding the plain filesystem provider on top of the sandboxed one fails the profile** — the two register the same service, so the profile refuses to load; use one or the other.

<a id="dev-note"></a>
### Dev Note

<details>
<summary>Working context for maintainers — click to expand</summary>

None.

</details>

The base composition mounts authorization and the platform account provider alongside credentials. The provider opens a callback listener only during an explicit login attempt.
