import { useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Card } from '@/components/ui/card'
import { IconTile } from '@/components/ui/icon-tile'
import { SectionLabel } from '@/components/ui/section-label'
import { EmptyState } from '@/components/ui/feedback'
import DonutBreakdown from '@/components/ui/charts/DonutBreakdown'
import LineTrend from '@/components/ui/charts/LineTrend'
import { num, timeAgo } from '@/lib/formatters'
import {
  Eye, BarChart3, Heart, MessageCircle, Share2, Bookmark, TrendingUp, Activity, LineChart,
} from 'lucide-react'

// Reach + views are the "how many saw it" pair; the four below compose engagement.
const METRIC_TILES = [
  { key: 'reach', labelKey: 'common:series.reach', icon: Eye, color: '#0EA5E9' },
  { key: 'views', labelKey: 'common:series.views', icon: BarChart3, color: '#7C3AED' },
  { key: 'likes', labelKey: 'common:series.likes', icon: Heart, color: '#EC4899' },
  { key: 'comments', labelKey: 'common:series.comments', icon: MessageCircle, color: '#F59E0B' },
  { key: 'shares', labelKey: 'metrics.sharesShort', icon: Share2, color: '#10B981' },
  { key: 'saves', labelKey: 'metrics.savesShort', icon: Bookmark, color: '#6366F1' },
]

const ENGAGEMENT = [
  { key: 'likes', labelKey: 'common:series.likes', color: '#EC4899' },
  { key: 'comments', labelKey: 'common:series.comments', color: '#F59E0B' },
  { key: 'shares', labelKey: 'metrics.sharesShort', color: '#10B981' },
  { key: 'saves', labelKey: 'metrics.savesShort', color: '#6366F1' },
]

const fmt = (n) => (n != null ? num(n) : '—')

// One metric tile: tinted icon, big number, eyebrow label.
function MetricTile({ icon: Icon, label, value, color }) {
  return (
    <div className="rounded-xl border border-border bg-surface-muted/50 p-3 text-center">
      <Icon size={16} strokeWidth={2.3} className="mx-auto" style={{ color }} />
      <p className="mt-1.5 font-display text-lg font-extrabold text-ink">{fmt(value)}</p>
      <SectionLabel className="text-[10px] font-semibold tracking-wide">{label}</SectionLabel>
    </div>
  )
}

function SectionCard({ icon: Icon, color, title, hint, children }) {
  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex items-center gap-2.5 border-b border-border p-4" style={{ background: `${color}08` }}>
        <IconTile icon={Icon} color={color} size="xs" tint="18" strokeWidth={2.3} />
        <div className="min-w-0">
          <h3 className="font-display text-sm font-bold text-ink">{title}</h3>
          {hint && <p className="truncate text-[11px] font-medium text-ink-muted">{hint}</p>}
        </div>
      </div>
      <div className="p-4">{children}</div>
    </Card>
  )
}

// The side-column performance stack. When metrics are present: a metric-tile
// grid, a headline engagement-rate stat, an engagement-composition donut, and —
// with more than one history point — an evolution line chart. When metrics are
// null: a friendly empty state (nothing is synced until the post is live).
export default function PostDetailPerformance({ metrics, history = [] }) {
  const { t } = useTranslation('posts')
  const engagementDonut = useMemo(
    () => ENGAGEMENT.map((e) => ({ label: t(e.labelKey), value: Number(metrics?.[e.key]) || 0, color: e.color })),
    [metrics, t],
  )
  const trend = useMemo(
    () => (history || []).map((h) => ({
      date: (h.captured_at || '').slice(0, 10),
      views: h.views,
      engagement: h.engagement,
      reach: h.reach,
    })),
    [history],
  )

  if (!metrics) {
    return (
      <EmptyState
        icon={LineChart}
        color="#7C3AED"
        title={t('performance.noMetrics.title')}
        description={t('performance.noMetrics.description')}
      />
    )
  }

  const engagementTotal = ENGAGEMENT.reduce((s, e) => s + (Number(metrics[e.key]) || 0), 0)
  const reach = Number(metrics.reach) || 0
  const rate = reach > 0 ? (engagementTotal / reach) * 100 : null

  return (
    <div className="space-y-5">
      <SectionCard
        icon={BarChart3}
        color="#7C3AED"
        title={t('performance.metricsTitle')}
        hint={metrics.captured_at ? t('performance.syncedAgo', { time: timeAgo(metrics.captured_at) }) : null}
      >
        <div className="grid grid-cols-3 gap-2.5">
          {METRIC_TILES.map((tile) => (
            <MetricTile key={tile.key} icon={tile.icon} label={t(tile.labelKey)} value={metrics[tile.key]} color={tile.color} />
          ))}
        </div>

        {rate != null && (
          <div className="mt-3 flex items-center gap-3 rounded-xl border border-border bg-surface-muted/40 p-3.5">
            <IconTile icon={TrendingUp} color="#10B981" size="sm" tint="18" strokeWidth={2.4} />
            <div className="min-w-0">
              <SectionLabel className="text-[10px] tracking-wide">{t('performance.engagementRate')}</SectionLabel>
              <p className="font-display text-xl font-extrabold text-ink">{`${num(Math.round(rate * 10) / 10)}%`}</p>
            </div>
            <p className="ml-auto text-right text-[11px] font-medium text-ink-muted">
              {t('performance.interactions', { value: fmt(engagementTotal) })}<br />{t('performance.overReach', { value: fmt(reach) })}
            </p>
          </div>
        )}
      </SectionCard>

      {engagementTotal > 0 && (
        <SectionCard icon={Activity} color="#EC4899" title={t('performance.engagementTitle')} hint={t('performance.engagementHint')}>
          <DonutBreakdown data={engagementDonut} total={engagementTotal} unit={t('performance.interactionsUnit')} legend />
        </SectionCard>
      )}

      {trend.length > 1 && (
        <SectionCard icon={LineChart} color="#0EA5E9" title={t('performance.evolutionTitle')} hint={t('performance.evolutionHint')}>
          <div className="overflow-x-auto">
            <div className="min-w-[280px]">
              <LineTrend data={trend} keys={['views', 'engagement', 'reach']} />
            </div>
          </div>
        </SectionCard>
      )}
    </div>
  )
}
