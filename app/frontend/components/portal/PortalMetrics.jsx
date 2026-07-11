import { useTranslation } from 'react-i18next'
import { Eye, Users, Heart, Megaphone, Bookmark, MessageCircle, Share2, ExternalLink, BarChart3 } from 'lucide-react'
import { StatCard } from '@/components/ui/page-header'
import { SectionLabel } from '@/components/ui/section-label'
import { Card } from '@/components/ui/card'
import { InlineSpinner, EmptyState } from '@/components/ui/feedback'
import { NetworkBadge, CreativeTypeChip } from '@/components/ui/iconography'
import LineTrend from '@/components/ui/charts/LineTrend'
import DonutBreakdown from '@/components/ui/charts/DonutBreakdown'
import RankBars from '@/components/ui/charts/RankBars'
import { channelMeta, creativeMeta } from '@/lib/constants'
import { compact, num, shortDt } from '@/lib/formatters'
import { usePortalMetrics } from '@/hooks/useData'
import { usePortalChannel } from '@/hooks/useRealtime'
import { cn } from '@/lib/utils'

// A titled panel with a tinted dot + section label header — mirrors the internal
// "Desempenho" dashboard (PostsPerformance) so the client portal reads as the
// same analytics surface.
function Panel({ title, color, className, children }) {
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

// A small pulsing "ao vivo" indicator — the portal metrics update in real time via
// the PortalChannel push, so surface that liveness with the agency accent.
function LiveDot({ accent }) {
  const { t } = useTranslation('portal')
  return (
    <span className="inline-flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-ink-muted">
      <span className="relative flex size-2">
        <span className="absolute inline-flex size-full animate-ping rounded-full opacity-60" style={{ background: accent }} />
        <span className="relative inline-flex size-2 rounded-full" style={{ background: accent }} />
      </span>
      {t('metrics.live')}
    </span>
  )
}

// Real-time campaign-metrics view for the login-less client portal. Consumes the
// same PostsOverview payload as the internal "Desempenho" dashboard and stays live
// through the token-authorized PortalChannel push.
export default function PortalMetrics({ token, projectId, accent = '#7C3AED' }) {
  const { t } = useTranslation('portal')
  const { data, isLoading } = usePortalMetrics(token, projectId)
  usePortalChannel(token, projectId)

  if (isLoading || !data) {
    return (
      <div className="flex items-center justify-center py-16">
        <InlineSpinner size={22} />
      </div>
    )
  }

  const overview = data.overview || {}
  const k = overview.kpis || {}

  if (!k.posts_count) {
    return (
      <EmptyState
        icon={BarChart3}
        title={t('metrics.emptyTitle')}
        description={t('metrics.emptyBody')}
        color={accent}
      />
    )
  }

  const rate = k.reach ? (k.engagement / k.reach) * 100 : 0

  const byNetwork = (overview.by_network || []).map((n) => ({
    label: channelMeta(n.provider).label,
    value: n.views,
    color: channelMeta(n.provider).color,
  }))
  const byType = (overview.by_type || []).map((it) => ({
    label: creativeMeta(it.creative_type).label,
    value: it.views,
    color: creativeMeta(it.creative_type).color,
    icon: creativeMeta(it.creative_type).icon,
  }))
  const topPosts = overview.top_posts || []

  // Secondary engagement KPIs — only surface the ones the network actually reported.
  const detailStats = [
    { key: 'likes', label: t('metrics.likes'), value: k.likes, icon: Heart, color: '#EC4899' },
    { key: 'comments', label: t('metrics.comments'), value: k.comments, icon: MessageCircle, color: '#F59E0B' },
    { key: 'shares', label: t('metrics.shares'), value: k.shares, icon: Share2, color: '#10B981' },
    { key: 'saves', label: t('metrics.saves'), value: k.saves, icon: Bookmark, color: '#6366F1' },
  ].filter((s) => s.value != null)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <SectionLabel as="h2" className="text-ink-secondary">{t('metrics.title')}</SectionLabel>
        <LiveDot accent={accent} />
      </div>

      {/* Primary KPI row */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <StatCard label={t('metrics.reach')} value={compact(k.reach)} icon={Users} color={accent} />
        <StatCard label={t('metrics.views')} value={compact(k.views)} icon={Eye} color="#7C3AED" />
        <StatCard label={t('metrics.engagement')} value={compact(k.engagement)} icon={Heart} color="#EC4899" />
        <StatCard label={t('metrics.posts')} value={num(k.posts_count)} icon={Megaphone} color="#6366F1" />
        <StatCard label={t('metrics.engagementRate')} value={`${num(Math.round(rate * 10) / 10)}%`} icon={Heart} color="#10B981" sub={t('metrics.engagementRateSub')} />
      </div>

      {/* Secondary engagement KPIs, when reported */}
      {detailStats.length > 0 && (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {detailStats.map((s) => (
            <StatCard key={s.key} label={s.label} value={compact(s.value)} icon={s.icon} color={s.color} />
          ))}
        </div>
      )}

      {/* Trend + network split */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Panel title={t('metrics.trend')} color="#7C3AED" className="lg:col-span-2">
          <LineTrend data={overview.timeseries || []} keys={['views', 'engagement', 'reach']} />
        </Panel>
        <Panel title={t('metrics.byNetwork')} color={accent}>
          <DonutBreakdown data={byNetwork} legend unit={t('metrics.views')} />
        </Panel>
      </div>

      {/* Format ranking */}
      <Panel title={t('metrics.byFormat')} color="#EC4899">
        <RankBars data={byType} />
      </Panel>

      {/* Top posts */}
      <Panel title={t('metrics.topPosts')} color="#10B981">
        {topPosts.length === 0 ? (
          <p className="rounded-xl bg-surface-muted/50 px-4 py-6 text-center text-sm text-ink-muted">{t('metrics.noPostsInPeriod')}</p>
        ) : (
          <ul className="divide-y divide-border">
            {topPosts.map((p, i) => (
              <li key={p.post_id} className="flex items-center gap-3 py-2.5 first:pt-0 last:pb-0">
                <span className="w-5 shrink-0 text-center font-display text-sm font-bold text-ink-muted">{i + 1}</span>
                <div className="min-w-0 flex-1">
                  {p.permalink ? (
                    <a href={p.permalink} target="_blank" rel="noreferrer" className="block truncate text-sm font-semibold text-ink hover:text-brand">
                      {p.label}
                    </a>
                  ) : (
                    <p className="block truncate text-sm font-semibold text-ink">{p.label}</p>
                  )}
                  <div className="mt-1 flex flex-wrap items-center gap-1.5">
                    <NetworkBadge provider={p.provider} withLabel={false} />
                    <CreativeTypeChip type={p.creative_type} />
                    {p.published_at && <span className="text-[11px] font-medium text-ink-muted">{shortDt(p.published_at)}</span>}
                  </div>
                </div>
                <div className="shrink-0 text-right">
                  <p className="font-display text-sm font-bold tabular-nums text-ink">{compact(p.views)}</p>
                  <p className="text-[11px] font-medium text-ink-muted">{t('metrics.engagementShort', { value: compact(p.engagement) })}</p>
                </div>
                {p.permalink && (
                  <a href={p.permalink} target="_blank" rel="noreferrer" className="shrink-0 text-ink-muted transition-colors hover:text-ink" title={t('metrics.openOnNetwork')}>
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
