import { ResponsiveContainer, PieChart, Pie, Cell, Tooltip } from 'recharts'
import { compact } from '@/lib/formatters'

// A donut split with a big total in the hole. `data` = [{ label, value, color }].
// Used for the network / format share of a metric (views by default). Legend is
// rendered by the caller (or set `legend` to inline a compact one).
export default function DonutBreakdown({ data = [], height = 200, total, unit = '', legend = false }) {
  const rows = data.filter((d) => (d.value || 0) > 0)
  const sum = total ?? rows.reduce((s, d) => s + (d.value || 0), 0)
  if (!rows.length) {
    return <div className="flex items-center justify-center rounded-xl bg-surface-muted/50 text-sm text-ink-muted" style={{ height }}>Sem dados</div>
  }
  return (
    <div className="flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
      <div className="relative" style={{ width: height, height }}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie data={rows} dataKey="value" nameKey="label" innerRadius="66%" outerRadius="100%" paddingAngle={2} strokeWidth={0}>
              {rows.map((d) => <Cell key={d.label} fill={d.color} />)}
            </Pie>
            <Tooltip formatter={(v) => compact(v)} />
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="font-display text-xl font-extrabold text-ink">{compact(sum)}</span>
          {unit && <span className="text-[10px] font-bold uppercase tracking-wider text-ink-muted">{unit}</span>}
        </div>
      </div>
      {legend && (
        <ul className="space-y-1.5">
          {rows.map((d) => (
            <li key={d.label} className="flex items-center gap-2 text-xs font-semibold text-ink-secondary">
              <span className="size-2.5 rounded-full" style={{ background: d.color }} />
              <span className="capitalize">{d.label}</span>
              <span className="ml-auto tabular-nums text-ink-muted">{compact(d.value)}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
