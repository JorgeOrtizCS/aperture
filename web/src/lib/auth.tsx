import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { api, setToken, setUnauthorizedHandler } from '../api/client'
import type { UserInfo } from '../api/types'
import { readStorage, writeStorage } from './storage'

// The token lives in sessionStorage: it is only valid until the API restarts anyway,
// and it should not outlive the browser tab.
const STORAGE_KEY = 'aperture.session'

interface StoredSession {
  token: string
  user: UserInfo
}

interface AuthState {
  user: UserInfo | null
  /** Set when the API rejected the token, so the login page can explain why. */
  signedOutReason: string | null
  signIn: (username: string, password: string) => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthState | null>(null)

function loadSession(): StoredSession | null {
  const raw = readStorage('session', STORAGE_KEY)
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw) as StoredSession
    return parsed.token && parsed.user ? parsed : null
  } catch {
    return null
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<StoredSession | null>(() => {
    const stored = loadSession()
    setToken(stored?.token ?? null)
    return stored
  })
  const [signedOutReason, setSignedOutReason] = useState<string | null>(null)

  const clear = useCallback((reason: string | null) => {
    setToken(null)
    writeStorage('session', STORAGE_KEY, null)
    setSession(null)
    setSignedOutReason(reason)
  }, [])

  useEffect(() => {
    setUnauthorizedHandler(() =>
      clear('Your sign-in is no longer valid (it expired or the server restarted). Please sign in again.'),
    )
    return () => setUnauthorizedHandler(null)
  }, [clear])

  const signIn = useCallback(async (username: string, password: string) => {
    const response = await api.login(username, password)
    if (!response.Success || !response.Token || !response.User) {
      throw new Error(response.Message || 'Invalid username or password.')
    }
    const next = { token: response.Token, user: response.User }
    setToken(next.token)
    writeStorage('session', STORAGE_KEY, JSON.stringify(next))
    setSignedOutReason(null)
    setSession(next)
  }, [])

  const signOut = useCallback(async () => {
    try {
      await api.logout()
    } catch {
      // Signing out locally is what matters; the token dies with the API process anyway.
    }
    clear(null)
  }, [clear])

  const value = useMemo<AuthState>(
    () => ({ user: session?.user ?? null, signedOutReason, signIn, signOut }),
    [session, signedOutReason, signIn, signOut],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthState {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
