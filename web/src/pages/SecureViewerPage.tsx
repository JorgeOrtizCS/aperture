import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import {
  Ban,
  CircleCheck,
  Clock,
  EyeOff,
  Hourglass,
  LoaderCircle,
  Lock,
  MapPin,
  Maximize2,
  RefreshCw,
  ShieldCheck,
  Smartphone,
  TriangleAlert,
  User,
  X,
} from 'lucide-react'
import { ApiError, api, endSessionOnUnload } from '../api/client'
import type { SessionResult, SharedContent, TimeWindowStatus } from '../api/types'
import { recordActivity } from '../lib/activity'
import { deviceName, getDeviceKey } from '../lib/device'
import { formatTime } from '../lib/format'
import { useGeolocation } from '../lib/geolocation'
import type { Tone } from '../components/ui'
import { errorMessage } from '../lib/errors'
import { Banner, Button, PolicyRow, SectionHeader, StatusPill, TopBar } from '../components/ui'

const CHECK_INTERVAL_MS = 5_000
const PAUSE_SECONDS = 30

type Phase =
  | { kind: 'ready' }
  | { kind: 'opening' }
  | { kind: 'denied'; message: string }
  | { kind: 'viewing' }
  | { kind: 'ended'; message: string }

type Live = 'granted' | 'suspended' | 'unverified'

// Minutes the API keeps an expired session waiting for an extension (TimeWindowCheck.ExpiryGraceSeconds).
const EXTENSION_GRACE_MINUTES = 5

type SuspensionKind = 'location' | 'expired' | 'hold' | 'other'

// Denials after which the server has already closed the session (ContentController.Check).
const SESSION_ENDING = /^access has (expired|been revoked)/i

/** Why the server is withholding the content, read from its denial message. */
function suspensionKind(message: string): SuspensionKind {
  if (/^session suspended/i.test(message)) return 'hold'
  if (/waiting for the sender to extend/i.test(message)) return 'expired'
  if (/location|allowed area|^(country|state\/region|city) restriction/i.test(message)) return 'location'
  return 'other'
}

function useWindowFocused(): boolean {
  const read = () => document.visibilityState === 'visible' && document.hasFocus()
  const [focused, setFocused] = useState(read)
  useEffect(() => {
    const update = () => setFocused(read())
    window.addEventListener('focus', update)
    window.addEventListener('blur', update)
    document.addEventListener('visibilitychange', update)
    return () => {
      window.removeEventListener('focus', update)
      window.removeEventListener('blur', update)
      document.removeEventListener('visibilitychange', update)
    }
  }, [])
  return focused
}

/** Mobile SecureViewerScreen + SecureContentViewerScreen, backed by viewing sessions. */
export default function SecureViewerPage() {
  const { id: idParam } = useParams()
  const id = Number(idParam)
  const navigate = useNavigate()

  const [item, setItem] = useState<SharedContent | null>(null)
  const [missing, setMissing] = useState(false)
  const [timeWindow, setTimeWindow] = useState<TimeWindowStatus | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [device, setDevice] = useState<{ trusted: boolean } | null>(null)
  const [deviceError, setDeviceError] = useState<string | null>(null)
  const [deviceBusy, setDeviceBusy] = useState(false)

  const [phase, setPhase] = useState<Phase>({ kind: 'ready' })
  const [content, setContent] = useState<SessionResult | null>(null)
  const [live, setLive] = useState<Live>('granted')
  const [liveMessage, setLiveMessage] = useState<string>('')
  const [verifiedAt, setVerifiedAt] = useState<Date | null>(null)
  const [holdUntil, setHoldUntil] = useState<Date | null>(null)
  const [now, setNow] = useState(() => Date.now())
  const [pauseBusy, setPauseBusy] = useState(false)

  const [geoEnabled, setGeoEnabled] = useState(false)
  const { fix, failed: geoFailed, state: geoState } = useGeolocation(geoEnabled)
  const focused = useWindowFocused()

  const sessionId = useRef<number | null>(null)
  const liveRef = useRef<Live>('granted')
  const title = item?.Title ?? content?.Title ?? 'Secure Viewer'

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const [items, window] = await Promise.all([api.listContent(), api.checkTimeWindow(id).catch(() => null)])
        if (cancelled) return
        const found = items.find((candidate) => candidate.Id === id && !candidate.Mine) ?? null
        setItem(found)
        setMissing(!found)
        setTimeWindow(window)
      } catch (err) {
        if (!cancelled) setLoadError(errorMessage(err))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [id])

  const setLiveState = useCallback(
    (next: Live, message: string) => {
      const previous = liveRef.current
      liveRef.current = next
      setLive(next)
      setLiveMessage(message)
      if (previous === 'granted' && next === 'suspended') recordActivity('suspended', `"${title}" hidden`, message)
      if (previous !== 'granted' && next === 'granted') recordActivity('restored', `"${title}" available again`, 'All viewing conditions are satisfied.')
    },
    [title],
  )

  const end = useCallback(
    (message: string) => {
      sessionId.current = null
      setContent(null)
      setPhase({ kind: 'ended', message })
      recordActivity('ended', `Viewing of "${title}" ended`, message)
    },
    [title],
  )

  // Periodic check: one request at a time, every 5 seconds, sending the latest GPS fix.
  useEffect(() => {
    if (phase.kind !== 'viewing') return
    let stopped = false
    let timer: number | undefined

    const tick = async () => {
      const current = sessionId.current
      if (current === null || stopped) return
      try {
        const result = await api.checkSession(current, fix.current)
        if (stopped) return
        setVerifiedAt(new Date())
        if (result.AccessGranted) {
          setContent(result)
          setHoldUntil(null)
          setLiveState('granted', result.Message)
        } else if (SESSION_ENDING.test(result.Message)) {
          end(result.Message)
          return
        } else {
          setLiveState('suspended', result.Message)
        }
      } catch (err) {
        if (stopped) return
        if (err instanceof ApiError && (err.status === 403 || err.status === 404)) {
          end(err.status === 404 ? 'The content was paused, revoked or has expired, so this viewing session was closed.' : err.message)
          return
        }
        if (err instanceof ApiError && err.status === 401) return // signed out; the app redirects to login
        setLiveState('unverified', 'Unable to verify the viewing conditions with the server.')
      }
      if (!stopped) timer = window.setTimeout(tick, CHECK_INTERVAL_MS)
    }

    timer = window.setTimeout(tick, CHECK_INTERVAL_MS)
    return () => {
      stopped = true
      window.clearTimeout(timer)
    }
  }, [phase.kind, fix, end, setLiveState])

  // Countdown for a viewer-requested pause.
  useEffect(() => {
    if (!holdUntil) return
    const timer = window.setInterval(() => setNow(Date.now()), 1000)
    return () => window.clearInterval(timer)
  }, [holdUntil])

  // Close the session when leaving the page or the tab.
  useEffect(() => {
    const onUnload = () => {
      if (sessionId.current !== null) endSessionOnUnload(sessionId.current)
    }
    window.addEventListener('pagehide', onUnload)
    return () => {
      window.removeEventListener('pagehide', onUnload)
      onUnload()
    }
  }, [])

  /** Waits until the browser answers with a position or an error; the first time this includes the permission prompt. */
  async function waitForFix(timeoutMs: number) {
    const started = Date.now()
    while (!fix.current && !geoFailed.current && Date.now() - started < timeoutMs) {
      await new Promise((resolve) => setTimeout(resolve, 200))
    }
  }

  async function open() {
    setPhase({ kind: 'opening' })
    setGeoEnabled(true)
    await waitForFix(30_000)
    try {
      const result = await api.openSession(id, getDeviceKey(), fix.current)
      if (!result.AccessGranted) {
        setPhase({ kind: 'denied', message: result.Message })
        recordActivity('denied', `"${title}" could not be opened`, result.Message)
        return
      }
      sessionId.current = result.SessionId
      liveRef.current = 'granted'
      setContent(result)
      setLive('granted')
      setLiveMessage(result.Message)
      setVerifiedAt(new Date())
      setPhase({ kind: 'viewing' })
      recordActivity('granted', `Opened "${result.Title ?? title}"`, 'All viewing conditions were satisfied.')
    } catch (err) {
      setPhase({ kind: 'denied', message: errorMessage(err) })
    }
  }

  async function finish() {
    const current = sessionId.current
    sessionId.current = null
    if (current !== null) {
      try {
        await api.endSession(current)
      } catch {
        // The session is closed server-side on its next failed check or on restart anyway.
      }
    }
    navigate('/dashboard')
  }

  async function pause() {
    const current = sessionId.current
    if (current === null) return
    setPauseBusy(true)
    try {
      const status = await api.suspendSession(current, 'Paused by the viewer', PAUSE_SECONDS)
      setHoldUntil(status.HoldUntilUtc ? new Date(status.HoldUntilUtc) : new Date(Date.now() + PAUSE_SECONDS * 1000))
      setNow(Date.now())
      setLiveState('suspended', 'Session suspended: Paused by the viewer')
    } catch (err) {
      setLiveState('unverified', errorMessage(err))
    } finally {
      setPauseBusy(false)
    }
  }

  async function registerDevice() {
    setDeviceBusy(true)
    setDeviceError(null)
    try {
      setDevice(await api.registerDevice(getDeviceKey(), deviceName()))
    } catch (err) {
      setDeviceError(err instanceof ApiError && err.status === 409 ? 'This browser is already registered to another account.' : errorMessage(err))
    } finally {
      setDeviceBusy(false)
    }
  }

  if (missing) {
    return (
      <main className="page stack gap-22">
        <TopBar title="Secure Viewer" />
        <Banner kind="error">This content was not found, or it was not shared with you.</Banner>
      </main>
    )
  }

  const unavailable = item ? item.Status !== 'Active' || item.PolicyStatus !== 'Active' : false
  const holdSeconds = holdUntil ? Math.max(0, Math.ceil((holdUntil.getTime() - now) / 1000)) : 0

  const locationDetail =
    geoState === 'granted'
      ? 'Your location is shared with each check.'
      : geoState === 'denied'
        ? 'Location access is blocked. Allow location for this site (the icon at the left of the address bar) and reload; on a Mac, also turn on your browser under System Settings > Privacy & Security > Location Services.'
        : geoState === 'unsupported'
          ? 'This browser cannot share its location.'
          : geoState === 'unavailable'
            ? 'Your location is not available right now. On a Mac, check that Location Services is on for your browser (System Settings > Privacy & Security > Location Services), then try again.'
            : 'If this content requires a location, the browser will ask to share it.'

  // ---------- Viewing ----------
  if (phase.kind === 'viewing' || phase.kind === 'ended') {
    const ended = phase.kind === 'ended'
    const hiddenByFocus = !ended && live === 'granted' && !focused
    const shield = ended || live !== 'granted' || hiddenByFocus
    const suspension = suspensionKind(liveMessage)
    return (
      <main className="page stack gap-22">
        <TopBar
          title={title}
          back="/dashboard"
          actions={
            !ended && (
              <span className="secure-badge">
                <Lock size={14} aria-hidden="true" /> Secure
              </span>
            )
          }
        />

        <div className={ended ? 'viewer ended' : 'viewer'} onContextMenu={(event) => event.preventDefault()}>
          {content?.FileDataBase64 && content.FileType ? (
            <img className="content-image" src={`data:${content.FileType};base64,${content.FileDataBase64}`} alt={title} draggable={false} />
          ) : (
            <div className="content-text">{content?.Body}</div>
          )}

          {shield && (
            <div className="shield" aria-live="polite">
              {ended ? (
                <>
                  <span className="icon-tile danger">
                    <Hourglass size={30} />
                  </span>
                  <h2>Viewing Ended</h2>
                  <p>{phase.message}</p>
                </>
              ) : hiddenByFocus ? (
                <>
                  <span className="icon-tile">
                    <EyeOff size={30} />
                  </span>
                  <h2>Content Hidden</h2>
                  <p>Aperture hides protected content while this window is in the background. Click here to continue viewing.</p>
                </>
              ) : live === 'unverified' ? (
                <>
                  <span className="icon-tile warning">
                    <LoaderCircle size={30} className="spin" />
                  </span>
                  <h2>Reconnecting…</h2>
                  <p>{liveMessage} The content stays hidden until the server confirms the conditions again.</p>
                </>
              ) : suspension === 'location' ? (
                <>
                  <span className="icon-tile warning">
                    <MapPin size={30} />
                  </span>
                  <h2>Viewing Paused: Wrong Location</h2>
                  <p>{liveMessage}</p>
                  {geoState === 'denied' || geoState === 'unavailable' || geoState === 'unsupported' ? (
                    <p>{locationDetail}</p>
                  ) : (
                    <p>Your session is still open. The content comes back automatically once your location passes the next check.</p>
                  )}
                </>
              ) : suspension === 'expired' ? (
                <>
                  <span className="icon-tile warning">
                    <Hourglass size={30} />
                  </span>
                  <h2>Viewing Time Expired</h2>
                  <p>
                    The sender's time window has ended. Your session stays open for {EXTENSION_GRACE_MINUTES} minutes in case they extend it; if they
                    do, the content comes back here automatically. Otherwise this session ends.
                  </p>
                </>
              ) : (
                <>
                  <span className="icon-tile warning">
                    <EyeOff size={30} />
                  </span>
                  <h2>Content Hidden</h2>
                  <p>
                    {liveMessage}
                    {holdSeconds > 0
                      ? ` Viewing resumes in about ${holdSeconds} s, once the next check passes.`
                      : ' Access returns automatically when the conditions are satisfied again.'}
                  </p>
                </>
              )}
            </div>
          )}
        </div>

        {!ended ? (
          <>
            <div className="row wrap small">
              <StatusPill
                label={
                  live === 'granted'
                    ? 'Conditions satisfied'
                    : live === 'unverified'
                      ? 'Not verified'
                      : suspension === 'location'
                        ? 'Suspended: location'
                        : suspension === 'expired'
                          ? 'Suspended: time expired'
                          : 'Suspended'
                }
                tone={live === 'granted' ? 'success' : 'warning'}
              />
              <span>{verifiedAt ? `Last verified ${formatTime(verifiedAt)} · rechecked every 5 seconds` : 'Verifying…'}</span>
            </div>
            <div className="two-col">
              <Button variant="secondary" icon={EyeOff} busy={pauseBusy} disabled={live !== 'granted'} onClick={() => void pause()}>
                Hide for {PAUSE_SECONDS} seconds
              </Button>
              <Button variant="danger" icon={X} onClick={() => void finish()}>
                End Viewing
              </Button>
            </div>
            <p className="muted">
              Aperture rechecks every condition while the content is on screen. It cannot stop a photo of the screen or a screenshot taken by the operating system.
            </p>
          </>
        ) : (
          <div className="two-col">
            <Button icon={RefreshCw} onClick={() => setPhase({ kind: 'ready' })}>
              Try Again
            </Button>
            <Button variant="secondary" onClick={() => navigate('/dashboard')}>
              Back to Dashboard
            </Button>
          </div>
        )}
      </main>
    )
  }

  // ---------- Before opening ----------
  const timeTone: Tone = !timeWindow ? 'primary' : timeWindow.passed ? 'success' : 'warning'
  return (
    <main className="page stack gap-28">
      <TopBar title="Secure Viewer" />
      {loadError && <Banner kind="error">{loadError}</Banner>}

      <div className="stack gap-12">
        <h2 className="title-md">{title}</h2>
        <div className="row small">
          <User size={16} aria-hidden="true" />
          <span>{item ? `Shared by ${item.Owner}` : 'Loading…'}</span>
        </div>
        <p className="body">
          {unavailable
            ? 'Access is currently unavailable: the sender paused or revoked it.'
            : 'Viewing conditions are checked when you open the content and every few seconds while it is on screen.'}
        </p>
      </div>

      {phase.kind === 'denied' && (
        <Banner kind="error">
          <strong>Access denied.</strong> {phase.message}
        </Banner>
      )}

      <Button icon={phase.kind === 'opening' ? LoaderCircle : Maximize2} busy={phase.kind === 'opening'} disabled={unavailable || !item} onClick={() => void open()}>
        {phase.kind === 'opening' ? 'Checking conditions…' : 'Open Secure Content'}
      </Button>

      <section className="stack gap-14">
        <SectionHeader title="Condition Checks" icon={ShieldCheck} />
        <div className="card flush rows">
          <PolicyRow
            icon={unavailable ? Ban : CircleCheck}
            tone={unavailable ? 'danger' : 'success'}
            title="Recipient authorization"
            detail={unavailable ? 'Access was paused or revoked by the sender.' : 'You are listed as an approved viewer.'}
          />
          <PolicyRow
            icon={Clock}
            tone={timeTone}
            title="Time window"
            detail={!timeWindow ? 'Checked when you open the content.' : timeWindow.passed ? 'Content is inside its viewing window.' : (timeWindow.reason ?? 'Outside the viewing window.')}
          />
          <PolicyRow icon={MapPin} tone={geoState === 'denied' ? 'warning' : 'primary'} title="Location requirement" detail={locationDetail} />
          <PolicyRow
            icon={Smartphone}
            tone={device ? (device.trusted ? 'success' : 'warning') : 'primary'}
            title="This device"
            detail={
              deviceError ??
              (device
                ? device.trusted
                  ? 'This browser is an approved device.'
                  : 'Registered, waiting for an administrator to approve it. Content that requires an approved device stays locked until then.'
                : 'Register this browser if the sender requires an approved device.')
            }
            trailing={
              !device?.trusted && (
                <Button variant="secondary" compact busy={deviceBusy} onClick={() => void registerDevice()}>
                  {device ? 'Check again' : 'Register'}
                </Button>
              )
            }
          />
          <PolicyRow
            icon={TriangleAlert}
            tone="muted"
            title="Capture protection"
            detail="Content is hidden when this window loses focus. Screenshots cannot be blocked in a browser."
          />
        </div>
      </section>
    </main>
  )
}
