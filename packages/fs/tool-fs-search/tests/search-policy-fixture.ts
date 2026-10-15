/** Search-consumer fixtures; process confinement is mocked and is not security evidence. */
import type { Context } from '@deepseek-ai/cordis'
import SandboxProvider from '@deepseek-ai/dsh-sandbox'
import type { ConfinedArgv, SandboxPolicy, SandboxMode } from '@deepseek-ai/dsh-sandbox'
import SandboxPolicyService from '@deepseek-ai/dsh-sandbox-policy'
import SessionProjectionRegistry from '@deepseek-ai/dsh-session-projection'
import type { Session } from '@deepseek-ai/dsh-session'

/** OS mock for consumer argv tests; callers observe partial enforcement explicitly. */
export class SearchFixtureSandbox extends SandboxProvider {
  readonly calls: { argv: string[]; policy: SandboxPolicy }[] = []

  /** Record the resolved policy and preserve the exact argv for the scripted subprocess. */
  override async confine(argv: readonly string[], policy: SandboxPolicy): Promise<ConfinedArgv> {
    this.calls.push({ argv: [...argv], policy })
    return { argv: [...argv], enforcement: 'partial', denialSignatures: [], runnerFailureRules: [] }
  }
}

/** Header-only test sessions have no persisted mode events; other policy resolution stays real. */
class SearchFixturePolicy extends SandboxPolicyService {
  override overrideOf(_session: Session): SandboxMode | undefined {
    return undefined
  }
}

/** Mount the required policy services without claiming kernel confinement. */
export async function mountSearchPolicy(ctx: Context, workspaceRoot = process.cwd()): Promise<void> {
  await ctx.plugin(SessionProjectionRegistry)
  await ctx.plugin(SearchFixturePolicy, { mode: 'workspace-write', workspaceRoot })
  await ctx.plugin(SearchFixtureSandbox)
}
