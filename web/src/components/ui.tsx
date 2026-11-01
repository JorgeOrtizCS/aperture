import { useState } from 'react'
import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import type { LucideIcon } from 'lucide-react'
import { ArrowLeft, CircleAlert, CircleCheck, Eye, EyeOff, Info, Lock, TriangleAlert } from 'lucide-react'

// Web counterparts of the mobile widgets in mobile/lib/widgets.

export function BrandMark({ small = false }: { small?: boolean }) {
  return (
    <span className={small ? 'brand-mark small' : 'brand-mark'} aria-hidden="true">
      <Lock size={small ? 42 : 58} strokeWidth={1.75} />
    </span>
  )
}

type ButtonVariant = 'primary' | 'secondary' | 'danger'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  icon?: LucideIcon
  variant?: ButtonVariant
  compact?: boolean
  busy?: boolean
}

/** Mobile ApertureButton: full-width, 56px tall, 14px radius. */
export function Button({ icon: Icon, variant = 'primary', compact, busy, children, className, disabled, ...rest }: ButtonProps) {
  const classes = ['button', variant !== 'primary' && variant, compact && 'compact', className].filter(Boolean).join(' ')
  return (
    <button type="button" className={classes} disabled={disabled || busy} {...rest}>
      {Icon && <Icon size={20} aria-hidden="true" className={busy ? 'spin' : undefined} />}
      {children}
    </button>
  )
}

interface TextFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string
  icon?: LucideIcon
  hint?: ReactNode
}

/** Mobile ApertureTextField: label above, leading icon, password reveal toggle. */
export function TextField({ label, icon: Icon, hint, id, type = 'text', ...rest }: TextFieldProps) {
  const [reveal, setReveal] = useState(false)
  const inputId = id ?? `field-${label.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
  const isPassword = type === 'password'
  return (
    <div className="field">
      <label htmlFor={inputId}>{label}</label>
      <div className={['input-wrap', Icon && 'has-leading', isPassword && 'has-trailing'].filter(Boolean).join(' ')}>
        {Icon && (
          <span className="leading">
            <Icon size={20} aria-hidden="true" />
          </span>
        )}
        <input id={inputId} className="input" type={isPassword && reveal ? 'text' : type} {...rest} />
        {isPassword && (
          <span className="trailing">
            <button
              type="button"
              className="icon-button plain"
              aria-label={reveal ? 'Hide password' : 'Show password'}
              onClick={() => setReveal((value) => !value)}
            >
              {reveal ? <EyeOff size={20} /> : <Eye size={20} />}
            </button>
          </span>
        )}
      </div>
      {hint && <p className="hint">{hint}</p>}
    </div>
  )
}

/** Mobile SectionHeader: icon + bold title. */
export function SectionHeader({ title, icon: Icon, count }: { title: string; icon: LucideIcon; count?: number }) {
  return (
    <div className="section-header">
      <Icon size={22} aria-hidden="true" />
      <h2>{title}</h2>
      {count !== undefined && <span className="count">{count}</span>}
    </div>
  )
}

/** Sub-page bar with a back arrow (the mobile AppBar). */
export function TopBar({ title, back = '/dashboard', actions }: { title: string; back?: string | -1; actions?: ReactNode }) {
  const navigate = useNavigate()
  return (
    <div className="top-bar">
      <button
        type="button"
        className="icon-button plain"
        aria-label="Back"
        onClick={() => (back === -1 ? navigate(-1) : navigate(back))}
      >
        <ArrowLeft size={22} />
      </button>
      <h1>{title}</h1>
      {actions}
    </div>
  )
}

export type Tone = 'primary' | 'success' | 'warning' | 'danger' | 'muted'

export function StatusPill({ label, tone }: { label: string; tone: Tone }) {
  return <span className={tone === 'primary' ? 'status' : `status ${tone}`}>{label}</span>
}

/** Mobile ContentCard: icon tile, title, subtitle, status. */
export function ContentCard({
  to,
  icon: Icon,
  title,
  subtitle,
  status,
  tone,
}: {
  to: string
  icon: LucideIcon
  title: string
  subtitle: string
  status: string
  tone: Tone
}) {
  return (
    <Link to={to} className="content-card">
      <span className="icon-tile">
        <Icon size={24} aria-hidden="true" />
      </span>
      <span className="text">
        <strong>{title}</strong>
        <span>{subtitle}</span>
      </span>
      <StatusPill label={status} tone={tone} />
    </Link>
  )
}

/** Mobile RestrictionTile: icon, title, subtitle, switch. */
export function ToggleTile({
  icon: Icon,
  title,
  subtitle,
  checked,
  onChange,
}: {
  icon: LucideIcon
  title: string
  subtitle: string
  checked: boolean
  onChange: (value: boolean) => void
}) {
  return (
    <div className="tile">
      <span className="icon-tile small">
        <Icon size={22} aria-hidden="true" />
      </span>
      <span className="text">
        <strong>{title}</strong>
        <span>{subtitle}</span>
      </span>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={title}
        className="switch"
        onClick={() => onChange(!checked)}
      />
    </div>
  )
}

export function Segmented<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: T
  options: { value: T; label: string; icon?: LucideIcon }[]
  onChange: (value: T) => void
}) {
  return (
    <div className="segmented" role="group" aria-label={label}>
      {options.map(({ value: optionValue, label: optionLabel, icon: Icon }) => (
        <button key={optionValue} type="button" aria-pressed={value === optionValue} onClick={() => onChange(optionValue)}>
          {Icon && <Icon size={18} aria-hidden="true" />}
          {optionLabel}
        </button>
      ))}
    </div>
  )
}

/** One line of a policy or condition list. */
export function PolicyRow({
  icon: Icon,
  tone = 'primary',
  title,
  detail,
  trailing,
}: {
  icon: LucideIcon
  tone?: Tone
  title: string
  detail: ReactNode
  trailing?: ReactNode
}) {
  return (
    <div className="policy-row">
      <span className={tone === 'primary' || tone === 'muted' ? 'icon' : `icon ${tone}`}>
        <Icon size={20} aria-hidden="true" />
      </span>
      <span className="text">
        <strong>{title}</strong>
        <span>{detail}</span>
      </span>
      {trailing}
    </div>
  )
}

const bannerIcons: Record<'error' | 'success' | 'warning' | 'info', LucideIcon> = {
  error: CircleAlert,
  success: CircleCheck,
  warning: TriangleAlert,
  info: Info,
}

export function Banner({ kind, children }: { kind: 'error' | 'success' | 'warning' | 'info'; children: ReactNode }) {
  const Icon = bannerIcons[kind]
  return (
    <div className={`banner ${kind}`} role={kind === 'error' ? 'alert' : 'status'}>
      <Icon size={18} aria-hidden="true" />
      <div>{children}</div>
    </div>
  )
}
