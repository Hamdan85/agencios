import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { Rows3, Archive, Ghost, Plus, Trash2 } from 'lucide-react'
import {
  WORKFLOW, STATUS_META, CHANNEL_META, CREATIVE_TYPE_META, PRIORITY_META,
} from '@/lib/constants'
import { toast } from 'sonner'
import { ticketsApi } from '@/api'
import { useTicketsList, useTicketArchiveMutations, useTicketBulkDelete } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { useSelection } from '@/hooks/useSelection'
import { canManage } from '@/lib/roles'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import { FilterBar } from '@/components/ui/filter-bar'
import { SelectionBar } from '@/components/ui/selection-bar'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Button } from '@/components/ui/button'
import TicketRow from '@/components/ticket/TicketRow'

const BRAND = '#EC4899'

// The list view of the tickets hub: every ticket of the workspace as rows —
// search, filter, bulk-select, archive. Filters come from the hub (they live in
// the URL, shared with the board view); the drawer also lives in the hub. The
// toolbar (view tabs + filter/selection bar) is portaled into `filtersSlot` — a
// node in the hub's fixed title band — so filters stay pinned while rows scroll.
export default function ListView({ filters, setFilters, filtersSlot, onOpenTicket, onNewTicket }) {
  // The list-only "view" tab (active | archived | all) defaults to active.
  const listFilters = useMemo(() => ({ view: 'active', ...filters }), [filters])

  const { data: me } = useCurrentUser()
  const manager = canManage(me?.membership?.role)
  const { archive, unarchive } = useTicketArchiveMutations()
  const bulkDelete = useTicketBulkDelete()
  const selection = useSelection()
  const [confirmOpen, setConfirmOpen] = useState(false)

  const query = useTicketsList(listFilters)
  const { data, isLoading, isError, hasNextPage, isFetchingNextPage, fetchNextPage } = query

  const rows = useMemo(() => (data?.pages || []).flatMap((p) => p.tickets || []), [data])
  const total = data?.pages?.[0]?.meta?.total ?? 0

  const set = (key) => (value) => setFilters((f) => ({ ...f, [key]: value }))

  // Reset the selection whenever the visible set changes (filters / tab / search)
  // so a bulk delete never hits tickets scrolled out of view.
  const { clear: clearSelection } = selection
  useEffect(() => { clearSelection() }, [JSON.stringify(listFilters), clearSelection])

  const confirmDelete = () => {
    bulkDelete.mutate(selection.list, {
      onSuccess: () => { selection.clear(); setConfirmOpen(false) },
    })
  }

  // Select-all spans the WHOLE filtered result set (not just loaded pages): fetch
  // every matching id from the server for the current filters.
  const selectAll = async () => {
    try {
      const { ids } = await ticketsApi.ids(listFilters)
      selection.set(ids)
    } catch {
      toast.error('Não foi possível selecionar todos os tickets.')
    }
  }

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
  // "Ativos" is the default (undefined `view`), so the situação picker only
  // offers the two non-default states — the pill still reads "Ativos" via its
  // placeholder.
  const situationOptions = [
    { value: 'archived', label: 'Arquivados' },
    { value: 'all', label: 'Todos' },
  ]

  // `view` (situação) is now the first filter — no separate tabs row that would
  // shift the filters when switching Quadro ⇄ Lista.
  const filterKeys = ['view', 'project_id', 'client_id', 'assignee_id', 'status', 'channel', 'creative_type', 'priority']
  const activeCount = filterKeys.filter((k) => filters[k]).length + (filters.q ? 1 : 0)
  // Clear filters (and reset situação to Ativos) but keep the text search.
  const clearFilters = () => setFilters((f) => {
    const next = { ...f }
    filterKeys.forEach((k) => delete next[k])
    return next
  })

  const filterSpec = [
    { key: 'view', type: 'options', label: 'Situação', placeholder: 'Ativos', options: situationOptions },
    { key: 'project_id', type: 'project', label: 'Campanha' },
    { key: 'client_id', type: 'client', label: 'Cliente' },
    { key: 'assignee_id', type: 'assignee', label: 'Responsável' },
    { key: 'status', type: 'options', label: 'Etapa', options: statusOptions },
    { key: 'channel', type: 'options', label: 'Canal', options: channelOptions },
    { key: 'creative_type', type: 'options', label: 'Tipo', options: creativeOptions },
    { key: 'priority', type: 'options', label: 'Prioridade', options: priorityOptions },
  ]

  // The toolbar lives in the hub's fixed title band, not inline with the rows.
  // Situação (Ativos/Arquivados/Todos) is the first filter now — no separate tabs
  // row above it.
  const toolbar = selection.count > 0 ? (
    <SelectionBar
      className="mb-0"
      count={selection.count}
      total={total}
      onSelectAll={selectAll}
      onClear={selection.clear}
    >
      <Button variant="destructive" size="sm" className="gap-1.5" onClick={() => setConfirmOpen(true)}>
        <Trash2 size={15} /> Excluir
      </Button>
    </SelectionBar>
  ) : (
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
  )

  return (
    <>
      {filtersSlot && createPortal(toolbar, filtersSlot)}

      {/* ── List ── */}
      {isLoading ? (
        <div className="flex justify-center py-24"><Spinner size={30} /></div>
      ) : isError ? (
        <EmptyState icon={Ghost} title="Erro ao carregar" description="Não foi possível carregar os tickets. Tente novamente." />
      ) : rows.length === 0 ? (
        <EmptyState
          icon={listFilters.view === 'archived' ? Archive : Rows3}
          color={BRAND}
          title={listFilters.view === 'archived' ? 'Nenhum ticket arquivado' : 'Nenhum ticket encontrado'}
          description={activeCount > 0 ? 'Ajuste os filtros para ver mais resultados.' : 'Crie o primeiro ticket e comece a mover o trabalho pelo funil.'}
          action={listFilters.view !== 'archived' && activeCount === 0
            ? <Button onClick={onNewTicket}><Plus size={18} /> Novo ticket</Button>
            : undefined}
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
                selected={selection.has(t.id)}
                onToggleSelect={selection.toggle}
                onOpen={onOpenTicket}
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

      <ConfirmDialog
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        icon={Trash2}
        destructive
        title={selection.count === 1 ? 'Excluir ticket?' : `Excluir ${selection.count} tickets?`}
        description="Esta ação é permanente e não pode ser desfeita. Os tickets e todo o seu conteúdo (subtarefas, criativos, posts) serão removidos."
        confirmLabel="Excluir"
        loading={bulkDelete.isPending}
        onConfirm={confirmDelete}
      />
    </>
  )
}
