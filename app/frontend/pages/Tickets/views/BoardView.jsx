import { useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { useTranslation } from 'react-i18next'
import {
  DndContext, DragOverlay, PointerSensor, KeyboardSensor,
  useSensor, useSensors, pointerWithin,
} from '@dnd-kit/core'
import { arrayMove, sortableKeyboardCoordinates } from '@dnd-kit/sortable'
import { Plus, LayoutGrid, Archive } from 'lucide-react'
import { WORKFLOW, statusMeta } from '@/lib/constants'
import { useBoard, useBoardMutations } from '@/hooks/useBoard'
import { useCurrentUser } from '@/hooks/useAuth'
import { canManage } from '@/lib/roles'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Button } from '@/components/ui/button'
import { ScrollShadow } from '@/components/ui/scroll-shadow'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { BoardColumn } from '@/components/board/BoardColumn'
import { TicketCard } from '@/components/board/TicketCard'

const BRAND = '#EC4899'

// Only the params the board endpoint understands. The shared URL may also carry
// list-only filters (status, priority, view) — the columns already express the
// status, so the board simply ignores them.
const BOARD_FILTER_KEYS = ['q', 'project_id', 'client_id', 'assignee_id', 'channel', 'creative_type']

// Build a {status: [tickets]} map from the API columns, in WORKFLOW order.
function toColumnMap(columns = []) {
  const map = {}
  WORKFLOW.forEach((s) => { map[s] = [] })
  columns.forEach((col) => {
    if (!col?.status) return
    map[col.status] = [...(col.tickets || [])]
  })
  return map
}

const findStatusOf = (map, id) =>
  WORKFLOW.find((s) => (map[s] || []).some((t) => String(t.id) === String(id)))

// The Kanban view of the tickets hub: columns are the 7 workflow statuses,
// cards drag between them. Filters, the drawer and the new-ticket dialog live
// in the hub (pages/Tickets/Index) — this view only renders the board itself.
export default function BoardView({ filters, onOpenTicket, onNewTicket }) {
  const { t } = useTranslation('board')
  const boardFilters = useMemo(() => {
    const f = {}
    BOARD_FILTER_KEYS.forEach((k) => { if (filters?.[k]) f[k] = filters[k] })
    return f
  }, [filters])

  const [activeId, setActiveId] = useState(null)
  const [clearStatus, setClearStatus] = useState(null)

  const { data, isLoading } = useBoard(boardFilters)
  const { advance, reorder, clearColumn } = useBoardMutations(boardFilters)
  const { data: me } = useCurrentUser()
  const isManager = canManage(me?.membership?.role)

  // Local optimistic copy of the column map, synced from the query.
  const [board, setBoard] = useState({})
  useEffect(() => {
    if (data?.columns) setBoard(toColumnMap(data.columns))
  }, [data])

  const labels = useMemo(() => {
    const m = {}
    ;(data?.columns || []).forEach((c) => { m[c.status] = c.label })
    return m
  }, [data])

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

  const activeTicket = useMemo(() => {
    if (!activeId) return null
    for (const s of WORKFLOW) {
      const found = (board[s] || []).find((t) => String(t.id) === String(activeId))
      if (found) return found
    }
    return null
  }, [activeId, board])

  const totalTickets = useMemo(
    () => WORKFLOW.reduce((sum, s) => sum + (board[s]?.length || 0), 0),
    [board],
  )

  const onDragStart = ({ active }) => setActiveId(active.id)

  // Move card between columns live as it's dragged over another column.
  const onDragOver = ({ active, over }) => {
    if (!over) return
    const activeIdStr = String(active.id)
    const overId = String(over.id)

    const fromStatus = findStatusOf(board, activeIdStr)
    let toStatus = overId.startsWith('column:')
      ? overId.slice('column:'.length)
      : findStatusOf(board, overId)

    if (!fromStatus || !toStatus || fromStatus === toStatus) return

    setBoard((prev) => {
      const next = { ...prev }
      const fromList = [...(next[fromStatus] || [])]
      const toList = [...(next[toStatus] || [])]
      const idx = fromList.findIndex((t) => String(t.id) === activeIdStr)
      if (idx === -1) return prev
      const [moved] = fromList.splice(idx, 1)

      let insertAt = toList.length
      const overIdx = toList.findIndex((t) => String(t.id) === overId)
      if (overIdx !== -1) insertAt = overIdx

      toList.splice(insertAt, 0, { ...moved, status: toStatus })
      next[fromStatus] = fromList
      next[toStatus] = toList
      return next
    })
  }

  const onDragEnd = ({ active, over }) => {
    setActiveId(null)
    if (!over) return

    const activeIdStr = String(active.id)
    const overId = String(over.id)
    const toStatus = overId.startsWith('column:')
      ? overId.slice('column:'.length)
      : findStatusOf(board, overId)
    if (!toStatus) return

    const originalStatus = findStatusOf(toColumnMap(data?.columns), activeIdStr)

    // Reorder within the destination column, then derive the final position.
    let finalBoard = board
    setBoard((prev) => {
      const list = [...(prev[toStatus] || [])]
      const oldIdx = list.findIndex((t) => String(t.id) === activeIdStr)
      const overIdx = list.findIndex((t) => String(t.id) === overId)
      if (oldIdx !== -1 && overIdx !== -1 && oldIdx !== overIdx) {
        const reordered = arrayMove(list, oldIdx, overIdx)
        const next = { ...prev, [toStatus]: reordered }
        finalBoard = next
        return next
      }
      finalBoard = prev
      return prev
    })

    const position = (finalBoard[toStatus] || []).findIndex((t) => String(t.id) === activeIdStr)
    const safePosition = position < 0 ? 0 : position

    if (originalStatus && originalStatus !== toStatus) {
      advance.mutate({ id: activeIdStr, toStatus, position: safePosition })
    } else {
      reorder.mutate({ id: activeIdStr, position: safePosition })
    }
  }

  const onDragCancel = () => {
    setActiveId(null)
    if (data?.columns) setBoard(toColumnMap(data.columns))
  }

  if (isLoading) return <PageLoader />

  if (totalTickets === 0) {
    return (
      <div className="flex min-h-0 flex-1 items-center justify-center">
        <EmptyState
          icon={LayoutGrid}
          color={BRAND}
          title={t('empty.title')}
          description={t('empty.description')}
          action={<Button onClick={onNewTicket}><Plus size={18} /> {t('newTicket')}</Button>}
        />
      </div>
    )
  }

  return (
    <>
      <DndContext
        sensors={sensors}
        collisionDetection={pointerWithin}
        onDragStart={onDragStart}
        onDragOver={onDragOver}
        onDragEnd={onDragEnd}
        onDragCancel={onDragCancel}
      >
        <ScrollShadow
          className="-mx-4 min-h-0 flex-1 sm:-mx-6"
          viewportClassName="scrollbar-subtle flex items-stretch gap-3.5 overflow-x-auto overflow-y-hidden px-2 pb-2 pt-0.5 scroll-px-2 snap-x snap-mandatory sm:snap-none"
        >
          {WORKFLOW.map((status) => (
            <BoardColumn
              key={status}
              status={status}
              label={labels[status] || statusMeta(status).label}
              tickets={board[status] || []}
              onOpenTicket={(ticket) => onOpenTicket(ticket.id)}
              onClear={status === 'done' && isManager ? () => setClearStatus('done') : undefined}
            />
          ))}
        </ScrollShadow>

        {createPortal(
          <DragOverlay dropAnimation={{ duration: 180 }}>
            {activeTicket ? (
              <div className="w-[270px]">
                <TicketCard ticket={activeTicket} overlay />
              </div>
            ) : null}
          </DragOverlay>,
          document.body,
        )}
      </DndContext>

      <ConfirmDialog
        open={!!clearStatus}
        onOpenChange={(o) => { if (!o) setClearStatus(null) }}
        icon={Archive}
        tone={statusMeta('done').color}
        title={t('clearDialog.title')}
        description={t('clearDialog.description', { count: board.done?.length || 0 })}
        confirmLabel={t('clearDialog.confirm')}
        loading={clearColumn.isPending}
        onConfirm={() => clearColumn.mutate(clearStatus, { onSuccess: () => setClearStatus(null) })}
      />
    </>
  )
}
