import { Link, useParams } from 'react-router-dom'
import {
  ArrowLeft, FileBarChart, Loader2, AlertTriangle, TrendingUp, TrendingDown,
  CheckCircle2, Sparkles, Target, Lightbulb, Rocket, CalendarClock, Users,
  Eye, Share2, Repeat, Heart, BarChart3, MessageCircle,
} from 'lucide-react'
import { useReport } from '@/hooks/useData'
import { Page } from '@/components/ui/page'
import { Card } from '@/components/ui/card'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { date } from '@/lib/formatters'

// Compact pt-BR number ("16,8 mil", "3,0 mi") for the headline tiles.
function compact(n) {
  if (n == null || Number.isNaN(Number(n))) return '—'
  const v = Number(n)
  if (Math.abs(v) >= 1_000_000) return `${(v / 1_000_000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi`
  if (Math.abs(v) >= 1_000) return `${(v / 1_000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil`
  return v.toLocaleString('pt-BR')
}

function pct(n) {
  if (n == null) return null
  const v = Number(n)
  return `${v > 0 ? '+' : ''}${v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`
}

const scoreColor = (s) => (s >= 7 ? '#10B981' : s >= 5 ? '#F59E0B' : '#EF4444')

function SectionTitle({ icon: Icon, children, color = '#7C3AED' }) {
  return (
    <div className="mb-3 mt-8 flex items-center gap-2.5">
      <div className="flex size-8 items-center justify-center rounded-lg" style={{ background: `${color}18`, color }}>
        <Icon size={16} strokeWidth={2.3} />
      </div>
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
        <span className="text-[11px] font-semibold uppercase tracking-wide">{label}</span>
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
  const color = tone === 'good' ? '#10B981' : '#EF4444'
  return (
    <Card className="overflow-hidden">
      <div className="px-4 py-3 text-sm font-bold text-white" style={{ background: color }}>{title}</div>
      <div className="divide-y divide-border">
        {items.length === 0 && <p className="p-4 text-sm text-ink-muted">Sem dados.</p>}
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
        {Number(score).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}
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

export default function ReportShow() {
  const { id } = useParams()
  const { data: report, isLoading } = useReport(id)

  if (isLoading) return <PageLoader />
  if (!report) return <Page><EmptyState icon={FileBarChart} title="Relatório não encontrado" /></Page>

  const back = report.project_id ? `/campanhas/${report.project_id}` : '/campanhas'

  if (report.status === 'generating') {
    return (
      <Page>
        <BackLink to={back} />
        <Card className="flex flex-col items-center gap-3 p-12 text-center">
          <Loader2 size={32} className="animate-spin text-brand" />
          <h1 className="font-display text-xl font-bold text-ink">Gerando a auditoria…</h1>
          <p className="text-sm text-ink-secondary">Estamos agregando as métricas e a análise estratégica da campanha. Isso atualiza sozinho.</p>
        </Card>
      </Page>
    )
  }

  if (report.status === 'failed') {
    return (
      <Page>
        <BackLink to={back} />
        <EmptyState icon={AlertTriangle} color="#EF4444" title="Não foi possível gerar o relatório" description="Tente finalizar a campanha novamente." />
      </Page>
    )
  }

  const d = report.data || {}
  const k = d.kpis || {}
  const overall = d.overall || {}
  const cp = d.content_performance || {}
  const plan = d.action_plan || {}
  const projection = d.projection || {}
  const growth = d.growth_angle || {}
  const score = Number(overall.score ?? report.overall_score)

  return (
    <Page>
      <BackLink to={back} />

      {/* Cover */}
      <Card className="mb-6 overflow-hidden">
        <div className="h-2.5 w-full bg-brand-gradient" />
        <div className="p-6">
          <div className="flex items-center gap-2 text-brand">
            <FileBarChart size={18} />
            <span className="text-xs font-bold uppercase tracking-widest">Auditoria de redes sociais</span>
          </div>
          <h1 className="mt-2 font-display text-3xl font-extrabold tracking-tight text-ink">{report.project_name}</h1>
          <p className="mt-1 text-sm font-semibold text-ink-secondary">
            {report.client_name}
            {report.period_start && <> · {date(report.period_start)} → {date(report.period_end)}</>}
          </p>
          {d.ai_ok === false && (
            <p className="mt-3 rounded-lg bg-amber/15 px-3 py-2 text-xs font-medium text-[#B45309]">
              A análise textual não pôde ser gerada agora — os números abaixo refletem os dados reais da campanha.
            </p>
          )}
        </div>
      </Card>

      {/* OS NÚMEROS */}
      <SectionTitle icon={BarChart3}>Os números</SectionTitle>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <KpiTile label="Seguidores" value={compact(k.followers)} delta={k.follower_growth_pct} icon={Users} />
        <KpiTile label="Novos seguidores" value={compact(k.new_followers)} icon={Users} />
        <KpiTile label="Contas alcançadas" value={compact(k.accounts_reached)} delta={k.reach_delta_pct} icon={Eye} />
        <KpiTile label="Visualizações" value={compact(k.views)} icon={BarChart3} />
        <KpiTile label="Alcance (posts)" value={compact(k.reach)} icon={Eye} />
        <KpiTile label="Compart. de Reels" value={compact(k.reel_shares)} icon={Share2} />
        <KpiTile label="Respostas em Stories" value={compact(k.story_replies)} icon={MessageCircle} />
        <KpiTile label="Engajamento" value={compact(k.engagement)} icon={Heart} />
      </div>
      {k.has_account_data === false && (
        <p className="mt-2 text-xs text-ink-muted">
          As métricas de perfil (seguidores, alcance de contas, respostas em Stories) começam a aparecer conforme o histórico de snapshots é coletado.
        </p>
      )}

      {/* NOTA GERAL */}
      {Number.isFinite(score) && score > 0 && (
        <>
          <SectionTitle icon={Target}>Nota geral</SectionTitle>
          <div className="grid gap-3 md:grid-cols-3">
            <Card className="flex flex-col items-center justify-center p-6 text-center">
              <p className="font-display text-6xl font-black" style={{ color: scoreColor(score) }}>
                {score.toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}
              </p>
              <p className="text-sm font-semibold text-ink-muted">/ 10</p>
              {overall.verdict && <p className="mt-2 text-sm text-ink-secondary">{overall.verdict}</p>}
            </Card>
            <Milestones title="Para chegar a 8" items={overall.to_8} color="#10B981" />
            <Milestones title="Para chegar a 9" items={overall.to_9} color="#F59E0B" />
          </div>
        </>
      )}

      {/* O QUE ESTÁ FUNCIONANDO */}
      {d.wins?.length > 0 && (
        <>
          <SectionTitle icon={CheckCircle2} color="#10B981">O que está funcionando</SectionTitle>
          <CardList items={d.wins} color="#10B981" />
        </>
      )}

      {/* PERFORMANCE DOS REELS / FORMATOS */}
      {(cp.winners?.length || cp.losers?.length) ? (
        <>
          <SectionTitle icon={Sparkles}>Performance por formato</SectionTitle>
          <div className="grid gap-3 md:grid-cols-2">
            <PerfColumn title="✅ O que performa" items={cp.winners} tone="good" />
            <PerfColumn title="❌ O que não funciona" items={cp.losers} tone="bad" />
          </div>
        </>
      ) : null}

      {/* GARGALOS */}
      {d.bottlenecks?.length > 0 && (
        <>
          <SectionTitle icon={AlertTriangle} color="#EF4444">Gargalos críticos</SectionTitle>
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
          <SectionTitle icon={Lightbulb} color="#F59E0B">O que precisa ser explorado</SectionTitle>
          <CardList items={d.opportunities} color="#F59E0B" />
        </>
      )}

      {/* MATRIZ */}
      {d.matrix?.length > 0 && (
        <>
          <SectionTitle icon={BarChart3}>Matriz de performance</SectionTitle>
          <Card className="divide-y divide-border px-4 py-1">
            {d.matrix.map((m, i) => <MatrixRow key={i} {...m} />)}
          </Card>
        </>
      )}

      {/* PLANO DE AÇÃO */}
      {(plan.d7 || plan.d30 || plan.d90) && (
        <>
          <SectionTitle icon={CalendarClock}>Plano de ação</SectionTitle>
          <div className="grid gap-3 md:grid-cols-3">
            <PlanColumn title="Próximos 7 dias" items={plan.d7} color="#EF4444" />
            <PlanColumn title="Próximos 30 dias" items={plan.d30} color="#F59E0B" />
            <PlanColumn title="Próximos 90 dias" items={plan.d90} color="#10B981" />
          </div>
        </>
      )}

      {/* PROJEÇÃO */}
      {projection.verdict && (
        <>
          <SectionTitle icon={TrendingUp}>Projeção 12 meses</SectionTitle>
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
          <SectionTitle icon={Rocket} color="#EC4899">{growth.title || 'Vetor de crescimento'}</SectionTitle>
          {growth.intro && <p className="mb-3 text-sm text-ink-secondary">{growth.intro}</p>}
          <CardList items={growth.tactics} color="#EC4899" />
        </>
      )}
    </Page>
  )
}

function BackLink({ to }) {
  return (
    <Link to={to} className="mb-5 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
      <ArrowLeft size={16} /> Voltar à campanha
    </Link>
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
