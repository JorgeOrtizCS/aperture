import { useCallback, useEffect, useState } from 'react'
import { useLocation, useParams } from 'react-router-dom'
import { Ban, CircleCheck, Clock, FileText, MapPin, Pause, Play, ShieldCheck, User } from 'lucide-react'
import { api } from '../api/client'
import type { SharedContent, TimeWindowStatus } from '../api/types'
import { recordActivity } from '../lib/activity'
import { formatDateTime, formatRadius, localInputToUtc, parseUtc, toLocalInput } from '../lib/format'
import type { AreaValue } from '../components/LocationPicker'
import { LocationPicker } from '../components/LocationPicker'
import { contentStatus } from '../lib/status'
import { Banner, Button, PolicyRow, SectionHeader, StatusPill, TextField, TopBar } from '../components/ui'
import { errorMessage } from '../lib/errors'

function windowSummary(window: TimeWindowStatus | null): string {
  if (!window) return 'Loading…'
  if (!window.startTime && !window.expiresAt) return 'No time limit.'
  const parts: string[] = []
  if (window.startTime) parts.push(`Opens ${formatDateTime(window.startTime)}`)
  if (window.expiresAt) parts.push(`expires ${formatDateTime(window.expiresAt)}`)
  const sentence = parts.join(', ')
  return sentence.charAt(0).toUpperCase() + sentence.slice(1) + '.'
}

/** Mobile ContentStatusScreen for content the user sent. */
export default function ContentStatusPage() {
  const { id: idParam } = useParams()
  const id = Number(idParam)
  const location = useLocation()
  const navState = location.state as { created?: boolean; warning?: string } | null

  const [item, setItem] = useState<SharedContent | null>(null)
  const [missing, setMissing] = useState(false)
  const [timeWindow, setTimeWindow] = useState<TimeWindowStatus | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(navState?.created ? 'Content shared securely.' : null)
  const [busy, setBusy] = useState<string | null>(null)

  const [startAt, setStartAt] = useState('')
  const [expiresAt, setExpiresAt] = useState('')
  const [area, setArea] = useState<AreaValue | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [items, window] = await Promise.all([api.listContent(), api.checkTimeWindow(id).catch(() => null)])
      const found = items.find((candidate) => candidate.Id === id && candidate.Mine) ?? null
      setItem(found)
      setMissing(!found)
      setTimeWindow(window)
      if (window) {
        setStartAt(toLocalInput(parseUtc(window.startTime)))
        setExpiresAt(toLocalInput(parseUtc(window.expiresAt)))
      }
    } catch (err) {
      setError(errorMessage(err))
    }
  }, [id])

  useEffect(() => {
    void load()
  }, [load])

  async function run(action: string, work: () => Promise<string>) {
    setBusy(action)
    setError(null)
    setNotice(null)
    try {
      setNotice(await work())
      await load()
    } catch (err) {
      setError(errorMessage(err))
    } finally {
      setBusy(null)
    }
  }

  const revoked = item ? item.Status !== 'Active' : false
  const paused = item?.PolicyStatus === 'Paused'
  const status = item ? contentStatus(item) : null

  const togglePause = () =>
    run('pause', async () => {
      const next = paused ? 'Active' : 'Paused'
      await api.setPolicyStatus(id, next)
      recordActivity('policy', `${next === 'Paused' ? 'Paused' : 'Resumed'} "${item?.Title}"`, next === 'Paused' ? 'Open viewing sessions were ended.' : 'The recipient can view it again.')
      return next === 'Paused' ? 'Access paused. Any open viewing session was ended.' : 'Access resumed.'
    })

  const revoke = () => {
    if (!window.confirm(`Revoke ${item?.Recipient ?? 'the recipient'}'s access to "${item?.Title}"? This cannot be undone.`)) return
    void run('revoke', async () => {
      await api.revoke(id)
      recordActivity('policy', `Revoked "${item?.Title}"`, `${item?.Recipient ?? 'The recipient'} can no longer open it.`)
      return 'Access revoked.'
    })
  }

  const saveWindow = (clear: boolean) =>
    run('window', async () => {
      const start = clear ? null : localInputToUtc(startAt)
      const expiry = clear ? null : localInputToUtc(expiresAt)
      await api.setTimeWindow(id, start, expiry)
      recordActivity('policy', `Updated the time window of "${item?.Title}"`, clear ? 'No time limit.' : windowSummary({ passed: true, startTime: start ?? undefined, expiresAt: expiry ?? undefined }))
      return clear ? 'Time limits removed.' : 'Time window saved. Open sessions pick it up on their next check.'
    })

  const saveLocation = () =>
    run('location', async () => {
      if (!area) throw new Error('Search for a place or click the map to choose where the content can be viewed.')
      await api.setPreciseLocation(id, area.latitude, area.longitude, area.radiusMeters)
      const place = area.label ?? `${area.latitude.toFixed(4)}, ${area.longitude.toFixed(4)}`
      recordActivity('policy', `Restricted "${item?.Title}" to an exact area`, `Within ${formatRadius(area.radiusMeters)} of ${place}.`)
      return 'Exact-area restriction saved. The recipient must now share their location while viewing.'
    })

  if (missing) {
    return (
      <main className="page stack gap-22">
        <TopBar title="Content Status" />
        <Banner kind="error">This content was not found, or you are not its sender.</Banner>
      </main>
    )
  }

  return (
    <main className="page stack gap-28">
      <TopBar title="Content Status" />

      {navState?.warning && <Banner kind="warning">{navState.warning}</Banner>}
      {notice && <Banner kind="success">{notice}</Banner>}
      {error && <Banner kind="error">{error}</Banner>}

      <div className="card row" style={{ alignItems: 'center' }}>
        <span className="icon-tile">
          <FileText size={24} aria-hidden="true" />
        </span>
        <div className="spacer" style={{ minWidth: 0 }}>
          <h2 className="title-sm">{item?.Title ?? 'Loading…'}</h2>
          <p className="small" style={{ marginTop: 4 }}>
            {item ? `Shared with ${item.Recipient ?? 'recipient'} · ${formatDateTime(item.CreatedAt)}` : ' '}
          </p>
        </div>
        {status && <StatusPill label={status.label} tone={status.tone} />}
      </div>

      <section className="stack gap-14">
        <SectionHeader title="Viewing Policy" icon={ShieldCheck} />
        <div className="card flush rows">
          <PolicyRow
            icon={revoked ? Ban : User}
            tone={revoked ? 'danger' : 'success'}
            title="Recipient access"
            detail={revoked ? 'Revoked. The recipient can no longer open this content.' : `${item?.Recipient ?? 'The recipient'} may open it while the conditions are met.`}
          />
          <PolicyRow
            icon={paused ? Pause : CircleCheck}
            tone={paused ? 'warning' : 'success'}
            title="Sharing"
            detail={paused ? 'Paused. Viewing is blocked until you resume.' : 'Active.'}
          />
          <PolicyRow
            icon={Clock}
            tone={timeWindow && !timeWindow.passed ? 'warning' : 'primary'}
            title="Time window"
            detail={timeWindow && !timeWindow.passed ? `${windowSummary(timeWindow)} ${timeWindow.reason ?? ''}` : windowSummary(timeWindow)}
          />
        </div>
      </section>

      {!revoked && (
        <div className="two-col">
          <Button variant="secondary" icon={paused ? Play : Pause} busy={busy === 'pause'} onClick={() => void togglePause()}>
            {paused ? 'Resume Access' : 'Pause Access'}
          </Button>
          <Button variant="danger" icon={Ban} busy={busy === 'revoke'} onClick={revoke}>
            Revoke Access
          </Button>
        </div>
      )}

      {!revoked && (
        <section className="stack gap-14">
          <SectionHeader title="Time Window" icon={Clock} />
          <p className="small">
            Times are in your local time zone. Leave a field empty to remove that limit. When the window expires, an open viewing session is paused for 5
            minutes: extend the expiration within that time and the recipient keeps viewing without reopening the content.
          </p>
          <div className="two-col">
            <TextField label="Opens" type="datetime-local" value={startAt} onChange={(event) => setStartAt(event.target.value)} />
            <TextField label="Expires" type="datetime-local" value={expiresAt} onChange={(event) => setExpiresAt(event.target.value)} />
          </div>
          <div className="two-col">
            <Button busy={busy === 'window'} onClick={() => void saveWindow(false)}>
              Save Time Window
            </Button>
            <Button variant="secondary" disabled={busy === 'window'} onClick={() => void saveWindow(true)}>
              Remove Time Limits
            </Button>
          </div>
        </section>
      )}

      {!revoked && (
        <section className="stack gap-14">
          <SectionHeader title="Exact Area" icon={MapPin} />
          <p className="small">Restrict viewing to an area on the map. This replaces any region restriction set when sharing.</p>
          <LocationPicker value={area} onChange={setArea} />
          <Button icon={MapPin} busy={busy === 'location'} disabled={!area} onClick={() => void saveLocation()}>
            Save Exact Area
          </Button>
        </section>
      )}
    </main>
  )
}
