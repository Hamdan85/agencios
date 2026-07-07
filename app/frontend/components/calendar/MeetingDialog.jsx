import { useNavigate } from 'react-router-dom'
import { Video, Clock, Building2, ExternalLink, ArrowUpRight, CalendarDays } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { ColorBadge } from '@/components/ui/badge'
import { dt, time } from '@/lib/formatters'
import { eventVisual } from './EventChip'

// A small detail dialog for a clicked calendar event.
// Meetings show the Meet link; posts offer a jump to the ticket.
export function MeetingDialog({ event, open, onOpenChange }) {
  const navigate = useNavigate()
  if (!event) return null

  const isMeeting = event.type === 'meeting'
  const { color, Icon } = eventVisual(event)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <div className="mb-1 flex items-center gap-3">
            <div className="grid size-11 place-items-center rounded-2xl" style={{ background: `${color}18`, color }}>
              {Icon ? <Icon size={22} strokeWidth={2.2} /> : <CalendarDays size={22} />}
            </div>
            <ColorBadge color={color} className="py-1 text-[11px] uppercase tracking-wide">
              {isMeeting ? 'Reunião' : 'Post agendado'}
            </ColorBadge>
          </div>
          <DialogTitle>{event.title || (isMeeting ? 'Reunião' : 'Publicação')}</DialogTitle>
          <DialogDescription>{dt(event.start)}</DialogDescription>
        </DialogHeader>

        <div className="space-y-2.5">
          <DetailRow icon={Clock} label="Horário">
            {time(event.start)}{event.end ? ` – ${time(event.end)}` : ''}
          </DetailRow>
          {event.client_name && (
            <DetailRow icon={Building2} label="Cliente">{event.client_name}</DetailRow>
          )}
        </div>

        <DialogFooter>
          {isMeeting && event.meet_url && (
            <Button asChild>
              <a href={event.meet_url} target="_blank" rel="noreferrer">
                <Video size={16} /> Entrar no Meet <ExternalLink size={14} className="opacity-70" />
              </a>
            </Button>
          )}
          {!isMeeting && event.ticket_id && (
            <Button onClick={() => { onOpenChange?.(false); navigate(`/tickets/${event.ticket_id}`) }}>
              Abrir ticket <ArrowUpRight size={16} />
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function DetailRow({ icon: Icon, label, children }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-border bg-surface-muted/60 px-3.5 py-2.5">
      <div className="grid size-8 place-items-center rounded-lg bg-surface text-ink-muted">
        <Icon size={15} strokeWidth={2.2} />
      </div>
      <div className="min-w-0">
        <p className="text-[10px] font-bold uppercase tracking-wider text-ink-faint">{label}</p>
        <p className="truncate text-sm font-semibold text-ink">{children}</p>
      </div>
    </div>
  )
}
