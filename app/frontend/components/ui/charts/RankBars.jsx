import { compact } from '@/lib/formatters'

// A labeled horizontal-bar ranking — one row per item, bar width proportional to
// the max. Pure CSS (no recharts) so it reads crisply at any row count and
// carries an icon + colored bar per row. `data` = [{ label, value, color, icon }].
export default function RankBars({ data = [], max, valueFormat = compact, emptyLabel = 'Sem dados' }) {
  const rows = (data || []).filter((d) => d && d.label != null)
  if (!rows.length) {
    return <p className="rounded-xl bg-surface-muted/50 px-4 py-6 text-center text-sm text-ink-muted">{emptyLabel}</p>
  }
  const peak = max ?? Math.max(1, ...rows.map((d) => d.value || 0))
  return (
    <div className="space-y-2.5">
      {rows.map((d) => {
        const Icon = d.icon
        const color = d.color || '#7C3AED'
        return (
          <div key={d.label} className="flex items-center gap-3">
            <div className="flex w-28 shrink-0 items-center gap-1.5 sm:w-32">
              {Icon && <Icon size={13} strokeWidth={2.3} style={{ color }} className="shrink-0" />}
              <span className="truncate text-xs font-semibold capitalize text-ink-secondary" title={d.label}>{d.label}</span>
            </div>
            <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-surface-muted">
              <div className="h-full rounded-full" style={{ width: `${Math.max(3, ((d.value || 0) / peak) * 100)}%`, background: color }} />
            </div>
            <span className="w-14 shrink-0 text-right font-display text-sm font-bold tabular-nums text-ink">{valueFormat(d.value || 0)}</span>
          </div>
        )
      })}
    </div>
  )
}
