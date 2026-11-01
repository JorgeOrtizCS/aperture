// Every storage access is guarded: private windows and blocked site data make it throw.

export function readStorage(storage: 'local' | 'session', key: string): string | null {
  try {
    return (storage === 'local' ? window.localStorage : window.sessionStorage).getItem(key)
  } catch {
    return null
  }
}

export function writeStorage(storage: 'local' | 'session', key: string, value: string | null) {
  try {
    const target = storage === 'local' ? window.localStorage : window.sessionStorage
    if (value === null) target.removeItem(key)
    else target.setItem(key, value)
  } catch {
    // Not persisted; the app keeps working for this page load.
  }
}
