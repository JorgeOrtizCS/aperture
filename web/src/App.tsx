import type { ReactNode } from 'react'
import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { useAuth } from './lib/auth'
import ActivityPage from './pages/ActivityPage'
import ContentStatusPage from './pages/ContentStatusPage'
import DashboardPage from './pages/DashboardPage'
import LoginPage from './pages/LoginPage'
import RegisterPage from './pages/RegisterPage'
import SecureViewerPage from './pages/SecureViewerPage'
import SharePage from './pages/SharePage'
import WelcomePage from './pages/WelcomePage'

function RequireAuth({ children }: { children: ReactNode }) {
  const { user } = useAuth()
  const location = useLocation()
  if (!user) return <Navigate to="/login" replace state={{ from: location.pathname }} />
  return children
}

function NotFound() {
  return (
    <main className="page narrow stack center gap-14" style={{ minHeight: '60vh', justifyContent: 'center' }}>
      <h1 className="title-md">Page not found</h1>
      <Link to="/">Back to Aperture</Link>
    </main>
  )
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<WelcomePage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route path="/dashboard" element={<RequireAuth><DashboardPage /></RequireAuth>} />
      <Route path="/share" element={<RequireAuth><SharePage /></RequireAuth>} />
      <Route path="/content/:id" element={<RequireAuth><ContentStatusPage /></RequireAuth>} />
      <Route path="/view/:id" element={<RequireAuth><SecureViewerPage /></RequireAuth>} />
      <Route path="/activity" element={<RequireAuth><ActivityPage /></RequireAuth>} />
      <Route path="*" element={<NotFound />} />
    </Routes>
  )
}
