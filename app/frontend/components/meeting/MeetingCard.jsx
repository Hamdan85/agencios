import {
  Video, CalendarClock, Users2, ExternalLink, MoreHorizontal,
  Pencil, Trash2, StickyNote, Building2,
} from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { MEETING_COLOR } from '@/components/calendar/EventChip'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { dt, time } from '@/lib/formatters'

function attendeeCount(attendees) {
  if (Array.isArray(attendees)) return attendees.length
  if (attendees && typeof attendees === 'object') return Object.keys(attendees).length
  return 0
}

// One meeting card, shared by /reunioes and the client page. Meetings are
// personal: `canEdit` gates the edit/cancel menu to the owner; `showOwner`
// surfaces who scheduled it on shared listings.
export function MeetingCard({ meeting, past, canEdit = true, showOwner = false, onEdit, onCancel }) {
  const { t } = useTranslation('meetings')
  const count = attendeeCount(meeting.attendees)
  return (
    <Card className="group flex flex-col overflow-hidden lift animate-rise">
      <div className="h-1.5 w-full" style={{ background: past ? '#94A3B8' : MEETING_COLOR }} />
      <div className="flex flex-1 flex-col p-5">
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-start gap-3">
            <div className="flex size-10 shrink-0 items-center justify-center rounded-xl" style={{ background: past ? '#94A3B814' : `${MEETING_COLOR}14`, color: past ? '#64748B' : MEETING_COLOR }}>
              <Video size={20} strokeWidth={2.2} />
            </div>
            <div>
              <h3 className="font-display text-base font-bold text-ink">{meeting.title}</h3>
              <p className="mt-0.5 flex items-center gap-1.5 text-xs font-medium text-ink-muted">
                <CalendarClock size={13} />
                {dt(meeting.starts_at)}{meeting.ends_at ? ` – ${time(meeting.ends_at)}` : ''}
              </p>
            </div>
          </div>
          {/* Only the owner (who scheduled it) edits or cancels. */}
          {canEdit && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon-sm" className="text-ink-muted opacity-0 transition group-hover:opacity-100">
                  <MoreHorizontal size={18} />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onSelect={() => onEdit(meeting)}><Pencil /> {t('card.edit')}</DropdownMenuItem>
                <DropdownMenuItem onSelect={() => onCancel(meeting)} className="text-danger data-[highlighted]:text-danger">
                  <Trash2 /> {t('card.cancel')}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          {showOwner && meeting.user_name && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-muted py-0.5 pl-0.5 pr-2.5 text-xs font-bold text-ink-secondary">
              <Avatar name={meeting.user_name} src={meeting.user_avatar_url} size={18} /> {meeting.user_name}
            </span>
          )}
          {meeting.client_name && (
            <Badge variant="muted" className="gap-1.5 bg-indigo/12 py-1 text-indigo tracking-normal">
              <Building2 size={12} /> {meeting.client_name}
            </Badge>
          )}
          {meeting.project_name && (
            <Badge variant="soft" className="gap-1.5 py-1 tracking-normal">
              {meeting.project_name}
            </Badge>
          )}
          {count > 0 && (
            <Badge variant="muted" className="gap-1.5 py-1 tracking-normal">
              <Users2 size={12} /> {t('card.attendees', { count })}
            </Badge>
          )}
        </div>

        {meeting.notes && (
          <p className="mt-3 flex items-start gap-1.5 text-sm text-ink-secondary">
            <StickyNote size={14} className="mt-0.5 shrink-0 text-amber" />
            <span className="line-clamp-2">{meeting.notes}</span>
          </p>
        )}

        {meeting.meet_url && (
          <div className="mt-4">
            {past ? (
              <Button asChild variant="outline" size="sm">
                <a href={meeting.meet_url} target="_blank" rel="noopener noreferrer">
                  <Video size={16} /> {t('card.openRecording')} <ExternalLink size={14} />
                </a>
              </Button>
            ) : (
              <Button
                asChild
                size="sm"
                className="text-white shadow-[0_8px_20px_-8px_rgba(20,184,166,0.6)] hover:brightness-105"
                style={{ background: `linear-gradient(135deg, ${MEETING_COLOR}, #0EA5E9)` }}
              >
                <a href={meeting.meet_url} target="_blank" rel="noopener noreferrer">
                  <Video size={16} /> {t('card.joinMeet')} <ExternalLink size={14} />
                </a>
              </Button>
            )}
          </div>
        )}
      </div>
    </Card>
  )
}

export default MeetingCard
