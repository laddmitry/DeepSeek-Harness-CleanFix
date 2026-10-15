/** Literal local model endpoints and outbound TCP admission for the cleaned CLI. */
import { appendFileSync } from 'node:fs'
import { isIP, Socket } from 'node:net'

/** A configured endpoint whose DNS resolution cannot select a public address. */
export interface LocalModelEndpoint {
  readonly baseURL: string
  readonly host: string
  readonly port: number
}

/**
 * Resolve a model API on loopback or an explicitly named private IPv4 address.
 * @param value - Deployment URL; localhost is normalized to IPv4 loopback.
 * @returns Validated URL and numeric TCP destination.
 * @throws When the URL requires public routing, DNS, credentials, or a non-HTTP protocol.
 */
export function resolveLocalModelEndpoint(value: string): LocalModelEndpoint {
  const url = new URL(value)
  if (url.hostname === 'localhost') url.hostname = '127.0.0.1'
  const host = url.hostname.replace(/^\[|\]$/g, '')
  const octets = host.split('.').map(Number)
  const privateV4 = isIP(host) === 4 && (octets[0] === 127 || octets[0] === 10
    || (octets[0] === 172 && octets[1]! >= 16 && octets[1]! <= 31)
    || (octets[0] === 192 && octets[1] === 168))
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password
    || url.search || url.hash || (!privateV4 && host !== '::1')) {
    throw new Error('LOCAL_NETWORK_POLICY: model URL must use loopback or a literal private IPv4 address without credentials, query or fragment')
  }
  return { baseURL: url.href.replace(/\/$/, ''), host, port: Number(url.port || (url.protocol === 'https:' ? 443 : 80)) }
}

/** Parse the public Socket.connect overloads, including Node's normalized argument tuple. */
function destination(args: readonly unknown[]): { host: string; port: number } | undefined {
  const normalized = Array.isArray(args[0]) ? args[0] : args
  const first: unknown = normalized[0]
  if (typeof first === 'object' && first !== null && 'port' in first) {
    const host = 'host' in first && typeof first.host === 'string' ? first.host : 'localhost'
    const port = first.port
    return { host, port: typeof port === 'number' || typeof port === 'string' ? Number(port) : NaN }
  }
  if (typeof first === 'number' || (typeof first === 'string' && /^\d+$/.test(first))) {
    return { port: Number(first), host: typeof normalized[1] === 'string' ? normalized[1] : 'localhost' }
  }
  return undefined
}

/**
 * Admit outbound TCP only to the configured model endpoint before plugins mount.
 * Local pipe transports are refused; anonymous inherited stdio is unaffected.
 * This process guard does not confine native code, child processes, or the model server.
 * @param endpoint - Validated numeric destination for this launch.
 * @param logPath - Optional JSONL evidence file, with destination metadata only.
 * @returns Disposer restoring the previous Socket implementation.
 */
export function installLocalNetworkPolicy(endpoint: LocalModelEndpoint, logPath?: string): () => void {
  const original = Socket.prototype.connect
  const guarded = function (this: Socket, ...args: unknown[]): Socket {
    const target = destination(args)
    const host = target?.host === 'localhost' ? '127.0.0.1' : target?.host.replace(/^\[|\]$/g, '')
    const allowed = host === endpoint.host && target?.port === endpoint.port
    if (logPath !== undefined) appendFileSync(logPath, JSON.stringify({ time: new Date().toISOString(), pid: process.pid,
      event: allowed ? 'TCP_ALLOWED' : 'TCP_DENIED', host: host ?? 'non-TCP', port: target?.port ?? null }) + '\n')
    if (!allowed) throw new Error(`LOCAL_NETWORK_POLICY: outbound connection refused (${host ?? 'non-TCP'}:${target?.port ?? ''})`)
    return Reflect.apply(original, this, args) as Socket
  } as typeof Socket.prototype.connect
  Socket.prototype.connect = guarded
  return () => { if (Socket.prototype.connect === guarded) Socket.prototype.connect = original }
}
