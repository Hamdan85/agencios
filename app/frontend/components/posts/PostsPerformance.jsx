import { Link } from 'react-router-dom'
import { Megaphone, Eye, Users, Heart, TrendingUp, ExternalLink, BarChart3 } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { StatCard } from '@/components/ui/page-header'
import { SectionLabel } from '@/components/ui/section-label'
import { Skeleton, EmptyState } from '@/components/ui/feedback'
import { NetworkBadge, CreativeTypeChip } from '@/components/ui/iconography'
import LineTrend from '@/components/ui/charts/LineTrend'
import DonutBreakdown from '@/components/ui/charts/DonutBreakdown'
import RankBars from '@/components/ui/charts/RankBars'
import { channelMeta, creativeMeta } from '@/lib/constants'
import { compact, num, shortDt } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const BRAND = '#0EA5E9'

// A titled panel with a tinted dot + section label header, matching the rest of
// the app's analytics cards.
function Panel({ title, color = '#7C3AED', className, children }) {
  return (
    <Card className={cn('p-5', className)}>
      <SectionLabel as="div" className="mb-4 flex items-center gap-2 text-ink-secondary">
        <span className="size-2 rounded-full" style={{ background: color }} />
        {title}
      </SectionLabel>
      {children}
    </Card>
  )
}

// The "Desempenho" tab: the analytics dashboard over the current filter window —
// a KPI row, a trend line, network / format / campaign breakdowns and the top
// performing posts.
export default function PostsPerformance({ overview, loading }) {
  if (loading) {
    return (
      <div className="flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
          {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-28 rounded-2xl" />)}
        </div>
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Skeleton className="h-72 rounded-2xl lg:col-span-2" />
          <Skeleton className="h-72 rounded-2xl" />
        </div>
      </div>
    )
  }

  if (!overview) {
    return (
      <EmptyState
        icon={BarChart3}
        title="Sem dados de desempenho"
        description="Publique conteúdo para começar a acompanhar alcance, visualizações e engajamento aqui."
        color={BRAND}
      />
    )
  }

  const k = overview.kpis || {}
  const rate = k.reach ? (k.engagement / k.reach) * 100 : 0

  const byNetwork = (overview.by_network || []).map((n) => ({
    label: channelMeta(n.provider).label,
    value: n.views,
    color: channelMeta(n.provider).color,
  }))
  const byType = (overview.by_type || []).map((t) => ({
    label: creativeMeta(t.creative_type).label,
    value: t.views,
    color: creativeMeta(t.creative_type).color,
    icon: creativeMeta(t.creative_type).icon,
  }))
  const byCampaign = (overview.by_campaign || []).map((c) => ({
    label: c.campaign || '—',
    value: c.views,
    color: BRAND,
  }))
  const topPosts = overview.top_posts || []

  return (
    <div className="flex flex-col gap-4">
      {/* KPI row */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <StatCard label="Publicações" value={num(k.posts_count)} icon={Megaphone} color={BRAND} />
        <StatCard label="Visualizações" value={compact(k.views)} icon={Eye} color="#7C3AED" />
        <StatCard label="Alcance" value={compact(k.reach)} icon={Users} color="#6366F1" />
        <StatCard label="Engajamento" value={compact(k.engagement)} icon={Heart} color="#EC4899" />
        <StatCard label="Taxa de engajamento" value={`${num(Math.round(rate * 10) / 10)}%`} icon={TrendingUp} color="#10B981" sub="engajamento / alcance" />
      </div>

      {/* Trend + network split */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Panel title="Tendência" color="#7C3AED" className="lg:col-span-2">
          <LineTrend data={overview.timeseries || []} keys={['views', 'engagement', 'reach']} />
        </Panel>
        <Panel title="Por rede" color={BRAND}>
          <DonutBreakdown data={byNetwork} legend unit="views" />
        </Panel>
      </div>

      {/* Format + campaign rankings */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Panel title="Por formato" color="#EC4899">
          <RankBars data={byType} />
        </Panel>
        <Panel title="Por campanha" color={BRAND}>
          <RankBars data={byCampaign} />
        </Panel>
      </div>

      {/* Top posts */}
      <Panel title="Melhores publicações" color="#10B981">
        {topPosts.length === 0 ? (
          <p className="rounded-xl bg-surface-muted/50 px-4 py-6 text-center text-sm text-ink-muted">Sem publicações no período</p>
        ) : (
          <ul className="divide-y divide-border">
            {topPosts.map((p, i) => (
              <li key={p.post_id} className="flex items-center gap-3 py-2.5 first:pt-0 last:pb-0">
                <span className="w-5 shrink-0 text-center font-display text-sm font-bold text-ink-muted">{i + 1}</span>
                <div className="min-w-0 flex-1">
                  <Link to={`/publicacoes/${p.post_id}`} className="block truncate text-sm font-semibold text-ink hover:text-brand">
                    {p.label}
                  </Link>
                  <div className="mt-1 flex flex-wrap items-center gap-1.5">
                    <NetworkBadge provider={p.provider} withLabel={false} />
                    <CreativeTypeChip type={p.creative_type} />
                    {p.published_at && <span className="text-[11px] font-medium text-ink-muted">{shortDt(p.published_at)}</span>}
                  </div>
                </div>
                <div className="shrink-0 text-right">
                  <p className="font-display text-sm font-bold tabular-nums text-ink">{compact(p.views)}</p>
                  <p className="text-[11px] font-medium text-ink-muted">{compact(p.engagement)} eng.</p>
                </div>
                {p.permalink && (
                  <a href={p.permalink} target="_blank" rel="noreferrer" className="shrink-0 text-ink-muted transition-colors hover:text-ink" title="Abrir na rede">
                    <ExternalLink size={15} />
                  </a>
                )}
              </li>
            ))}
          </ul>
        )}
      </Panel>
    </div>
  )
}
