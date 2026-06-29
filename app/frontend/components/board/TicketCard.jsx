import { useLocation, useNavigate } from 'react-router-dom'
import { CheckSquare, ImageIcon, CalendarClock } from 'lucide-react'
import { cn } from '@/lib/utils'
import { relativeDay } from '@/lib/formatters'
import { CreativeTypeChip, ChannelIcons, PriorityDot } from '@/components/ui/iconography'
import { Avatar } from '@/components/ui/avatar'

// A single, graphic ticket card on the Kanban board.
// Lifts on hover; clicking (when not dragging) opens the ticket — in the side
// drawer when an `onOpen` handler is provided, otherwise the full detail page.
export function TicketCard({ ticket, dragging = false, overlay = false, onOpen }) {
  const navigate = useNavigate()
  const location = useLocation()
  if (!ticket) return null

  const project = ticket.project || null
  const accent = project?.color || '#7C3AED'
  const due = relativeDay(ticket.due_date)
  const subtasksCount = Number(ticket.subtasks_count) || 0
  const subtasksDone = Number(ticket.subtasks_done) || 0
  const progress = subtasksCount > 0 ? Math.round((subtasksDone / subtasksCount) * 100) : 0
  const creatives = Number(ticket.creatives_count) || 0
  const channels = ticket.channels || []
  const title = ticket.display_title || ticket.title || 'Sem título'

  const open = () => {
    if (dragging) return
    if (onOpen) { onOpen(ticket); return }
    navigate(`/tickets/${ticket.id}`, { state: { from: location.pathname + location.search } })
  }

  const toneClass = {
    danger: 'bg-danger/12 text-danger',
    warning: 'bg-amber/15 text-[#B45309]',
    muted: 'bg-surface-muted text-ink-muted',
  }

  return (
    <div
      onClick={open}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter') open() }}
      className={cn(
        'group relative cursor-pointer overflow-hidden rounded-2xl border border-border bg-surface p-3.5 text-left',
        'shadow-[0_1px_2px_rgba(24,18,43,0.04)] transition-all',
        !overlay && 'hover:-translate-y-0.5 hover:border-strong hover:shadow-[0_14px_30px_-16px_rgba(24,18,43,0.3)]',
        dragging && !overlay && 'opacity-40',
        overlay && 'rotate-2 scale-[1.02] shadow-[0_24px_50px_-18px_rgba(24,18,43,0.45)] ring-1 ring-brand/20',
      )}
    >
      {/* left accent bar in the project color */}
      <span className="absolute inset-y-0 left-0 w-1" style={{ background: accent }} />

      {/* project chip + priority */}
      <div className="mb-2 flex items-center justify-between gap-2 pl-1.5">
        {project ? (
          <span
            className="inline-flex max-w-[70%] items-center gap-1.5 truncate rounded-full px-2 py-0.5 text-[11px] font-bold"
            style={{ background: `${accent}16`, color: accent }}
          >
            <span className="size-1.5 shrink-0 rounded-full" style={{ background: accent }} />
            <span className="truncate">{project.name}</span>
          </span>
        ) : (
          <span className="text-[11px] font-bold text-ink-faint">Sem projeto</span>
        )}
        <PriorityDot priority={ticket.priority} />
      </div>

      {/* title */}
      <h4 className="mb-2.5 pl-1.5 font-display text-[14px] font-semibold leading-snug text-ink line-clamp-2">
        {title}
      </h4>

      {/* type + channels */}
      <div className="mb-3 flex flex-wrap items-center gap-1.5 pl-1.5">
        {ticket.creative_type && <CreativeTypeChip type={ticket.creative_type} />}
        {channels.length > 0 && <ChannelIcons channels={channels} size={12} max={5} />}
      </div>

      {/* subtasks progress */}
      {subtasksCount > 0 && (
        <div className="mb-2.5 pl-1.5">
          <div className="mb-1 flex items-center justify-between text-[11px] font-bold text-ink-muted">
            <span className="inline-flex items-center gap-1">
              <CheckSquare size={11} strokeWidth={2.4} />
              {subtasksDone}/{subtasksCount}
            </span>
            <span>{progress}%</span>
          </div>
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
            <div
              className="h-full rounded-full transition-all"
              style={{ width: `${progress}%`, background: accent }}
            />
          </div>
        </div>
      )}

      {/* footer */}
      <div className="flex items-center justify-between gap-2 pl-1.5 pt-0.5">
        <div className="flex items-center gap-1.5">
          {due && (
            <span className={cn('inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[10.5px] font-bold', toneClass[due.tone] || toneClass.muted)}>
              <CalendarClock size={11} strokeWidth={2.4} />
              {due.text}
            </span>
          )}
          {creatives > 0 && (
            <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-1.5 py-0.5 text-[10.5px] font-bold text-ink-muted">
              <ImageIcon size={11} strokeWidth={2.4} />
              {creatives}
            </span>
          )}
        </div>
        {ticket.assignee && (
          <Avatar name={ticket.assignee.name} src={ticket.assignee.avatar_url} size={26} />
        )}
      </div>
    </div>
  )
}

export default TicketCard
