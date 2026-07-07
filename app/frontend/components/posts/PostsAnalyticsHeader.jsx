import { Card } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/feedback'
import LineTrend from '@/components/ui/charts/LineTrend'
import BarBreakdown from '@/components/ui/charts/BarBreakdown'
import { compact } from '@/lib/formatters'

function Kpi({ label, value }) {
  return (
    <Card className="p-4">
      <p className="text-xs font-medium text-ink-muted">{label}</p>
      <p className="mt-1 font-display text-2xl font-bold text-ink">{compact(value)}</p>
    </Card>
  )
}

// The analytics band that heads /publicacoes: four KPI tiles, a trend line, and
// a views-by-format bar chart, all over the current filter window.
export default function PostsAnalyticsHeader({ overview, loading }) {
  if (loading || !overview) return <Skeleton className="mb-6 h-40 rounded-2xl" />
  const k = overview.kpis || {}
  const byType = (overview.by_type || []).map((t) => ({ label: t.creative_type, value: t.views }))
  return (
    <div className="mb-6 flex flex-col gap-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Posts" value={k.posts_count} />
        <Kpi label="Visualizações" value={k.views} />
        <Kpi label="Alcance" value={k.reach} />
        <Kpi label="Engajamento" value={k.engagement} />
      </div>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card className="p-4">
          <p className="mb-2 text-sm font-semibold text-ink">Tendência</p>
          <LineTrend data={overview.timeseries} keys={['views', 'engagement']} />
        </Card>
        <Card className="p-4">
          <p className="mb-2 text-sm font-semibold text-ink">Por formato</p>
          <BarBreakdown data={byType} />
        </Card>
      </div>
    </div>
  )
}
