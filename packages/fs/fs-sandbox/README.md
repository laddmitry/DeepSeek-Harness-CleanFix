---
description: "The offline-kit ctx.fs backend for deployments confining file observation and mutations to a fixed workspace."
kind: "package-reference"
---

# @deepseek-ai/dsh-fs-sandbox

English | [中文](README.zh.md)

## Summary

`dsh-fs-sandbox` restricts reads, metadata, listings, watches, writes and edits to the deployment workspace configured by `ctx.sandboxPolicy.workspaceRoot`. `read-only` additionally rejects every mutation; `workspace-write` requires both deployment containment and the per-call writable policy. `danger-full-access` is forbidden. Use it instead of `fs-local` in the offline kit. Denied filesystem operations return `FS_SANDBOX_DENIED`.

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

Mount this backend instead of `fs-local` when file observation and mutations must remain inside one deployment workspace. Session cwd, platform temp roots and approved write grants cannot widen that workspace. The calling session's policy can narrow its writable set or select read-only access.

### Minimal composition

Load the shared policy service, then this backend, then the tools; the read-before-edit policy plugin stays optional.

```yaml
- name: '@deepseek-ai/dsh-sandbox-policy'
- name: '@deepseek-ai/dsh-fs-sandbox'
  config:
    cwd: /absolute/path/to/workspace
- name: '@deepseek-ai/dsh-tool-fs'
```

The backend's config is unchanged from the local backend's (`cwd` resolution default and `diffBasisMaxBytes` overwrite bound); the [configuration catalog](../../../docs/config-catalog.md#deepseek-aidsh-fs-sandbox) is the exhaustive source.

### How the fence behaves

The provider canonicalizes and checks targets against the deployment root during resolution and immediately before each operation. A caller-supplied `FsTarget` cannot bypass this check. Mutations additionally enforce the resolved per-call mode: read-only denies writes and edits; workspace-write intersects `writableRoots` with the deployment workspace. Temp paths outside the deployment root remain denied. Full-access deployment configuration and full-access write stamps are rejected.

### Observable success and failures

Inside the deployment workspace, reads, listings, metadata and watches retain the local backend's behavior. Outside access fails before the delegated operation. An approved workspace-write stamp can permit an inside write under a read-only default, but cannot enable full access or extend the deployment root.

-----

<a id="understand-the-implementation"></a>
## Understand the implementation

<details>
<summary>Implementation internals — click to expand</summary>

This section explains the design decisions behind the sandbox backend and points at the code that realizes them; the observable behavior is fully covered in [Use this package](#use-this-package).

### Design concept

The fence is a policy check in trusted code over a model-controlled path — not a kernel boundary. The operations are the seam's own (open, rename); only the target path is untrusted, so canonicalize-then-contain is the complete answer to this surface. Kernel-grade isolation of untrusted code stays `ctx.shell`'s job.

### Source map

| File | Role |
|---|---|
| [`src/index.ts`](src/index.ts) | `SandboxedFileSystem`: deployment-root checks on all filesystem operations, mutation mode checks, `sandboxMode` fact |
| [`src/containment.ts`](src/containment.ts) | Ancestor containment check with lexical fast path and identity-based fallback |

### How a mutation is fenced

Each mutation rejects full access, checks the supplied target against the deployment root, and rejects read-only writes. Workspace-write then resolves the display path again and requires containment under a per-call writable root. Both checks must succeed; the delegated mutation uses the fresh target.

### Threat model

The residual resolve-to-syscall TOCTOU is narrowed by re-canonicalizing immediately before the write and is accepted for this threat model; a kernel-tight boundary would need `openat2`-class primitives whose portability cost is not worth it here. A denial is a structured `FsError`, not stderr inference — an in-process fence knows exactly what it refused.

</details>

-----

<a id="further-exploration"></a>
## Further Exploration

Read these pages when the package-level contract is not enough. They move from this backend to the shared policy home and the confinement decisions behind it.

- [Filesystem subsystem](../../../docs/subsystems/filesystem.md) — exhaustive provider contract, policy events, and error taxonomy.
- [dsh-fs](../fs/README.md) — the `ctx.fs` contract this backend implements.
- [fs-local](../fs-local/README.md) — the local backend this one extends.
- [sandbox-policy](../../sandbox/sandbox-policy/README.md) — the shared per-session policy resolver this backend requires.
- [Process sandbox subsystem](../../../docs/subsystems/sandbox.md) — modes, per-call policy, and fail-closed errors.
- [Cross-family fs sandbox decision](../../../.agents/notes/implemented/feature/2026-07-14-cross-family-fs-sandbox.md) — the shared mode fence and its escalation choreography.

-----

<a id="model-experience"></a>
## Model Experience

### Filesystem policy and refusals

#### What the model sees

The policy owner contributes capability-neutral `sandbox:policy` context. Indirectly, `dsh-tool-fs` renders this backend's `FS_SANDBOX_DENIED` refusals as the `[sandbox: file access denied under <mode> mode]` marker plus the same-turn escalation hint.

#### Token effect

The current-policy clause adds a small runtime-context message while this backend is mounted; a denial adds the bounded marker and escalation hint to conversation history.

#### KV Cache effect

A standing-policy change appends an owner-rendered superseding runtime-context snapshot after retained history; operation results remain append-only.

## Known Limitations and Deferred Work

<a id="known-limitations-and-deferred-work"></a>


These limits define when the sandbox backend is a poor fit or needs special operational care. They are current package constraints, not a general sandbox comparison or a task backlog.

- **A policy fence, not a kernel boundary** — the check is trusted code over a model-controlled path, so the residual resolve-to-syscall TOCTOU is narrowed (by the in-place re-canonicalization) but not eliminated; adversarial host processes are out of scope. Kernel-grade isolation of untrusted code stays `ctx.shell`'s.
- **Filesystem access is narrower than process temp grants** — the deployment-root check also applies when `writableRoots` permits a temp area outside that root.
- **Requires `ctx.sandboxPolicy`** — tools use it to resolve each session policy and the backend uses it for agentless-call fallbacks; the backend does not confine without it composed.

<a id="dev-note"></a>
### Dev Note

<details>
<summary>Working context for maintainers — click to expand</summary>

None.

</details>

**Runtime invariant:** No companion is published. This stateless adapter delegates policy and filesystem relations to their owning seams.
