import {
  FileBarChart, AlertTriangle, TrendingUp, TrendingDown,
  CheckCircle2, Sparkles, Target, Lightbulb, Rocket, CalendarClock, Users,
  Eye, Share2, Repeat, Heart, BarChart3, MessageCircle,
} from 'lucide-react'
import { useTranslation } from 'react-i18next'
import i18n from '@/i18n'
import { Card } from '@/components/ui/card'
import { IconTile } from '@/components/ui/icon-tile'
import { SectionLabel } from '@/components/ui/section-label'
import { date, num, pct } from '@/lib/formatters'

// Compact number ("16,8 mil", "3,0 mi") for the headline tiles.
// Unlike formatters.compact(), null/NaN render as "—" (missing metric).
function compact(n) {
  if (n == null || Number.isNaN(Number(n))) return '—'
  const v = Number(n)
  if (Math.abs(v) >= 1_000_000) return i18n.t('reports:compact.millions', { value: (v / 1_000_000).toLocaleString(i18n.language, { maximumFractionDigits: 1 }) })
  if (Math.abs(v) >= 1_000) return i18n.t('reports:compact.thousands', { value: (v / 1_000).toLocaleString(i18n.language, { maximumFractionDigits: 1 }) })
  return num(v)
}

const scoreColor = (s) => (s >= 7 ? '#10B981' : s >= 5 ? '#F59E0B' : '#EF4444')

function SectionTitle({ icon: Icon, children, color = '#7C3AED' }) {
  return (
    <div className="mb-3 mt-8 flex items-center gap-2.5">
      <IconTile icon={Icon} color={color} size="xs" tint="18" strokeWidth={2.3} />
      <h2 className="font-display text-lg font-bold text-ink">{children}</h2>
    </div>
  )
}

function KpiTile({ label, value, delta, icon: Icon }) {
  const down = delta != null && Number(delta) < 0
  return (
    <Card className="p-4">
      <div className="flex items-center gap-2 text-ink-muted">
        {Icon && <Icon size={14} />}
        <SectionLabel as="span" className="font-semibold tracking-wide text-inherit">{label}</SectionLabel>
      </div>
      <p className="mt-1.5 font-display text-2xl font-extrabold text-ink">{value}</p>
      {delta != null && (
        <span className={`mt-1 inline-flex items-center gap-1 text-xs font-bold ${down ? 'text-danger' : 'text-emerald'}`}>
          {down ? <TrendingDown size={13} /> : <TrendingUp size={13} />} {pct(delta)}
        </span>
      )}
    </Card>
  )
}

function CardList({ items = [], color }) {
  if (!items.length) return null
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {items.map((it, i) => (
        <Card key={i} className="p-4">
          <div className="flex items-start gap-2">
            {it.emoji && <span className="text-lg leading-none">{it.emoji}</span>}
            <div>
              {it.tag && (
                <span className="mb-1 inline-block rounded-md px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide" style={{ background: `${color}18`, color }}>
                  {it.tag}
                </span>
              )}
              <h3 className="font-display text-sm font-bold text-ink" style={it.color ? { color } : undefined}>{it.title}</h3>
              <p className="mt-1 text-sm text-ink-secondary">{it.body}</p>
            </div>
          </div>
        </Card>
      ))}
    </div>
  )
}

function PerfColumn({ title, items = [], tone }) {
  const { t } = useTranslation('reports')
  const color = tone === 'good' ? '#10B981' : '#EF4444'
  return (
    <Card className="overflow-hidden">
      <div className="px-4 py-3 text-sm font-bold text-white" style={{ background: color }}>{title}</div>
      <div className="divide-y divide-border">
        {items.length === 0 && <p className="p-4 text-sm text-ink-muted">{t('deck.noData')}</p>}
        {items.map((it, i) => (
          <div key={i} className="p-4">
            <p className="font-semibold text-ink">{it.label}</p>
            <p className="text-sm" style={{ color }}>{it.metric}</p>
          </div>
        ))}
      </div>
    </Card>
  )
}

function MatrixRow({ dimension, score, comment }) {
  const color = scoreColor(Number(score))
  return (
    <div className="flex items-center gap-4 py-3">
      <span className="w-36 shrink-0 font-display text-sm font-bold text-ink">{dimension}</span>
      <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-surface-muted">
        <div className="h-full rounded-full" style={{ width: `${Math.min(100, Number(score) * 10)}%`, background: color }} />
      </div>
      <span className="w-10 shrink-0 text-right font-display text-sm font-extrabold" style={{ color }}>
        {Number(score).toLocaleString(i18n.language, { minimumFractionDigits: 1, maximumFractionDigits: 1 })}
      </span>
      <span className="hidden flex-1 text-xs text-ink-secondary md:block">{comment}</span>
    </div>
  )
}

function PlanColumn({ title, items = [], color }) {
  return (
    <Card className="overflow-hidden">
      <div className="px-4 py-3 text-sm font-bold text-white" style={{ background: color }}>{title}</div>
      <ul className="space-y-2 p-4">
        {(items || []).map((it, i) => (
          <li key={i} className="flex items-start gap-2 text-sm text-ink-secondary">
            <CheckCircle2 size={14} className="mt-0.5 shrink-0" style={{ color }} /> <span>{it}</span>
          </li>
        ))}
      </ul>
    </Card>
  )
}

function Milestones({ title, items = [], color }) {
  return (
    <Card className="overflow-hidden">
      <div className="px-4 py-3 text-sm font-bold text-white" style={{ background: color }}>{title}</div>
      <ul className="space-y-2 p-4">
        {(items || []).map((it, i) => (
          <li key={i} className="flex items-start gap-2 text-sm text-ink-secondary">
            <Repeat size={14} className="mt-0.5 shrink-0" style={{ color }} /> <span>{it}</span>
          </li>
        ))}
      </ul>
    </Card>
  )
}

// Presentational campaign report deck: renders every section from `report.data`
// (Cover → growth angle). Reused by the internal report page and the client
// approval portal — it owns no page shell, no navigation, and no status states.
export default function ReportDeck({ report }) {
  const { t } = useTranslation('reports')
  const d = report.data || {}
  const k = d.kpis || {}
  const overall = d.overall || {}
  const cp = d.content_performance || {}
  const plan = d.action_plan || {}
  const projection = d.projection || {}
  const growth = d.growth_angle || {}
  const score = Number(overall.score ?? report.overall_score)

  return (
    <>
      {/* Cover */}
      <Card className="mb-6 overflow-hidden">
        <div className="h-2.5 w-full bg-brand-gradient" />
        <div className="p-6">
          <div className="flex items-center gap-2 text-brand">
            <FileBarChart size={18} />
            <SectionLabel as="span" className="text-xs tracking-widest text-inherit">{t('deck.coverEyebrow')}</SectionLabel>
          </div>
          <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight text-ink">{report.project_name}</h1>
          <p className="mt-1 text-sm font-semibold text-ink-secondary">
            {report.client_name}
            {report.period_start && <> · {date(report.period_start)} → {date(report.period_end)}</>}
          </p>
          {d.ai_ok === false && (
            <p className="mt-3 rounded-lg bg-amber/15 px-3 py-2 text-xs font-medium text-[#B45309]">
              {t('deck.aiUnavailable')}
            </p>
          )}
        </div>
      </Card>

      {/* OS NÚMEROS */}
      <SectionTitle icon={BarChart3}>{t('deck.numbersTitle')}</SectionTitle>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <KpiTile label={t('deck.kpis.followers')} value={compact(k.followers)} delta={k.follower_growth_pct} icon={Users} />
        <KpiTile label={t('deck.kpis.newFollowers')} value={compact(k.new_followers)} icon={Users} />
        <KpiTile label={t('deck.kpis.accountsReached')} value={compact(k.accounts_reached)} delta={k.reach_delta_pct} icon={Eye} />
        <KpiTile label={t('deck.kpis.views')} value={compact(k.views)} icon={BarChart3} />
        <KpiTile label={t('deck.kpis.postsReach')} value={compact(k.reach)} icon={Eye} />
        <KpiTile label={t('deck.kpis.reelShares')} value={compact(k.reel_shares)} icon={Share2} />
        <KpiTile label={t('deck.kpis.storyReplies')} value={compact(k.story_replies)} icon={MessageCircle} />
        <KpiTile label={t('deck.kpis.engagement')} value={compact(k.engagement)} icon={Heart} />
      </div>
      {k.has_account_data === false && (
        <p className="mt-2 text-xs text-ink-muted">
          {t('deck.accountDataNotice')}
        </p>
      )}

      {/* NOTA GERAL */}
      {Number.isFinite(score) && score > 0 && (
        <>
          <SectionTitle icon={Target}>{t('deck.overallTitle')}</SectionTitle>
          <div className="grid gap-3 md:grid-cols-3">
            <Card className="flex flex-col items-center justify-center p-6 text-center">
              <p className="font-display text-6xl font-black" style={{ color: scoreColor(score) }}>
                {score.toLocaleString(i18n.language, { minimumFractionDigits: 1, maximumFractionDigits: 1 })}
              </p>
              <p className="text-sm font-semibold text-ink-muted">{t('deck.outOfTen')}</p>
              {overall.verdict && <p className="mt-2 text-sm text-ink-secondary">{overall.verdict}</p>}
            </Card>
            <Milestones title={t('deck.toReach8')} items={overall.to_8} color="#10B981" />
            <Milestones title={t('deck.toReach9')} items={overall.to_9} color="#F59E0B" />
          </div>
        </>
      )}

      {/* O QUE ESTÁ FUNCIONANDO */}
      {d.wins?.length > 0 && (
        <>
          <SectionTitle icon={CheckCircle2} color="#10B981">{t('deck.winsTitle')}</SectionTitle>
          <CardList items={d.wins} color="#10B981" />
        </>
      )}

      {/* PERFORMANCE DOS REELS / FORMATOS */}
      {(cp.winners?.length || cp.losers?.length) ? (
        <>
          <SectionTitle icon={Sparkles}>{t('deck.formatPerformanceTitle')}</SectionTitle>
          <div className="grid gap-3 md:grid-cols-2">
            <PerfColumn title={t('deck.whatPerforms')} items={cp.winners} tone="good" />
            <PerfColumn title={t('deck.whatDoesnt')} items={cp.losers} tone="bad" />
          </div>
        </>
      ) : null}

      {/* GARGALOS */}
      {d.bottlenecks?.length > 0 && (
        <>
          <SectionTitle icon={AlertTriangle} color="#EF4444">{t('deck.bottlenecksTitle')}</SectionTitle>
          <div className="space-y-3">
            {d.bottlenecks.map((b, i) => (
              <Card key={i} className="flex gap-4 p-4">
                <span className="font-display text-2xl font-black text-ink-muted">{String(i + 1).padStart(2, '0')}</span>
                <div>
                  <h3 className="font-display text-sm font-bold text-ink">{b.title}</h3>
                  <p className="mt-1 text-sm text-ink-secondary">{b.body}</p>
                </div>
              </Card>
            ))}
          </div>
        </>
      )}

      {/* OPORTUNIDADES */}
      {d.opportunities?.length > 0 && (
        <>
          <SectionTitle icon={Lightbulb} color="#F59E0B">{t('deck.opportunitiesTitle')}</SectionTitle>
          <CardList items={d.opportunities} color="#F59E0B" />
        </>
      )}

      {/* MATRIZ */}
      {d.matrix?.length > 0 && (
        <>
          <SectionTitle icon={BarChart3}>{t('deck.matrixTitle')}</SectionTitle>
          <Card className="divide-y divide-border px-4 py-1">
            {d.matrix.map((m, i) => <MatrixRow key={i} {...m} />)}
          </Card>
        </>
      )}

      {/* PLANO DE AÇÃO */}
      {(plan.d7 || plan.d30 || plan.d90) && (
        <>
          <SectionTitle icon={CalendarClock}>{t('deck.actionPlanTitle')}</SectionTitle>
          <div className="grid gap-3 md:grid-cols-3">
            <PlanColumn title={t('deck.next7Days')} items={plan.d7} color="#EF4444" />
            <PlanColumn title={t('deck.next30Days')} items={plan.d30} color="#F59E0B" />
            <PlanColumn title={t('deck.next90Days')} items={plan.d90} color="#10B981" />
          </div>
        </>
      )}

      {/* PROJEÇÃO */}
      {projection.verdict && (
        <>
          <SectionTitle icon={TrendingUp}>{t('deck.projectionTitle')}</SectionTitle>
          <Card className="p-6">
            <p className="font-display text-lg font-bold text-ink">{projection.verdict}</p>
            {(projection.narrative || []).map((p, i) => (
              <p key={i} className="mt-3 text-sm text-ink-secondary">{p}</p>
            ))}
          </Card>
        </>
      )}

      {/* GROWTH ANGLE */}
      {growth.tactics?.length > 0 && (
        <>
          <SectionTitle icon={Rocket} color="#EC4899">{growth.title || t('deck.growthFallbackTitle')}</SectionTitle>
          {growth.intro && <p className="mb-3 text-sm text-ink-secondary">{growth.intro}</p>}
          <CardList items={growth.tactics} color="#EC4899" />
        </>
      )}
    </>
  )
}
