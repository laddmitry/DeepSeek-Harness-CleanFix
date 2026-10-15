/** Host registry-response probing for the plugin installation dialog. */

import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { MAX_TIMER_DELAY_MS } from '@deepseek-ai/dsh-timeout'
import { Remote, TypertRemoteService } from '@deepseek-ai/dsh-typert-protocol'

declare module '@deepseek-ai/cordis' {
  interface Context {
    pluginRegistryProbe: PluginRegistryProbe
  }
}

/** Registry-probe deadline and process-local cache policy. */
export interface Config {
  /** Whether the dialog can compare the public npm registries. */
  registryProbeEnabled: boolean
  /** Deadline for the parallel HTTPS probes, including response cleanup. */
  registryProbeTimeoutMs: number
  /** Lifetime of a winning registry or unavailable result. */
  registryProbeCacheTtlMs: number
}

/** Compares public registry responses on the Host; the Client owns the initial selection. */
export default class PluginRegistryProbe extends TypertRemoteService {
  static Config: z<Partial<Config>, Config> = z.object({
    registryProbeEnabled: z.boolean().default(false),
    registryProbeTimeoutMs: z.natural().min(1).max(MAX_TIMER_DELAY_MS).default(1500),
    registryProbeCacheTtlMs: z.natural().default(300000),
  })

  constructor(ctx: Context, _config: Config) {
    super(ctx, 'pluginRegistryProbe')
  }

  /**
   * Offline deployment: registry network probing is physically removed.
   * @returns null; this deployment never contacts a registry.
   */
  @Remote
  async fastest(): Promise<string | null> {
    return null
  }
}
