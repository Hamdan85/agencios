import { useMemo } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { useTicket, useTicketMutations } from '@/hooks/useTicket'
import { useTicketChannel } from '@/hooks/useRealtime'
import { WORKFLOW, STATUS_META, statusMeta } from '@/lib/constants'
import { Button } from '@/components/ui/button'
import { StatusPill } from '@/components/ui/iconography'
import { ColorBadge } from '@/components/ui/badge'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel,
} from '@/components/ui/dropdown-menu'
import StatusStepper from '@/components/ticket/StatusStepper'
import TicketBody from '@/components/ticket/TicketBody'
import AutopilotButton from '@/components/ticket/AutopilotButton'
import TicketActionsMenu from '@/components/ticket/TicketActionsMenu'
import {
  ArrowLeft, ArrowRight, ChevronDown, Building2, Ghost, Folder, Layers, AlertTriangle, Archive,
} from 'lucide-react'

export default function Show() {
  const { id, tab } = useParams()
  const navigate = useNavigate()
  const location = useLocation()

  const { data, isLoading } = useTicket(id)
  const mut = useTicketMutations(id)
  useTicketChannel(id)

  const ticket = data?.ticket
  const subtasks = data?.subtasks || []
  const creatives = data?.creatives || []
  const attachments = data?.attachments || []
  const posts = data?.posts || []
  const notes = data?.notes || []

  const status = ticket?.status
  const m = useMemo(() => statusMeta(status), [status])
  const nextStatus = ticket?.next_status
  const nextMeta = nextStatus ? STATUS_META[nextStatus] : null

  // Return to wherever the ticket was opened from (tickets hub, calendar or
  // campaign); fall back to the tickets hub.
  const back = useMemo(() => {
    const from = location.state?.from
    if (from?.startsWith('/campanhas/')) return { to: from, label: 'Voltar à campanha' }
    if (from?.startsWith('/calendario') || from?.startsWith('/meu-calendario')) return { to: from, label: 'Voltar ao calendário' }
    if (from?.startsWith('/tickets')) return { to: from, label: 'Voltar aos tickets' }
    if (from) return { to: from, label: 'Voltar' }
    return { to: '/tickets', label: 'Voltar aos tickets' }
  }, [location.state])

  if (isLoading) return <PageLoader />
  if (!ticket) {
    return (
      <Page>
        <EmptyState
          icon={Ghost}
          title="Ticket não encontrado"
          description="Este ticket pode ter sido removido ou você não tem acesso a ele."
          action={<Button asChild><Link to={back.to}>{back.label}</Link></Button>}
        />
      </Page>
    )
  }

  const jumpTo = (toStatus) => {
    if (toStatus === status) return
    mut.advance.mutate({ toStatus })
  }

  return (
    // w-full pins this column flex-item to the layout's content width. Without a
    // definite width it sizes to its content's max-content, and the
    // StatusStepper's horizontal-scroll row then widens the whole page (mobile
    // horizontal scroll). With w-full the page stays at the viewport width and
    // the stepper scrolls inside its own card instead.
    <Page className="animate-rise">
      {/* ── Top bar ── */}
      <div className="mb-5">
        <Link to={back.to} className="mb-3 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
          <ArrowLeft size={15} /> {back.label}
        </Link>

        <div className="flex flex-col gap-4 sm:flex-row sm:flex-wrap sm:items-start sm:justify-between">
          <div className="min-w-0">
            <div className="mb-2 flex flex-wrap items-center gap-2">
              {ticket.project && (
                <Link to={`/campanhas/${ticket.project.id}`} className="min-w-0 max-w-[60vw] sm:max-w-60">
                  <ColorBadge color={ticket.project.color || m.color} solid className="max-w-full gap-1.5 lift">
                    <Folder size={11} className="shrink-0" /> <span className="truncate">{ticket.project.name}</span>
                  </ColorBadge>
                </Link>
              )}
              {ticket.project?.client_name && (
                ticket.project.client_id ? (
                  <Link
                    to={`/clientes/${ticket.project.client_id}`}
                    className="inline-flex items-center gap-1 text-xs font-semibold text-ink-muted transition hover:text-brand"
                  >
                    <Building2 size={12} /> {ticket.project.client_name}
                  </Link>
                ) : (
                  <span className="inline-flex items-center gap-1 text-xs font-semibold text-ink-muted">
                    <Building2 size={12} /> {ticket.project.client_name}
                  </span>
                )
              )}
              <StatusPill status={status} size="sm" />
              {ticket.archived && (
                <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide text-ink-muted">
                  <Archive size={11} strokeWidth={2.4} /> Arquivado
                </span>
              )}
              {ticket.overdue && (
                <span className="inline-flex items-center gap-1 rounded-full bg-danger/12 px-2 py-0.5 text-[11px] font-bold text-danger">
                  <AlertTriangle size={12} strokeWidth={2.4} /> Atrasado
                </span>
              )}
            </div>
            <h1 className="font-display text-[22px] font-extrabold leading-tight tracking-tight text-ink sm:text-[30px]">
              {ticket.display_title || ticket.title}
            </h1>
          </div>

          <div className="flex w-full items-center gap-2 sm:w-auto sm:flex-wrap">
            {/* Status jump */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="default" disabled={mut.advance.isPending} className="shrink-0" aria-label="Mover etapa">
                  <Layers size={15} /> <span className="hidden sm:inline">Mover etapa</span> <ChevronDown size={14} className="hidden sm:inline" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-52">
                <DropdownMenuLabel>Ir para a etapa</DropdownMenuLabel>
                {WORKFLOW.map((key) => {
                  const sm = STATUS_META[key]
                  const Icon = sm.icon
                  const active = key === status
                  return (
                    <DropdownMenuItem
                      key={key}
                      disabled={active}
                      onClick={() => jumpTo(key)}
                      className={active ? 'opacity-60' : ''}
                    >
                      <span className="flex size-5 items-center justify-center rounded-md" style={{ background: `${sm.color}1A`, color: sm.color }}>
                        <Icon size={12} strokeWidth={2.5} />
                      </span>
                      <span className="font-semibold">{sm.label}</span>
                      {active && <span className="ml-auto text-[10px] font-bold uppercase text-ink-faint">atual</span>}
                    </DropdownMenuItem>
                  )
                })}
              </DropdownMenuContent>
            </DropdownMenu>

            {/* GO mode — shown on the ticket view page (and the board drawer),
                on auto-generatable tickets not yet scheduled. */}
            {(ticket.autopilot_run?.active ||
              (ticket.autopilot_eligible && ['ideation', 'scoping', 'production'].includes(status))) && (
              <span className="shrink-0">
                <AutopilotButton
                  run={ticket.autopilot_run}
                  estimating={mut.autopilotEstimate.isPending}
                  starting={mut.autopilot.isPending}
                  onEstimate={() => mut.autopilotEstimate.mutateAsync().then((d) => d?.estimate)}
                  onStart={() => mut.autopilot.mutate({ mode: 'scheduled' })}
                />
              </span>
            )}

            {/* Advance — always the rightmost action. Hidden on the posting step,
                where publishing (not a manual move) carries the ticket to "No ar". */}
            {nextStatus && nextMeta && status !== 'scheduled' && (
              <Button
                onClick={() => mut.advance.mutate({ toStatus: nextStatus })}
                disabled={mut.advance.isPending}
                style={{ background: `linear-gradient(135deg, ${nextMeta.color}, ${nextMeta.color}cc)` }}
                className="min-w-0 flex-1 justify-center text-white shadow-[0_8px_20px_-8px_rgba(0,0,0,0.4)] hover:brightness-105 sm:flex-none"
              >
                <span className="truncate">Avançar para {nextMeta.label}</span>
                <ArrowRight size={15} className="shrink-0" />
              </Button>
            )}

            {/* Archive / delete */}
            <TicketActionsMenu
              ticket={ticket}
              mut={mut}
              hasScheduledPosts={posts.some((p) => p.status === 'scheduled')}
              hasPublishedPosts={posts.some((p) => p.status === 'published')}
              onDeleted={() => navigate(back.to)}
            />
          </div>
        </div>
      </div>

      {/* ── Status stepper centerpiece ── */}
      <div className="mb-6">
        <StatusStepper status={status} onJump={jumpTo} busy={mut.advance.isPending} />
      </div>

      {/* ── Shared detail body (2-column on desktop, tabbed on mobile) ── */}
      <TicketBody
        id={id}
        status={status}
        ticket={ticket}
        subtasks={subtasks}
        creatives={creatives}
        attachments={attachments}
        posts={posts}
        notes={notes}
        mut={mut}
        tab={tab}
        onTabChange={(v) => navigate(`/tickets/${id}/${v === 'activity' ? 'atividade' : 'detalhes'}`, { replace: true })}
      />
    </Page>
  )
}
