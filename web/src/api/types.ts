// Response and request shapes of the Aperture Web API (see docs/ARCHITECTURE.md and /swagger).
// Most bodies are PascalCase; a few endpoints answer with camelCase anonymous objects.

export interface UserInfo {
  Id: number
  Username: string
}

export interface LoginResponse {
  Success: boolean
  Message: string
  Token?: string
  ExpiresAt?: string
  User?: UserInfo
}

export interface SharedContent {
  Id: number
  Title: string
  Owner: string
  Mine: boolean
  CreatedAt: string
  /** Recipient's access: Active or Revoked. */
  Status: string
  /** Policy: Active or Paused. */
  PolicyStatus: string
  /** Set on content the user sent. */
  Recipient?: string
}

export interface CreateContentRequest {
  Title: string
  Recipient: string
  Body?: string
  FileDataBase64?: string
  FileType?: 'image/png' | 'image/jpeg'
  StartTime?: string
  ExpiresAt?: string
  MaxViews?: 1
  RequireTrustedDevice: boolean
  ScreenshotRestriction: boolean
  AllowedCountry?: string
  AllowedRegion?: string
  AllowedCity?: string
}

export interface SessionResult {
  SessionId: number
  AccessGranted: boolean
  DeviceVerified: boolean
  LocationVerified: boolean
  Message: string
  Title?: string
  Body?: string
  FileDataBase64?: string
  FileType?: string
}

export interface TimeWindowStatus {
  passed: boolean
  reason?: string
  startTime?: string
  expiresAt?: string
}

export interface SuspensionStatus {
  SessionId: number
  Suspended: boolean
  Source?: 'manual' | 'check'
  Reason?: string
  SinceUtc?: string
  HoldUntilUtc?: string
}

export interface GeoFix {
  latitude: number
  longitude: number
}
