import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid, Cell } from 'recharts'
import ChartTooltip, { barCursor } from './ChartTooltip'

// Themed bar chart for a breakdown. `data` = [{ label, value, color? }]. Each bar
// is the hit target (branded per-bar tooltip, soft wash cursor); a per-row `color`
// paints identity, else the brand hue. Labels are the caller's copy (already PT-BR).
export default function BarBreakdown({ data = [], height = 220, color = '#7C3AED' }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="rgba(139,134,163,0.15)" vertical={false} />
        <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#8B86A3' }} tickLine={false} axisLine={false} />
        <YAxis tick={{ fontSize: 11, fill: '#8B86A3' }} width={40} tickLine={false} axisLine={false} />
        <Tooltip content={<ChartTooltip />} cursor={barCursor} />
        <Bar dataKey="value" radius={[6, 6, 0, 0]} maxBarSize={56}>
          {data.map((d, i) => <Cell key={i} fill={d.color || color} />)}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}
