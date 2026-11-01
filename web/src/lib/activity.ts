import { useSyncExternalStore } from 'react'
import { readStorage, writeStorage } from './storage'
import { randomId } from './uuid'

// Activity is recorded by this browser as things happen (the API has no notifications feed).

export type ActivityKind = 'granted' | 'denied' | 'suspended' | 'restored' | 'ended' | 'shared' | 'policy'

export interface ActivityEvent {
  id: string
  at: string
  kind: ActivityKind
  title: string
  detail: string
}

const KEY = 'aperture.activity'
const LIMIT = 50
const listeners = new Set<() => void>()
let cache: ActivityEvent[] | null = null

function load(): ActivityEvent[] {
  if (cache) return cache
  try {
    const parsed = JSON.parse(readStorage('local', KEY) ?? '[]')
    cache = Array.isArray(parsed) ? (parsed as ActivityEvent[]) : []
  } catch {
    cache = []
  }
  return cache
}

export function recordActivity(kind: ActivityKind, title: string, detail: string) {
  const next = [{ id: randomId(), at: new Date().toISOString(), kind, title, detail }, ...load()].slice(0, LIMIT)
  cache = next
  writeStorage('local', KEY, JSON.stringify(next))
  listeners.forEach((listener) => listener())
}

export function clearActivity() {
  cache = []
  writeStorage('local', KEY, null)
  listeners.forEach((listener) => listener())
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function useActivity(): ActivityEvent[] {
  return useSyncExternalStore(subscribe, load, load)
}
