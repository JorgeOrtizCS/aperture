import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import { Lock, User, UserPlus } from 'lucide-react'
import { api } from '../api/client'
import { useAuth } from '../lib/auth'
import { Banner, BrandMark, Button, TextField, TopBar } from '../components/ui'
import { errorMessage } from '../lib/errors'

/** Account creation (POST /api/register), in the style of the mobile login screen. */
export default function RegisterPage() {
  const { user } = useAuth()
  const navigate = useNavigate()
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (user) return <Navigate to="/dashboard" replace />

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!firstName.trim() || !lastName.trim() || !username.trim()) {
      setError('First name, last name and username are required.')
      return
    }
    if (password.length < 8) {
      setError('Password must be at least 8 characters.')
      return
    }
    setBusy(true)
    setError(null)
    try {
      await api.register(firstName.trim(), lastName.trim(), username.trim(), password)
      navigate('/login', { replace: true, state: { registered: username.trim() } })
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
            Create Account
          </h1>
          <p className="body">Start sharing on your own terms</p>
        </div>

        <div className="two-col">
          <TextField label="First name" icon={User} autoComplete="given-name" maxLength={100} value={firstName} onChange={(e) => setFirstName(e.target.value)} />
          <TextField label="Last name" icon={User} autoComplete="family-name" maxLength={100} value={lastName} onChange={(e) => setLastName(e.target.value)} />
        </div>
        <TextField
          label="Username"
          icon={UserPlus}
          placeholder="Choose a username"
          autoComplete="username"
          maxLength={100}
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
        <TextField
          label="Password"
          icon={Lock}
          type="password"
          placeholder="At least 8 characters"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />

        {error && <Banner kind="error">{error}</Banner>}

        <Button type="submit" busy={busy}>
          {busy ? 'Creating account…' : 'Create Account'}
        </Button>
        <p className="small center" style={{ display: 'block' }}>
          Already have an account? <Link to="/login">Sign in</Link>
        </p>
      </form>
    </main>
  )
}
