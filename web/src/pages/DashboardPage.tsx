import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Bell, FileText, Inbox, LogOut, Plus, RefreshCw, Send } from 'lucide-react'
import { api } from '../api/client'
import type { SharedContent } from '../api/types'
import { useActivity } from '../lib/activity'
import { useAuth } from '../lib/auth'
import { formatDateTime } from '../lib/format'
import { contentStatus } from '../lib/status'
import { Banner, Button, ContentCard, SectionHeader } from '../components/ui'
import { errorMessage } from '../lib/errors'

/** Mobile DashboardScreen, with the user's real content from GET /api/content. */
export default function DashboardPage() {
  const { user, signOut } = useAuth()
  const navigate = useNavigate()
  const activity = useActivity()
  const [items, setItems] = useState<SharedContent[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      setItems(await api.listContent())
    } catch (err) {
      setError(errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const received = items?.filter((item) => !item.Mine) ?? []
  const sent = items?.filter((item) => item.Mine) ?? []

  return (
    <main className="page stack gap-28">
      <header className="app-header">
        <div className="titles">
          <h1>Aperture</h1>
          <p>Secure Content Dashboard</p>
        </div>
        <button type="button" className="icon-button" aria-label="Activity" onClick={() => navigate('/activity')}>
          <Bell size={21} />
          {activity.length > 0 && <span className="dot" />}
        </button>
        <button type="button" className="icon-button plain" aria-label="Sign out" title="Sign out" onClick={() => void signOut()}>
          <LogOut size={21} />
        </button>
      </header>

      <div className="stack gap-8">
        <h2 className="title-md">Welcome back{user ? `, ${user.Username}` : ''}!</h2>
        <p className="body">Manage the content you share and the content others have securely shared with you.</p>
      </div>

      <Button icon={Plus} onClick={() => navigate('/share')}>
        Share New Content
      </Button>

      {error && (
        <Banner kind="error">
          {error}{' '}
          <button type="button" className="link-button" onClick={() => void load()}>
            Try again
          </button>
        </Banner>
      )}

      <section className="stack gap-14">
        <SectionHeader title="Shared With Me" icon={Inbox} count={items ? received.length : undefined} />
        {items === null && !error && <p className="empty">Loading…</p>}
        {items && received.length === 0 && <p className="empty">Nothing has been shared with you yet.</p>}
        {received.map((item) => {
          const status = contentStatus(item)
          return (
            <ContentCard
              key={`r-${item.Id}`}
              to={`/view/${item.Id}`}
              icon={FileText}
              title={item.Title}
              subtitle={`From ${item.Owner} · ${formatDateTime(item.CreatedAt)}`}
              status={status.label}
              tone={status.tone}
            />
          )
        })}
      </section>

      <section className="stack gap-14">
        <SectionHeader title="My Shared Content" icon={Send} count={items ? sent.length : undefined} />
        {items && sent.length === 0 && <p className="empty">You haven't shared anything yet.</p>}
        {sent.map((item) => {
          const status = contentStatus(item)
          return (
            <ContentCard
              key={`s-${item.Id}`}
              to={`/content/${item.Id}`}
              icon={FileText}
              title={item.Title}
              subtitle={`To ${item.Recipient ?? 'recipient'} · ${formatDateTime(item.CreatedAt)}`}
              status={status.label}
              tone={status.tone}
            />
          )
        })}
      </section>

      <div className="row" style={{ justifyContent: 'center' }}>
        <Button variant="secondary" compact icon={RefreshCw} busy={loading} onClick={() => void load()}>
          Refresh
        </Button>
      </div>
    </main>
  )
}
