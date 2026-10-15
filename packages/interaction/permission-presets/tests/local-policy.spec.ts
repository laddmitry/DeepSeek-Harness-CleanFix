import { describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import SessionStore, { SessionId } from '@deepseek-ai/dsh-session'
import SessionProjectionRegistry from '@deepseek-ai/dsh-session-projection'
import SandboxPolicy from '@deepseek-ai/dsh-sandbox-policy'
import PermissionPresets from '../src/index.ts'

async function mount() {
  const ctx = new Context()
  await ctx.plugin(SessionStore)
  await ctx.plugin(SessionProjectionRegistry)
  await ctx.plugin(SandboxPolicy, { mode: 'workspace-write' })
  ctx.provide('approval', { config: { policy: 'ask' } })
  await ctx.plugin(PermissionPresets)
  return ctx
}

describe('local permissions without a shell executor', () => {
  it('switches safe modes, preserves the projection, and resumes recorded policy', async () => {
    const ctx = await mount()
    try {
      expect(ctx.get('shell')).toBeUndefined()
      const session = ctx.sessions.create(SessionId('local-permissions'))
      expect(ctx.permissionPresets.current(session)).toBe('workspace-write')
      ctx.permissionPresets.set(session, 'read-only')
      expect(ctx.sandboxPolicy.resolve({ session }).mode).toBe('read-only')
      expect(ctx.sessionProjections.snapshot(session).values.permissions).toEqual({ currentValue: 'read-only' })
      const resumed = ctx.sessions.create(SessionId('local-resumed'), { seed: session.snapshotEvents() })
      expect(ctx.permissionPresets.current(resumed)).toBe('read-only')
      expect(ctx.sandboxPolicy.resolve({ session: resumed }).mode).toBe('read-only')
      const length = resumed.snapshotEvents().length
      ctx.permissionPresets.set(resumed, 'read-only')
      expect(resumed.snapshotEvents()).toHaveLength(length)
    } finally { await ctx.fiber.dispose() }
  })

  it('does not advertise or register full access, including Auto', async () => {
    const ctx = await mount()
    try {
      expect(ctx.permissionPresets.names).toEqual(['workspace-write', 'read-only'])
      expect(() => ctx.permissionPresets.registerAuto(() => {})).toThrow(/forbidden/)
      const session = ctx.sessions.create(SessionId('local-no-full-access'))
      const before = session.snapshotEvents()
      expect(() => ctx.permissionPresets.set(session, 'danger-full-access')).toThrow(/unknown preset/)
      expect(session.snapshotEvents()).toEqual(before)
    } finally { await ctx.fiber.dispose() }
  })
})
