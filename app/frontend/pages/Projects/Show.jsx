import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowLeft, Wallet, CalendarRange, ListChecks, KanbanSquare, Pencil, Building2,
  FileText, CheckCircle2, Play, Plus, Sparkles, MoreHorizontal, Archive, ArchiveRestore,
  Trash2, Receipt, Send, AlertTriangle, Target, Eye, Heart, FolderKanban, Settings,
} from 'lucide-react'
import {
  useProject, useProjectMutations, useTicketArchiveMutations, useTicketBulkDelete,
  useReport, useWorkspaceMembers,
} from '@/hooks/useData'
import { useStrategySession, useStrategyPlan, useApplyStrategy, useDiscardStrategy } from '@/hooks/useStrategy'
import { useUrlFilters, useUrlParam } from '@/hooks/useUrlState'
import { useCurrentUser } from '@/hooks/useAuth'
import { useSelection } from '@/hooks/useSelection'
import { canManage } from '@/lib/roles'
import { StrategyDrawer } from '@/components/project/StrategyDrawer'
import { PlanBuildingLoader } from '@/components/project/PlanBuildingLoader'
import { ProjectFormDialog } from '@/components/project/ProjectFormDialog'
import ProjectSettingsTab from '@/components/project/ProjectSettingsTab'
import { SendScopeDialog } from '@/components/project/SendScopeDialog'
import AutopilotButton from '@/components/ticket/AutopilotButton'
import { InvoiceFormDialog } from '@/components/billing/InvoiceFormDialog'
import { ticketsApi } from '@/api'
import analytics, { EVENTS } from '@/lib/analytics'
import { invalidateTicketSurfaces } from '@/hooks/data/shared'
import { PageLoader, EmptyState, InlineSpinner } from '@/components/ui/feedback'
import { Button } from '@/components/ui/button'
import { Badge, ColorBadge } from '@/components/ui/badge'
import { IconTile } from '@/components/ui/icon-tile'
import { Card } from '@/components/ui/card'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
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
  active: { label: 'Ativa', variant: 'success' },
  paused: { label: 'Pausada', variant: 'warning' },
  archived: { label: 'Arquivada', variant: 'muted' },
  completed: { label: 'Finalizada', variant: 'soft' },
}

// Ticket filters live in the URL (?status=…&channel=…&q=…) so a project's
// filtered view is shareable / reload-safe. Stable reference — see useUrlFilters.
const FILTER_KEYS = ['q', 'status', 'assignee_id', 'channel', 'creative_type']

// A proposed (ghost) ticket row — the dimmed `proposed` variant of TicketRow fed
// from a plan card. Shared by the full-plan preview and the additive/ops rows
// (create = new piece, update = edit of a real ticket, remove = its removal).
function GhostTicketRow({ g }) {
  return (
    <TicketRow
      proposed
      state={g.state}
      op={g.op || 'create'}
      ticket={{
        display_title: g.title,
        status: 'ideation',
        priority: g.priority,
        creative_type: g.creative_type,
        channels: g.channels,
        scheduled_at: g.scheduled_at,
      }}
    />
  )
}

// Live progress of a project-level "GO mode" run: how far the batch has walked
// its tickets. Rendered only while a batch is active; refreshes off the board
// channel (autopilot_batch_started / step / completed → invalidate `projects`).
function AutopilotProgress({ batch }) {
  if (!batch) return null
  const total = batch.total || 0
  const done = Math.min(batch.done || 0, total)
  const pct = total ? Math.round((done / total) * 100) : 0
  const failed = batch.failed || 0
  return (
    <div className="mb-6 rounded-2xl border border-brand/25 bg-brand-soft/40 p-4">
      <div className="mb-2.5 flex flex-wrap items-center justify-between gap-2">
        <span className="inline-flex items-center gap-2 text-sm font-bold text-brand">
          <InlineSpinner size={15} /> Piloto automático em andamento
        </span>
        <span className="text-xs font-semibold text-ink-secondary">
          {done} de {total} {total === 1 ? 'ticket' : 'tickets'}
          {failed > 0 && (
            <span className="ml-2 inline-flex items-center gap-1 text-danger">
              <AlertTriangle size={12} /> {failed} com falha
            </span>
          )}
        </span>
      </div>
      <div className="h-2.5 w-full overflow-hidden rounded-full bg-brand/15">
        <div
          className="h-full rounded-full transition-all duration-500 ease-out"
          style={{ width: `${pct}%`, background: 'linear-gradient(135deg, #7C3AED, #EC4899)' }}
        />
      </div>
    </div>
  )
}

const TAB_TO_SEG = { tickets: '', config: 'configuracoes' }
const SEG_TO_TAB = { configuracoes: 'config' }

export default function ProjectShow() {
  const { id, tab: seg } = useParams()
  const navigate = useNavigate()
  const tab = SEG_TO_TAB[seg] || 'tickets'
  const setTab = (value) => {
    const s = TAB_TO_SEG[value] || ''
    navigate(`/campanhas/${id}${s ? `/${s}` : ''}`, { replace: true })
  }
  const qc = useQueryClient()
  const [filters, setFilters] = useUrlFilters(FILTER_KEYS)
  const [drawerId, setDrawerId] = useUrlParam('ticket')
  const [ticketOpen, setTicketOpen] = useState(false)
  const [strategyOpen, setStrategyOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [billingOpen, setBillingOpen] = useState(false)
  const [scopeOpen, setScopeOpen] = useState(false)
  const { data, isLoading } = useProject(id, filters)
  const { data: latestReport } = useReport(data?.project?.latest_report_id)
  const { data: strategySession } = useStrategySession(id)
  // The live proposed plan (cards) + build/revise signals — owned here so the table
  // fills in live from the channel whether the chat is open or not.
  const { cards, creating, generating, additive } = useStrategyPlan(id, strategySession)
  const applyStrategy = useApplyStrategy(id)
  const discardStrategy = useDiscardStrategy(id)
  const { start, finalize, update, destroy, sendScope, autopilotEstimate, autopilot } = useProjectMutations()
  const { archive, unarchive, assign } = useTicketArchiveMutations()
  const { data: members } = useWorkspaceMembers()
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

  // Opened straight from project creation (…/campanhas/:id?planejar=1) → jump into
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
      invalidateTicketSurfaces(qc, { projects: true })
      analytics.track(EVENTS.TICKET_CREATED)
      toast.success('Ticket criado!')
    },
    onError: (err) => toast.error(err?.error || 'Erro ao criar ticket.'),
  })

  if (isLoading) return <PageLoader />

  const project = data?.project || {}
  const tickets = data?.tickets || project?.tickets || []
  // The project-level GO run, if one is walking the tickets right now (null once
  // it stops — completed / failed / cancelled — so the GO button comes back).
  const autopilotBatch = data?.autopilot || null
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
  // Ghost rows preview the plan ONLY while the chat is open (§ visibility rule) —
  // a proposed plan with the chat closed shows the real tickets, with the banner
  // below to reopen/approve. The cards come live from useStrategyPlan.
  const planActive = creating || generating // a build/revise is in flight
  const showGhosts = strategyOpen && (planActive || strategySession?.status === 'proposed')
  const ghostTickets = showGhosts ? cards : []
  // A full plan hides the real tickets so the preview (or its loader) stands alone;
  // an ADDITIVE proposal instead shows the new ghosts BESIDE the existing tickets.
  const planMode = showGhosts && !additive
  // New ghost rows to append below the real tickets (additive proposal).
  const additiveGhosts = showGhosts && additive && ghostTickets.length > 0
  // Staged edits/removals target REAL tickets (op cards carry `ticket_id`); map
  // them so each affected real row is dimmed + badged, paired with its ghost.
  const pendingByTicket = {}
  if (additiveGhosts) {
    ghostTickets.forEach((g) => {
      if (g.op === 'remove') pendingByTicket[g.ticket_id] = 'remove'
      else if (g.op === 'update') pendingByTicket[g.ticket_id] = 'edit'
    })
  }
  // The table-level loader is EPHEMERAL: only between "vou começar" and the first
  // skeleton rows landing (plan_started → plan_outline).
  const tableLoading = strategyOpen && creating
  // A proposed plan awaiting a decision with the planner closed → banner to review.
  const pendingReview = !strategyOpen && strategySession?.status === 'proposed'
  const persistedPlan = strategySession?.status === 'proposed' ? strategySession.proposed_plan : null
  const persistedAdditive = persistedPlan?.mode === 'append'
  // An additive plan can mix creates/edits/removals — summarize what applying does.
  const opsSummary = (() => {
    if (!persistedAdditive) return null
    const t = persistedPlan.tickets || []
    const n = (op) => t.filter((c) => (c.op || 'create') === op).length
    return [[n('create'), 'a adicionar'], [n('update'), 'a editar'], [n('remove'), 'a remover']]
      .filter(([c]) => c > 0).map(([c, label]) => `${c} ${label}`).join(' · ')
  })()
  const hasRemoval = persistedAdditive && (persistedPlan.tickets || []).some((c) => c.op === 'remove')

  const handleStart = () => start.mutate(id)

  const handleFinalize = async () => {
    const ok = await confirm({
      title: 'Finalizar campanha?',
      description: 'Vamos encerrar a campanha e gerar o relatório de auditoria com o resumo da produção.',
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
      { onSuccess: () => toast.success(isArchived ? 'Campanha reativada.' : 'Campanha arquivada.') },
    )
  }

  const handleDelete = async () => {
    const ok = await confirm({
      title: 'Excluir campanha?',
      description: 'Isso remove a campanha e todos os seus tickets. Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir campanha',
      destructive: true,
    })
    if (!ok) return
    destroy.mutate(id, { onSuccess: () => navigate('/campanhas') })
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
      <Link to="/campanhas" className="mb-5 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
        <ArrowLeft size={16} /> Campanhas
      </Link>

      {/* Hero */}
      <Card className="mb-6 overflow-hidden">
        <div className="h-2.5 w-full" style={{ background: color }} />
        <div className="flex flex-col gap-4 p-5 sm:flex-row sm:flex-wrap sm:items-start sm:justify-between sm:p-6">
          <div className="flex items-start gap-4">
            <IconTile icon={KanbanSquare} color={color} tint="1A" iconSize={26} className="sm:size-14" />
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="font-display text-xl font-extrabold tracking-tight text-ink sm:text-2xl">{project.name || 'Campanha'}</h1>
                <Badge variant={st.variant}>{st.label}</Badge>
                {reportGenerating && (
                  <Badge variant="soft"><InlineSpinner size={11} /> Gerando auditoria…</Badge>
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
              <Button className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Iniciar campanha" onClick={handleStart} disabled={start.isPending}>
                <Play size={16} /> <span className="hidden sm:inline">Iniciar campanha</span>
              </Button>
            )}
            {!isCompleted && (
              <AutopilotButton
                run={autopilotBatch}
                estimating={autopilotEstimate.isPending}
                starting={autopilot.isPending}
                onEstimate={() => autopilotEstimate.mutateAsync(id).then((d) => d?.estimate)}
                onStart={() => autopilot.mutate({ id, payload: { mode: 'scheduled' } })}
              />
            )}
            {!isCompleted && !isDraft && (
              <Button className="w-10 justify-center px-0 sm:w-auto sm:justify-start sm:px-4" aria-label="Finalizar campanha" onClick={handleFinalize} disabled={finalize.isPending}>
                <CheckCircle2 size={16} /> <span className="hidden sm:inline">Finalizar campanha</span>
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
          <ColorBadge color={color} tint="14" className="px-3 py-1.5 text-sm">
            <ListChecks size={15} /> {project.tickets_count ?? tickets.length} tickets
          </ColorBadge>
          {project.budget_cents != null && (
            <Badge variant="success" className="gap-1.5 px-3 py-1.5 text-sm tracking-normal">
              <Wallet size={15} /> {brl(project.budget_cents)}
            </Badge>
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

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="mb-5">
          <TabsTrigger value="tickets"><FolderKanban size={15} /> Tickets</TabsTrigger>
          <TabsTrigger value="config"><Settings size={15} /> Configurações</TabsTrigger>
        </TabsList>
        <TabsContent value="tickets" className="animate-rise">

      {/* GO mode walking the project — live progress bar (hides while none runs). */}
      <AutopilotProgress batch={autopilotBatch} />

      {/* A proposed plan is waiting (survived a reload) — review / apply / discard. */}
      {pendingReview && (
        <div className="mb-4 flex flex-col gap-3 rounded-2xl border border-brand/30 bg-brand-soft/40 p-4 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
          <div className="flex items-center gap-2.5">
            <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-soft text-brand">
              <Sparkles size={18} strokeWidth={2.3} />
            </span>
            <div>
              <p className="text-sm font-semibold text-ink">
                {persistedAdditive
                  ? `Alterações propostas · ${opsSummary || 'nenhuma'}`
                  : `Plano proposto pronto · ${persistedPlan.tickets.length} tickets`}
              </p>
              <p className="text-xs text-ink-muted">
                {persistedAdditive
                  ? (hasRemoval ? 'Revise no chat ou aplique — inclui remoção de ticket.' : 'Revise no chat ou aplique à campanha.')
                  : 'Revise no chat ou aplique para criar os tickets.'}
              </p>
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

      {tableLoading && <PlanBuildingLoader className="mb-3" />}

      {planMode ? (
        // Planning: show ONLY the proposed (dimmed) plan — old tickets are hidden.
        // While the batch is still building, the loader above is the sole content.
        // Rows use the same TicketRow, in its `proposed` variant, with a per-card
        // `state` (drafting = skeleton, revising = glow) driven live by the channel.
        ghostTickets.length > 0 ? (
          <div className="space-y-2">
            {ghostTickets.map((g, i) => <GhostTicketRow key={g.key || `ghost-${i}`} g={g} />)}
          </div>
        ) : null
      ) : tickets.length === 0 && !additiveGhosts ? (
        hasFilters ? (
          <EmptyState
            icon={ListChecks}
            color={color}
            title="Nenhum ticket corresponde aos filtros"
            description="Ajuste ou limpe os filtros para ver mais tickets desta campanha."
            action={<Button variant="outline" onClick={() => setFilters({})}>Limpar filtros</Button>}
          />
        ) : (
          <EmptyState
            icon={KanbanSquare}
            color={color}
            title="Sem tickets nesta campanha"
            description="Crie o primeiro ticket desta campanha para começar a produção."
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
              pendingChange={pendingByTicket[t.id] || null}
              members={members}
              onAssign={(tid, assigneeId) => assign.mutate({ id: tid, assigneeId })}
            />
          ))}
          {/* Additive proposal: NEW pieces (create) and EDITS (update, shown as the
              proposed "after") sit below the real ones, dimmed, awaiting approval.
              Removals aren't repeated here — their real row above is already flagged. */}
          {additiveGhosts && ghostTickets.filter((g) => g.op !== 'remove').map((g, i) => (
            <GhostTicketRow key={g.key || `ghost-${i}`} g={g} />
          ))}
        </div>
      )}
        </TabsContent>
        <TabsContent value="config" className="animate-rise">
          <ProjectSettingsTab project={project} />
        </TabsContent>
      </Tabs>

      <TicketDrawer
        ticketId={drawerId}
        open={!!drawerId}
        onOpenChange={(o) => { if (!o) setDrawerId(null, { replace: true }) }}
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
          cards={cards}
          generating={generating}
          additive={additive}
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
