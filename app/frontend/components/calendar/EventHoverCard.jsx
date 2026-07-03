import { Building2, CircleCheck, CircleDashed, Clock, Ticket, UserRound, Users } from 'lucide-react'
import { Tooltip, TooltipTrigger, TooltipContent } from '@/components/ui/tooltip'
import { time, date } from '@/lib/formatters'
import { channelMeta } from '@/lib/constants'
import { eventVisual } from './EventChip'
import { parseEventStart } from './calendarUtils'

const TYPE_LABEL = { post: 'Post agendado', meeting: 'Reunião', task: 'Tarefa' }

// Rich hover card for any calendar event — replaces the native `title` tooltip
// with a designed preview: type, title, time and the context lines that matter
// per event kind. Desktop-only by nature (hover); click behavior is untouched.
export function EventHoverCard({ event, showWorkspace = false, children }) {
  if (!event) return children
  const { color, Icon } = eventVisual(event)
  const title = event.title || TYPE_LABEL[event.type] || 'Evento'
  const network = event.type === 'post' ? channelMeta(event.provider)?.label : null

  const when = event.all_day
    ? `${date(parseEventStart(event).toISOString())} · dia inteiro`
    : event.end
      ? `${time(event.start)} – ${time(event.end)}`
      : time(event.start)

  return (
    <Tooltip delayDuration={250}>
      <TooltipTrigger asChild>{children}</TooltipTrigger>
      <TooltipContent
        side="top"
        align="start"
        sideOffset={8}
        className="w-[16.5rem] max-w-[16.5rem] overflow-hidden rounded-xl border border-border bg-surface p-0 text-ink shadow-[0_4px_12px_rgba(24,18,43,0.08),0_16px_40px_-12px_rgba(24,18,43,0.22)]"
      >
        {/* type band */}
        <div className="flex items-center gap-2 px-3 pt-2.5" style={{ color }}>
          <span className="grid size-5 shrink-0 place-items-center rounded-md" style={{ background: color, color: '#fff' }}>
            {Icon ? <Icon size={11} strokeWidth={2.6} /> : <span className="size-1.5 rounded-full bg-white" />}
          </span>
          <span className="text-[10px] font-bold uppercase tracking-[0.12em]">
            {network ? `${TYPE_LABEL.post} · ${network}` : TYPE_LABEL[event.type] || 'Evento'}
          </span>
          {event.type === 'task' && (
            <TaskState done={event.done} overdue={event.overdue} />
          )}
        </div>

        <p className={`px-3 pt-1.5 text-[13px] font-bold leading-snug text-ink ${event.done ? 'line-through opacity-60' : ''}`}>
          {title}
        </p>

        <div className="flex flex-col gap-1 px-3 pb-2.5 pt-2">
          <DetailRow icon={Clock}>{when}</DetailRow>
          {event.type === 'task' && event.ticket_title && <DetailRow icon={Ticket}>{event.ticket_title}</DetailRow>}
          {event.type === 'task' && event.assignee_name && <DetailRow icon={UserRound}>{event.assignee_name}</DetailRow>}
          {event.client_name && <DetailRow icon={Building2}>{event.client_name}</DetailRow>}
          {showWorkspace && event.workspace_name && <DetailRow icon={Users}>{event.workspace_name}</DetailRow>}
        </div>
      </TooltipContent>
    </Tooltip>
  )
}

function TaskState({ done, overdue }) {
  if (done) {
    return (
      <span className="ml-auto inline-flex items-center gap-1 text-[10px] font-bold text-emerald-600">
        <CircleCheck size={11} strokeWidth={2.6} /> Feita
      </span>
    )
  }
  if (overdue) {
    return (
      <span className="ml-auto inline-flex items-center gap-1 text-[10px] font-bold text-rose-500">
        <CircleDashed size={11} strokeWidth={2.6} /> Atrasada
      </span>
    )
  }
  return null
}

function DetailRow({ icon: Icon, children }) {
  return (
    <span className="flex items-center gap-1.5 text-[11.5px] font-medium text-ink-secondary">
      <Icon size={12} strokeWidth={2.2} className="shrink-0 text-ink-faint" />
      <span className="truncate">{children}</span>
    </span>
  )
}
