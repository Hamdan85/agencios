import { SquareCheck, Video } from 'lucide-react'
import { cn } from '@/lib/utils'
import { time } from '@/lib/formatters'
import { channelMeta } from '@/lib/constants'

const MEETING_COLOR = '#14B8A6'
const TASK_COLOR = '#F59E0B'

// Resolve a vivid color + icon for any calendar event (post, meeting or task).
export function eventVisual(ev) {
  if (!ev) return { color: '#8B86A3', Icon: null }
  if (ev.type === 'meeting') return { color: ev.color || MEETING_COLOR, Icon: Video }
  if (ev.type === 'task') return { color: ev.color || TASK_COLOR, Icon: SquareCheck }
  const m = channelMeta(ev.provider)
  return { color: ev.color || m.color, Icon: m.icon }
}

// A compact, colorful chip rendered inside a day cell. When `showWorkspace` is set
// (the cross-team "Meu calendário" view), the owning team is appended so events from
// different workspaces are tellable apart at a glance.
// Extra props (incl. `ref`) are forwarded to the button so the chip can sit
// inside a Radix `asChild` trigger (the EventHoverCard).
export function EventChip({ event, onClick, compact = false, showWorkspace = false, ...props }) {
  const { color, Icon } = eventVisual(event)
  const label = event?.title || (event?.type === 'meeting' ? 'Reunião' : 'Post')
  const ws = showWorkspace ? event?.workspace_name : null
  return (
    <button
      {...props}
      type="button"
      onClick={(e) => { e.stopPropagation(); onClick?.(event) }}
      className={cn(
        'group/chip flex w-full items-center gap-1.5 overflow-hidden rounded-lg px-1.5 text-left text-[11px] font-bold leading-none transition-all hover:brightness-105 hover:saturate-150',
        compact ? 'py-1' : 'py-1.5',
      )}
      style={{ background: `${color}1A`, color }}
    >
      <span className="grid size-4 shrink-0 place-items-center rounded-md" style={{ background: color, color: '#fff' }}>
        {Icon ? <Icon size={9} strokeWidth={2.6} /> : <span className="size-1.5 rounded-full bg-white" />}
      </span>
      {!event?.all_day && (
        <span className="hidden shrink-0 font-mono text-[9.5px] tabular-nums opacity-70 sm:inline">{time(event?.start)}</span>
      )}
      <span className={cn('truncate', event?.done && 'line-through opacity-60')}>{label}</span>
      {ws && (
        <span
          className="ml-auto max-w-[45%] shrink-0 truncate rounded px-1 py-0.5 text-[9.5px] font-bold uppercase tracking-wide"
          style={{ background: `${color}26` }}
        >
          {ws}
        </span>
      )}
    </button>
  )
}

export { MEETING_COLOR }
