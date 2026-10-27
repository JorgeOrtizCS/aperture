import { Link, Navigate } from 'react-router-dom'
import { useAuth } from '../lib/auth'
import { BrandMark } from '../components/ui'

/** Mobile WelcomeScreen. */
export default function WelcomePage() {
  const { user } = useAuth()
  if (user) return <Navigate to="/dashboard" replace />

  return (
    <main className="page narrow stack center gap-28" style={{ minHeight: '100vh', justifyContent: 'center' }}>
      <BrandMark />
      <div className="stack center gap-14">
        <h1 className="title-xl">Aperture</h1>
        <p className="lead">Share sensitive content securely.</p>
        <p className="body">Control who can view your content and the conditions required to access it.</p>
      </div>
      <div className="stack gap-14" style={{ width: '100%', marginTop: 24 }}>
        <Link to="/login" className="button">
          Get Started
        </Link>
        <Link to="/register" className="button secondary">
          Create an account
        </Link>
        <p className="muted">Secure • Controlled • Private</p>
      </div>
    </main>
  )
}
