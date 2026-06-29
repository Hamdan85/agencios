import { useDroppable } from '@dnd-kit/core'
import { SortableContext, verticalListSortingStrategy, useSortable } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { Inbox, MoreVertical, Archive } from 'lucide-react'
import { cn } from '@/lib/utils'
import { statusMeta } from '@/lib/constants'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { TicketCard } from './TicketCard'

// A draggable wrapper around a TicketCard inside a sortable column.
function SortableTicket({ ticket, onOpen }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: String(ticket.id),
    data: { type: 'ticket', status: ticket.status, ticket },
  })

  const style = {
    transform: CSS.Translate.toString(transform),
    transition,
  }

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners} className="touch-none">
      <TicketCard ticket={ticket} dragging={isDragging} onOpen={onOpen} />
    </div>
  )
}

// One status column: accent header, count badge, tinted droppable body.
// `onClear`, when provided, surfaces a column menu to bulk-archive its cards.
export function BoardColumn({ status, label, tickets = [], onOpenTicket, onClear }) {
  const m = statusMeta(status)
  const Icon = m.icon
  const ids = tickets.map((t) => String(t.id))

  const { setNodeRef, isOver } = useDroppable({
    id: `column:${status}`,
    data: { type: 'column', status },
  })

  return (
    <div className="flex h-full w-[290px] shrink-0 flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-[0_1px_2px_rgba(24,18,43,0.04),0_12px_30px_-20px_rgba(24,18,43,0.22)]">
      {/* top accent bar */}
      <div className="h-1.5 shrink-0" style={{ background: m.color }} />

      {/* header */}
      <div
        className="flex shrink-0 items-center justify-between gap-2 border-b border-border px-3.5 py-3"
        style={{ background: `${m.color}0D` }}
      >
        <div className="flex min-w-0 items-center gap-2">
          <span className="flex size-7 shrink-0 items-center justify-center rounded-lg" style={{ background: `${m.color}1F`, color: m.color }}>
            <Icon size={15} strokeWidth={2.4} />
          </span>
          <div className="min-w-0">
            <p className="truncate font-display text-[13px] font-bold leading-tight text-ink">{label || m.label}</p>
            <p className="truncate text-[10.5px] font-medium text-ink-muted">{m.hint}</p>
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <span
            className="flex h-6 min-w-6 items-center justify-center rounded-full px-1.5 text-[12px] font-extrabold"
            style={{ background: `${m.color}1A`, color: m.color }}
          >
            {tickets.length}
          </span>
          {onClear && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button
                  type="button"
                  aria-label="Ações da coluna"
                  className="flex size-6 items-center justify-center rounded-md text-ink-muted transition hover:bg-surface-muted hover:text-ink focus:outline-none"
                >
                  <MoreVertical size={15} />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-52">
                <DropdownMenuItem onClick={onClear} disabled={tickets.length === 0}>
                  <Archive size={15} /> Arquivar concluídos
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
        </div>
      </div>

      {/* droppable body */}
      <div
        ref={setNodeRef}
        className={cn(
          'scrollbar-subtle flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto p-2.5 transition-colors',
          isOver ? 'bg-brand-soft/60' : 'bg-surface-muted/35',
        )}
        style={isOver ? { boxShadow: `inset 0 0 0 2px ${m.color}55` } : undefined}
      >
        <SortableContext items={ids} strategy={verticalListSortingStrategy}>
          {tickets.map((t) => (
            <SortableTicket key={t.id} ticket={t} onOpen={onOpenTicket} />
          ))}
        </SortableContext>

        {tickets.length === 0 && (
          <div className="flex flex-1 flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-border/80 py-8 text-center">
            <Inbox size={20} className="text-ink-faint" strokeWidth={2} />
            <p className="text-[11.5px] font-semibold text-ink-faint">Arraste cards para cá</p>
          </div>
        )}
      </div>
    </div>
  )
}

export default BoardColumn
