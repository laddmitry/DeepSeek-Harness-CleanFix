/** Authenticated worker identity selection; credentials never enter child argv or environment. */
import { readFileSync } from 'node:fs'
import { isAbsolute } from 'node:path'
import { allocPtrSlot, allocUint32, decodePtr, decodePtrAt, decodeUint32, sameSidAt, throwLastError } from './ffi.ts'
import type { NativePtr, Win32Bindings } from './ffi.ts'
import { openCurrentProcessToken } from './token.ts'

/** Read a controller-private credential file and authenticate exactly its expected worker SID.
 * @param api - native Win32 binding table.
 * @param path - administrator-provisioned, controller-private absolute credential path.
 * @returns owned primary worker token, which the caller must close.
 */
export function logonWorker(api: Win32Bindings, path: string): NativePtr {
  if (!isAbsolute(path)) throw new Error('worker credentials path must be absolute')
  const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'))
  if (parsed === null || typeof parsed !== 'object') throw new Error('invalid worker credentials')
  const fields = parsed as Record<string, unknown>
  const { username, domain, password, expectedSid } = fields
  if (typeof username !== 'string' || username.length === 0 || typeof domain !== 'string' || domain.length === 0
    || typeof password !== 'string' || password.length === 0 || typeof expectedSid !== 'string' || !/^S-1-5-21-\d+-\d+-\d+-\d+$/u.test(expectedSid)) {
    throw new Error('invalid worker credentials fields')
  }
  const slot = allocPtrSlot()
  // INTERACTIVE creates a primary token with a logon SID needed by the existing restricting list.
  if (api.logonUserW(username, domain, password, 2, 0, slot) === 0) throwLastError(api, 'LogonUserW', 'worker authentication failed')
  const token = decodePtr(slot)
  if (token === null) throw new Error('LogonUserW returned a null worker token')
  let expected: NativePtr | undefined
  let controller: NativePtr | undefined
  try {
    const sidSlot = allocPtrSlot()
    if (api.convertStringSidToSidW(expectedSid, sidSlot) === 0) throwLastError(api, 'ConvertStringSidToSidW', 'expected worker SID')
    expected = decodePtr(sidSlot) ?? undefined
    if (expected === undefined) throw new Error('expected worker SID allocation failed')
    const workerInfo = tokenUser(api, token)
    const workerSid = decodePtrAt(workerInfo, 0)
    if (workerSid === null || !sameSidAt(workerSid, 0, expected, 0)) throw new Error('authenticated worker SID does not match provisioned identity')
    controller = openCurrentProcessToken(api)
    const controllerInfo = tokenUser(api, controller)
    const controllerSid = decodePtrAt(controllerInfo, 0)
    if (controllerSid === null || sameSidAt(workerSid, 0, controllerSid, 0)) throw new Error('worker and controller identities must differ')
    // Inherited stdio/control handles cannot cross Windows sessions. Do not
    // obtain SeTcbPrivilege or silently change token sessions to work around it.
    if (tokenSession(api, token) !== tokenSession(api, controller)) throw new Error('worker/controller Windows sessions differ; inherited handles require the same session')
    return token
  } catch (error) {
    api.closeHandle(token)
    throw error
  } finally {
    if (controller !== undefined) api.closeHandle(controller)
    if (expected !== undefined) api.localFree(expected)
    // A JavaScript string cannot be reliably zeroed; keep its lifetime controller-only.
    fields.password = ''
  }
}

function tokenUser(api: Win32Bindings, token: NativePtr): Buffer {
  const size = allocUint32()
  api.getTokenInformation(token, 1, null, 0, size)
  const bytes = decodeUint32(size)
  if (bytes < 16 || bytes > 65536) throw new Error('invalid TokenUser byte count')
  const data = Buffer.alloc(bytes)
  if (api.getTokenInformation(token, 1, data, bytes, size) === 0) throwLastError(api, 'GetTokenInformation', 'TokenUser')
  return data
}

function tokenSession(api: Win32Bindings, token: NativePtr): number {
  const data = Buffer.alloc(4)
  const needed = allocUint32()
  if (api.getTokenInformation(token, 12, data, data.length, needed) === 0) throwLastError(api, 'GetTokenInformation', 'TokenSessionId')
  return data.readUInt32LE(0)
}
