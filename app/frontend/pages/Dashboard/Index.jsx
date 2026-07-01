import { Link } from 'react-router-dom'
import {
  Plus, Ticket, Users, FolderKanban, CalendarClock,
  Receipt, TrendingUp, Video, Calendar, Sparkles, ArrowUpRight,
  KanbanSquare, Wand2, CalendarDays, ChevronRight, Clock,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { dt, brl, relativeDay } from '@/lib/formatters'
import { WORKFLOW, statusMeta, GENERATION_KIND_META } from '@/lib/constants'
import { useDashboard } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { StatCard } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'

function greeting() {
  const h = new Date().getHours()
  if (h < 12) return 'Bom dia'
  if (h < 18) return 'Boa tarde'
  return 'Boa noite'
}

const firstName = (name) => (name || '').trim().split(/\s+/)[0] || 'por aqui'

const GEN_STATUS = {
  completed: { label: 'Pronto', variant: 'success' },
  succeeded: { label: 'Pronto', variant: 'success' },
  ready:     { label: 'Pronto', variant: 'success' },
  processing:{ label: 'Gerando', variant: 'warning' },
  pending:   { label: 'Na fila', variant: 'muted' },
  queued:    { label: 'Na fila', variant: 'muted' },
  failed:    { label: 'Falhou', variant: 'danger' },
  error:     { label: 'Falhou', variant: 'danger' },
}

const SHORTCUTS = [
  { to: '/quadro', label: 'Quadro', hint: 'Funil de produção', icon: KanbanSquare, color: '#EC4899' },
  { to: '/estudio', label: 'Estúdio', hint: 'Gerar criativos', icon: Wand2, color: '#7C3AED' },
  { to: '/calendario', label: 'Calendário', hint: 'Posts e reuniões', icon: CalendarDays, color: '#0EA5E9' },
  { to: '/clientes', label: 'Clientes', hint: 'Sua carteira', icon: Users, color: '#10B981' },
]

export default function Dashboard() {
  const { data, isLoading } = useDashboard()
  const { data: me } = useCurrentUser()

  if (isLoading) return <PageLoader />

  const stats = data?.stats || {}
  const byStatus = data?.tickets_by_status || {}
  const meetings = data?.upcoming_meetings || []
  const generations = data?.recent_generations || []

  const user = me?.user || {}
  const workspace = me?.workspace || {}
  const name = firstName(user.display_name || user.name)

  const totalFunnel = WORKFLOW.reduce((sum, s) => sum + (Number(byStatus[s]) || 0), 0)

  const statCards = [
    { label: 'Tickets ativos', value: stats.active_tickets ?? 0, icon: Ticket, color: '#EC4899', sub: 'em produção agora', to: '/quadro' },
    { label: 'Clientes', value: stats.clients ?? 0, icon: Users, color: '#10B981', sub: 'na carteira', to: '/clientes' },
    { label: 'Projetos', value: stats.projects ?? 0, icon: FolderKanban, color: '#7C3AED', sub: 'em andamento', to: '/projetos' },
    { label: 'Posts agendados', value: stats.scheduled_posts ?? 0, icon: CalendarClock, color: '#0EA5E9', sub: 'na fila', to: '/calendario' },
    { label: 'Cobranças abertas', value: stats.open_invoices ?? 0, icon: Receipt, color: '#F59E0B', sub: 'aguardando', to: '/cobrancas' },
    { label: 'Receita', value: brl(stats.revenue_cents), icon: TrendingUp, color: '#14B8A6', sub: 'recebido', to: '/cobrancas' },
  ]

  return (
    <Page className="space-y-6 sm:space-y-7">
      {/* ── Hero ───────────────────────────────────────────────── */}
      <section className="animate-rise relative overflow-hidden rounded-3xl bg-shell-gradient p-6 text-white shadow-[0_24px_60px_-30px_rgba(17,10,36,0.7)] sm:p-9">
        <div className="bg-aurora pointer-events-none absolute inset-0 opacity-90" />
        <div className="relative flex flex-col gap-5 sm:flex-row sm:flex-wrap sm:items-end sm:justify-between">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-[0.18em] text-white/55">{workspace.name || 'Sua agência'}</p>
            <h1 className="mt-1.5 font-display text-[26px] font-extrabold leading-tight tracking-tight sm:text-[34px]">
              {greeting()}, {name} <span className="inline-block">👋</span>
            </h1>
            <p className="mt-2 max-w-md text-sm text-white/70">
              Aqui está o pulso da agência hoje. Mova o trabalho pelo funil e mantenha tudo no ar.
            </p>
          </div>
          <div className="flex w-full gap-2.5 sm:w-auto sm:flex-wrap sm:items-center">
            <Button asChild size="lg" variant="glow" className="flex-1 justify-center bg-white text-brand-ink hover:bg-white/90 sm:flex-none">
              <Link to="/quadro"><Plus size={18} /> Novo ticket</Link>
            </Button>
            <Button asChild size="lg" variant="ghost" className="flex-1 justify-center text-white hover:bg-white/10 sm:flex-none">
              <Link to="/estudio"><Sparkles size={18} /> Estúdio</Link>
            </Button>
          </div>
        </div>
      </section>

      {/* ── Stat cards ─────────────────────────────────────────── */}
      <section className="animate-rise grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-6">
        {statCards.map((s) => (
          <Link key={s.label} to={s.to} className="block">
            <StatCard label={s.label} value={s.value} icon={s.icon} color={s.color} sub={s.sub} />
          </Link>
        ))}
      </section>

      {/* ── Funnel ─────────────────────────────────────────────── */}
      <section className="animate-rise">
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <div>
              <CardTitle>Funil de produção</CardTitle>
              <p className="text-sm text-ink-muted">{totalFunnel} tickets distribuídos pelas 7 etapas</p>
            </div>
            <Button asChild variant="outline" size="sm">
              <Link to="/quadro">Abrir quadro <ArrowUpRight size={15} /></Link>
            </Button>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col gap-2 sm:flex-row sm:items-stretch sm:gap-2">
              {WORKFLOW.map((status) => {
                const m = statusMeta(status)
                const Icon = m.icon
                const count = Number(byStatus[status]) || 0
                const grow = 1 + (totalFunnel ? count / totalFunnel : 0)
                return (
                  <Link
                    key={status}
                    to="/quadro"
                    className="group relative flex min-w-[120px] flex-col justify-between gap-3 overflow-hidden rounded-2xl border border-border p-3.5 transition-all hover:-translate-y-0.5 hover:shadow-[0_14px_30px_-16px_rgba(24,18,43,0.3)] sm:min-w-0"
                    style={{ flexGrow: grow, flexBasis: 0, background: `${m.color}0D`, borderColor: `${m.color}33` }}
                  >
                    <div className="flex items-center justify-between">
                      <span className="flex size-8 items-center justify-center rounded-xl" style={{ background: `${m.color}1F`, color: m.color }}>
                        <Icon size={16} strokeWidth={2.4} />
                      </span>
                      <span className="font-display text-2xl font-extrabold leading-none" style={{ color: m.color }}>{count}</span>
                    </div>
                    <div>
                      <p className="truncate text-[12px] font-bold text-ink">{m.short}</p>
                      <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-white/60">
                        <div className="h-full rounded-full" style={{ width: `${totalFunnel ? (count / totalFunnel) * 100 : 0}%`, background: m.color, minWidth: count > 0 ? 6 : 0 }} />
                      </div>
                    </div>
                  </Link>
                )
              })}
            </div>
          </CardContent>
        </Card>
      </section>

      {/* ── Meetings + Generations ─────────────────────────────── */}
      <section className="animate-rise grid grid-cols-1 gap-5 lg:grid-cols-2">
        {/* Upcoming meetings */}
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <span className="flex size-8 items-center justify-center rounded-xl bg-sky/12 text-sky"><Calendar size={16} strokeWidth={2.4} /></span>
              Próximas reuniões
            </CardTitle>
            <Button asChild variant="ghost" size="sm"><Link to="/reunioes">Ver todas <ChevronRight size={15} /></Link></Button>
          </CardHeader>
          <CardContent className="space-y-2">
            {meetings.length === 0 ? (
              <EmptyState
                icon={Calendar}
                color="#0EA5E9"
                title="Sem reuniões agendadas"
                description="Quando você marcar reuniões, elas aparecem aqui."
                action={<Button asChild variant="outline" size="sm"><Link to="/reunioes"><Plus size={15} /> Agendar reunião</Link></Button>}
              />
            ) : (
              meetings.map((mtg) => (
                <div key={mtg.id} className="flex items-center justify-between gap-3 rounded-xl border border-border bg-surface p-3 transition-colors hover:bg-surface-muted">
                  <div className="flex min-w-0 items-center gap-3">
                    <span className="flex size-10 shrink-0 flex-col items-center justify-center rounded-xl bg-sky/12 text-sky">
                      <Clock size={16} strokeWidth={2.4} />
                    </span>
                    <div className="min-w-0">
                      <p className="truncate font-semibold text-ink">{mtg.title || 'Reunião'}</p>
                      <p className="truncate text-[12.5px] text-ink-muted">
                        {dt(mtg.starts_at)}{mtg.client_name ? ` · ${mtg.client_name}` : ''}
                      </p>
                    </div>
                  </div>
                  {mtg.meet_url && (
                    <Button asChild size="sm" variant="outline" className="shrink-0">
                      <a href={mtg.meet_url} target="_blank" rel="noreferrer"><Video size={15} /> Entrar</a>
                    </Button>
                  )}
                </div>
              ))
            )}
          </CardContent>
        </Card>

        {/* Recent generations */}
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <span className="flex size-8 items-center justify-center rounded-xl bg-brand-soft text-brand"><Sparkles size={16} strokeWidth={2.4} /></span>
              Gerações recentes
            </CardTitle>
            <Button asChild variant="ghost" size="sm"><Link to="/estudio">Estúdio <ChevronRight size={15} /></Link></Button>
          </CardHeader>
          <CardContent className="space-y-2">
            {generations.length === 0 ? (
              <EmptyState
                icon={Wand2}
                color="#7C3AED"
                title="Nenhuma geração ainda"
                description="Gere carrosséis, vídeos e imagens com IA no Estúdio."
                action={<Button asChild variant="outline" size="sm"><Link to="/estudio"><Sparkles size={15} /> Abrir Estúdio</Link></Button>}
              />
            ) : (
              generations.map((gen) => {
                const m = GENERATION_KIND_META[gen.kind] || GENERATION_KIND_META.image
                const Icon = m.icon
                const rel = relativeDay(gen.created_at)
                const st = GEN_STATUS[gen.status] || { label: gen.status || '—', variant: 'muted' }
                return (
                  <div key={gen.id} className="flex items-center justify-between gap-3 rounded-xl border border-border bg-surface p-3 transition-colors hover:bg-surface-muted">
                    <div className="flex min-w-0 items-center gap-3">
                      <span className="flex size-10 shrink-0 items-center justify-center rounded-xl" style={{ background: `${m.color}16`, color: m.color }}>
                        <Icon size={17} strokeWidth={2.3} />
                      </span>
                      <div className="min-w-0">
                        <p className="truncate font-semibold text-ink">{m.label}</p>
                        <p className="truncate text-[12.5px] text-ink-muted">{rel?.text || dt(gen.created_at)}</p>
                      </div>
                    </div>
                    <Badge variant={st.variant} className="shrink-0">{st.label}</Badge>
                  </div>
                )
              })
            )}
          </CardContent>
        </Card>
      </section>

      {/* ── Shortcuts ──────────────────────────────────────────── */}
      <section className="animate-rise">
        <h2 className="mb-3 text-[11px] font-bold uppercase tracking-[0.14em] text-ink-muted">Atalhos</h2>
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {SHORTCUTS.map((s) => {
            const Icon = s.icon
            return (
              <Link
                key={s.to}
                to={s.to}
                className="group relative flex items-center gap-3.5 overflow-hidden rounded-2xl border border-border p-4 transition-all hover:-translate-y-0.5 hover:shadow-[0_14px_30px_-16px_rgba(24,18,43,0.3)]"
                style={{ background: `${s.color}0D`, borderColor: `${s.color}26` }}
              >
                <span className="flex size-11 shrink-0 items-center justify-center rounded-2xl text-white shadow-sm" style={{ background: s.color }}>
                  <Icon size={20} strokeWidth={2.3} />
                </span>
                <div className="min-w-0">
                  <p className="font-display text-[15px] font-bold text-ink">{s.label}</p>
                  <p className="truncate text-[12.5px] text-ink-muted">{s.hint}</p>
                </div>
                <ArrowUpRight size={16} className="ml-auto shrink-0 text-ink-faint transition-colors group-hover:text-ink" />
              </Link>
            )
          })}
        </div>
      </section>
    </Page>
  )
}
