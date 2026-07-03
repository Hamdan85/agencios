import { useLocation, useNavigate } from 'react-router-dom'
import {
  Maximize2, X, ArrowRight, ChevronDown, Layers, Folder, Building2, Ghost,
} from 'lucide-react'
import { useTicket, useTicketMutations } from '@/hooks/useTicket'
import { useTicketChannel } from '@/hooks/useRealtime'
import { WORKFLOW, STATUS_META, statusMeta } from '@/lib/constants'
import { Sheet, SheetContent, SheetClose, SheetTitle } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { StatusPill } from '@/components/ui/iconography'
import { ColorBadge } from '@/components/ui/badge'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel,
} from '@/components/ui/dropdown-menu'
import StatusStepper from './StatusStepper'
import TicketBody from './TicketBody'
import AutopilotButton from './AutopilotButton'
import TicketActionsMenu from './TicketActionsMenu'

// The board side drawer: a near-complete, mobile-friendly mirror of the ticket
// detail screen. The header carries an "Abrir tela cheia" action that hands off
// to the full /tickets/:id page.
export default function TicketDrawer({ ticketId, open, onOpenChange, showAutopilot = false }) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent aria-describedby={undefined}>
        {ticketId ? (
          <DrawerContent id={String(ticketId)} onOpenChange={onOpenChange} showAutopilot={showAutopilot} />
        ) : (
          <SheetTitle className="sr-only">Ticket</SheetTitle>
        )}
      </SheetContent>
    </Sheet>
  )
}

function DrawerContent({ id, onOpenChange, showAutopilot }) {
  const navigate = useNavigate()
  const location = useLocation()
  const { data, isLoading } = useTicket(id)
  const mut = useTicketMutations(id)
  useTicketChannel(id)

  const ticket = data?.ticket
  const status = ticket?.status
  const m = statusMeta(status)
  const nextStatus = ticket?.next_status
  const nextMeta = nextStatus ? STATUS_META[nextStatus] : null

  const expand = () => {
    onOpenChange?.(false)
    // Hand the full page the real origin (board / list / calendar / campaign),
    // minus the ?ticket= param so "back" doesn't re-open the drawer.
    const sp = new URLSearchParams(location.search)
    sp.delete('ticket')
    const qs = sp.toString()
    navigate(`/tickets/${id}`, { state: { from: `${location.pathname}${qs ? `?${qs}` : ''}` } })
  }

  const jumpTo = (toStatus) => {
    if (!status || toStatus === status) return
    mut.advance.mutate({ toStatus })
  }

  return (
    <>
      {/* ── Sticky header ── */}
      <div className="shrink-0 border-b border-border bg-surface/85 px-5 pb-4 pt-4 backdrop-blur">
        <div className="mb-3 flex items-center justify-between">
          <Button variant="ghost" size="sm" onClick={expand} className="-ml-2 hidden text-ink-secondary md:inline-flex">
            <Maximize2 size={15} /> Abrir tela cheia
          </Button>
          <div className="ml-auto flex items-center gap-1">
            {ticket && (
              <TicketActionsMenu
                ticket={ticket}
                mut={mut}
                size="icon-sm"
                variant="ghost"
                hasScheduledPosts={(data?.posts || []).some((p) => p.status === 'scheduled')}
                onDeleted={() => onOpenChange?.(false)}
              />
            )}
            <SheetClose asChild>
              <Button variant="ghost" size="icon-sm" aria-label="Fechar">
                <X size={18} />
              </Button>
            </SheetClose>
          </div>
        </div>

        {isLoading || !ticket ? (
          <SheetTitle className="text-lg font-bold">
            {isLoading ? 'Carregando ticket…' : 'Ticket não encontrado'}
          </SheetTitle>
        ) : (
          <>
            <div className="mb-2 flex flex-wrap items-center gap-2">
              {/* The campaign chip stays a single line — long names truncate with
                  an ellipsis instead of wrapping the badge across lines. */}
              {ticket.project && (
                <ColorBadge color={ticket.project.color || m.color} solid className="max-w-[60vw] gap-1.5 sm:max-w-60">
                  <Folder size={11} className="shrink-0" /> <span className="min-w-0 truncate">{ticket.project.name}</span>
                </ColorBadge>
              )}
              {ticket.project?.client_name && (
                <span className="inline-flex items-center gap-1 text-xs font-semibold text-ink-muted">
                  <Building2 size={12} /> {ticket.project.client_name}
                </span>
              )}
              <StatusPill status={status} size="sm" />
            </div>

            <SheetTitle className="text-xl font-extrabold leading-tight">
              {ticket.display_title || ticket.title}
            </SheetTitle>

            <div className="mt-3 flex w-full items-center gap-2 sm:w-auto sm:flex-wrap">
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="outline" size="sm" disabled={mut.advance.isPending} className="shrink-0" aria-label="Mover etapa">
                    <Layers size={14} /> <span className="hidden sm:inline">Mover etapa</span> <ChevronDown size={13} className="hidden sm:inline" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="start" className="min-w-52">
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

              {/* GO mode — only where the drawer opts in (board), and only on
                  auto-generatable tickets not yet scheduled. Hidden in the
                  project's ticket drawer. */}
              {showAutopilot && (ticket.autopilot_run?.active ||
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

              {/* Advance — always the rightmost action; fills the row on mobile. */}
              {nextStatus && nextMeta && (
                <Button
                  size="sm"
                  onClick={() => mut.advance.mutate({ toStatus: nextStatus })}
                  disabled={mut.advance.isPending}
                  style={{ background: `linear-gradient(135deg, ${nextMeta.color}, ${nextMeta.color}cc)` }}
                  className="min-w-0 flex-1 justify-center text-white shadow-[0_8px_20px_-8px_rgba(0,0,0,0.4)] hover:brightness-105 sm:flex-none"
                >
                  <span className="truncate">Avançar para {nextMeta.label}</span>
                  <ArrowRight size={14} className="shrink-0" />
                </Button>
              )}
            </div>
          </>
        )}
      </div>

      {/* ── Scrollable body ── */}
      <div className="scrollbar-subtle min-h-0 flex-1 overflow-y-auto px-5 py-5">
        {isLoading ? (
          <div className="flex justify-center py-20"><Spinner size={28} /></div>
        ) : !ticket ? (
          <EmptyState
            icon={Ghost}
            title="Ticket não encontrado"
            description="Este ticket pode ter sido removido ou você não tem acesso a ele."
          />
        ) : (
          <div className="space-y-5">
            <StatusStepper status={status} onJump={jumpTo} busy={mut.advance.isPending} />
            <TicketBody
              compact
              id={id}
              status={status}
              ticket={ticket}
              subtasks={data?.subtasks || []}
              creatives={data?.creatives || []}
              attachments={data?.attachments || []}
              posts={data?.posts || []}
              notes={data?.notes || []}
              mut={mut}
            />
          </div>
        )}
      </div>
    </>
  )
}
