import { cn } from '@/lib/utils'

export function Spinner({ size = 22, className }) {
  return (
    <span
      role="status"
      aria-label="Carregando"
      className={cn('inline-block rounded-full border-[3px] border-brand/20 border-t-brand', className)}
      style={{ width: size, height: size, animation: 'ag-spin 0.7s linear infinite' }}
    />
  )
}

export function PageLoader() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <Spinner size={30} />
    </div>
  )
}

export function Skeleton({ className }) {
  return <div className={cn('animate-pulse rounded-xl bg-surface-muted', className)} style={{ animationName: 'ag-pulse' }} />
}

// Big, friendly, iconographic empty state.
export function EmptyState({ icon: Icon, title, description, action, color = '#7C3AED' }) {
  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-border bg-surface/60 px-6 py-16 text-center">
      {Icon && (
        <div className="mb-4 flex size-16 items-center justify-center rounded-2xl" style={{ background: `${color}14`, color }}>
          <Icon size={30} strokeWidth={2} />
        </div>
      )}
      <h3 className="font-display text-lg font-bold text-ink">{title}</h3>
      {description && <p className="mt-1 max-w-sm text-sm text-ink-muted">{description}</p>}
      {action && <div className="mt-5">{action}</div>}
    </div>
  )
}
