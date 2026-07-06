import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'

// Themed line chart for one or more metrics over time. `data` = [{ date, ...metrics }].
export default function LineTrend({ data = [], keys = ['views'], height = 240 }) {
  const colors = { views: '#7C3AED', engagement: '#EC4899', reach: '#0EA5E9' }
  return (
    <ResponsiveContainer width="100%" height={height}>
      <LineChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="rgba(139,134,163,0.15)" />
        <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#8B86A3' }} />
        <YAxis tick={{ fontSize: 11, fill: '#8B86A3' }} width={40} />
        <Tooltip />
        {keys.map((k) => (
          <Line key={k} type="monotone" dataKey={k} stroke={colors[k] || '#7C3AED'} strokeWidth={2} dot={false} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  )
}
