import {
  CreditCard, Check, Crown, Users2, CalendarClock, Sparkles, Rocket,
  ExternalLink, AlertTriangle, RefreshCw, Zap,
} from 'lucide-react'
import { useBilling, useBillingMutations } from '@/hooks/useData'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { PageLoader } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import { PLAN_META } from '@/lib/constants'
import { brl, date } from '@/lib/formatters'
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

function PlanCard({ plan, current, onChange, pending }) {
  const meta = PLAN_META[plan.key] || { label: plan.name, color: '#7C3AED' }
  const Icon = PLAN_ICON[plan.key] || Sparkles
  const gradient = PLAN_GRADIENT[plan.key] || 'linear-gradient(135deg, #7C3AED, #EC4899)'
  const features = plan.features || []

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
        <div className="flex size-11 items-center justify-center rounded-xl bg-white/20 backdrop-blur">
          <Icon size={22} strokeWidth={2.2} />
        </div>
        <h3 className="mt-3 font-display text-xl font-extrabold">{plan.name || meta.label}</h3>
        <div className="mt-1 flex items-baseline gap-1">
          <span className="font-display text-3xl font-extrabold tracking-tight">{brl(plan.price_cents)}</span>
          <span className="text-sm font-semibold text-white/80">/mês</span>
        </div>
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
              <Zap size={16} /> Mudar para {plan.name || meta.label}
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

export default function BillingIndex() {
  const { data, isLoading } = useBilling()
  const { changePlan, cancel, reactivate } = useBillingMutations()

  if (isLoading) return <PageLoader />

  const sub = data?.subscription || {}
  const plans = data?.plans || []
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
              <h2 className="font-display text-2xl font-extrabold">{meta.label}</h2>
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
      <div className="mb-3 flex items-center gap-2">
        <Sparkles size={18} className="text-brand" />
        <h2 className="font-display text-lg font-bold text-ink">Planos</h2>
      </div>
      {plans.length > 0 && (
        <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
          {plans.map((p) => (
            <PlanCard
              key={p.key}
              plan={p}
              current={p.key === sub.plan}
              onChange={(k) => changePlan.mutate(k)}
              pending={changePlan.isPending}
            />
          ))}
        </div>
      )}

      {/* Actions */}
      <Card className="mt-8">
        <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
          <div>
            <p className="font-display text-base font-bold text-ink">Gerenciar pagamento</p>
            <p className="text-sm text-ink-muted">Atualize forma de pagamento e veja faturas no portal Stripe.</p>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline">
              <ExternalLink size={16} /> Gerenciar no portal
            </Button>
            {!sub.cancel_at && sub.status !== 'canceled' && (
              <Button
                variant="ghost"
                className="text-danger hover:bg-danger/10 hover:text-danger"
                onClick={() => { if (window.confirm('Cancelar a assinatura ao fim do período atual?')) cancel.mutate() }}
                disabled={cancel.isPending}
              >
                Cancelar assinatura
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    </Page>
  )
}
