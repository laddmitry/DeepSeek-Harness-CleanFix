/** Launcher-owned profile locations and composition inputs. */
import { loadProfileDirectory, type Profile } from './profile.ts'
import { join } from 'node:path'
import { composeEntries, loadOptionalPatches } from './index.ts'
import { PROFILE_PATCH_FILENAME } from './profile.ts'
import type { PatchOptions } from '@deepseek-ai/cordis-plugin-include'

/** Application-owned package manager executable; environment applies only to package operations. */
export interface ProfilePnpmInvocation {
  readonly command: string
  readonly args: readonly string[]
  readonly env: Readonly<Record<string, string>>
}

/** Current profile facts; scheduling and mutation belong to their callers. */
export interface ProfileContext {
  readonly name: string
  /** Packaged applications supply their bundled runtime instead of a PATH executable. */
  readonly packageManager?: ProfilePnpmInvocation
  readonly dir: string
  readonly patchPath: string
  readonly installAnchor: string
  readonly cwd: string
  readonly home: string
  /** Bundle packages used to start this process, before any persisted edits. */
  readonly startedBundles: readonly string[]
  /** Parsed command-line overlays, applied above profile and home patches. */
  readonly overlays: readonly PatchOptions[]
  /** Launch-time DSH_TELEMETRY_DISABLED value; any non-empty value opts out. */
  readonly telemetryDisabledEnv: string | undefined
}

declare module '@deepseek-ai/cordis' {
  interface Context {
    /** Present only in a profile launched by dsh. */
    profileContext: ProfileContext
  }
}

const TELEMETRY_ROW_ID = 'session-telemetry-otel'

/**
 * Resolve the telemetry opt-out switch into its boot patch. ANY non-empty
 * value (including `'0'`/`'false'`) disables: a privacy switch prefers
 * off-by-mistake over on-by-mistake. A composition without the telemetry row
 * exports nothing, so the switch is then trivially satisfied and no patch is
 * generated — custom profiles need not mount telemetry to run with the
 * switch set.
 * @param disabledEnv - the raw `DSH_TELEMETRY_DISABLED` value (`undefined` when unset).
 * @param hasRow - whether the composition carries the telemetry row.
 * @returns the disable patch, or `undefined` when no hard-disable patch is required.
 */
export function resolveTelemetryPatch(disabledEnv: string | undefined, hasRow: boolean): PatchOptions | undefined {
  if ((disabledEnv ?? '') === '' || !hasRow) return undefined
  return { id: TELEMETRY_ROW_ID, disabled: true }
}

/** Read reviewed local bundle layers, then user, home and command-line patches.
 * @param binName Diagnostic prefix.
 * @param context Launcher facts.
 * @param initialProfile Previously resolved installation profile.
 * @returns Installation-owned patches.
 */
export function readProfilePatches(binName: string, context: ProfileContext, initialProfile?: Profile): PatchOptions[] {
  const expected: Record<string, readonly string[]> = {
    web: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'],
    headless: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-headless'],
    sdk: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-sdk-app'],
    acp: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-acp-app'],
  }
  const bundles = expected[context.name]
  if (bundles === undefined) {
    throw new Error(`${binName}: cleaned build permits web, headless, sdk and acp`)
  }
  const profile = initialProfile ?? loadProfileDirectory(binName, context.dir, context.installAnchor, { userLayer: false })
  if (profile.skippedBundles.length !== 0
    || JSON.stringify(profile.layers.map(layer => layer.packageName)) !== JSON.stringify(bundles)) {
    throw new Error(`${binName}: offline build requires exactly the reviewed installation bundles`)
  }
  const patches = structuredClone([
    ...profile.layers.flatMap(layer => layer.patches),
    ...(initialProfile?.patches ?? loadOptionalPatches(binName, context.patchPath) ?? []),
    ...(loadOptionalPatches(binName, join(context.home, PROFILE_PATCH_FILENAME)) ?? []),
    ...context.overlays,
  ])
  const telemetryPatch = resolveTelemetryPatch('1', composeEntries([patches]).some(row => row.id === TELEMETRY_ROW_ID))
  if (telemetryPatch !== undefined) patches.push(telemetryPatch)
  return patches
}
