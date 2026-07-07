import { cn } from '@/lib/utils'
import { IconTile } from '@/components/ui/icon-tile'

// The bold page header used across every screen. `actionsClassName` lets a
// screen reshape the actions container (e.g. stretch it full-width on mobile
// for a continuous control row) without affecting other pages.
export function PageHeader({ eyebrow, title, icon: Icon, color = '#7C3AED', description, actions, actionsClassName, className }) {
  return (
    <div className={cn('mb-7 flex flex-wrap items-start justify-between gap-4', className)}>
      <div className="flex items-start gap-3.5">
        {Icon && <IconTile icon={Icon} color={color} className="shadow-sm" />}
        <div>
          {eyebrow && <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-ink-muted">{eyebrow}</p>}
          <h1 className="font-display text-2xl font-extrabold tracking-tight text-ink sm:text-[28px]">{title}</h1>
          {description && <p className="mt-0.5 max-w-xl text-sm text-ink-muted">{description}</p>}
        </div>
      </div>
      {actions && <div className={cn('flex items-center gap-2', actionsClassName)}>{actions}</div>}
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
        {Icon && <IconTile icon={Icon} color={color} size="sm" />}
      </div>
      <p className={cn('mt-3 truncate font-display font-extrabold tracking-tight text-ink', compact ? 'text-lg' : 'text-2xl sm:text-3xl')}>{value}</p>
      {sub && <p className="mt-1 text-xs font-medium text-ink-muted">{sub}</p>}
    </div>
  )
}
