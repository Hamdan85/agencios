import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'
import ChartTooltip, { lineCursor } from './ChartTooltip'
import { seriesLabel, seriesColor } from './labels'

// Themed line chart for one or more metrics over time. `data` = [{ date, ...metrics }].
// Series identity is carried by the house color per key + a Portuguese legend, and
// hovers use the branded ChartTooltip (values lead, keys mapped to PT-BR) with a
// faint crosshair cursor. `legend` (default true for ≥2 series) draws the key.
export default function LineTrend({ data = [], keys = ['views'], height = 240, legend }) {
  const showLegend = legend ?? keys.length >= 2
  return (
    <div>
      <ResponsiveContainer width="100%" height={height}>
        <LineChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="rgba(139,134,163,0.15)" vertical={false} />
          <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#8B86A3' }} tickLine={false} axisLine={false} />
          <YAxis tick={{ fontSize: 11, fill: '#8B86A3' }} width={40} tickLine={false} axisLine={false} />
          <Tooltip content={<ChartTooltip />} cursor={lineCursor} />
          {keys.map((k) => (
            <Line
              key={k}
              type="monotone"
              dataKey={k}
              stroke={seriesColor(k)}
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 4, strokeWidth: 2, stroke: '#fff' }}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
      {showLegend && (
        <div className="mt-2 flex flex-wrap items-center justify-center gap-x-4 gap-y-1">
          {keys.map((k) => (
            <span key={k} className="inline-flex items-center gap-1.5 text-[11px] font-semibold text-ink-muted">
              <span className="h-0.5 w-3.5 rounded-full" style={{ background: seriesColor(k) }} />
              {seriesLabel(k)}
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
