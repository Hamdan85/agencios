import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Rows3, Archive, ArchiveRestore, MoreVertical, Ghost, CalendarClock,
} from 'lucide-react'
import {
  WORKFLOW, STATUS_META, CHANNEL_META, CREATIVE_TYPE_META, PRIORITY_META, statusMeta,
} from '@/lib/constants'
import { useTicketsList, useTicketArchiveMutations } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { canManage } from '@/lib/roles'
import { relativeDay } from '@/lib/formatters'
import { cn } from '@/lib/utils'
import { PageHeader } from '@/components/ui/page-header'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import { FilterBar } from '@/components/ui/filter-bar'
import { Page } from '@/components/ui/page'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import {
  StatusPill, StatusDot, CreativeTypeChip, ChannelIcons, PriorityDot,
} from '@/components/ui/iconography'
import { Avatar } from '@/components/ui/avatar'
import TicketDrawer from '@/components/ticket/TicketDrawer'

const BRAND = '#06B6D4'

// A single ticket row. Clicking the body opens the side drawer; the trailing
// menu archives / restores (managers only).
function TicketRow({ ticket, onOpen, manager, onArchive, onUnarchive, busy }) {
  const project = ticket.project
  const accent = project?.color || statusMeta(ticket.status).color
  const due = relativeDay(ticket.due_date)
  const tone = { danger: 'bg-danger/12 text-danger', warning: 'bg-amber/15 text-[#B45309]', muted: 'bg-surface-muted text-ink-muted' }

  return (
    <div className={cn(
      'group flex items-center gap-3 rounded-xl border border-border bg-surface px-3.5 py-2.5 transition-all',
      'hover:border-brand/40 hover:shadow-[0_10px_24px_-18px_rgba(24,18,43,0.32)]',
      ticket.archived && 'opacity-75',
    )}>
      <span className="hidden sm:block"><StatusDot status={ticket.status} size={9} /></span>

      <button onClick={() => onOpen(ticket.id)} className="flex min-w-0 flex-1 items-center gap-3 text-left">
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            <span className="truncate font-display text-[15px] font-semibold text-ink">{ticket.display_title}</span>
            {ticket.archived && (
              <span className="shrink-0 rounded-full bg-surface-muted px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-ink-muted">
                Arquivado
              </span>
            )}
          </span>
          <span className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[12px] font-medium text-ink-muted">
            {project && (
              <span className="inline-flex items-center gap-1 truncate" style={{ color: accent }}>
                <span className="size-1.5 rounded-full" style={{ background: accent }} />
                <span className="truncate">{project.name}</span>
              </span>
            )}
            {ticket.client?.name && <span className="truncate">· {ticket.client.name}</span>}
          </span>
        </span>
      </button>

      <div className="hidden items-center gap-1.5 md:flex">
        {ticket.creative_type && <CreativeTypeChip type={ticket.creative_type} />}
        {ticket.channels?.length > 0 && <ChannelIcons channels={ticket.channels} size={12} max={4} />}
      </div>

      {due && (
        <span className={cn('hidden items-center gap-1 rounded-md px-1.5 py-0.5 text-[10.5px] font-bold lg:inline-flex', tone[due.tone] || tone.muted)}>
          <CalendarClock size={11} strokeWidth={2.4} /> {due.text}
        </span>
      )}

      <span className="hidden xl:block"><StatusPill status={ticket.status} size="sm" /></span>
      <PriorityDot priority={ticket.priority} />
      {ticket.assignee
        ? <Avatar name={ticket.assignee.name} src={ticket.assignee.avatar_url} size={26} />
        : <span className="size-[26px] shrink-0 rounded-full border border-dashed border-border" />}

      {manager && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label="Ações do ticket"
              className="flex size-7 shrink-0 items-center justify-center rounded-md text-ink-muted transition hover:bg-surface-muted hover:text-ink focus:outline-none"
            >
              <MoreVertical size={16} />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-44">
            {ticket.archived ? (
              <DropdownMenuItem onClick={() => onUnarchive(ticket.id)} disabled={busy}>
                <ArchiveRestore size={15} /> Restaurar
              </DropdownMenuItem>
            ) : (
              <DropdownMenuItem onClick={() => onArchive(ticket.id)} disabled={busy}>
                <Archive size={15} /> Arquivar
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </div>
  )
}

export default function TicketsList() {
  const [filters, setFilters] = useState({ view: 'active' })
  const [drawerId, setDrawerId] = useState(null)

  const { data: me } = useCurrentUser()
  const manager = canManage(me?.membership?.role)
  const { archive, unarchive } = useTicketArchiveMutations()

  const query = useTicketsList(filters)
  const { data, isLoading, isError, hasNextPage, isFetchingNextPage, fetchNextPage, isFetching } = query

  const rows = useMemo(() => (data?.pages || []).flatMap((p) => p.tickets || []), [data])
  const total = data?.pages?.[0]?.meta?.total ?? 0

  const set = (key) => (value) => setFilters((f) => ({ ...f, [key]: value }))

  // Infinite scroll.
  const sentinelRef = useRef(null)
  useEffect(() => {
    const el = sentinelRef.current
    if (!el) return
    const io = new IntersectionObserver(
      (entries) => { if (entries[0].isIntersecting && hasNextPage && !isFetchingNextPage) fetchNextPage() },
      { rootMargin: '300px' },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [hasNextPage, isFetchingNextPage, fetchNextPage, rows.length])

  const statusOptions = WORKFLOW.map((k) => ({ value: k, label: STATUS_META[k].label, color: STATUS_META[k].color, icon: STATUS_META[k].icon }))
  const channelOptions = Object.entries(CHANNEL_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))
  const creativeOptions = Object.entries(CREATIVE_TYPE_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))
  const priorityOptions = Object.entries(PRIORITY_META).map(([k, m]) => ({ value: k, label: m.label, color: m.dot }))

  const filterKeys = ['project_id', 'client_id', 'assignee_id', 'status', 'channel', 'creative_type', 'priority']
  const activeCount = filterKeys.filter((k) => filters[k]).length + (filters.q ? 1 : 0)
  // Clear filters but keep the current tab (view) and the text search.
  const clearFilters = () => setFilters((f) => {
    const next = { ...f }
    filterKeys.forEach((k) => delete next[k])
    return next
  })

  const filterSpec = [
    { key: 'project_id', type: 'project', label: 'Projeto' },
    { key: 'client_id', type: 'client', label: 'Cliente' },
    { key: 'assignee_id', type: 'assignee', label: 'Responsável' },
    { key: 'status', type: 'options', label: 'Etapa', options: statusOptions },
    { key: 'channel', type: 'options', label: 'Canal', options: channelOptions },
    { key: 'creative_type', type: 'options', label: 'Tipo', options: creativeOptions },
    { key: 'priority', type: 'options', label: 'Prioridade', options: priorityOptions },
  ]

  return (
    <Page className="animate-rise">
      <PageHeader
        eyebrow="Operação"
        title="Tickets"
        icon={Rows3}
        color={BRAND}
        description="Todos os tickets do workspace em lista — busque, filtre e arquive."
      />

      {/* ── Toolbar: view tabs, then search + filters on one line ── */}
      <div className="mb-5 space-y-3">
        <Tabs value={filters.view} onValueChange={(v) => set('view')(v)}>
          <TabsList>
            <TabsTrigger value="active">Ativos</TabsTrigger>
            <TabsTrigger value="archived">Arquivados</TabsTrigger>
            <TabsTrigger value="all">Todos</TabsTrigger>
          </TabsList>
        </Tabs>
        <FilterBar
          search
          searchValue={filters.q || ''}
          onSearch={(v) => setFilters((f) => ({ ...f, q: v }))}
          searchPlaceholder="Buscar por título…"
          filters={filterSpec}
          values={filters}
          onChange={(key, value) => set(key)(value)}
          onClear={clearFilters}
          className="mb-0"
        />
      </div>

      {/* ── List ── */}
      {isLoading ? (
        <div className="flex justify-center py-24"><Spinner size={30} /></div>
      ) : isError ? (
        <EmptyState icon={Ghost} title="Erro ao carregar" description="Não foi possível carregar os tickets. Tente novamente." />
      ) : rows.length === 0 ? (
        <EmptyState
          icon={filters.view === 'archived' ? Archive : Rows3}
          color={BRAND}
          title={filters.view === 'archived' ? 'Nenhum ticket arquivado' : 'Nenhum ticket encontrado'}
          description={activeCount > 0 ? 'Ajuste os filtros para ver mais resultados.' : 'Os tickets criados no quadro aparecem aqui.'}
        />
      ) : (
        <>
          <p className="mb-2 px-1 text-[12px] font-semibold text-ink-muted">
            {total} ticket{total === 1 ? '' : 's'}
          </p>
          <div className="space-y-2">
            {rows.map((t) => (
              <TicketRow
                key={t.id}
                ticket={t}
                manager={manager}
                busy={archive.isPending || unarchive.isPending}
                onOpen={setDrawerId}
                onArchive={(id) => archive.mutate(id)}
                onUnarchive={(id) => unarchive.mutate(id)}
              />
            ))}
          </div>

          <div ref={sentinelRef} aria-hidden className="h-1" />
          {isFetchingNextPage && <div className="flex justify-center py-5"><Spinner size={20} /></div>}
          {!hasNextPage && rows.length > 8 && (
            <p className="py-5 text-center text-[12px] text-ink-faint">Fim da lista</p>
          )}
        </>
      )}

      <TicketDrawer
        ticketId={drawerId}
        open={!!drawerId}
        onOpenChange={(o) => { if (!o) setDrawerId(null) }}
      />
    </Page>
  )
}
