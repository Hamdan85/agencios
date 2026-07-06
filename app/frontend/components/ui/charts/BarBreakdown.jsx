import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'

// Themed bar chart for a breakdown. `data` = [{ label, value }].
export default function BarBreakdown({ data = [], height = 220 }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="rgba(139,134,163,0.15)" />
        <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#8B86A3' }} />
        <YAxis tick={{ fontSize: 11, fill: '#8B86A3' }} width={40} />
        <Tooltip />
        <Bar dataKey="value" fill="#7C3AED" radius={[6, 6, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  )
}
