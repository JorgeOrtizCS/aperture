import { useEffect, useRef, useState } from 'react'
import type { GeoFix } from '../api/types'

export type GeoState = 'unsupported' | 'pending' | 'granted' | 'denied' | 'unavailable'

/**
 * Watches the browser's location while `enabled` and keeps the latest fix in a ref, so periodic
 * checks can send it as X-Client-Latitude / X-Client-Longitude without re-rendering.
 */
export function useGeolocation(enabled: boolean) {
  const fix = useRef<GeoFix | null>(null)
  /** Set when the browser refuses or fails, so callers waiting for a fix can stop early. */
  const failed = useRef(false)
  const [state, setState] = useState<GeoState>(() => ('geolocation' in navigator ? 'pending' : 'unsupported'))

  useEffect(() => {
    if (!enabled || !('geolocation' in navigator)) return
    const id = navigator.geolocation.watchPosition(
      (position) => {
        fix.current = { latitude: position.coords.latitude, longitude: position.coords.longitude }
        failed.current = false
        setState('granted')
      },
      (error) => {
        fix.current = null
        failed.current = true
        setState(error.code === error.PERMISSION_DENIED ? 'denied' : 'unavailable')
      },
      { enableHighAccuracy: true, maximumAge: 10_000, timeout: 15_000 },
    )
    return () => navigator.geolocation.clearWatch(id)
  }, [enabled])

  return { fix, failed, state }
}

/** One-off position for forms ("Use my current location"). */
export function currentPosition(): Promise<GeoFix> {
  return new Promise((resolve, reject) => {
    if (!('geolocation' in navigator)) {
      reject(new Error('This browser cannot share its location.'))
      return
    }
    navigator.geolocation.getCurrentPosition(
      (position) => resolve({ latitude: position.coords.latitude, longitude: position.coords.longitude }),
      (error) =>
        reject(
          new Error(
            error.code === error.PERMISSION_DENIED
              ? 'Location permission was denied. Allow it in the browser to use your current location.'
              : 'Your location is not available right now.',
          ),
        ),
      { enableHighAccuracy: true, timeout: 15_000 },
    )
  })
}
