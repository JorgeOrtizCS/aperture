import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Lock, User } from 'lucide-react'
import { useAuth } from '../lib/auth'
import { Banner, BrandMark, Button, TextField, TopBar } from '../components/ui'
import { errorMessage } from '../lib/errors'

/** Mobile LoginScreen, signing in against POST /api/auth/login. */
export default function LoginPage() {
  const { user, signIn, signedOutReason } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const registered = (location.state as { registered?: string } | null)?.registered
  const [username, setUsername] = useState(registered ?? '')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (user) return <Navigate to="/dashboard" replace />

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!username.trim() || !password) {
      setError('Please enter your username and password.')
      return
    }
    setBusy(true)
    setError(null)
    try {
      await signIn(username.trim(), password)
      const from = (location.state as { from?: string } | null)?.from
      navigate(from && from !== '/login' ? from : '/dashboard', { replace: true })
    } catch (err) {
      setError(errorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="page narrow">
      <TopBar title="" back="/" />
      <form className="stack gap-22" onSubmit={submit} noValidate>
        <div className="stack center gap-12" style={{ marginBottom: 18 }}>
          <BrandMark small />
          <h1 className="title-lg" style={{ marginTop: 16 }}>
            Welcome Back
          </h1>
          <p className="body">Sign in to continue to Aperture</p>
        </div>

        {registered && <Banner kind="success">Account created. Sign in to continue.</Banner>}
        {signedOutReason && !registered && <Banner kind="warning">{signedOutReason}</Banner>}

        <TextField
          label="Username"
          icon={User}
          placeholder="Enter your username"
          autoComplete="username"
          value={username}
          onChange={(event) => setUsername(event.target.value)}
        />
        <TextField
          label="Password"
          icon={Lock}
          type="password"
          placeholder="Enter your password"
          autoComplete="current-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />

        {error && <Banner kind="error">{error}</Banner>}

        <Button type="submit" busy={busy}>
          {busy ? 'Signing in…' : 'Sign In'}
        </Button>
        <p className="small center" style={{ display: 'block' }}>
          New to Aperture? <Link to="/register">Create an account</Link>
        </p>
        <p className="muted center" style={{ display: 'block' }}>
          Your content. Your conditions. Your control.
        </p>
      </form>
    </main>
  )
}
