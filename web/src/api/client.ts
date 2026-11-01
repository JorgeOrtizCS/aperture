import type {
  CreateContentRequest,
  GeoFix,
  LoginResponse,
  SessionResult,
  SharedContent,
  SuspensionStatus,
  TimeWindowStatus,
} from './types'

export class ApiError extends Error {
  readonly status: number
  readonly body: unknown

  constructor(status: number, message: string, body: unknown) {
    super(message)
    this.status = status
    this.body = body
  }
}

type UnauthorizedHandler = () => void

let token: string | null = null
let onUnauthorized: UnauthorizedHandler | null = null

export function setToken(value: string | null) {
  token = value
}

/** Called when an authenticated call gets 401: the token expired or the API restarted. */
export function setUnauthorizedHandler(handler: UnauthorizedHandler | null) {
  onUnauthorized = handler
}

interface RequestOptions {
  body?: unknown
  headers?: Record<string, string>
  /** Statuses whose JSON body is a normal result rather than an error (e.g. 403 SessionResult). */
  resultStatuses?: number[]
  /** Do not treat 401 as "signed out" (login itself answers 401 for bad credentials). */
  anonymous?: boolean
}

function messageFrom(body: unknown, fallback: string): string {
  if (body && typeof body === 'object') {
    const record = body as Record<string, unknown>
    const text = record.Message ?? record.message
    if (typeof text === 'string' && text.trim()) return text
  }
  if (typeof body === 'string' && body.trim()) return body
  return fallback
}

async function request<T>(method: string, path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json', ...options.headers }
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'
  if (token && !options.anonymous) headers.Authorization = `Bearer ${token}`

  let response: Response
  try {
    response = await fetch(`/api${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    })
  } catch {
    throw new ApiError(0, 'Cannot reach the Aperture server. Make sure the Web API is running.', null)
  }

  const text = await response.text()
  let body: unknown = null
  if (text) {
    try {
      body = JSON.parse(text)
    } catch {
      body = text
    }
  }

  if (response.ok || options.resultStatuses?.includes(response.status)) {
    return body as T
  }

  if (response.status === 401 && !options.anonymous && onUnauthorized) {
    onUnauthorized()
  }

  const fallback =
    response.status === 404
      ? 'Not found, or you no longer have access.'
      : response.status === 401
        ? 'Your sign-in has expired. Please sign in again.'
        : `Request failed (${response.status}).`
  throw new ApiError(response.status, messageFrom(body, fallback), body)
}

function locationHeaders(fix: GeoFix | null): Record<string, string> {
  return fix
    ? { 'X-Client-Latitude': String(fix.latitude), 'X-Client-Longitude': String(fix.longitude) }
    : {}
}

export const api = {
  register: (firstName: string, lastName: string, username: string, password: string) =>
    request<{ success: boolean; message: string }>('POST', '/register', {
      body: { firstName, lastName, username, password },
      anonymous: true,
    }),

  login: (username: string, password: string) =>
    request<LoginResponse>('POST', '/auth/login', {
      body: { username, password },
      anonymous: true,
      resultStatuses: [401],
    }),

  logout: () => request<unknown>('POST', '/auth/logout'),

  listContent: () => request<SharedContent[]>('GET', '/content'),

  share: (content: CreateContentRequest) => request<{ id: number }>('POST', '/content', { body: content }),

  setPolicyStatus: (id: number, status: 'Active' | 'Paused') =>
    request<{ status: string }>('POST', `/content/${id}/policy`, { body: { status } }),

  revoke: (id: number) => request<unknown>('POST', `/content/${id}/revoke`, { body: {} }),

  setPreciseLocation: (id: number, latitude: number, longitude: number, radiusMeters: number) =>
    request<unknown>('POST', `/situational/content/${id}/location`, {
      body: { latitude, longitude, radiusMeters },
    }),

  setTimeWindow: (id: number, startTime: string | null, expiresAt: string | null) =>
    request<unknown>('POST', `/situational/content/${id}/time`, { body: { startTime, expiresAt } }),

  checkTimeWindow: (id: number) => request<TimeWindowStatus>('GET', `/situational/content/${id}/time`),

  registerDevice: (deviceKey: string, deviceName: string) =>
    request<{ trusted: boolean }>('POST', '/devices', { body: { deviceKey, deviceName } }),

  /** 200 = granted; 403 = denied by a policy (the body says why). */
  openSession: (id: number, deviceKey: string, fix: GeoFix | null) =>
    request<SessionResult>('POST', `/content/${id}/sessions`, {
      body: { deviceKey },
      headers: locationHeaders(fix),
      resultStatuses: [403],
    }),

  /** 200 with AccessGranted true/false while the session is open; 403/404 once it has ended. */
  checkSession: (sessionId: number, fix: GeoFix | null) =>
    request<SessionResult>('POST', `/content/sessions/${sessionId}/check`, {
      body: {},
      headers: locationHeaders(fix),
    }),

  endSession: (sessionId: number) => request<unknown>('POST', `/content/sessions/${sessionId}/end`, { body: {} }),

  suspendSession: (sessionId: number, reason: string, durationSeconds: number) =>
    request<SuspensionStatus>('POST', `/situational/sessions/${sessionId}/suspend`, {
      body: { reason, durationSeconds },
    }),
}

/** Bearer token for a best-effort request that must outlive the page (ending a session on unload). */
export function endSessionOnUnload(sessionId: number) {
  if (!token) return
  void fetch(`/api/content/sessions/${sessionId}/end`, {
    method: 'POST',
    keepalive: true,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: '{}',
  }).catch(() => undefined)
}
