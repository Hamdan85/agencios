import { useMemo, useState } from 'react'
import {
  Check, Crown, Users2, Sparkles, Rocket, Zap, ShieldCheck, Coins, LogOut, Settings,
} from 'lucide-react'
import { Link } from 'react-router-dom'
import { useBilling, useBillingMutations } from '@/hooks/useData'
import { useCurrentUser, useLogout } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { PageLoader } from '@/components/ui/feedback'
import { BrandMark } from '@/components/brand/BrandMark'
import { IntervalToggle } from '@/components/billing/IntervalToggle'
import { PLAN_META } from '@/lib/constants'
import { brl } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const PLAN_ICON = { solo: Sparkles, agencia: Rocket, enterprise: Crown }
const PLAN_GRADIENT = {
  solo: 'linear-gradient(135deg, #0EA5E9, #6366F1)',
  agencia: 'linear-gradient(135deg, #7C3AED, #EC4899)',
  enterprise: 'linear-gradient(135deg, #EC4899, #F97316)',
}

function PaywallPlan({ plan, highlight, interval, discountPercent, onSubscribe, pending }) {
  const meta = PLAN_META[plan.key] || { label: plan.name, color: '#7C3AED' }
  const Icon = PLAN_ICON[plan.key] || Sparkles
  const gradient = PLAN_GRADIENT[plan.key] || 'linear-gradient(135deg, #7C3AED, #EC4899)'
  const features = plan.features || []
  const annual = interval === 'year'
  // Annual: headline the monthly-equivalent price + the full yearly amount as a caption.
  const displayCents = annual && plan.annual_monthly_equivalent_cents != null
    ? plan.annual_monthly_equivalent_cents
    : plan.price_cents

  return (
    <Card className={cn('relative flex flex-col overflow-hidden', highlight ? 'ring-2 ring-brand' : 'lift')}>
      {highlight && (
        <div className="absolute right-0 top-0 z-10">
          <span className="inline-block rounded-bl-xl bg-brand px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-white">
            Mais popular
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
        <div className="mt-2 flex flex-wrap items-center gap-1.5 text-sm font-medium text-white/90">
          {plan.seats != null && (
            <span className="inline-flex items-center gap-1.5">
              <Users2 size={14} /> {plan.seats} {plan.seats === 1 ? 'assento' : 'assentos'}
            </span>
          )}
          {plan.included_credits != null && (
            <span className="inline-flex items-center gap-1.5">
              <Coins size={14} /> {plan.included_credits} créditos/mês
            </span>
          )}
        </div>
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
        <Button
          className="mt-5 w-full text-white"
          style={{ background: gradient }}
          onClick={() => onSubscribe(plan.key)}
          disabled={pending}
        >
          <Zap size={16} /> Assinar {plan.name || meta.label}
        </Button>
        {annual && (
          <p className="mt-2 text-center text-xs text-ink-muted">Cobrado uma vez por ano</p>
        )}
      </CardContent>
    </Card>
  )
}

// The total paywall: shown by the app shell whenever the workspace is not
// billing-active. Presents the plans and starts a card-required 7-day trial via
// Stripe Checkout. Everything else in the app is blocked behind this — only
// /assinatura, /configuracoes and logout stay reachable.
export default function Paywall() {
  const { data, isLoading } = useBilling()
  const { checkout } = useBillingMutations()
  const { data: me } = useCurrentUser()
  const logout = useLogout()

  const [interval, setInterval] = useState('month')

  const plans = data?.plans || []
  const trialDays = 7
  const discountPercent = data?.annual_discount_percent || 0

  const highlightKey = useMemo(() => {
    if (plans.some((p) => p.key === 'agencia')) return 'agencia'
    return plans[1]?.key || plans[0]?.key
  }, [plans])

  if (isLoading) return <PageLoader />

  return (
    <div className="min-h-dvh overflow-y-auto canvas-texture">
      {/* Slim top bar — brand + escape hatches (settings / logout) */}
      <header className="flex items-center justify-between px-5 py-4 sm:px-8">
        <span className="flex items-center gap-2">
          <BrandMark className="size-8" />
          <span className="font-display text-lg font-extrabold tracking-tight text-ink">agencios</span>
        </span>
        <div className="flex items-center gap-1.5">
          <Button asChild variant="ghost" size="sm">
            <Link to="/configuracoes"><Settings size={15} /> Configurações</Link>
          </Button>
          <Button variant="ghost" size="sm" className="text-danger hover:bg-danger/10 hover:text-danger" onClick={() => logout.mutate()}>
            <LogOut size={15} /> Sair
          </Button>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-5 pb-16 pt-6 sm:px-8">
        {/* Hero */}
        <div className="mx-auto max-w-2xl text-center">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-brand-soft px-3.5 py-1.5 text-xs font-bold text-brand">
            <Sparkles size={13} /> Ative seu workspace
          </span>
          <h1 className="mt-5 font-display text-3xl font-extrabold tracking-tight text-ink sm:text-4xl">
            Escolha um plano para começar
          </h1>
          <p className="mx-auto mt-3 max-w-xl text-ink-muted">
            Sua conta{me?.workspace?.name ? ` (${me.workspace.name})` : ''} ainda não tem um plano ativo.
            Assine para liberar o quadro, o estúdio de criação e todas as integrações.
          </p>
          <div className="mt-5 flex flex-wrap items-center justify-center gap-2.5 text-sm font-semibold text-ink-secondary">
            <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-surface px-3 py-1.5">
              <ShieldCheck size={15} className="text-emerald" /> {trialDays} dias de teste
            </span>
            <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-surface px-3 py-1.5">
              <Zap size={15} className="text-amber" /> Cartão obrigatório para iniciar
            </span>
            <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-surface px-3 py-1.5">
              <Coins size={15} className="text-brand" /> Créditos pré-pagos para vídeo e imagem
            </span>
          </div>
        </div>

        {/* Billing interval toggle */}
        {discountPercent > 0 && (
          <div className="mt-8 flex justify-center">
            <IntervalToggle value={interval} onChange={setInterval} discountPercent={discountPercent} />
          </div>
        )}

        {/* Plans */}
        <div className="mt-6 grid grid-cols-1 gap-5 md:grid-cols-3">
          {plans.map((p) => (
            <PaywallPlan
              key={p.key}
              plan={p}
              highlight={p.key === highlightKey}
              interval={interval}
              discountPercent={discountPercent}
              onSubscribe={(k) => checkout.mutate({ plan: k, interval })}
              pending={checkout.isPending}
            />
          ))}
        </div>

        <p className="mt-8 text-center text-sm text-ink-muted">
          Sem plano gratuito. Carrosséis e legendas com IA estão inclusos; vídeos e imagens consomem
          créditos (1 crédito = R$ 1). Cancele quando quiser.
        </p>
      </div>
    </div>
  )
}
