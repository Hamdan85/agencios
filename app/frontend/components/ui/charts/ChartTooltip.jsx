import { compact } from '@/lib/formatters'
import { seriesLabel } from './labels'

// The one branded tooltip for every recharts chart in the app — a surface card in
// the design-system chrome (rounded, bordered, elevated), keyed to the viewer's
// theme. Follows the house dataviz spec: the VALUE leads (strong ink), the series
// name follows (muted ink), and identity rides a short colored stroke — never a
// filled box, never colored text. Series keys are mapped to Portuguese via
// `seriesLabel`, so a hover never leaks a raw English key.
//
// Drop into any chart as `<Tooltip content={<ChartTooltip />} cursor={...} />`.
// `labelFormat` formats the header (the X value); `valueFormat` formats each row.
export default function ChartTooltip({ active, payload, label, labelFormat, valueFormat = compact }) {
  if (!active || !payload?.length) return null

  const header = labelFormat ? labelFormat(label) : label
  // Resolve each row's identity per chart shape: a multi-series LINE keys rows by
  // `dataKey` (views/engagement…) → mapped to PT-BR; a BAR/PIE keys the single
  // mark by its category/slice name (`payload.label` via nameKey) → passthrough.
  const rows = payload.map((p) => {
    const key = p.dataKey
    const raw = key && key !== 'value' ? key : (p.payload?.label ?? p.name)
    return {
      name: seriesLabel(raw),
      value: p.value,
      color: p.color || p.stroke || p.fill || p.payload?.color || '#7C3AED',
    }
  })

  // Hide the header when it would just echo the only row (bar hovers, where
  // recharts sets `label` to the same category); keep it for the line's date axis.
  const showHeader = header != null && header !== '' && !(rows.length === 1 && String(header) === String(rows[0].name))

  return (
    <div className="rounded-xl border border-border bg-surface px-3 py-2 shadow-[0_8px_24px_-8px_rgba(24,18,43,0.25)]">
      {showHeader && (
        <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wider text-ink-muted">{header}</p>
      )}
      <div className="space-y-1">
        {rows.map((r, i) => (
          <div key={i} className="flex items-center gap-2.5">
            <span className="h-0.5 w-3.5 shrink-0 rounded-full" style={{ background: r.color }} />
            <span className="text-xs font-medium text-ink-secondary">{r.name}</span>
            <span className="ml-auto pl-3 font-display text-sm font-bold tabular-nums text-ink">{valueFormat(r.value)}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

// A recessive hover cursor for line/area charts — a faint brand hairline crosshair
// instead of recharts' default heavy gray band.
export const lineCursor = { stroke: '#7C3AED', strokeWidth: 1, strokeOpacity: 0.35, strokeDasharray: '3 3' }
// A soft wash behind the hovered bar/segment (never a hard gray rect).
export const barCursor = { fill: 'rgba(124,58,237,0.08)' }
