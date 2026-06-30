import { useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft, Wallet, CalendarRange, ListChecks, KanbanSquare, Pencil, Building2,
  FileText, CheckCircle2,
} from 'lucide-react'
import { useProject, useProjectMutations } from '@/hooks/useData'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { StatusPill, PriorityDot } from '@/components/ui/iconography'
import { Page } from '@/components/ui/page'
import { TicketFilters } from '@/components/ticket/TicketFilters'
import { brl, date, relativeDay } from '@/lib/formatters'

const STATUS = {
  active: { label: 'Ativo', variant: 'success' },
  paused: { label: 'Pausado', variant: 'warning' },
  archived: { label: 'Arquivado', variant: 'muted' },
  completed: { label: 'Finalizado', variant: 'soft' },
}

export default function ProjectShow() {
  const { id } = useParams()
  const location = useLocation()
  const navigate = useNavigate()
  const [filters, setFilters] = useState({})
  const { data, isLoading } = useProject(id, filters)
  const { finalize } = useProjectMutations()

  if (isLoading) return <PageLoader />

  const project = data?.project || {}
  const tickets = data?.tickets || project?.tickets || []
  const color = project.color || '#7C3AED'
  const st = STATUS[project.status] || STATUS.active
  const hasRange = project.starts_on || project.ends_on
  const hasFilters = Object.values(filters).some(Boolean)
  const isCompleted = project.status === 'completed'

  const handleFinalize = async () => {
    if (!window.confirm('Finalizar este projeto e gerar o relatório de auditoria?')) return
    const res = await finalize.mutateAsync(id)
    const reportId = res?.report?.id
    if (reportId) navigate(`/relatorios/${reportId}`)
  }

  return (
    <Page>
      <Link to="/projetos" className="mb-5 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
        <ArrowLeft size={16} /> Projetos
      </Link>

      {/* Hero */}
      <Card className="mb-6 overflow-hidden">
        <div className="h-2.5 w-full" style={{ background: color }} />
        <div className="flex flex-wrap items-start justify-between gap-4 p-6">
          <div className="flex items-start gap-4">
            <div className="flex size-14 shrink-0 items-center justify-center rounded-2xl" style={{ background: `${color}1A`, color }}>
              <KanbanSquare size={28} strokeWidth={2.2} />
            </div>
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="font-display text-2xl font-extrabold tracking-tight text-ink">{project.name || 'Projeto'}</h1>
                <Badge variant={st.variant}>{st.label}</Badge>
              </div>
              {project.client_name && (
                <Link
                  to={project.client_id ? `/clientes/${project.client_id}` : '/clientes'}
                  className="mt-1 inline-flex items-center gap-1.5 text-sm font-semibold text-brand hover:underline"
                >
                  <Building2 size={14} /> {project.client_name}
                </Link>
              )}
              {project.description && (
                <p className="mt-3 max-w-2xl text-sm text-ink-secondary">{project.description}</p>
              )}
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button asChild variant="outline">
              <Link to="/projetos"><Pencil size={16} /> Editar</Link>
            </Button>
            {project.latest_report_id && (
              <Button asChild variant="outline">
                <Link to={`/relatorios/${project.latest_report_id}`}><FileText size={16} /> Ver relatório</Link>
              </Button>
            )}
            {!isCompleted && (
              <Button onClick={handleFinalize} disabled={finalize.isPending}>
                <CheckCircle2 size={16} /> Finalizar projeto
              </Button>
            )}
          </div>
        </div>

        <div className="flex flex-wrap gap-2 border-t border-border bg-surface-muted/50 px-6 py-4">
          <span className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-bold" style={{ background: `${color}14`, color }}>
            <ListChecks size={15} /> {project.tickets_count ?? tickets.length} tickets
          </span>
          {project.budget_cents != null && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald/12 px-3 py-1.5 text-sm font-bold text-emerald">
              <Wallet size={15} /> {brl(project.budget_cents)}
            </span>
          )}
          {hasRange && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-surface px-3 py-1.5 text-sm font-medium text-ink-secondary">
              <CalendarRange size={15} className="text-indigo" />
              {date(project.starts_on)}{project.ends_on ? ` → ${date(project.ends_on)}` : ''}
            </span>
          )}
        </div>
      </Card>

      {/* Tickets */}
      <div className="mb-3 flex items-center gap-2">
        <ListChecks size={18} style={{ color }} />
        <h2 className="font-display text-lg font-bold text-ink">Tickets</h2>
      </div>

      <TicketFilters filters={filters} onChange={setFilters} />

      {tickets.length === 0 ? (
        hasFilters ? (
          <EmptyState
            icon={ListChecks}
            color={color}
            title="Nenhum ticket corresponde aos filtros"
            description="Ajuste ou limpe os filtros para ver mais tickets deste projeto."
            action={<Button variant="outline" onClick={() => setFilters({})}>Limpar filtros</Button>}
          />
        ) : (
          <EmptyState
            icon={KanbanSquare}
            color={color}
            title="Sem tickets neste projeto"
            description="Os tickets deste projeto aparecem no quadro. Crie um para começar a produção."
            action={<Button asChild><Link to="/quadro"><KanbanSquare size={16} /> Ir para o quadro</Link></Button>}
          />
        )
      ) : (
        <Card className="divide-y divide-border">
          {tickets.map((t) => {
            const rel = relativeDay(t.due_date || t.scheduled_at)
            return (
              <Link
                key={t.id}
                to={`/tickets/${t.id}`}
                state={{ from: location.pathname + location.search }}
                className="flex items-center justify-between gap-4 p-4 transition-colors hover:bg-surface-muted/60"
              >
                <div className="flex min-w-0 items-center gap-3">
                  <StatusPill status={t.status} size="sm" />
                  <span className="truncate font-medium text-ink">{t.display_title || t.title}</span>
                </div>
                <div className="flex shrink-0 items-center gap-3">
                  {t.priority && <PriorityDot priority={t.priority} />}
                  {rel && (
                    <Badge variant={rel.tone === 'danger' ? 'danger' : rel.tone === 'warning' ? 'warning' : 'muted'}>
                      {rel.text}
                    </Badge>
                  )}
                </div>
              </Link>
            )
          })}
        </Card>
      )}
    </Page>
  )
}
