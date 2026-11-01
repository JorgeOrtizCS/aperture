import { readStorage, writeStorage } from './storage'
import { randomId } from './uuid'

const KEY = 'aperture.deviceKey'

/**
 * This browser's device key, created once and kept in localStorage. Like the desktop client's
 * key, it is a demo identifier that can be copied: not hardware attestation.
 */
export function getDeviceKey(): string {
  const existing = readStorage('local', KEY)
  if (existing && /^[0-9a-f-]{36}$/i.test(existing)) return existing
  const created = randomId()
  writeStorage('local', KEY, created)
  return created
}

export function deviceName(): string {
  const platform = navigator.platform || 'Browser'
  return `Web browser (${platform})`.slice(0, 100)
}
