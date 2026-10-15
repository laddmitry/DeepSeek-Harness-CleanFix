/**
 * Tests for the sandbox-enforcing filesystem backend: the per-call policy fence
 * on write/edit and deployment-root reads (read-only denies mutations,
 * workspace-write contains, danger-full-access is rejected), the capability fact, and the
 * containment matrix — `..` traversal, absolute paths outside, and symlink
 * escapes (a symlinked directory inside the workspace pointing out, and a new
 * file created under one). The fence is exercised on a real filesystem: a
 * denied write leaves no file on disk.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, parse } from 'node:path'
import { Context } from '@deepseek-ai/cordis'
import { FsError, FsTargetKey } from '@deepseek-ai/dsh-fs'
import type { FsTarget } from '@deepseek-ai/dsh-fs'
import SandboxPolicyService from '@deepseek-ai/dsh-sandbox-policy'
import SessionProjectionRegistry from '@deepseek-ai/dsh-session-projection'
import type { SandboxMode } from '@deepseek-ai/dsh-sandbox'
import { SandboxedFileSystem } from '@deepseek-ai/dsh-fs-sandbox'
import { assertWorkspaceOutsideTemp, outsideTempWorkspaceParent } from '../../../../scripts/snapshot-workspace-parent.ts'

let base: string
let workspace: string
let outside: string
let ctx: Context
let fs: SandboxedFileSystem
let fiber: Awaited<ReturnType<Context['plugin']>>

async function boot(mode: SandboxMode): Promise<void> {
  ctx = new Context()
  await ctx.plugin(SessionProjectionRegistry)
  await ctx.plugin(SandboxPolicyService, { mode, workspaceRoot: workspace })
  fiber = await ctx.plugin(SandboxedFileSystem, { cwd: workspace })
  fs = ctx.fs as SandboxedFileSystem
}

beforeEach(async ({ onTestFinished }) => {
  // Both siblings must be outside automatic temp grants for containment denials to be meaningful.
  const directory = await mkdtemp(join(outsideTempWorkspaceParent(), '.dsh-fssbx-'))
  onTestFinished(async () => { await rm(directory, { recursive: true, force: true }) })
  base = directory
  assertWorkspaceOutsideTemp(base)
  workspace = join(base, 'ws')
  outside = join(base, 'out')
  await mkdir(workspace)
  await mkdir(outside)
})
afterEach(async () => {
  await fiber?.dispose()
})

/** Resolve a path through the backend and return its target. */
function target(path: string): Promise<FsTarget> {
  return fs.resolve(path)
}

describe('the capability fact', () => {
  it('reports the deployment default mode (what the tool layer advertises against)', async () => {
    await boot('workspace-write')
    expect(fs.sandboxMode).toBe('workspace-write')
  })
})

describe('read-only', () => {
  beforeEach(() => boot('read-only'))

  it('denies write, leaving no file on disk', async () => {
    const path = join(workspace, 'denied.txt')
    await expect(fs.writeText(await target(path), 'x')).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(existsSync(path)).toBe(false)
  })

  it('denies edit of an existing file (the content is unchanged)', async () => {
    const path = join(workspace, 'file.txt')
    await writeFile(path, 'original')
    await expect(fs.editText(await target(path), { oldString: 'original', newString: 'changed', replaceAll: false }))
      .rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(await readFile(path, 'utf8')).toBe('original')
  })

  it('allows reads (every mode permits reading)', async () => {
    const path = join(workspace, 'readable.txt')
    await writeFile(path, 'hello')
    expect(await fs.readText(await target(path))).toBe('hello')
  })
})

describe('workspace-write containment', () => {
  beforeEach(() => boot('workspace-write'))

  it('a write under the workspace lands', async () => {
    const path = join(workspace, 'nested', 'ok.txt')
    const outcome = await fs.writeText(await target(path), 'inside')
    expect(outcome.operation).toBe('create')
    expect(await readFile(path, 'utf8')).toBe('inside')
  })

  it('rejects platform temp outside the deployment root', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'dsh-fssbx-tmp-'))
    try {
      const path = join(dir, 'temp.txt')
      await expect(target(path).then(t => fs.writeText(t, 'temp'))).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
      expect(existsSync(path)).toBe(false)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  it('an absolute path outside the workspace is denied, no file created', async () => {
    const path = join(outside, 'escape.txt')
    await expect(target(path).then(t => fs.writeText(t, 'x'))).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(existsSync(path)).toBe(false)
  })

  it('a `..` traversal out of the workspace is denied', async () => {
    const path = join(workspace, '..', 'sibling-escape.txt')
    await expect(target(path).then(t => fs.writeText(t, 'x'))).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(existsSync(join(workspace, '..', 'sibling-escape.txt'))).toBe(false)
  })

  it('a symlinked directory inside the workspace pointing OUT is denied (canonicalized before containment)', async () => {
    // workspace/link -> outside ; writing workspace/link/f.txt would land in outside/f.txt.
    await symlink(outside, join(workspace, 'link'), process.platform === 'win32' ? 'junction' : 'dir')
    const path = join(workspace, 'link', 'f.txt')
    await expect(target(path).then(t => fs.writeText(t, 'x'))).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(existsSync(join(outside, 'f.txt'))).toBe(false)
  })

  it('a NEW file created under a symlinked-out directory is denied (deepest-ancestor realpath)', async () => {
    await symlink(outside, join(workspace, 'link'), process.platform === 'win32' ? 'junction' : 'dir')
    const path = join(workspace, 'link', 'newdir', 'deep.txt')
    await expect(target(path).then(t => fs.writeText(t, 'x'))).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(existsSync(join(outside, 'newdir'))).toBe(false)
  })

  it('an edit outside the workspace is denied; the original is untouched', async () => {
    const path = join(outside, 'file.txt')
    await writeFile(path, 'original')
    await expect(target(path).then(t => fs.editText(t, { oldString: 'original', newString: 'x', replaceAll: false })))
      .rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(await readFile(path, 'utf8')).toBe('original')
  })

  it('an edit inside the workspace lands', async () => {
    const path = join(workspace, 'edit.txt')
    await writeFile(path, 'original')
    const outcome = await fs.editText(await target(path), { oldString: 'original', newString: 'changed', replaceAll: false })
    expect(outcome.after).toBe('changed')
    expect(await readFile(path, 'utf8')).toBe('changed')
  })

  it('rejects an outside targetKey even when displayPath is inside', async () => {
    const insidePath = join(workspace, 'landed.txt')
    const staleTarget: FsTarget = { displayPath: insidePath, targetKey: FsTargetKey(join(outside, 'escaped.txt')) }
    await expect(fs.writeText(staleTarget, 'inside')).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(existsSync(insidePath)).toBe(false)
    expect(existsSync(join(outside, 'escaped.txt'))).toBe(false)
  })

  it('the workspace root itself passes the fence (path equal to a writable root), failing only on file type', async () => {
    // isUnder's path-equals-root branch: the fence allows the root, and the
    // write then fails because the root is a directory, not a regular file.
    await expect(fs.writeText(await target(workspace), 'x')).rejects.toMatchObject({ code: 'FS_NOT_REGULAR_FILE' })
  })
})

describe('workspace-write with the filesystem root as the workspace (a root ending in the path separator)', () => {
  it('grants writes anywhere on that volume', async () => {
    // A degenerate but valid config: the filesystem root containing the target.
    // It exercises the separator-suffixed-root branch on POSIX and Windows.
    const rootCtx = new Context()
    await rootCtx.plugin(SessionProjectionRegistry)
    await rootCtx.plugin(SandboxPolicyService, { mode: 'workspace-write', workspaceRoot: parse(base).root })
    const rootFiber = await rootCtx.plugin(SandboxedFileSystem, { cwd: workspace })
    const rootFs = rootCtx.fs as SandboxedFileSystem
    try {
      const path = join(base, 'anywhere.txt') // outside temp — allowed only via the filesystem root
      await rootFs.writeText(await rootFs.resolve(path), 'anywhere')
      expect(await readFile(path, 'utf8')).toBe('anywhere')
    } finally {
      await rootFiber.dispose()
    }
  })
})

describe('danger-full-access', () => {
  it('rejects the deployment mode during configuration', async () => {
    await expect(boot('danger-full-access')).rejects.toThrow('danger-full-access is forbidden')
  })
})

describe('the per-call policy override (escalation)', () => {
  it('a workspace-write stamp on a read-only default lets a contained write land for that call only', async () => {
    await boot('read-only')
    const path = join(workspace, 'escalated.txt')
    // Default read-only would deny; the per-call workspace-write policy allows it (contained).
    await fs.writeText(await target(path), 'granted', undefined, undefined, { mode: 'workspace-write', workspaceRoot: workspace })
    expect(await readFile(path, 'utf8')).toBe('granted')
    // A neighboring plain call still runs under the read-only default.
    await expect(fs.writeText(await target(join(workspace, 'plain.txt')), 'x'))
      .rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
  })

  it('rejects a danger-full-access stamp even for an inside target', async () => {
    await boot('read-only')
    const path = join(workspace, 'granted-full.txt')
    await expect(fs.writeText(await target(path), 'full', undefined, undefined, { mode: 'danger-full-access', workspaceRoot: workspace }))
      .rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(existsSync(path)).toBe(false)
  })
})

describe('deployment-root observation', () => {
  beforeEach(() => boot('workspace-write'))

  it.each(['stat', 'readText', 'readBytes', 'readByteRange', 'listDir', 'streamText'] as const)('denies direct %s with a forged outside target', async (method) => {
    const path = join(outside, 'canary.txt')
    await writeFile(path, 'outside-canary')
    const forged: FsTarget = { displayPath: path, targetKey: FsTargetKey(path) }
    const operations = {
      stat: () => fs.stat(forged),
      readText: () => fs.readText(forged),
      readBytes: () => fs.readBytes(forged, undefined, 1024),
      readByteRange: () => fs.readByteRange(forged, { offset: 0, length: 10 }),
      listDir: () => fs.listDir(forged),
      streamText: () => fs.streamText(forged),
    }
    await expect(operations[method]()).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    expect(await readFile(path, 'utf8')).toBe('outside-canary')
  })

  it('denies lstat outside and a session-selected cwd cannot widen the root', async () => {
    await expect(fs.lstat(join(outside, 'metadata.txt'))).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    await expect(fs.resolve('metadata.txt', { cwd: outside })).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
  })

  it('denies outside watches and releases a watcher if the guard regresses', async () => {
    const controller = new AbortController()
    let dispose: (() => Promise<void>) | undefined
    const forged: FsTarget = { displayPath: outside, targetKey: FsTargetKey(outside) }
    try {
      const watching = fs.watch(forged, () => {}, controller.signal).then(handler => { dispose = handler; return handler })
      await expect(watching).rejects.toMatchObject({ code: 'FS_SANDBOX_DENIED' })
    } finally {
      controller.abort()
      await dispose?.()
    }
  })
})

describe('registration and HMR safety', () => {
  it('registers as ctx.fs and unregisters cleanly from a child fiber', async () => {
    await boot('workspace-write')
    expect(ctx.fs).toBeInstanceOf(SandboxedFileSystem)
    await fiber.dispose()
    expect(ctx.get('fs')).toBeUndefined()
    // Re-mount below the disposed one to prove no lingering registration.
    fiber = await ctx.plugin(SandboxedFileSystem, { cwd: workspace })
    expect(ctx.fs).toBeInstanceOf(SandboxedFileSystem)
  })
})

describe('FsError identity', () => {
  it('the denial is a structured FsError distinct from a host permission error', async () => {
    await boot('read-only')
    const error = await fs.writeText(await target(join(workspace, 'x.txt')), 'x').catch((e: unknown) => e)
    expect(error).toBeInstanceOf(FsError)
    expect((error as FsError).code).toBe('FS_SANDBOX_DENIED')
  })
})
