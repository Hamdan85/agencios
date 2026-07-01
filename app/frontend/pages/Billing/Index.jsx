import {
  CreditCard, Check, Crown, Users2, CalendarClock, Sparkles, Rocket,
  ExternalLink, AlertTriangle, RefreshCw, Zap, Coins, Wallet, Image as ImageIcon,
  Video, GalleryHorizontalEnd, Infinity as InfinityIcon, ArrowUpRight, ArrowDownRight,
} from 'lucide-react'
import { useState } from 'react'
import { useBilling, useBillingMutations, useCredits, useCreditsMutations } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { PageLoader } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import { IntervalToggle } from '@/components/billing/IntervalToggle'
import { ConfirmDialog, useConfirm } from '@/components/ui/confirm-dialog'
import { PLAN_META } from '@/lib/constants'
import { brl, date, dt } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const STATUS_VARIANT = {
  active: 'success', trialing: 'soft', past_due: 'danger',
  canceled: 'muted', incomplete: 'warning',
}
const STATUS_LABEL = {
  active: 'Ativo', trialing: 'Em teste', past_due: 'Pagamento pendente',
  canceled: 'Cancelado', incomplete: 'Incompleto',
}

const PLAN_ICON = { solo: Sparkles, agencia: Rocket, enterprise: Crown }
const PLAN_GRADIENT = {
  solo: 'linear-gradient(135deg, #0EA5E9, #6366F1)',
  agencia: 'linear-gradient(135deg, #7C3AED, #EC4899)',
  enterprise: 'linear-gradient(135deg, #EC4899, #F97316)',
}

function PlanCard({ plan, current, samePlan, subscribed, interval, discountPercent, onChange, pending }) {
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
            Plano atual
          </span>
        </div>
      )}
      <div className="px-5 pt-6 pb-4 text-white" style={{ background: gradient }}>
        <div className="flex items-center justify-between">
          <div className="flex size-11 items-center justify-center rounded-xl bg-white/20 backdrop-blur">
            <Icon size={22} strokeWidth={2.2} />
          </div>
          {annual && discountPercent > 0 && (
            <span className="rounded-full bg-white/20 px-2.5 py-1 text-[11px] font-bold text-white backdrop-blur">
              Economize {discountPercent}%
            </span>
          )}
        </div>
        <h3 className="mt-3 font-display text-xl font-extrabold">{plan.name || meta.label}</h3>
        <div className="mt-1 flex items-baseline gap-1">
          <span className="font-display text-3xl font-extrabold tracking-tight">{brl(displayCents)}</span>
          <span className="text-sm font-semibold text-white/80">/mês</span>
        </div>
        {annual && plan.annual_price_cents != null && (
          <p className="mt-0.5 text-xs font-medium text-white/75">{brl(plan.annual_price_cents)}/ano · cobrado anualmente</p>
        )}
        {plan.seats != null && (
          <p className="mt-1 inline-flex items-center gap-1.5 text-sm font-medium text-white/90">
            <Users2 size={14} /> {plan.seats} {plan.seats === 1 ? 'assento' : 'assentos'}
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
              <Check size={16} /> Seu plano
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
                  ? `Mudar para ${interval === 'year' ? 'anual' : 'mensal'}`
                  : subscribed
                    ? `Mudar para ${plan.name || meta.label}`
                    : `Assinar ${plan.name || meta.label}`
              }
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// The per-action credit cost card (Imagem / Carrossel / Vídeo).
const COST_META = [
  { key: 'image', label: 'Imagem', icon: ImageIcon, color: '#0EA5E9', suffix: 'por imagem' },
  { key: 'carousel', label: 'Carrossel', icon: GalleryHorizontalEnd, color: '#7C3AED', suffix: 'incluso' },
  { key: 'video_standard_15s', label: 'Vídeo 15s', icon: Video, color: '#EC4899', suffix: 'padrão' },
  { key: 'video_photoreal_15s', label: 'Vídeo 15s', icon: Video, color: '#F43F5E', suffix: 'fotorrealista' },
]

function creditLabel(n) {
  if (n === 0) return 'Incluso'
  return `${n} ${n === 1 ? 'crédito' : 'créditos'}`
}

// The prepaid credit wallet: balance, per-action costs, buyable packs and a
// short ledger. Rendered under the plan cards on the billing screen.
function CreditsSection() {
  const { data, isLoading } = useCredits()
  const { checkout } = useCreditsMutations()

  if (isLoading) {
    return <div className="h-40 animate-pulse rounded-2xl border border-border bg-surface-muted/40" />
  }

  const wallet = data?.wallet || {}
  const packs = data?.packs || []
  const costs = data?.costs || {}
  const transactions = data?.transactions || []
  const unlimited = wallet.unlimited || wallet.available == null
  const balance = Number(wallet.available ?? 0)

  return (
    <div className="mt-10">
      <div className="mb-3 flex items-center gap-2">
        <Coins size={18} className="text-amber" />
        <h2 className="font-display text-lg font-bold text-ink">Créditos</h2>
      </div>

      {/* Balance banner */}
      <Card className="mb-5 overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-4 p-6 text-white" style={{ background: 'linear-gradient(135deg, #F59E0B, #EC4899)' }}>
          <div className="flex items-center gap-4">
            <div className="flex size-14 items-center justify-center rounded-2xl bg-white/20 backdrop-blur">
              <Wallet size={28} strokeWidth={2.2} />
            </div>
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-white/80">Saldo disponível</p>
              <p className="font-display text-3xl font-extrabold">
                {unlimited ? <InfinityIcon size={30} className="inline align-[-4px]" /> : balance.toLocaleString('pt-BR')}
                {!unlimited && <span className="ml-1.5 text-base font-semibold text-white/80">créditos</span>}
              </p>
            </div>
          </div>
          {!unlimited && (
            <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm text-white/90">
              <span>Do plano: <strong className="font-extrabold">{Number(wallet.granted ?? 0).toLocaleString('pt-BR')}</strong></span>
              <span>Comprados: <strong className="font-extrabold">{Number(wallet.purchased ?? 0).toLocaleString('pt-BR')}</strong></span>
              {wallet.granted_expires_at && (
                <span className="text-white/75">Créditos do plano expiram em {date(wallet.granted_expires_at)}</span>
              )}
            </div>
          )}
        </div>

        {/* Per-action costs */}
        <CardContent className="grid grid-cols-2 gap-3 p-5 sm:grid-cols-4">
          {COST_META.map((c) => (
            <div key={c.key + c.suffix} className="flex items-center gap-3 rounded-xl border border-border bg-canvas px-3 py-2.5">
              <span className="flex size-9 shrink-0 items-center justify-center rounded-lg" style={{ background: `${c.color}16`, color: c.color }}>
                <c.icon size={17} strokeWidth={2.2} />
              </span>
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
                <span className="font-display text-2xl font-extrabold text-ink">{Number(pack.credits).toLocaleString('pt-BR')}</span>
                <span className="text-xs font-semibold text-ink-muted">créditos</span>
              </p>
              <p className="mt-0.5 text-sm text-ink-muted">{brl(pack.price_cents)}</p>
              <Button
                variant="outline"
                size="sm"
                className="mt-3 w-full"
                onClick={() => checkout.mutate(pack.key)}
                disabled={checkout.isPending}
              >
                <Zap size={14} /> Comprar
              </Button>
            </Card>
          ))}
        </div>
      )}

      {/* Recent ledger */}
      {transactions.length > 0 && (
        <Card>
          <CardContent className="p-0">
            <p className="border-b border-border px-5 py-3 font-display text-sm font-bold text-ink">Movimentações recentes</p>
            <ul className="divide-y divide-border">
              {transactions.slice(0, 8).map((tx) => {
                const positive = Number(tx.amount) >= 0
                return (
                  <li key={tx.id} className="flex items-center justify-between gap-3 px-5 py-2.5">
                    <div className="flex min-w-0 items-center gap-2.5">
                      <span className={cn('flex size-7 shrink-0 items-center justify-center rounded-lg', positive ? 'bg-emerald/12 text-emerald' : 'bg-danger/12 text-danger')}>
                        {positive ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}
                      </span>
                      <div className="min-w-0">
                        <p className="truncate text-sm font-semibold text-ink">{tx.description || (positive ? 'Crédito' : 'Débito')}</p>
                        <p className="text-xs text-ink-muted">{dt(tx.created_at)}</p>
                      </div>
                    </div>
                    <span className={cn('shrink-0 font-display text-sm font-extrabold', positive ? 'text-emerald' : 'text-danger')}>
                      {positive ? '+' : ''}{Number(tx.amount).toLocaleString('pt-BR')}
                    </span>
                  </li>
                )
              })}
            </ul>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

export default function BillingIndex() {
  const { data, isLoading } = useBilling()
  const { data: me } = useCurrentUser()
  const { changePlan, cancel, reactivate, portal } = useBillingMutations()
  const confirm = useConfirm()
  // null until the user manually toggles — so we can default the toggle to the
  // subscription's CURRENT cycle (annual subscribers open on "Anual").
  const [intervalOverride, setInterval] = useState(null)
  const [confirmPlan, setConfirmPlan] = useState(null) // plan pending confirmation

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
        eyebrow="Plano"
        title="Assinatura"
        icon={CreditCard}
        color="#7C3AED"
        description="Gerencie o plano da sua agência no agencios."
      />

      {/* Seat overage banner — a downgrade (in-app or via the Stripe dashboard)
          left more active members than the plan allows. Existing members keep
          access; the backend blocks new tickets/projects until this clears. */}
      {me?.workspace?.over_seat_limit && (
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-danger/30 bg-danger/8 px-5 py-3.5">
          <p className="flex items-center gap-2 text-sm font-semibold text-danger">
            <AlertTriangle size={18} />
            O workspace tem {me.workspace.seat_count} membros, e o plano atual permite até{' '}
            {me.workspace.seat_limit}. Remova membros ou faça upgrade — novos tickets e projetos
            estão bloqueados enquanto isso.
          </p>
        </div>
      )}

      {/* Trial banner */}
      {sub.trialing && (
        <div className="mb-5 flex flex-wrap items-center gap-3 rounded-2xl border border-sky/30 bg-sky/8 px-5 py-3.5">
          <span className="flex size-9 items-center justify-center rounded-xl bg-sky/15 text-sky"><Sparkles size={18} /></span>
          <p className="text-sm font-semibold text-ink">
            Período de teste ativo
            {sub.trial_ends_at && <span className="font-normal text-ink-muted"> — termina em {date(sub.trial_ends_at)}</span>}
          </p>
        </div>
      )}

      {/* Cancellation banner */}
      {sub.cancel_at && (
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-danger/30 bg-danger/8 px-5 py-3.5">
          <p className="flex items-center gap-2 text-sm font-semibold text-danger">
            <AlertTriangle size={18} />
            Assinatura será cancelada em {date(sub.cancel_at)}.
          </p>
          <Button variant="solid" size="sm" onClick={() => reactivate.mutate()} disabled={reactivate.isPending}>
            <RefreshCw size={15} /> Reativar
          </Button>
        </div>
      )}

      {/* Current plan card */}
      <Card className="mb-8 overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-4 p-6 text-white" style={{ background: gradient }}>
          <div className="flex items-center gap-4">
            <div className="flex size-14 items-center justify-center rounded-2xl bg-white/20 backdrop-blur">
              <Icon size={28} strokeWidth={2.2} />
            </div>
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-white/80">Plano atual</p>
              <h2 className="font-display text-2xl font-extrabold">
                {meta.label}
                {subscribed && <span className="text-base font-semibold text-white/70"> · {(sub.interval || 'month') === 'year' ? 'Anual' : 'Mensal'}</span>}
              </h2>
            </div>
          </div>
          <Badge variant={STATUS_VARIANT[sub.status] || 'soft'} className="bg-white/20 text-white">
            {STATUS_LABEL[sub.status] || sub.status || 'Ativo'}
          </Badge>
        </div>
        <CardContent className="grid grid-cols-1 gap-4 p-6 sm:grid-cols-3">
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-indigo/12 text-indigo"><Users2 size={18} /></span>
            <div>
              <p className="text-xs font-bold uppercase tracking-wider text-ink-muted">Assentos</p>
              <p className="font-display text-lg font-extrabold text-ink">
                {sub.seats ?? '—'}{sub.seat_limit ? ` / ${sub.seat_limit}` : ''}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-emerald/12 text-emerald"><CalendarClock size={18} /></span>
            <div>
              <p className="text-xs font-bold uppercase tracking-wider text-ink-muted">Próxima renovação</p>
              <p className="font-display text-lg font-extrabold text-ink">{sub.current_period_end ? date(sub.current_period_end) : '—'}</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-brand-soft text-brand"><Check size={18} /></span>
            <div>
              <p className="text-xs font-bold uppercase tracking-wider text-ink-muted">Acesso</p>
              <p className="font-display text-lg font-extrabold text-ink">{sub.access_granted ? 'Liberado' : 'Restrito'}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Pricing cards */}
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Sparkles size={18} className="text-brand" />
          <h2 className="font-display text-lg font-bold text-ink">Planos</h2>
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

      {/* Credit wallet */}
      <CreditsSection />

      {/* Actions */}
      <Card className="mt-8">
        <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
          <div>
            <p className="font-display text-base font-bold text-ink">Gerenciar pagamento</p>
            <p className="text-sm text-ink-muted">Atualize forma de pagamento e veja faturas no portal Stripe.</p>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline" onClick={() => portal.mutate()} disabled={portal.isPending}>
              <ExternalLink size={16} /> Gerenciar no portal
            </Button>
            {!sub.cancel_at && sub.status !== 'canceled' && (
              <Button
                variant="ghost"
                className="text-danger hover:bg-danger/10 hover:text-danger"
                onClick={async () => {
                  const ok = await confirm({
                    title: 'Cancelar assinatura?',
                    description: 'Sua assinatura continua ativa até o fim do período atual e não será renovada.',
                    confirmLabel: 'Cancelar assinatura',
                    cancelLabel: 'Manter assinatura',
                    destructive: true,
                  })
                  if (ok) cancel.mutate()
                }}
                disabled={cancel.isPending}
              >
                Cancelar assinatura
              </Button>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Plan change / subscribe confirmation */}
      {confirmPlan && (() => {
        const isYear = interval === 'year'
        const cents = isYear
          ? (confirmPlan.annual_monthly_equivalent_cents ?? confirmPlan.price_cents)
          : confirmPlan.price_cents
        const cycle = isYear ? 'anual' : 'mensal'
        const name = confirmPlan.name || PLAN_META[confirmPlan.key]?.label || confirmPlan.key
        const price = `${brl(cents)}/mês${isYear ? ' (cobrado anualmente)' : ''}`
        return (
          <ConfirmDialog
            open
            onOpenChange={(o) => { if (!o) setConfirmPlan(null) }}
            title={subscribed ? 'Confirmar mudança de plano' : 'Confirmar assinatura'}
            description={subscribed
              ? `Mudar para o plano ${name} (${cycle}), ${price}. A diferença é ajustada proporcionalmente na sua próxima fatura (proração).`
              : `Assinar o plano ${name} (${cycle}), ${price}. Você será levado ao pagamento seguro do Stripe.`}
            confirmLabel={subscribed ? 'Confirmar mudança' : 'Ir para o pagamento'}
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
