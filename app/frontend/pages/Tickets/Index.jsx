import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { KanbanSquare, Plus } from 'lucide-react'
import { useUrlFilters, useUrlParam } from '@/hooks/useUrlState'
import { useBoardMutations } from '@/hooks/useBoard'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { PageShell, PageTitle, PageContent } from '@/components/ui/page'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { BoardFilters } from '@/components/board/BoardFilters'
import { NewTicketDialog } from '@/components/board/NewTicketDialog'
import TicketDrawer from '@/components/ticket/LazyTicketDrawer'
import BoardView from './views/BoardView'
import ListView from './views/ListView'

const BRAND = '#EC4899'

// Every filter both views understand, shared through the URL so switching
// between Quadro and Lista keeps the selection (?visao=lista&project_id=…).
// status / priority / view are list-only; the board ignores them.
const FILTER_KEYS = ['q', 'project_id', 'client_id', 'assignee_id', 'status', 'channel', 'creative_type', 'priority', 'view']

// The single tickets page: one fixed title band (header + view tabs + new-ticket
// action) over one content band that renders as a Kanban board (?visao=quadro,
// the default) or a flat list (?visao=lista). Only the content band changes
// shape between views — the title stays put, and the swap cross-fades — so the
// tabs never move under the cursor and the filters don't appear to jump.
export default function TicketsHub() {
  const [searchParams, setSearchParams] = useSearchParams()
  const visao = searchParams.get('visao') === 'lista' ? 'lista' : 'quadro'
  const isQuadro = visao === 'quadro'

  const [filters, setFilters] = useUrlFilters(FILTER_KEYS)
  const [drawerTicketId, setDrawerTicketId] = useUrlParam('ticket')
  const [dialogOpen, setDialogOpen] = useState(false)
  // The filters live in the fixed title band. The board's filter bar is driven
  // straight from hub state, so it renders here directly; the list's toolbar is
  // coupled to the list's own selection/total, so ListView portals it into this
  // slot instead of lifting all that state up.
  const [filtersSlot, setFiltersSlot] = useState(null)
  const { create } = useBoardMutations()

  const setVisao = (v) => {
    setSearchParams(
      (prev) => {
        const sp = new URLSearchParams(prev)
        if (v === 'lista') {
          sp.set('visao', v)
        } else {
          sp.delete('visao')
          // status / priority / view are list-only — the board expresses the
          // status through its columns and has no archived/priority filters.
          // Drop them so the URL reflects the filters actually in effect.
          sp.delete('status')
          sp.delete('priority')
          sp.delete('view')
        }
        return sp
      },
      { replace: true },
    )
  }

  return (
    <PageShell className="animate-rise">
      {/* ── Fixed title band — header + view tabs + new-ticket, then the filters.
          Constant respiro gutter (like every page's title); the whole band stays
          put and always visible while the content varies/scrolls beneath. ── */}
      <PageTitle className="pb-4">
        <PageHeader
          className="mb-0"
          actionsClassName="max-sm:w-full"
          eyebrow="Operação"
          title="Tickets"
          icon={KanbanSquare}
          color={BRAND}
          description="O funil de produção da agência, da ideia ao arquivo."
          actions={
            // Mobile: one continuous control row — the view tabs stretch to meet
            // the button instead of the two sitting at opposite screen edges.
            <div className="flex w-full items-center gap-2 sm:w-auto">
              <Tabs value={visao} onValueChange={setVisao} className="min-w-0 flex-1 sm:flex-none">
                <TabsList className="w-full sm:w-auto">
                  <TabsTrigger value="quadro" className="flex-1 sm:flex-none">Quadro</TabsTrigger>
                  <TabsTrigger value="lista" className="flex-1 sm:flex-none">Lista</TabsTrigger>
                </TabsList>
              </Tabs>
              <Button onClick={() => setDialogOpen(true)} className="shrink-0">
                <Plus size={18} /> Novo ticket
              </Button>
            </div>
          }
        />
        {/* Filters slot: board filters render straight in; the list portals its
            toolbar here (see ListView). */}
        <div ref={setFiltersSlot} className="mt-5">
          {isQuadro && <BoardFilters filters={filters} onChange={setFilters} />}
        </div>
      </PageTitle>

      {/* ── Content band — just the board/list. Owns the per-view width/padding;
          when it scrolls (list), the scrollbar sits at the screen edge and the
          content is an inner container that expands to fill it. `key={visao}`
          remounts it on a view switch so it cross-fades in at its new shape. ── */}
      <PageContent
        key={visao}
        wide={isQuadro}
        flush={isQuadro}
        scroll={!isQuadro}
        className="animate-rise pt-1"
      >
        {isQuadro ? (
          <BoardView
            filters={filters}
            onOpenTicket={setDrawerTicketId}
            onNewTicket={() => setDialogOpen(true)}
          />
        ) : (
          <ListView
            filters={filters}
            setFilters={setFilters}
            filtersSlot={filtersSlot}
            onOpenTicket={setDrawerTicketId}
            onNewTicket={() => setDialogOpen(true)}
          />
        )}
      </PageContent>

      <NewTicketDialog open={dialogOpen} onOpenChange={setDialogOpen} create={create} />

      <TicketDrawer
        ticketId={drawerTicketId}
        open={!!drawerTicketId}
        showAutopilot
        onOpenChange={(o) => { if (!o) setDrawerTicketId(null, { replace: true }) }}
      />
    </PageShell>
  )
}
