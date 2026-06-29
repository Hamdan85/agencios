import { cn } from '@/lib/utils'

// The bold page header used across every screen.
export function PageHeader({ eyebrow, title, icon: Icon, color = '#7C3AED', description, actions, className }) {
  return (
    <div className={cn('mb-7 flex flex-wrap items-start justify-between gap-4', className)}>
      <div className="flex items-start gap-3.5">
        {Icon && (
          <div className="flex size-12 shrink-0 items-center justify-center rounded-2xl shadow-sm" style={{ background: `${color}16`, color }}>
            <Icon size={24} strokeWidth={2.2} />
          </div>
        )}
        <div>
          {eyebrow && <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-ink-muted">{eyebrow}</p>}
          <h1 className="font-display text-2xl font-extrabold tracking-tight text-ink sm:text-[28px]">{title}</h1>
          {description && <p className="mt-0.5 max-w-xl text-sm text-ink-muted">{description}</p>}
        </div>
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  )
}

// A vivid metric card — big number, icon chip, trend.
export function StatCard({ label, value, icon: Icon, color = '#7C3AED', sub, className }) {
  // Long values (formatted money like "R$ 14.700,00", which uses a non-breaking
  // space so it can't wrap) get a smaller size so they fit on one line even in
  // the tightest grids (2-col on mobile, 6-col on desktop). Short counts stay
  // big and punchy.
  const compact = typeof value === 'string' && value.replace(/\s/g, '').length > 8
  return (
    <div className={cn('relative overflow-hidden rounded-2xl border border-border bg-surface p-4 lift sm:p-5', className)}>
      <div className="absolute -right-6 -top-6 size-24 rounded-full opacity-[0.07]" style={{ background: color }} />
      <div className="flex items-center justify-between gap-2">
        <p className="min-w-0 text-xs font-bold uppercase tracking-wider text-ink-muted">{label}</p>
        {Icon && (
          <div className="flex size-9 shrink-0 items-center justify-center rounded-xl" style={{ background: `${color}16`, color }}>
            <Icon size={18} strokeWidth={2.2} />
          </div>
        )}
      </div>
      <p className={cn('mt-3 truncate font-display font-extrabold tracking-tight text-ink', compact ? 'text-lg' : 'text-2xl sm:text-3xl')}>{value}</p>
      {sub && <p className="mt-1 text-xs font-medium text-ink-muted">{sub}</p>}
    </div>
  )
}
