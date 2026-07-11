import {
  CreditCard, Check, Crown, Users2, CalendarClock, Sparkles, Rocket,
  ExternalLink, AlertTriangle, RefreshCw, Zap, Coins, Wallet, Image as ImageIcon,
  Video, GalleryHorizontalEnd, Infinity as InfinityIcon,
  BarChart3, TrendingUp, Activity, Clock, Info, ChevronLeft, ChevronRight,
} from 'lucide-react'
import { useState } from 'react'
import { useTranslation, Trans } from 'react-i18next'
import i18n from '@/i18n'
import {
  useBilling, useBillingMutations, useCredits, useCreditsMutations, useCreditUsage,
} from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { useParams, useNavigate } from 'react-router-dom'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Badge, ColorBadge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { PageLoader, Skeleton } from '@/components/ui/feedback'
import { IconTile } from '@/components/ui/icon-tile'
import { SectionLabel } from '@/components/ui/section-label'
import { Page } from '@/components/ui/page'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Select, SelectTrigger, SelectContent, SelectItem, SelectValue } from '@/components/ui/select'
import { IntervalToggle } from '@/components/billing/IntervalToggle'
import { ConfirmDialog, useConfirm } from '@/components/ui/confirm-dialog'
import { PLAN_META } from '@/lib/constants'
import { brl, date, dt, num } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const STATUS_VARIANT = {
  active: 'success', trialing: 'soft', past_due: 'danger',
  canceled: 'muted', incomplete: 'warning',
}
// Copy is resolved lazily (getters) so it follows the active locale.
const tr = (key) => i18n.t(`billing:${key}`)
const STATUS_LABEL = {
  get active() { return tr('subscriptionStatus.active') },
  get trialing() { return tr('subscriptionStatus.trialing') },
  get past_due() { return tr('subscriptionStatus.past_due') },
  get canceled() { return tr('subscriptionStatus.canceled') },
  get incomplete() { return tr('subscriptionStatus.incomplete') },
}

const PLAN_ICON = { solo: Sparkles, agencia: Rocket, enterprise: Crown }
const PLAN_GRADIENT = {
  solo: 'linear-gradient(135deg, #0EA5E9, #6366F1)',
  agencia: 'linear-gradient(135deg, #7C3AED, #EC4899)',
  enterprise: 'linear-gradient(135deg, #EC4899, #F97316)',
}

function PlanCard({ plan, current, samePlan, subscribed, interval, discountPercent, onChange, pending }) {
  const { t } = useTranslation('billing')
  const meta = PLAN_META[plan.key] || { label: plan.name, color: '#7C3AED' }
  const Icon = PLAN_ICON[plan.key] || Sparkles
  const gradient = PLAN_GRADIENT[plan.key] || 'linear-gradient(135deg, #7C3AED, #EC4899)'
  const features = plan.features || []
  const annual = interval === 'year'
  const displayCents = annual && plan.annual_monthly_equivalent_cents != null
    ? plan.annual_monthly_equivalent_cents
    : plan.price_cents

  return (
    <Card className={cn(
      'relative flex flex-col overflow-hidden transition-transform',
      current ? 'ring-2 ring-brand' : 'lift',
    )}>
      {current && (
        <div className="absolute right-0 top-0 z-10">
          <span className="inline-block rounded-bl-xl bg-brand px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-white">
            {t('plan.currentBadge')}
          </span>
        </div>
      )}
      <div className="px-5 pt-6 pb-4 text-white" style={{ background: gradient }}>
        <div className="flex items-center justify-between">
          <IconTile icon={Icon} color="#FFFFFF" tint="33" size="sm" className="size-11 backdrop-blur" iconSize={22} />
          {annual && discountPercent > 0 && (
            <ColorBadge color="#FFFFFF" tint="33" className="py-1 text-[11px] backdrop-blur">
              {t('plan.save', { percent: discountPercent })}
            </ColorBadge>
          )}
        </div>
        <h3 className="mt-3 font-display text-xl font-extrabold">{plan.name || meta.label}</h3>
        <div className="mt-1 flex items-baseline gap-1">
          <span className="font-display text-3xl font-extrabold tracking-tight">{brl(displayCents)}</span>
          <span className="text-sm font-semibold text-white/80">{t('plan.perMonth')}</span>
        </div>
        {annual && plan.annual_price_cents != null && (
          <p className="mt-0.5 text-xs font-medium text-white/75">{t('plan.annualBilledYearly', { price: brl(plan.annual_price_cents) })}</p>
        )}
        {plan.seats != null && (
          <p className="mt-1 inline-flex items-center gap-1.5 text-sm font-medium text-white/90">
            <Users2 size={14} /> {t('plan.seats', { count: plan.seats })}
          </p>
        )}
      </div>
      <CardContent className="flex flex-1 flex-col p-5">
        <ul className="flex-1 space-y-2.5">
          {features.map((f, i) => (
            <li key={i} className="flex items-start gap-2 text-sm text-ink-secondary">
              <span className="mt-0.5 flex size-4 shrink-0 items-center justify-center rounded-full" style={{ background: `${meta.color}1A`, color: meta.color }}>
                <Check size={11} strokeWidth={3} />
              </span>
              {f}
            </li>
          ))}
        </ul>
        <div className="mt-5">
          {current ? (
            <Button variant="outline" className="w-full" disabled>
              <Check size={16} /> {t('plan.yours')}
            </Button>
          ) : (
            <Button
              className="w-full text-white"
              style={{ background: gradient }}
              onClick={() => onChange(plan.key)}
              disabled={pending}
            >
              <Zap size={16} /> {
                samePlan
                  ? (interval === 'year' ? t('plan.switchToAnnual') : t('plan.switchToMonthly'))
                  : subscribed
                    ? t('plan.switchTo', { name: plan.name || meta.label })
                    : t('plan.subscribe', { name: plan.name || meta.label })
              }
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// The per-action credit cost card (Imagem / Carrossel / Vídeo). Video is
// cost-based, so its figure is derived server-side (credit_costs.video_15s) — an
// estimate for a 15s clip, shown as "a partir de".
const COST_META = [
  { key: 'image', get label() { return i18n.t('common:generationKind.image') }, icon: ImageIcon, color: '#0EA5E9', get suffix() { return tr('costs.perImage') } },
  { key: 'carousel', get label() { return i18n.t('common:generationKind.carousel') }, icon: GalleryHorizontalEnd, color: '#7C3AED', get suffix() { return tr('costs.perCarousel') } },
  { key: 'video_15s', get label() { return tr('costs.video15s') }, icon: Video, color: '#EC4899', get suffix() { return tr('costs.from15s') } },
]

function creditLabel(n) {
  if (n === 0) return tr('credits.included')
  return i18n.t('billing:credits.count', { count: n })
}

// The prepaid credit wallet: balance, per-action costs, buyable packs and a
// short ledger. Rendered under the plan cards on the billing screen.
function CreditsSection() {
  const { t } = useTranslation('billing')
  const { data, isLoading } = useCredits()
  const { checkout } = useCreditsMutations()

  if (isLoading) {
    return <Skeleton className="h-40 rounded-2xl border border-border bg-surface-muted/40" />
  }

  const wallet = data?.wallet || {}
  const packs = data?.packs || []
  const costs = data?.costs || {}
  const unlimited = wallet.unlimited || wallet.available == null
  const balance = Number(wallet.available ?? 0)

  return (
    <div className="mt-10">
      <div className="mb-3 flex items-center gap-2">
        <Coins size={18} className="text-amber" />
        <h2 className="font-display text-lg font-bold text-ink">{t('credits.title')}</h2>
      </div>

      {/* Balance banner */}
      <Card className="mb-5 overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-4 p-6 text-white" style={{ background: 'linear-gradient(135deg, #F59E0B, #EC4899)' }}>
          <div className="flex items-center gap-4">
            <IconTile icon={Wallet} color="#FFFFFF" tint="33" className="size-14 backdrop-blur" iconSize={28} />
            <div>
              <SectionLabel className="text-white/80">{t('credits.balance')}</SectionLabel>
              <p className="font-display text-3xl font-extrabold">
                {unlimited ? <InfinityIcon size={30} className="inline align-[-4px]" /> : num(balance)}
                {!unlimited && <span className="ml-1.5 text-base font-semibold text-white/80">{t('credits.unit')}</span>}
              </p>
            </div>
          </div>
          {!unlimited && (
            <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm text-white/90">
              <span>{t('credits.fromPlan')} <strong className="font-extrabold">{num(wallet.granted)}</strong></span>
              <span>{t('credits.purchased')} <strong className="font-extrabold">{num(wallet.purchased)}</strong></span>
              {wallet.granted_expires_at && (
                <span className="text-white/75">{t('credits.expiresOn', { date: date(wallet.granted_expires_at) })}</span>
              )}
            </div>
          )}
        </div>

        {/* Per-action costs */}
        <CardContent className="grid grid-cols-1 gap-2.5 p-4 sm:grid-cols-2 sm:gap-3 sm:p-5 lg:grid-cols-4">
          {COST_META.map((c) => (
            <div key={c.key + c.suffix} className="flex items-center gap-3 rounded-xl border border-border bg-canvas px-3 py-2.5">
              <IconTile icon={c.icon} color={c.color} size="xs" className="size-9" iconSize={17} />
              <div className="min-w-0">
                <p className="truncate text-xs font-bold text-ink">{c.label} <span className="font-medium text-ink-muted">· {c.suffix}</span></p>
                <p className="font-display text-sm font-extrabold text-ink">{creditLabel(Number(costs[c.key] ?? 0))}</p>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Buyable packs */}
      {!unlimited && packs.length > 0 && (
        <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {packs.map((pack) => (
            <Card key={pack.key} className="flex flex-col p-4 lift">
              <p className="font-display text-sm font-bold text-ink">{pack.name}</p>
              <p className="mt-1 flex items-baseline gap-1">
                <span className="font-display text-2xl font-extrabold text-ink">{num(pack.credits)}</span>
                <span className="text-xs font-semibold text-ink-muted">{t('credits.unit')}</span>
              </p>
              <p className="mt-0.5 text-sm text-ink-muted">{brl(pack.price_cents)}</p>
              <Button
                variant="outline"
                size="sm"
                className="mt-3 w-full"
                onClick={() => checkout.mutate(pack.key)}
                disabled={checkout.isPending}
              >
                <Zap size={14} /> {t('credits.buy')}
              </Button>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}

// ── Usage tab ────────────────────────────────────────────────────
// What the workspace spent credits on. Vídeo, Imagem, and Carrossel all consume
// credits (carousel cost is admin-tunable, default 1).
const KIND_META = {
  video: { get label() { return i18n.t('common:generationKind.video') }, icon: Video, color: '#EC4899' },
  image: { get label() { return i18n.t('common:generationKind.image') }, icon: ImageIcon, color: '#0EA5E9' },
  carousel: { get label() { return i18n.t('common:generationKind.carousel') }, icon: GalleryHorizontalEnd, color: '#7C3AED' },
}
const GEN_STATUS = {
  queued: { get label() { return tr('generationStatus.queued') }, className: 'bg-ink/8 text-ink-muted' },
  processing: { get label() { return tr('generationStatus.processing') }, className: 'bg-sky/12 text-sky' },
  completed: { get label() { return tr('generationStatus.completed') }, className: 'bg-emerald/12 text-emerald' },
  failed: { get label() { return tr('generationStatus.failed') }, className: 'bg-danger/12 text-danger' },
}
const USAGE_RANGES = [
  { key: '7d', get label() { return tr('usage.ranges.7d') } },
  { key: '30d', get label() { return tr('usage.ranges.30d') } },
  { key: '90d', get label() { return tr('usage.ranges.90d') } },
  { key: '12m', get label() { return tr('usage.ranges.12m') } },
]

function chartLabel(iso, granularity) {
  const d = new Date(iso)
  if (granularity === 'month') return d.toLocaleDateString(i18n.language, { month: 'short' })
  return d.toLocaleDateString(i18n.language, { day: '2-digit', month: '2-digit' })
}

// The trend chart plots on a normalized 100×100 viewBox stretched to the card
// (preserveAspectRatio="none"); strokes stay crisp via vector-effect. Yellow is
// the total; each creative type gets its own KIND_META color.
const TOTAL_COLOR = '#F59E0B'
function linePath(values, max) {
  const n = values.length
  if (n === 0) return ''
  return values
    .map((v, i) => {
      const x = n === 1 ? 50 : (i / (n - 1)) * 100
      // Map into [4, 100] so the peak line isn't clipped by the top edge.
      const y = 4 + (1 - Math.max(0, Number(v) || 0) / max) * 96
      return `${i === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`
    })
    .join(' ')
}

function UsageStat({ icon: Icon, label, value, sub, color }) {
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-border bg-canvas px-4 py-3.5">
      <IconTile icon={Icon} color={color} size="sm" className="size-11" iconSize={20} />
      <div className="min-w-0">
        <SectionLabel className="tracking-wider">{label}</SectionLabel>
        <p className="font-display text-xl font-extrabold leading-tight text-ink">{value}</p>
        {sub && <p className="truncate text-xs text-ink-muted">{sub}</p>}
      </div>
    </div>
  )
}

const KIND_FILTERS = [
  { key: 'all', get label() { return tr('usage.filters.allKinds') } },
  { key: 'video', get label() { return i18n.t('common:generationKind.video') } },
  { key: 'image', get label() { return i18n.t('common:generationKind.image') } },
  { key: 'carousel', get label() { return i18n.t('common:generationKind.carousel') } },
]
const STATUS_FILTERS = [
  { key: 'all', get label() { return tr('usage.filters.allStatuses') } },
  { key: 'completed', get label() { return tr('generationStatus.completed') } },
  { key: 'processing', get label() { return tr('generationStatus.processing') } },
  { key: 'queued', get label() { return tr('generationStatus.queued') } },
  { key: 'failed', get label() { return tr('generationStatus.failed') } },
]

function UsageSection() {
  const { t } = useTranslation('billing')
  const [range, setRange] = useState('30d')
  const [kind, setKind] = useState('all')
  const [status, setStatus] = useState('all')
  const [page, setPage] = useState(1)
  // null = auto (credits when the period spent any, else generation activity).
  const [metricOverride, setMetricOverride] = useState(null)

  // The time range drives the whole tab; kind/status/page scope the log below.
  const params = {
    range,
    page,
    ...(kind !== 'all' && { kind }),
    ...(status !== 'all' && { status }),
  }
  const { data, isLoading, isFetching } = useCreditUsage(params)

  const totals = data?.totals || {}
  const byKind = data?.by_kind || []
  const series = data?.series || []
  const recent = data?.recent?.items || []
  const meta = data?.recent?.meta || {}
  const granularity = data?.granularity || 'day'

  const spent = Number(totals.spent ?? 0)
  const totalKindCredits = byKind.reduce((s, k) => s + Number(k.credits || 0), 0)
  const hasActivity = Number(totals.generations ?? 0) > 0

  // The trend plots real credit spend, but auto-falls back to generation
  // activity when the period spent 0 credits (only free carousels, or a
  // godfathered workspace) — so the card is never blank. The user can switch.
  const seriesCredits = series.reduce((s, p) => s + Number(p.credits || 0), 0)
  const metric = metricOverride ?? (seriesCredits > 0 ? 'credits' : 'generations')
  // The selected metric can be all-zero (e.g. "Créditos" on a period that only
  // ran free carousels) — bars would render at 1px and read as a blank card, so
  // show an explicit empty state for that metric instead.
  const metricTotal = series.reduce((s, p) => s + Number(p[metric] || 0), 0)

  // One line per creative type (its own color) plus the yellow total envelope.
  // The total is the y-scale max since it dominates every per-kind line.
  const totalValues = series.map((s) => Number(s[metric] || 0))
  const chartMax = Math.max(1, ...totalValues)
  const chartLines = [
    { key: 'total', label: t('usage.chart.total'), color: TOTAL_COLOR, width: 2.25, values: totalValues },
    ...['video', 'image', 'carousel'].map((k) => ({
      key: k,
      label: KIND_META[k]?.label || k,
      color: KIND_META[k]?.color || '#7C3AED',
      width: 1.5,
      values: series.map((s) => Number(s.by_kind?.[k]?.[metric] || 0)),
    })),
  ]

  // Range / filter changes reset paging.
  const changeRange = (r) => { setRange(r); setPage(1) }
  const changeKind = (k) => { setKind(k); setPage(1) }
  const changeStatus = (s) => { setStatus(s); setPage(1) }

  const total = Number(meta.total ?? recent.length)
  const per = Number(meta.per ?? 20)
  const from = total === 0 ? 0 : (page - 1) * per + 1
  const to = Math.min(page * per, total)
  const filtered = kind !== 'all' || status !== 'all'

  return (
    <div>
      {/* Time range — the page-wide filter for every card below. */}
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <BarChart3 size={18} className="text-brand" />
          <h2 className="font-display text-lg font-bold text-ink">{t('usage.title')}</h2>
        </div>
        <div className="inline-flex items-center gap-1 rounded-xl bg-surface-muted p-1">
          {USAGE_RANGES.map((r) => (
            <button
              key={r.key}
              type="button"
              onClick={() => changeRange(r.key)}
              className={cn(
                'rounded-lg px-3 py-1.5 text-sm font-semibold transition-all',
                range === r.key ? 'bg-surface text-ink shadow-sm' : 'text-ink-muted hover:text-ink',
              )}
            >
              {r.label}
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <Skeleton className="h-64 rounded-2xl border border-border bg-surface-muted/40" />
      ) : (
        <>
          {/* Model explainer — the source of truth, spelled out for the user */}
          <div className="mb-5 flex items-start gap-2.5 rounded-2xl border border-sky/25 bg-sky/6 px-4 py-3">
            <Info size={16} className="mt-0.5 shrink-0 text-sky" />
            <p className="text-sm text-ink-secondary">
              <Trans t={t} i18nKey="usage.explainer" components={{ b: <strong className="font-semibold text-ink" /> }} />
            </p>
          </div>

          {/* Summary stats */}
          <div className="mb-5 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <UsageStat
              icon={Coins}
              color="#F59E0B"
              label={t('usage.spent')}
              value={num(spent)}
              sub={t('usage.inPeriod')}
            />
            <UsageStat
              icon={Activity}
              color="#7C3AED"
              label={t('usage.generations')}
              value={num(totals.generations)}
              sub={t('usage.generationsSub')}
            />
            <UsageStat
              icon={TrendingUp}
              color="#10B981"
              label={t('usage.added')}
              value={num(Number(totals.granted_added ?? 0) + Number(totals.purchased_added ?? 0))}
              sub={t('usage.addedSub', { granted: num(totals.granted_added), purchased: num(totals.purchased_added) })}
            />
          </div>

          {!hasActivity ? (
            <Card>
              <CardContent className="flex flex-col items-center justify-center gap-2 py-14 text-center">
                <span className="flex size-12 items-center justify-center rounded-2xl bg-surface-muted text-ink-muted">
                  <BarChart3 size={24} />
                </span>
                <p className="font-display text-base font-bold text-ink">{t('usage.empty.title')}</p>
                <p className="max-w-sm text-sm text-ink-muted">
                  {t('usage.empty.description')}
                </p>
              </CardContent>
            </Card>
          ) : (
            <div className="grid grid-cols-1 gap-5 lg:grid-cols-5">
              {/* Breakdown by kind */}
              <Card className="lg:col-span-2">
                <CardContent className="p-5">
                  <p className="mb-4 font-display text-sm font-bold text-ink">{t('usage.byKind')}</p>
                  <div className="space-y-4">
                    {byKind.map((k) => {
                      const meta = KIND_META[k.kind] || { label: k.kind, icon: Sparkles, color: '#7C3AED' }
                      const credits = Number(k.credits || 0)
                      const pct = totalKindCredits > 0 ? Math.round((credits / totalKindCredits) * 100) : 0
                      const free = credits === 0
                      return (
                        <div key={k.kind}>
                          <div className="mb-1.5 flex items-center justify-between gap-2">
                            <span className="flex items-center gap-2 text-sm font-semibold text-ink">
                              <span className="flex size-7 items-center justify-center rounded-lg" style={{ background: `${meta.color}16`, color: meta.color }}>
                                <meta.icon size={15} strokeWidth={2.2} />
                              </span>
                              {meta.label}
                              <span className="text-xs font-medium text-ink-muted">· {t('usage.generationCount', { count: Number(k.count || 0) })}</span>
                            </span>
                            <span className="shrink-0 font-display text-sm font-extrabold" style={{ color: free ? undefined : meta.color }}>
                              {free ? <span className="text-emerald">{t('credits.included')}</span> : t('usage.creditsShort', { value: num(credits) })}
                            </span>
                          </div>
                          <div className="h-2 overflow-hidden rounded-full bg-surface-muted">
                            <div
                              className="h-full rounded-full transition-all"
                              style={{ width: `${free ? 100 : Math.max(pct, 3)}%`, background: free ? 'var(--color-emerald, #10B981)' : meta.color, opacity: free ? 0.35 : 1 }}
                            />
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </CardContent>
              </Card>

              {/* Spend / activity trend */}
              <Card className="lg:col-span-3">
                <CardContent className="p-5">
                  <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
                    <p className="font-display text-sm font-bold text-ink">
                      {metric === 'credits' ? t('usage.chart.creditsOverTime') : t('usage.chart.generationsOverTime')}
                    </p>
                    <div className="inline-flex items-center gap-0.5 rounded-lg bg-surface-muted p-0.5">
                      {[['credits', t('credits.title')], ['generations', t('usage.generations')]].map(([k, l]) => (
                        <button
                          key={k}
                          type="button"
                          onClick={() => setMetricOverride(k)}
                          className={cn(
                            'rounded-md px-2.5 py-1 text-xs font-semibold transition-all',
                            metric === k ? 'bg-surface text-ink shadow-sm' : 'text-ink-muted hover:text-ink',
                          )}
                        >
                          {l}
                        </button>
                      ))}
                    </div>
                  </div>
                  {series.length === 0 || metricTotal === 0 ? (
                    <p className="py-16 text-center text-sm text-ink-muted">
                      {metric === 'credits' ? t('usage.chart.emptyCredits') : t('usage.chart.emptyGenerations')}
                    </p>
                  ) : (
                    <>
                      <div className="relative h-44 w-full overflow-hidden rounded-xl bg-surface-muted/30">
                        <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="h-full w-full">
                          {chartLines.map((line) => (
                            <path
                              key={line.key}
                              d={linePath(line.values, chartMax)}
                              fill="none"
                              stroke={line.color}
                              strokeWidth={line.width}
                              strokeLinejoin="round"
                              strokeLinecap="round"
                              vectorEffect="non-scaling-stroke"
                              opacity={line.key === 'total' ? 1 : 0.85}
                            />
                          ))}
                          {/* Transparent hit columns give a hover tooltip per bucket. */}
                          {series.map((s, i) => {
                            const w = 100 / series.length
                            const unit = metric === 'credits' ? t('usage.chart.unitCredits') : t('usage.chart.unitGenerations')
                            const tip = t('usage.chart.tooltip', { date: chartLabel(s.date, granularity), total: Number(s[metric] || 0), unit })
                              + ['video', 'image', 'carousel']
                                .map((k) => t('usage.chart.tooltipKind', { label: KIND_META[k]?.label, value: Number(s.by_kind?.[k]?.[metric] || 0) }))
                                .join('')
                            return (
                              <rect key={s.date} x={i * w} y="0" width={w} height="100" fill="transparent">
                                <title>{tip}</title>
                              </rect>
                            )
                          })}
                        </svg>
                      </div>
                      <div className="mt-2 flex justify-between text-[10px] font-medium text-ink-muted">
                        <span>{chartLabel(series[0].date, granularity)}</span>
                        <span>{chartLabel(series[series.length - 1].date, granularity)}</span>
                      </div>
                      {/* Legend — yellow total + one swatch per creative type. */}
                      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1.5">
                        {chartLines.map((line) => (
                          <span key={line.key} className="flex items-center gap-1.5 text-xs font-semibold text-ink-secondary">
                            <span className="h-0.5 w-4 rounded-full" style={{ background: line.color }} />
                            {line.label}
                          </span>
                        ))}
                      </div>
                    </>
                  )}
                </CardContent>
              </Card>
            </div>
          )}

          {/* Recent generations — the full, filterable, paged log */}
          {hasActivity && (
            <Card className="mt-5">
              <CardContent className="p-0">
                <div className="flex flex-wrap items-center gap-2 border-b border-border px-5 py-3">
                  <p className="mr-auto flex items-center gap-2 font-display text-sm font-bold text-ink">
                    <Clock size={15} className="text-ink-muted" /> {t('usage.recent.title')}
                    {total > 0 && <span className="text-xs font-medium text-ink-muted">· {num(total)}</span>}
                  </p>
                  <Select value={kind} onValueChange={changeKind}>
                    <SelectTrigger className="h-9 w-auto min-w-32.5"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {KIND_FILTERS.map((f) => <SelectItem key={f.key} value={f.key}>{f.label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Select value={status} onValueChange={changeStatus}>
                    <SelectTrigger className="h-9 w-auto min-w-32.5"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {STATUS_FILTERS.map((f) => <SelectItem key={f.key} value={f.key}>{f.label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>

                {recent.length === 0 ? (
                  <div className="px-5 py-12 text-center text-sm text-ink-muted">
                    {filtered ? t('usage.recent.emptyFiltered') : t('usage.chart.emptyGenerations')}
                  </div>
                ) : (
                  <ul className={cn('max-h-112 divide-y divide-border overflow-y-auto transition-opacity', isFetching && 'opacity-60')}>
                    {recent.map((g) => {
                      const km = KIND_META[g.kind] || { label: g.kind, icon: Sparkles, color: '#7C3AED' }
                      const st = GEN_STATUS[g.status] || { label: g.status, className: 'bg-ink/8 text-ink-muted' }
                      const credits = Number(g.credits || 0)
                      return (
                        <li key={g.id} className="flex items-center justify-between gap-3 px-5 py-2.5">
                          <div className="flex min-w-0 items-center gap-2.5">
                            <IconTile icon={km.icon} color={km.color} size="xs" />
                            <div className="min-w-0">
                              <p className="flex items-center gap-2 text-sm font-semibold text-ink">
                                {km.label}
                                <span className={cn('rounded-md px-1.5 py-0.5 text-[10px] font-bold', st.className)}>{st.label}</span>
                              </p>
                              <p className="text-xs text-ink-muted">{dt(g.created_at)}{g.provider ? ` · ${g.provider}` : ''}</p>
                            </div>
                          </div>
                          <span className={cn('shrink-0 font-display text-sm font-extrabold', credits > 0 ? 'text-ink' : 'text-emerald')}>
                            {credits > 0 ? t('usage.creditsShort', { value: num(credits) }) : t('credits.included')}
                          </span>
                        </li>
                      )
                    })}
                  </ul>
                )}

                {total > per && (
                  <div className="flex items-center justify-between gap-3 border-t border-border px-5 py-3">
                    <p className="text-xs text-ink-muted">{t('usage.recent.pageInfo', { from, to, total: num(total) })}</p>
                    <div className="flex items-center gap-1.5">
                      <Button variant="outline" size="sm" disabled={page <= 1 || isFetching} onClick={() => setPage((p) => Math.max(1, p - 1))}>
                        <ChevronLeft size={15} /> {t('usage.recent.prev')}
                      </Button>
                      <Button variant="outline" size="sm" disabled={!meta.has_more || isFetching} onClick={() => setPage((p) => p + 1)}>
                        {t('usage.recent.next')} <ChevronRight size={15} />
                      </Button>
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          )}
        </>
      )}
    </div>
  )
}

// Each tab is its own URL (Portuguese segment); "plano" is the base path.
const TAB_TO_SEG = { plano: '', uso: 'uso' }
const SEG_TO_TAB = { uso: 'uso' }

export default function BillingIndex() {
  const { t } = useTranslation('billing')
  const { data, isLoading } = useBilling()
  const { data: me } = useCurrentUser()
  const { changePlan, cancel, reactivate, portal } = useBillingMutations()
  const confirm = useConfirm()
  // null until the user manually toggles — so we can default the toggle to the
  // subscription's CURRENT cycle (annual subscribers open on "Anual").
  const [intervalOverride, setInterval] = useState(null)
  const [confirmPlan, setConfirmPlan] = useState(null) // plan pending confirmation
  // Each tab is its own URL (Portuguese segment); "plano" is the base path.
  const { tab: seg } = useParams()
  const navigate = useNavigate()
  const tab = SEG_TO_TAB[seg] || 'plano'
  const setTab = (value) => {
    const s = TAB_TO_SEG[value] || ''
    navigate(`/assinatura${s ? `/${s}` : ''}`, { replace: true })
  }

  if (isLoading) return <PageLoader />

  const sub = data?.subscription || {}
  const plans = data?.plans || []
  const discountPercent = data?.annual_discount_percent || 0
  const interval = intervalOverride ?? (sub.interval || 'month')
  // A workspace is "subscribed" once it has a live Stripe subscription (any
  // status other than `incomplete`). Until then, plan buttons subscribe (start
  // checkout) rather than swap plans.
  const subscribed = !!sub.id && sub.status !== 'incomplete'
  const meta = PLAN_META[sub.plan] || { label: sub.plan || '—', color: '#7C3AED' }
  const Icon = PLAN_ICON[sub.plan] || Sparkles
  const gradient = PLAN_GRADIENT[sub.plan] || 'linear-gradient(135deg, #7C3AED, #EC4899)'

  return (
    <Page>
      <PageHeader
        eyebrow={t('page.eyebrow')}
        title={t('page.title')}
        icon={CreditCard}
        color="#7C3AED"
        description={t('page.description')}
      />

      {/* Seat overage banner — a downgrade (in-app or via the Stripe dashboard)
          left more active members than the plan allows. Existing members keep
          access; the backend blocks new tickets/projects until this clears. */}
      {me?.workspace?.over_seat_limit && (
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-danger/30 bg-danger/8 px-5 py-3.5">
          <p className="flex items-center gap-2 text-sm font-semibold text-danger">
            <AlertTriangle size={18} />
            {t('seatOverage', { count: me.workspace.seat_count, limit: me.workspace.seat_limit })}
          </p>
        </div>
      )}

      {/* Trial banner */}
      {sub.trialing && (
        <div className="mb-5 flex flex-wrap items-center gap-3 rounded-2xl border border-sky/30 bg-sky/8 px-5 py-3.5">
          <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-sky/15 text-sky"><Sparkles size={18} /></span>
          <div className="min-w-0">
            <p className="text-sm font-semibold text-ink">
              {t('trial.active')}
              {sub.trial_ends_at && <span className="font-normal text-ink-muted"> {t('trial.endsOn', { date: date(sub.trial_ends_at) })}</span>}
            </p>
            <p className="mt-0.5 text-[13px] leading-snug text-ink-muted">
              {t('trial.description')}
            </p>
          </div>
        </div>
      )}

      {/* Cancellation banner */}
      {sub.cancel_at && (
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-danger/30 bg-danger/8 px-5 py-3.5">
          <p className="flex items-center gap-2 text-sm font-semibold text-danger">
            <AlertTriangle size={18} />
            {t('cancelBanner.message', { date: date(sub.cancel_at) })}
          </p>
          <Button variant="solid" size="sm" onClick={() => reactivate.mutate()} disabled={reactivate.isPending}>
            <RefreshCw size={15} /> {t('cancelBanner.reactivate')}
          </Button>
        </div>
      )}

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="mb-6">
          <TabsTrigger value="plano"><CreditCard size={15} /> {t('tabs.plan')}</TabsTrigger>
          <TabsTrigger value="uso"><BarChart3 size={15} /> {t('tabs.usage')}</TabsTrigger>
        </TabsList>

        <TabsContent value="plano">
      {/* Current plan card */}
      <Card className="mb-8 overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-4 p-6 text-white" style={{ background: gradient }}>
          <div className="flex items-center gap-4">
            <IconTile icon={Icon} color="#FFFFFF" tint="33" className="size-14 backdrop-blur" iconSize={28} />
            <div>
              <SectionLabel className="text-white/80">{t('plan.currentBadge')}</SectionLabel>
              <h2 className="font-display text-2xl font-extrabold">
                {meta.label}
                {subscribed && <span className="text-base font-semibold text-white/70"> · {(sub.interval || 'month') === 'year' ? t('plan.annual') : t('plan.monthly')}</span>}
              </h2>
            </div>
          </div>
          <Badge variant={STATUS_VARIANT[sub.status] || 'soft'} className="bg-white/20 text-white">
            {STATUS_LABEL[sub.status] || sub.status || t('subscriptionStatus.active')}
          </Badge>
        </div>
        <CardContent className="grid grid-cols-1 gap-4 p-6 sm:grid-cols-3">
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-indigo/12 text-indigo"><Users2 size={18} /></span>
            <div>
              <SectionLabel className="text-xs tracking-wider">{t('currentPlan.seats')}</SectionLabel>
              <p className="font-display text-lg font-extrabold text-ink">
                {sub.seats ?? '—'}{sub.seat_limit ? ` / ${sub.seat_limit}` : ''}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-emerald/12 text-emerald"><CalendarClock size={18} /></span>
            <div>
              <SectionLabel className="text-xs tracking-wider">{t('currentPlan.nextRenewal')}</SectionLabel>
              <p className="font-display text-lg font-extrabold text-ink">{sub.current_period_end ? date(sub.current_period_end) : '—'}</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-brand-soft text-brand"><Check size={18} /></span>
            <div>
              <SectionLabel className="text-xs tracking-wider">{t('currentPlan.access')}</SectionLabel>
              <p className="font-display text-lg font-extrabold text-ink">{sub.access_granted ? t('currentPlan.granted') : t('currentPlan.restricted')}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Credit wallet — an active subscriber cares about their balance first,
          so it leads; a prospect still choosing a plan sees Planos first. */}
      {subscribed && <CreditsSection />}

      {/* Pricing cards */}
      <div className={cn('mb-3 flex flex-wrap items-center justify-between gap-3', subscribed && 'mt-10')}>
        <div className="flex items-center gap-2">
          <Sparkles size={18} className="text-brand" />
          <h2 className="font-display text-lg font-bold text-ink">{t('plans.title')}</h2>
        </div>
        {discountPercent > 0 && (
          <IntervalToggle value={interval} onChange={setInterval} discountPercent={discountPercent} />
        )}
      </div>
      {plans.length > 0 && (
        <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
          {plans.map((p) => (
            <PlanCard
              key={p.key}
              plan={p}
              // "Current" only when BOTH the plan and the billing cycle match, so
              // toggling Anual on your monthly plan offers the switch.
              current={subscribed && p.key === sub.plan && interval === (sub.interval || 'month')}
              samePlan={subscribed && p.key === sub.plan}
              subscribed={subscribed}
              interval={interval}
              discountPercent={discountPercent}
              onChange={() => setConfirmPlan(p)}
              pending={changePlan.isPending}
            />
          ))}
        </div>
      )}

      {!subscribed && <CreditsSection />}

      {/* Actions */}
      <Card className="mt-8">
        <CardContent className="flex flex-col gap-4 p-5 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="font-display text-base font-bold text-ink">{t('manage.title')}</p>
            <p className="text-sm text-ink-muted">{t('manage.description')}</p>
          </div>
          <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
            <Button variant="outline" className="w-full sm:w-auto" onClick={() => portal.mutate()} disabled={portal.isPending}>
              <ExternalLink size={16} /> {t('manage.portal')}
            </Button>
            {!sub.cancel_at && sub.status !== 'canceled' && (
              <Button
                variant="ghost"
                className="w-full text-danger hover:bg-danger/10 hover:text-danger sm:w-auto"
                onClick={async () => {
                  const ok = await confirm({
                    title: t('manage.confirmCancel.title'),
                    description: t('manage.confirmCancel.description'),
                    confirmLabel: t('manage.cancel'),
                    cancelLabel: t('manage.confirmCancel.keep'),
                    destructive: true,
                  })
                  if (ok) cancel.mutate()
                }}
                disabled={cancel.isPending}
              >
                {t('manage.cancel')}
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
        </TabsContent>

        <TabsContent value="uso">
          <UsageSection />
        </TabsContent>
      </Tabs>

      {/* Plan change / subscribe confirmation */}
      {confirmPlan && (() => {
        const isYear = interval === 'year'
        const cents = isYear
          ? (confirmPlan.annual_monthly_equivalent_cents ?? confirmPlan.price_cents)
          : confirmPlan.price_cents
        const cycle = isYear ? t('plan.cycleAnnual') : t('plan.cycleMonthly')
        const name = confirmPlan.name || PLAN_META[confirmPlan.key]?.label || confirmPlan.key
        const price = isYear ? t('confirmChange.priceAnnual', { price: brl(cents) }) : t('confirmChange.priceMonthly', { price: brl(cents) })
        return (
          <ConfirmDialog
            open
            onOpenChange={(o) => { if (!o) setConfirmPlan(null) }}
            title={subscribed ? t('confirmChange.titleChange') : t('confirmChange.titleSubscribe')}
            description={subscribed
              ? t('confirmChange.descriptionChange', { name, cycle, price })
              : t('confirmChange.descriptionSubscribe', { name, cycle, price })}
            confirmLabel={subscribed ? t('confirmChange.confirm') : t('confirmChange.goToPayment')}
            icon={Zap}
            tone="#7C3AED"
            loading={changePlan.isPending}
            onConfirm={() => { changePlan.mutate({ plan: confirmPlan.key, interval }); setConfirmPlan(null) }}
          />
        )
      })()}
    </Page>
  )
}
