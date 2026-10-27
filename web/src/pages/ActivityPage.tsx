import type { LucideIcon } from 'lucide-react'
import { Ban, Bell, CircleCheck, EyeOff, Send, ShieldCheck, Trash, TriangleAlert } from 'lucide-react'
import type { ActivityKind } from '../lib/activity'
import { clearActivity, useActivity } from '../lib/activity'
import { formatDateTime } from '../lib/format'
import type { Tone } from '../components/ui'
import { Button, SectionHeader, TopBar } from '../components/ui'

const look: Record<ActivityKind, { icon: LucideIcon; tone: Tone }> = {
  granted: { icon: CircleCheck, tone: 'success' },
  restored: { icon: CircleCheck, tone: 'success' },
  denied: { icon: Ban, tone: 'danger' },
  ended: { icon: TriangleAlert, tone: 'danger' },
  suspended: { icon: EyeOff, tone: 'warning' },
  shared: { icon: Send, tone: 'primary' },
  policy: { icon: ShieldCheck, tone: 'primary' },
}

/** Mobile NotificationsScreen, fed by what this browser has seen happen. */
export default function ActivityPage() {
  const events = useActivity()

  return (
    <main className="page stack gap-22">
      <TopBar title="Notifications" />
      <SectionHeader title="Recent Activity" icon={Bell} count={events.length} />
      <p className="small">Access decisions and policy changes seen in this browser, newest first.</p>
      {events.length === 0 && <p className="empty">No activity yet. Open or share content and it will show up here.</p>}
      <div className="stack gap-12">
        {events.map((event) => {
          const { icon: Icon, tone } = look[event.kind]
          return (
            <div key={event.id} className="tile">
              <span className={tone === 'primary' ? 'icon-tile small' : `icon-tile small ${tone}`}>
                <Icon size={22} aria-hidden="true" />
              </span>
              <span className="text">
                <strong>{event.title}</strong>
                <span>{event.detail}</span>
                <span className="muted" style={{ marginTop: 6 }}>
                  {formatDateTime(event.at)}
                </span>
              </span>
            </div>
          )
        })}
      </div>
      {events.length > 0 && (
        <Button variant="secondary" icon={Trash} onClick={clearActivity}>
          Clear activity
        </Button>
      )}
    </main>
  )
}
