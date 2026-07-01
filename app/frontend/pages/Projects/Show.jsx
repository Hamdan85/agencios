import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowLeft, Wallet, CalendarRange, ListChecks, KanbanSquare, Pencil, Building2,
  FileText, CheckCircle2, Play, Plus, Sparkles, MoreHorizontal, Archive, ArchiveRestore,
  Trash2, Receipt, Send, Loader2, AlertTriangle, Target, Eye, Heart,
} from 'lucide-react'
import {
  useProject, useProjectMutations, useTicketArchiveMutations, useTicketBulkDelete,
  useReport,
} from '@/hooks/useData'
import { useStrategySession, useApplyStrategy, useDiscardStrategy } from '@/hooks/useStrategy'
import { useCurrentUser } from '@/hooks/useAuth'
import { useSelection } from '@/hooks/useSelection'
import { canManage } from '@/lib/roles'
import { StrategyDrawer } from '@/components/project/StrategyDrawer'
import { PlanBuildingLoader } from '@/components/project/PlanBuildingLoader'
import { ProjectFormDialog } from '@/components/project/ProjectFormDialog'
import { SendScopeDialog } from '@/components/project/SendScopeDialog'
import AutopilotButton from '@/components/ticket/AutopilotButton'
import { InvoiceFormDialog } from '@/components/billing/InvoiceFormDialog'
import { ticketsApi } from '@/api'
import analytics, { EVENTS } from '@/lib/analytics'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { Page } from '@/components/ui/page'
import { SelectionBar } from '@/components/ui/selection-bar'
import { ConfirmDialog, useConfirm } from '@/components/ui/confirm-dialog'
import { TicketFilters } from '@/components/ticket/TicketFilters'
import TicketRow from '@/components/ticket/TicketRow'
import TicketDrawer from '@/components/ticket/TicketDrawer'
import { NewTicketDialog } from '@/components/board/NewTicketDialog'
import { brl, date, shortDt, compact } from '@/lib/formatters'

const STATUS = {
  draft: { label: 'Rascunho', variant: 'muted' },
  active: { label: 'Ativo', variant: 'success' },
  paused: { label: 'Pausado', variant: 'warning' },
  archived: { label: 'Arquivado', variant: 'muted' },
  completed: { label: 'Finalizado', variant: 'soft' },
}

export default function ProjectShow() {
  const { id } = useParams()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [filters, setFilters] = useState({})
  const [ticketOpen, setTicketOpen] = useState(false)
  const [strategyOpen, setStrategyOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [billingOpen, setBillingOpen] = useState(false)
  const [scopeOpen, setScopeOpen] = useState(false)
  const [drawerId, setDrawerId] = useState(null)
  const [proposedPlan, setProposedPlan] = useState(null)
  const [generating, setGenerating] = useState(false)
  const { data, isLoading } = useProject(id, filters)
  const { data: latestReport } = useReport(data?.project?.latest_report_id)
  const { data: strategySession } = useStrategySession(id)
  const applyStrategy = useApplyStrategy(id)
  const discardStrategy = useDiscardStrategy(id)
  const { start, finalize, update, destroy, sendScope, autopilotEstimate, autopilot } = useProjectMutations()
  const { archive, unarchive } = useTicketArchiveMutations()
  const { data: me } = useCurrentUser()
  const manager = canManage(me?.membership?.role)
  const bulkDelete = useTicketBulkDelete()
  const selection = useSelection()
  const confirm = useConfirm()
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false)
  const [searchParams, setSearchParams] = useSearchParams()

  // Reset the selection whenever the filtered set changes, so a bulk delete
  // never hits tickets that scrolled out of view.
  const { clear: clearSelection } = selection
  useEffect(() => { clearSelection() }, [JSON.stringify(filters), clearSelection])

  // Opened straight from project creation (…/projetos/:id?planejar=1) → jump into
  // the strategy planner, then drop the flag so a refresh doesn't reopen it.
  useEffect(() => {
    if (searchParams.get('planejar') === '1') {
      setStrategyOpen(true)
      searchParams.delete('planejar')
      setSearchParams(searchParams, { replace: true })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Create a ticket pre-scoped to this project; refresh the project's list + board.
  const create = useMutation({
    mutationFn: (payload) => ticketsApi.create(payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['projects'] })
      qc.invalidateQueries({ queryKey: ['board'] })
      analytics.track(EVENTS.TICKET_CREATED)
      toast.success('Ticket criado!')
    },
    onError: (err) => toast.error(err?.error || 'Erro ao criar ticket.'),
  })

  if (isLoading) return <PageLoader />

  const project = data?.project || {}
  const tickets = data?.tickets || project?.tickets || []
  const color = project.color || '#7C3AED'
  const st = STATUS[project.status] || STATUS.active
  const hasRange = project.starts_on || project.ends_on
  const hasFilters = Object.values(filters).some(Boolean)
  const isDraft = project.status === 'draft'
  const isCompleted = project.status === 'completed'
  const isArchived = project.status === 'archived'
  // The end-of-run audit report generates async (AI + metric aggregation).
  // While it's in flight, show at most a small animated badge — never block
  // the page on it — and it clears itself once `latestReport` flips to
  // ready/failed (polled by useReport while status is `generating`).
  const reportGenerating = latestReport?.status === 'generating'
  const reportFailed = latestReport?.status === 'failed'
  const reportReady = latestReport?.status === 'ready'
  const reportKpis = reportReady ? (latestReport.data?.kpis || {}) : {}
  // The plan to preview as ghost rows: the drawer's live proposal, falling back
  // to the persisted `proposed` plan — so a proposed plan SURVIVES a reload and
  // keeps showing on the project (drawer open or not) until it's applied/discarded.
  // Never mid-generation, where the loader takes over instead.
  const persistedPlan = strategySession?.status === 'proposed' ? strategySession.proposed_plan : null
  const buildingPlan = strategyOpen && generating
  const previewPlan = strategyOpen ? (proposedPlan || persistedPlan) : persistedPlan
  const ghostTickets = !buildingPlan ? (previewPlan?.tickets || []) : []
  // While planning (building or reviewing a plan), the list shows ONLY the plan —
  // the existing tickets are hidden so the preview is clean.
  const planMode = buildingPlan || ghostTickets.length > 0
  // A proposed plan waiting for a decision, with the planner closed → show a
  // banner so the user can review / apply / discard it after a reload.
  const pendingReview = !strategyOpen && !!persistedPlan

  const handleStart = () => start.mutate(id)

  const handleFinalize = async () => {
    const ok = await confirm({
      title: 'Finalizar projeto?',
      description: 'Vamos encerrar o projeto e gerar o relatório de auditoria com o resumo da produção.',
      confirmLabel: 'Finalizar',
      icon: CheckCircle2,
      tone: '#10B981',
    })
    if (!ok) return
    // Stay on the project — the audit report generates async (see the
    // `reportGenerating` badge below) instead of navigating to a full-page
    // "generating…" screen that could strand the user if it's slow.
    await finalize.mutateAsync(id)
  }

  const handleArchiveToggle = () => {
    update.mutate(
      { id, data: { status: isArchived ? 'active' : 'archived' } },
      { onSuccess: () => toast.success(isArchived ? 'Projeto reativado.' : 'Projeto arquivado.') },
    )
  }

  const handleDelete = async () => {
    const ok = await confirm({
      title: 'Excluir projeto?',
      description: 'Isso remove o projeto e todos os seus tickets. Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir projeto',
      destructive: true,
    })
    if (!ok) return
    destroy.mutate(id, { onSuccess: () => navigate('/projetos') })
  }

  const confirmBulkDelete = () => {
    bulkDelete.mutate(selection.list, {
      onSuccess: () => { selection.clear(); setConfirmDeleteOpen(false) },
    })
  }

  // The project ticket list isn't paginated, so "select all" is simply every
  // real (non-ghost) ticket currently loaded.
  const selectAll = () => selection.set(tickets.map((t) => t.id))

  return (
    <Page>
      <Link to="/projetos" className="mb-5 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
        <ArrowLeft size={16} /> Projetos
      </Link>

      {/* Hero */}
      <Card className="mb-6 overflow-hidden">
        <div className="h-2.5 w-full" style={{ background: color }} />
        <div className="flex flex-col gap-4 p-5 sm:flex-row sm:flex-wrap sm:items-start sm:justify-between sm:p-6">
          <div className="flex items-start gap-4">
            <div className="flex size-12 shrink-0 items-center justify-center rounded-2xl sm:size-14" style={{ background: `${color}1A`, color }}>
              <KanbanSquare size={26} strokeWidth={2.2} />
            </div>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="font-display text-xl font-extrabold tracking-tight text-ink sm:text-2xl">{project.name || 'Projeto'}</h1>
                <Badge variant={st.variant}>{st.label}</Badge>
                {reportGenerating && (
                  <Badge variant="soft"><Loader2 size={11} className="animate-spin" /> Gerando auditoria…</Badge>
                )}
                {reportFailed && (
                  <Badge variant="danger"><AlertTriangle size={11} /> Falha ao gerar auditoria</Badge>
                )}
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
          <div className="flex flex-wrap items-center justify-end gap-2 sm:justify-start">
            {!isCompleted && (
              <Button variant="outline" className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Planejar conteúdo com IA" onClick={() => setStrategyOpen(true)}>
                <Sparkles size={16} /> <span className="hidden sm:inline">Planejar conteúdo com IA</span>
              </Button>
            )}
            <Button variant="outline" className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Editar" onClick={() => setEditOpen(true)}>
              <Pencil size={16} /> <span className="hidden sm:inline">Editar</span>
            </Button>
            {project.latest_report_id && reportReady && (
              <Button asChild variant="outline" className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Ver relatório">
                <Link to={`/relatorios/${project.latest_report_id}`}><FileText size={16} /> <span className="hidden sm:inline">Ver relatório</span></Link>
              </Button>
            )}
            {isDraft && (
              <Button variant="outline" className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Enviar escopo ao cliente" onClick={() => setScopeOpen(true)}>
                <Send size={16} /> <span className="hidden sm:inline">Enviar escopo ao cliente</span>
              </Button>
            )}
            {isDraft && (
              <Button className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Iniciar projeto" onClick={handleStart} disabled={start.isPending}>
                <Play size={16} /> <span className="hidden sm:inline">Iniciar projeto</span>
              </Button>
            )}
            {!isCompleted && (
              <AutopilotButton
                estimating={autopilotEstimate.isPending}
                starting={autopilot.isPending}
                onEstimate={() => autopilotEstimate.mutateAsync(id).then((d) => d?.estimate)}
                onStart={() => autopilot.mutate({ id, payload: { mode: 'scheduled' } })}
              />
            )}
            {!isCompleted && !isDraft && (
              <Button className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Finalizar projeto" onClick={handleFinalize} disabled={finalize.isPending}>
                <CheckCircle2 size={16} /> <span className="hidden sm:inline">Finalizar projeto</span>
              </Button>
            )}
            {isCompleted && (
              <Button className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Iniciar cobrança" onClick={() => setBillingOpen(true)}>
                <Receipt size={16} /> <span className="hidden sm:inline">Iniciar cobrança</span>
              </Button>
            )}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="icon" aria-label="Mais ações">
                  <MoreHorizontal size={16} />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-44">
                <DropdownMenuItem onSelect={() => setScopeOpen(true)}>
                  <Send size={15} /> Enviar escopo ao cliente
                </DropdownMenuItem>
                <DropdownMenuItem onSelect={handleArchiveToggle}>
                  {isArchived ? <><ArchiveRestore size={15} /> Reativar</> : <><Archive size={15} /> Arquivar</>}
                </DropdownMenuItem>
                <DropdownMenuItem onSelect={handleDelete} className="text-danger focus:text-danger">
                  <Trash2 size={15} /> Excluir
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>

        <div className="flex flex-wrap justify-end gap-2 border-t border-border bg-surface-muted/50 px-5 py-3.5 sm:justify-start sm:px-6 sm:py-4">
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
              <span className="sm:hidden">{shortDt(project.starts_on)}{project.ends_on ? ` → ${shortDt(project.ends_on)}` : ''}</span>
              <span className="hidden sm:inline">{date(project.starts_on)}{project.ends_on ? ` → ${date(project.ends_on)}` : ''}</span>
            </span>
          )}
          {reportReady && (
            <>
              {Number.isFinite(Number(latestReport.overall_score)) && (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-indigo/12 px-3 py-1.5 text-sm font-bold text-indigo">
                  <Target size={15} /> Nota {Number(latestReport.overall_score).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}/10
                </span>
              )}
              <span className="inline-flex items-center gap-1.5 rounded-full bg-sky/12 px-3 py-1.5 text-sm font-bold text-sky">
                <Eye size={15} /> {compact(reportKpis.views)} visualizações
              </span>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-pink/12 px-3 py-1.5 text-sm font-bold text-pink">
                <Heart size={15} /> {compact(reportKpis.engagement)} engajamento
              </span>
            </>
          )}
        </div>
      </Card>

      {/* A proposed plan is waiting (survived a reload) — review / apply / discard. */}
      {pendingReview && (
        <div className="mb-4 flex flex-col gap-3 rounded-2xl border border-brand/30 bg-brand-soft/40 p-4 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
          <div className="flex items-center gap-2.5">
            <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-soft text-brand">
              <Sparkles size={18} strokeWidth={2.3} />
            </span>
            <div>
              <p className="text-sm font-semibold text-ink">
                Plano proposto pronto · {persistedPlan.tickets.length} tickets
              </p>
              <p className="text-xs text-ink-muted">Revise no chat ou aplique para criar os tickets.</p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="ghost" size="sm" onClick={() => discardStrategy.mutate(strategySession.id)} disabled={discardStrategy.isPending}>
              Descartar
            </Button>
            <Button variant="outline" size="sm" onClick={() => setStrategyOpen(true)}>
              <Sparkles size={15} /> Revisar
            </Button>
            <Button size="sm" onClick={() => applyStrategy.mutate(strategySession.id)} disabled={applyStrategy.isPending}>
              <CheckCircle2 size={15} /> {applyStrategy.isPending ? 'Aplicando…' : 'Aplicar'}
            </Button>
          </div>
        </div>
      )}

      {/* Tickets */}
      <div className="mb-3 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <ListChecks size={18} style={{ color }} />
          <h2 className="font-display text-lg font-bold text-ink">Tickets</h2>
        </div>
        <Button size="sm" onClick={() => setTicketOpen(true)}>
          <Plus size={16} /> Novo ticket
        </Button>
      </div>

      {manager && selection.count > 0 ? (
        <SelectionBar
          count={selection.count}
          total={tickets.length}
          onSelectAll={selectAll}
          onClear={selection.clear}
        >
          <Button variant="destructive" size="sm" className="gap-1.5" onClick={() => setConfirmDeleteOpen(true)}>
            <Trash2 size={15} /> Excluir
          </Button>
        </SelectionBar>
      ) : (
        <TicketFilters filters={filters} onChange={setFilters} />
      )}

      {buildingPlan && <PlanBuildingLoader className="mb-3" />}

      {planMode ? (
        // Planning: show ONLY the proposed (dimmed) plan — old tickets are hidden.
        // While still building, the loader above is the sole content. The rows use
        // the same TicketRow as the real list, in its `proposed` variant.
        ghostTickets.length > 0 ? (
          <div className="space-y-2">
            {ghostTickets.map((g, i) => (
              <TicketRow
                key={`ghost-${i}`}
                proposed
                ticket={{
                  display_title: g.title,
                  status: 'ideation',
                  priority: g.priority,
                  creative_type: g.creative_type,
                  channels: g.channels,
                  scheduled_at: g.scheduled_at,
                }}
              />
            ))}
          </div>
        ) : null
      ) : tickets.length === 0 ? (
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
            description="Crie o primeiro ticket deste projeto para começar a produção."
            action={<Button onClick={() => setTicketOpen(true)}><Plus size={16} /> Novo ticket</Button>}
          />
        )
      ) : (
        <div className="space-y-2">
          {tickets.map((t) => (
            <TicketRow
              key={t.id}
              ticket={t}
              manager={manager}
              busy={archive.isPending || unarchive.isPending}
              selected={selection.has(t.id)}
              onToggleSelect={selection.toggle}
              onOpen={setDrawerId}
              onArchive={(tid) => archive.mutate(tid)}
              onUnarchive={(tid) => unarchive.mutate(tid)}
            />
          ))}
        </div>
      )}

      <TicketDrawer
        ticketId={drawerId}
        open={!!drawerId}
        onOpenChange={(o) => { if (!o) setDrawerId(null) }}
      />

      <NewTicketDialog
        open={ticketOpen}
        onOpenChange={setTicketOpen}
        create={create}
        defaultProjectId={project.id}
      />

      {project.id && (
        <ProjectFormDialog open={editOpen} onOpenChange={setEditOpen} project={project} />
      )}

      {project.id && (
        <SendScopeDialog open={scopeOpen} onOpenChange={setScopeOpen} project={project} mutation={sendScope} />
      )}

      {project.id && (
        <InvoiceFormDialog
          open={billingOpen}
          onOpenChange={setBillingOpen}
          initialClientId={project.client_id}
          initialProjectIds={[project.id]}
        />
      )}

      {project.id && (
        <StrategyDrawer
          open={strategyOpen}
          onOpenChange={setStrategyOpen}
          projectId={project.id}
          session={strategySession}
          onProposalChange={setProposedPlan}
          onGeneratingChange={setGenerating}
        />
      )}

      <ConfirmDialog
        open={confirmDeleteOpen}
        onOpenChange={setConfirmDeleteOpen}
        icon={Trash2}
        destructive
        title={selection.count === 1 ? 'Excluir ticket?' : `Excluir ${selection.count} tickets?`}
        description="Esta ação é permanente e não pode ser desfeita. Os tickets e todo o seu conteúdo (subtarefas, criativos, posts) serão removidos."
        confirmLabel="Excluir"
        loading={bulkDelete.isPending}
        onConfirm={confirmBulkDelete}
      />
    </Page>
  )
}
