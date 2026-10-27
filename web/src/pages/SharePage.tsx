import { useRef, useState } from 'react'
import type { ChangeEvent, FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Clock,
  FileText,
  Image as ImageIcon,
  MapPin,
  Monitor,
  Send,
  ShieldCheck,
  Smartphone,
  Type,
  Upload,
  UserPlus,
  Eye,
} from 'lucide-react'
import { api } from '../api/client'
import type { CreateContentRequest } from '../api/types'
import { recordActivity } from '../lib/activity'
import { formatRadius, localInputToUtc } from '../lib/format'
import type { AreaValue } from '../components/LocationPicker'
import { LocationPicker } from '../components/LocationPicker'
import { Banner, Button, SectionHeader, Segmented, TextField, ToggleTile, TopBar } from '../components/ui'
import { errorMessage } from '../lib/errors'

const MAX_IMAGE_BYTES = 5 * 1024 * 1024
const MAX_TEXT = 10_000

type ContentKind = 'text' | 'image'
type LocationMode = 'none' | 'region' | 'precise'

// The mobile app's expiration choices, plus "none" and a custom date.
const EXPIRATIONS = [
  { value: 'none', label: 'No expiration', hours: 0 },
  { value: '12h', label: '12 hours', hours: 12 },
  { value: '24h', label: '24 hours', hours: 24 },
  { value: '48h', label: '48 hours', hours: 48 },
  { value: '7d', label: '7 days', hours: 168 },
  { value: 'custom', label: 'Choose a date…', hours: 0 },
] as const
type Expiration = (typeof EXPIRATIONS)[number]['value']

interface PickedImage {
  name: string
  type: 'image/png' | 'image/jpeg'
  base64: string
  dataUrl: string
}

function readImage(file: File): Promise<PickedImage> {
  return new Promise((resolve, reject) => {
    if (file.type !== 'image/png' && file.type !== 'image/jpeg') {
      reject(new Error('Only PNG or JPEG images are supported.'))
      return
    }
    if (file.size > MAX_IMAGE_BYTES) {
      reject(new Error('Images can be at most 5 MB.'))
      return
    }
    const reader = new FileReader()
    reader.onload = () => {
      const dataUrl = String(reader.result)
      resolve({ name: file.name, type: file.type as PickedImage['type'], dataUrl, base64: dataUrl.slice(dataUrl.indexOf(',') + 1) })
    }
    reader.onerror = () => reject(new Error('The image could not be read.'))
    reader.readAsDataURL(file)
  })
}

/** Mobile ShareContentScreen, sending POST /api/content (+ the precise-location policy). */
export default function SharePage() {
  const navigate = useNavigate()
  const fileInput = useRef<HTMLInputElement>(null)

  const [kind, setKind] = useState<ContentKind>('text')
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [image, setImage] = useState<PickedImage | null>(null)
  const [recipient, setRecipient] = useState('')

  const [startNow, setStartNow] = useState(true)
  const [startAt, setStartAt] = useState('')
  const [expiration, setExpiration] = useState<Expiration>('48h')
  const [expiresAt, setExpiresAt] = useState('')
  const [oneView, setOneView] = useState(false)
  const [trustedDevice, setTrustedDevice] = useState(false)
  const [screenshot, setScreenshot] = useState(false)

  const [locationMode, setLocationMode] = useState<LocationMode>('none')
  const [country, setCountry] = useState('')
  const [region, setRegion] = useState('')
  const [city, setCity] = useState('')
  const [area, setArea] = useState<AreaValue | null>(null)

  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function pickImage(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    try {
      setImage(await readImage(file))
      if (!title.trim()) setTitle(file.name.replace(/\.[^.]+$/, '').slice(0, 160))
      setError(null)
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  function buildRequest(): { request?: CreateContentRequest; precise?: AreaValue; problem?: string } {
    if (!title.trim()) return { problem: 'Give the content a title.' }
    if (title.trim().length > 160) return { problem: 'The title can be at most 160 characters.' }
    if (!recipient.trim()) return { problem: 'Enter the username of the recipient.' }
    if (kind === 'text' && !body.trim()) return { problem: 'Write the text you want to share.' }
    if (kind === 'image' && !image) return { problem: 'Choose a PNG or JPEG image to share.' }

    const now = Date.now()
    const start = startNow ? null : localInputToUtc(startAt)
    if (!startNow && !start) return { problem: 'Choose when access starts, or select "Immediately".' }

    let expiry: string | null = null
    const choice = EXPIRATIONS.find((option) => option.value === expiration)!
    if (expiration === 'custom') {
      expiry = localInputToUtc(expiresAt)
      if (!expiry) return { problem: 'Choose the expiration date and time.' }
    } else if (choice.hours > 0) {
      const base = start ? new Date(start).getTime() : now
      expiry = new Date(base + choice.hours * 3_600_000).toISOString()
    }
    if (expiry && new Date(expiry).getTime() <= now) return { problem: 'The expiration must be in the future.' }
    if (expiry && start && new Date(expiry) <= new Date(start)) return { problem: 'The expiration must be after the start time.' }

    const request: CreateContentRequest = {
      Title: title.trim(),
      Recipient: recipient.trim(),
      RequireTrustedDevice: trustedDevice,
      ScreenshotRestriction: screenshot,
      ...(start ? { StartTime: start } : {}),
      ...(expiry ? { ExpiresAt: expiry } : {}),
      ...(oneView ? { MaxViews: 1 as const } : {}),
      ...(kind === 'text' ? { Body: body } : { FileDataBase64: image!.base64, FileType: image!.type }),
    }

    if (locationMode === 'region') {
      if (!country.trim() && !region.trim() && !city.trim()) return { problem: 'Enter a country, state/region or city, or turn the location requirement off.' }
      request.AllowedCountry = country.trim() || undefined
      request.AllowedRegion = region.trim() || undefined
      request.AllowedCity = city.trim() || undefined
    }

    if (locationMode === 'precise') {
      if (!area) return { problem: 'Search for a place or click the map to choose where the content can be viewed.' }
      return { request, precise: area }
    }

    return { request }
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    const { request, precise, problem } = buildRequest()
    if (problem || !request) {
      setError(problem ?? 'Check the form.')
      return
    }
    setBusy(true)
    setError(null)
    try {
      const { id } = await api.share(request)
      let warning: string | undefined
      if (precise) {
        try {
          await api.setPreciseLocation(id, precise.latitude, precise.longitude, precise.radiusMeters)
        } catch (err) {
          warning = `The content was shared, but the precise location could not be saved: ${errorMessage(err)}`
        }
      }
      recordActivity('shared', `Shared "${request.Title}"`, `With ${request.Recipient}.`)
      navigate(`/content/${id}`, { replace: true, state: { created: true, warning } })
    } catch (err) {
      setError(errorMessage(err))
      setBusy(false)
    }
  }

  return (
    <main className="page">
      <TopBar title="Share Content" />
      <form className="stack gap-34" onSubmit={submit} noValidate>
        <div className="stack gap-8">
          <h2 className="title-md">Upload and configure</h2>
          <p className="body">Set up the content details, recipient, and viewing restrictions before sharing.</p>
        </div>

        <section className="stack gap-14">
          <SectionHeader title="Content" icon={Upload} />
          <Segmented<ContentKind>
            label="Content type"
            value={kind}
            onChange={setKind}
            options={[
              { value: 'text', label: 'Text', icon: Type },
              { value: 'image', label: 'Image', icon: ImageIcon },
            ]}
          />
          <TextField
            label="Content Title"
            icon={FileText}
            placeholder="Example: Project Document"
            maxLength={160}
            value={title}
            onChange={(event) => setTitle(event.target.value)}
          />
          {kind === 'text' ? (
            <div className="field">
              <label htmlFor="body">Message</label>
              <textarea
                id="body"
                className="textarea"
                placeholder="Write the content only your recipient should see"
                maxLength={MAX_TEXT}
                value={body}
                onChange={(event) => setBody(event.target.value)}
              />
              <p className="hint">
                {body.length.toLocaleString()} / {MAX_TEXT.toLocaleString()} characters
              </p>
            </div>
          ) : (
            <div className="stack gap-12">
              <button type="button" className="file-picker" onClick={() => fileInput.current?.click()}>
                <span className="icon-tile">{image ? <ImageIcon size={24} /> : <Upload size={24} />}</span>
                <span className="text">
                  <strong>{image ? image.name : 'Select an image'}</strong>
                  <span>{image ? 'Image selected for secure sharing · click to replace' : 'PNG or JPEG, up to 5 MB'}</span>
                </span>
              </button>
              <input ref={fileInput} type="file" accept="image/png,image/jpeg" hidden onChange={pickImage} />
              {image && <img className="preview-thumb" src={image.dataUrl} alt="Selected image preview" />}
            </div>
          )}
        </section>

        <section className="stack gap-14">
          <SectionHeader title="Recipient" icon={UserPlus} />
          <TextField
            label="Recipient"
            icon={UserPlus}
            placeholder="Their Aperture username"
            autoComplete="off"
            value={recipient}
            onChange={(event) => setRecipient(event.target.value)}
          />
        </section>

        <section className="stack gap-14">
          <SectionHeader title="Viewing Restrictions" icon={ShieldCheck} />

          <div className="two-col">
            <div className="field">
              <label htmlFor="start">Access starts</label>
              <select
                id="start"
                className="select"
                value={startNow ? 'now' : 'scheduled'}
                onChange={(event) => setStartNow(event.target.value === 'now')}
              >
                <option value="now">Immediately</option>
                <option value="scheduled">At a scheduled time…</option>
              </select>
              {!startNow && (
                <input className="input" type="datetime-local" aria-label="Start date and time" value={startAt} onChange={(event) => setStartAt(event.target.value)} />
              )}
            </div>
            <div className="field">
              <label htmlFor="expiration">
                <Clock size={15} aria-hidden="true" style={{ verticalAlign: '-2px', marginRight: 6 }} />
                Expiration
              </label>
              <select id="expiration" className="select" value={expiration} onChange={(event) => setExpiration(event.target.value as Expiration)}>
                {EXPIRATIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
              {expiration === 'custom' && (
                <input className="input" type="datetime-local" aria-label="Expiration date and time" value={expiresAt} onChange={(event) => setExpiresAt(event.target.value)} />
              )}
            </div>
          </div>

          <div className="field">
            <label htmlFor="views">
              <Eye size={15} aria-hidden="true" style={{ verticalAlign: '-2px', marginRight: 6 }} />
              View Limit
            </label>
            <select id="views" className="select" value={oneView ? '1' : 'unlimited'} onChange={(event) => setOneView(event.target.value === '1')}>
              <option value="unlimited">Unlimited</option>
              <option value="1">1 view</option>
            </select>
          </div>

          <ToggleTile
            icon={Smartphone}
            title="Approved Device"
            subtitle={trustedDevice ? 'Only a device an administrator has approved can open it.' : 'Any device the recipient signs in on can open it.'}
            checked={trustedDevice}
            onChange={setTrustedDevice}
          />
          <ToggleTile
            icon={Monitor}
            title="Screenshot Protection"
            subtitle={
              screenshot
                ? 'Web and desktop viewers cannot block screenshots, so the server will refuse to show it there.'
                : 'No screenshot restriction is selected.'
            }
            checked={screenshot}
            onChange={setScreenshot}
          />

          <div className="field">
            <span className="label">
              <MapPin size={15} aria-hidden="true" style={{ verticalAlign: '-2px', marginRight: 6 }} />
              Location
            </span>
            <Segmented<LocationMode>
              label="Location requirement"
              value={locationMode}
              onChange={setLocationMode}
              options={[
                { value: 'none', label: 'Anywhere' },
                { value: 'region', label: 'Region' },
                { value: 'precise', label: 'Exact area' },
              ]}
            />
          </div>

          {locationMode === 'region' && (
            <div className="stack gap-12">
              <p className="hint">Checked against the recipient's IP address. Blank fields are not restricted.</p>
              <div className="two-col">
                <TextField label="Country" placeholder="United States or US" value={country} onChange={(event) => setCountry(event.target.value)} />
                <TextField label="State / region" placeholder="Florida or FL" value={region} onChange={(event) => setRegion(event.target.value)} />
              </div>
              <TextField label="City" placeholder="Boca Raton" value={city} onChange={(event) => setCity(event.target.value)} />
            </div>
          )}

          {locationMode === 'precise' && (
            <div className="stack gap-12">
              <p className="hint">
                The recipient's device shares its GPS position with every check and must stay within {area ? formatRadius(area.radiusMeters) : 'the chosen distance'} of the pin.
                If they leave the area, the content is hidden until they come back.
              </p>
              <LocationPicker value={area} onChange={setArea} />
            </div>
          )}
        </section>

        {error && <Banner kind="error">{error}</Banner>}

        <Button type="submit" icon={Send} busy={busy}>
          {busy ? 'Sharing…' : 'Share Securely'}
        </Button>
      </form>
    </main>
  )
}
