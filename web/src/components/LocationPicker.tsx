import { useEffect, useRef, useState } from 'react'
import type { KeyboardEvent } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { Crosshair, MapPin, Search } from 'lucide-react'
import { currentPosition } from '../lib/geolocation'
import { errorMessage } from '../lib/errors'
import { formatRadius } from '../lib/format'
import { Button } from './ui'

export interface AreaValue {
  latitude: number
  longitude: number
  radiusMeters: number
  /** Human-readable place name, for display only (not sent to the API). */
  label?: string
}

interface Place {
  label: string
  latitude: number
  longitude: number
}

// Radius slider stops: fine steps near a building, coarse ones for a neighborhood or city.
const RADIUS_STEPS = [50, 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000, 25000, 50000]
export const DEFAULT_RADIUS = 500

const DEFAULT_CENTER: L.LatLngTuple = [39.8, -98.6] // continental US
const DEFAULT_ZOOM = 4

// OpenStreetMap's free Nominatim service: no key needed, but its usage policy allows at most one
// request per second and no search-as-you-type, so searches run only on Enter / the Search button.
const NOMINATIM = 'https://nominatim.openstreetmap.org'

function nearestStep(meters: number): number {
  let best = 0
  RADIUS_STEPS.forEach((step, index) => {
    if (Math.abs(step - meters) < Math.abs(RADIUS_STEPS[best] - meters)) best = index
  })
  return best
}

async function queryPlaces(query: string, near: L.LatLngBounds | null, signal: AbortSignal): Promise<Place[]> {
  const params = new URLSearchParams({ format: 'jsonv2', limit: '5', q: query })
  if (near) {
    params.set('viewbox', near.toBBoxString())
    params.set('bounded', '1')
  }
  const response = await fetch(`${NOMINATIM}/search?${params}`, { signal, headers: { Accept: 'application/json' } })
  if (!response.ok) throw new Error(`Location search failed (${response.status}). Try again in a moment.`)
  const results = (await response.json()) as { display_name: string; lat: string; lon: string }[]
  return results.map((result) => ({ label: result.display_name, latitude: Number(result.lat), longitude: Number(result.lon) }))
}

/**
 * Like a map app: when the map is zoomed in to a city or closer, look around what is on screen
 * first (so "Starbucks" means a nearby one), and search everywhere only if nothing is found there.
 */
async function searchPlaces(query: string, view: L.Map | null, signal: AbortSignal): Promise<Place[]> {
  if (view && view.getZoom() >= 9) {
    const nearby = await queryPlaces(query, view.getBounds().pad(1), signal)
    if (nearby.length > 0) return nearby
    await new Promise((resolve) => setTimeout(resolve, 1000)) // Nominatim allows one request per second
  }
  return queryPlaces(query, null, signal)
}

async function placeName(latitude: number, longitude: number, signal: AbortSignal): Promise<string | undefined> {
  const params = new URLSearchParams({ format: 'jsonv2', lat: String(latitude), lon: String(longitude), zoom: '18' })
  try {
    const response = await fetch(`${NOMINATIM}/reverse?${params}`, { signal, headers: { Accept: 'application/json' } })
    if (!response.ok) return undefined
    const result = (await response.json()) as { display_name?: string }
    return result.display_name
  } catch {
    return undefined // a missing name is cosmetic; the coordinates are what is saved
  }
}

const pinIcon = L.divIcon({
  className: 'map-pin',
  html: '<span></span>',
  iconSize: [28, 28],
  iconAnchor: [14, 28],
})

/**
 * Pick an exact area on a map: search for a place (like a map app), click or drag the pin to
 * fine-tune it, and choose how far around it the recipient may be. Map data © OpenStreetMap.
 */
export function LocationPicker({ value, onChange }: { value: AreaValue | null; onChange: (value: AreaValue) => void }) {
  const container = useRef<HTMLDivElement>(null)
  const map = useRef<L.Map | null>(null)
  const marker = useRef<L.Marker | null>(null)
  const circle = useRef<L.Circle | null>(null)
  const pending = useRef<AbortController | null>(null)
  // Leaflet handlers are bound once, so they read the latest props through refs.
  const valueRef = useRef(value)
  const onChangeRef = useRef(onChange)
  valueRef.current = value
  onChangeRef.current = onChange

  const [query, setQuery] = useState('')
  const [results, setResults] = useState<Place[] | null>(null)
  const [searching, setSearching] = useState(false)
  const [locating, setLocating] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  const radius = value?.radiusMeters ?? DEFAULT_RADIUS

  /** Moves the pin, keeping the radius, and looks up the place name in the background. */
  function pinAt(latitude: number, longitude: number, label?: string) {
    const radiusMeters = valueRef.current?.radiusMeters ?? DEFAULT_RADIUS
    onChangeRef.current({ latitude, longitude, radiusMeters, label })
    if (label) return
    pending.current?.abort()
    const controller = new AbortController()
    pending.current = controller
    void placeName(latitude, longitude, controller.signal).then((name) => {
      const current = valueRef.current
      if (name && !controller.signal.aborted && current && current.latitude === latitude && current.longitude === longitude) {
        onChangeRef.current({ ...current, label: name })
      }
    })
  }

  function focusArea(latitude: number, longitude: number, radiusMeters: number) {
    map.current?.fitBounds(L.latLng(latitude, longitude).toBounds(radiusMeters * 2.6), { maxZoom: 17 })
  }

  // Create the map once.
  useEffect(() => {
    if (!container.current) return
    const instance = L.map(container.current, { scrollWheelZoom: false }).setView(DEFAULT_CENTER, DEFAULT_ZOOM)
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(instance)
    instance.on('click', (event: L.LeafletMouseEvent) => pinAt(event.latlng.lat, event.latlng.lng))
    // Wheel zoom only after the map is clicked, so scrolling the page does not get stuck on it.
    instance.on('focus', () => instance.scrollWheelZoom.enable())
    instance.on('blur', () => instance.scrollWheelZoom.disable())
    map.current = instance
    const initial = valueRef.current
    if (initial) focusArea(initial.latitude, initial.longitude, initial.radiusMeters)
    return () => {
      pending.current?.abort()
      instance.remove()
      map.current = null
      marker.current = null
      circle.current = null
    }
    // Created once on purpose: the Leaflet handlers read the latest props through refs.
  }, [])

  // Keep the pin and circle in step with the value.
  useEffect(() => {
    const instance = map.current
    if (!instance) return
    if (!value) {
      marker.current?.remove()
      circle.current?.remove()
      marker.current = null
      circle.current = null
      return
    }
    const point = L.latLng(value.latitude, value.longitude)
    if (!marker.current) {
      marker.current = L.marker(point, { icon: pinIcon, draggable: true, keyboard: false, title: 'Drag to adjust' }).addTo(instance)
      marker.current.on('dragend', () => {
        const moved = marker.current?.getLatLng()
        if (moved) pinAt(moved.lat, moved.lng)
      })
      circle.current = L.circle(point, { radius: value.radiusMeters, className: 'map-area' }).addTo(instance)
    } else {
      marker.current.setLatLng(point)
      circle.current?.setLatLng(point).setRadius(value.radiusMeters)
    }
  }, [value])

  async function search() {
    const text = query.trim()
    if (!text || searching) return
    setSearching(true)
    setProblem(null)
    pending.current?.abort()
    const controller = new AbortController()
    pending.current = controller
    try {
      const found = await searchPlaces(text, map.current, controller.signal)
      setResults(found)
      if (found.length === 1) choose(found[0])
    } catch (err) {
      if (!controller.signal.aborted) setProblem(errorMessage(err))
    } finally {
      setSearching(false)
    }
  }

  function choose(place: Place) {
    setResults(null)
    pinAt(place.latitude, place.longitude, place.label)
    focusArea(place.latitude, place.longitude, radius)
  }

  async function pinMyLocation() {
    setLocating(true)
    setProblem(null)
    try {
      const fix = await currentPosition()
      pinAt(fix.latitude, fix.longitude)
      focusArea(fix.latitude, fix.longitude, radius)
    } catch (err) {
      setProblem(errorMessage(err))
    } finally {
      setLocating(false)
    }
  }

  function changeRadius(step: number) {
    const radiusMeters = RADIUS_STEPS[step]
    if (value) {
      onChange({ ...value, radiusMeters })
      focusArea(value.latitude, value.longitude, radiusMeters)
    }
  }

  // Enter searches; the picker sits inside the Share form, so it must not submit it.
  function onSearchKey(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Enter') {
      event.preventDefault()
      void search()
    }
  }

  return (
    <div className="location-picker stack gap-12">
      <div className="field">
        <label htmlFor="location-search">Find a place</label>
        <div className="search-row">
          <div className="input-wrap has-leading spacer">
            <span className="leading">
              <Search size={20} aria-hidden="true" />
            </span>
            <input
              id="location-search"
              className="input"
              type="search"
              placeholder="Address, building or landmark"
              autoComplete="off"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={onSearchKey}
            />
          </div>
          <Button compact busy={searching} disabled={!query.trim()} onClick={() => void search()}>
            Search
          </Button>
        </div>
      </div>

      {results && (
        <div className="card flush place-results" role="listbox" aria-label="Search results">
          {results.length === 0 ? (
            <p className="small place-result">No places found. Try a fuller address or a nearby landmark.</p>
          ) : (
            results.map((place) => (
              <button key={`${place.latitude},${place.longitude}`} type="button" className="place-result" onClick={() => choose(place)}>
                <MapPin size={16} aria-hidden="true" />
                <span>{place.label}</span>
              </button>
            ))
          )}
        </div>
      )}

      <div ref={container} className="map" aria-label="Map: click to place the pin, drag the pin to adjust" />

      <p className="small">
        {value
          ? `Pinned: ${value.label ?? `${value.latitude.toFixed(5)}, ${value.longitude.toFixed(5)}`}`
          : 'Search for a place or click the map to drop a pin.'}
      </p>

      <div className="field">
        <label htmlFor="location-radius">
          Allowed distance from the pin: <span className="radius-value">{formatRadius(radius)}</span>
        </label>
        <input
          id="location-radius"
          className="range"
          type="range"
          min={0}
          max={RADIUS_STEPS.length - 1}
          step={1}
          value={nearestStep(radius)}
          disabled={!value}
          aria-valuetext={formatRadius(radius)}
          onChange={(event) => changeRadius(Number(event.target.value))}
        />
      </div>

      <Button variant="secondary" icon={Crosshair} busy={locating} onClick={() => void pinMyLocation()}>
        {locating ? 'Finding your location…' : 'Use my current location'}
      </Button>

      {problem && <p className="small error-text">{problem}</p>}
    </div>
  )
}
