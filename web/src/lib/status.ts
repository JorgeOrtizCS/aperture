import type { SharedContent } from '../api/types'
import type { Tone } from '../components/ui'

/** Status chip for a dashboard card, from the recipient's access and the policy status. */
export function contentStatus(item: SharedContent): { label: string; tone: Tone } {
  if (item.Status !== 'Active') return { label: 'Revoked', tone: 'danger' }
  if (item.PolicyStatus === 'Paused') return { label: 'Paused', tone: 'warning' }
  return item.Mine ? { label: 'Active', tone: 'success' } : { label: 'Available', tone: 'success' }
}
