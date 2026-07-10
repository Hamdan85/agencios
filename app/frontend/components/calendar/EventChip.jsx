import { SquareCheck, Video } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { time } from '@/lib/formatters'
import { channelMeta } from '@/lib/constants'

const MEETING_COLOR = '#14B8A6'
const TASK_COLOR = '#F59E0B'

// Resolve a vivid color + icon for any calendar event (post, meeting, task or a
// planned funnel ticket). A ticket carries the project color and, since it can
// target several networks, the icon of its first channel.
export function eventVisual(ev) {
  if (!ev) return { color: '#8B86A3', Icon: null }
  if (ev.type === 'meeting') return { color: ev.color || MEETING_COLOR, Icon: Video }
  if (ev.type === 'task') return { color: ev.color || TASK_COLOR, Icon: SquareCheck }
  if (ev.type === 'ticket') {
    const m = channelMeta(ev.channels?.[0])
    return { color: ev.color || m.color, Icon: m.icon }
  }
  const m = channelMeta(ev.provider)
  return { color: ev.color || m.color, Icon: m.icon }
}

// A compact, colorful chip rendered inside a day cell. When `showWorkspace` is set
// (the cross-team "Meu calendário" view), the owning team is appended so events from
// different workspaces are tellable apart at a glance.
// Extra props (incl. `ref`) are forwarded to the button so the chip can sit
// inside a Radix `asChild` trigger (the EventHoverCard).
export function EventChip({ event, onClick, compact = false, showWorkspace = false, ...props }) {
  const { t } = useTranslation('calendar')
  const { color, Icon } = eventVisual(event)
  const label = event?.title || (event?.type === 'meeting' ? t('event.meeting') : t('event.post'))
  const ws = showWorkspace ? event?.workspace_name : null
  // "Previsto": a funnel ticket with a planned publish date but no scheduled post
  // yet. It's tentative, not committed — render it as a ghost (faint fill, dashed
  // outline, hollow icon) so it reads distinctly from an actual "agendado" post.
  const planned = event?.type === 'ticket'
  return (
    <button
      {...props}
      type="button"
      onClick={(e) => { e.stopPropagation(); onClick?.(event) }}
      className={cn(
        'group/chip flex w-full items-center gap-1.5 overflow-hidden rounded-lg px-1.5 text-left text-[11px] font-bold leading-none transition-all hover:brightness-105 hover:saturate-150',
        planned && 'border border-dashed',
        compact ? 'py-1' : 'py-1.5',
      )}
      style={{
        background: planned ? `${color}0D` : `${color}1A`,
        color,
        ...(planned ? { borderColor: `${color}66` } : {}),
      }}
    >
      <span
        className="grid size-4 shrink-0 place-items-center rounded-md"
        style={planned
          ? { color, boxShadow: `inset 0 0 0 1.5px ${color}` }
          : { background: color, color: '#fff' }}
      >
        {Icon ? <Icon size={9} strokeWidth={2.6} /> : <span className="size-1.5 rounded-full" style={{ background: planned ? color : '#fff' }} />}
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
