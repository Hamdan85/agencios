import {
  Archive, ArchiveRestore, MoreVertical, CalendarClock,
} from 'lucide-react'
import { statusMeta } from '@/lib/constants'
import { relativeDay } from '@/lib/formatters'
import { cn } from '@/lib/utils'
import { SelectCheckbox } from '@/components/ui/select-checkbox'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import {
  StatusPill, StatusDot, CreativeTypeChip, ChannelIcons, PriorityDot,
} from '@/components/ui/iconography'
import { Avatar } from '@/components/ui/avatar'
import { WorkingBadge } from '@/components/ticket/WorkingBadge'
import { AlertBadge } from '@/components/ticket/AlertBadge'

const TONE = {
  danger: 'bg-danger/12 text-danger',
  warning: 'bg-amber/15 text-[#B45309]',
  muted: 'bg-surface-muted text-ink-muted',
}

// A single ticket row, shared by the global ticket list and the project page.
// Clicking the body opens the ticket (drawer); the trailing menu archives /
// restores (managers only). Pass `proposed` to render a dimmed, non-interactive
// preview of a planned ticket (the AI strategy proposal) with a "Proposto" badge
// in place of the assignee / menu.
export function TicketRow({
  ticket, onOpen, manager, onArchive, onUnarchive, busy,
  selected, onToggleSelect, proposed = false, state = 'ready', op = 'create',
  pendingChange = null,
}) {
  const project = ticket.project
  const title = ticket.display_title || ticket.title
  const accent = project?.color || statusMeta(ticket.status).color
  const due = relativeDay(ticket.due_date || ticket.scheduled_at)
  // Ghost rows carry a live state: `drafting` (still filling → skeleton) and
  // `revising` (a single card being re-generated → glow); `ready` is the default.
  const drafting = proposed && state === 'drafting'
  const revising = proposed && state === 'revising'
  // A ghost's op decides how it reads: a NEW card (create), an EDIT of an existing
  // ticket (update), or a REMOVAL of one (remove — struck-through, in danger tone).
  const removing = (proposed && op === 'remove') || pendingChange === 'remove'
  // A real row targeted by a staged edit/removal is dimmed with a pending badge.
  const GHOST_BADGE = { create: ['Proposto', 'text-brand border-brand/50'], update: ['Editar', 'text-amber-600 border-amber-500/50'], remove: ['Remover', 'text-danger border-danger/50'] }
  const PENDING_BADGE = { edit: ['A editar', 'text-amber-600 border-amber-500/50'], remove: ['A remover', 'text-danger border-danger/50'] }
  const [ghostLabel, ghostCls] = GHOST_BADGE[op] || GHOST_BADGE.create

  // The title block is identical whether it's a clickable button or a static
  // (proposed) row — factor it so both branches share the exact same markup.
  const body = drafting ? (
    <span className="min-w-0 flex-1">
      <span className="block h-4 w-40 max-w-[60%] animate-pulse rounded bg-ink/10" />
      <span className="mt-1.5 block h-3 w-24 animate-pulse rounded bg-ink/[0.07]" />
    </span>
  ) : (
    <span className="min-w-0 flex-1">
      <span className="flex items-center gap-2">
        <span className={cn('truncate font-display text-[15px] font-semibold text-ink', removing && 'text-ink-muted line-through')}>{title}</span>
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
  )

  return (
    <div className={cn(
      'group flex items-center gap-3 rounded-xl border bg-surface px-3.5 py-2.5 transition-all',
      proposed
        ? cn('border-dashed opacity-60', removing ? 'border-danger/40' : op === 'update' ? 'border-amber-500/40' : 'border-brand/40')
        : selected
          ? 'border-brand/60 bg-brand/[0.04]'
          : 'border-border hover:border-brand/40 hover:shadow-[0_10px_24px_-18px_rgba(24,18,43,0.32)]',
      // A real row with a staged (ghost) edit/removal awaiting apply — dim it so the
      // pairing with its ghost below is obvious.
      !proposed && pendingChange && 'opacity-70',
      !proposed && pendingChange === 'remove' && 'border-danger/40',
      // A card being revised glows and stays fully opaque so it stands out as the
      // one thing updating; the rest of the proposed list stays dimmed.
      revising && 'border-brand/60 opacity-100 shadow-[0_0_0_3px_rgba(124,58,237,0.16)]',
      // Executing on autopilot → steady brand ring so the "working" row stands out.
      !proposed && ticket.autopilot_running && 'border-brand/50 ring-1 ring-brand/40',
      // In alert (posting failed) → danger ring (takes precedence).
      !proposed && ticket.in_alert && 'border-danger/50 ring-1 ring-danger/40',
      !proposed && ticket.archived && 'opacity-75',
    )}>
      {manager && !proposed && (
        <SelectCheckbox checked={selected} onChange={() => onToggleSelect(ticket.id)} label={`Selecionar ${title}`} />
      )}
      <span className="hidden sm:block"><StatusDot status={ticket.status} size={9} /></span>

      {proposed ? (
        <span className="flex min-w-0 flex-1 items-center gap-3 text-left">{body}</span>
      ) : (
        <button onClick={() => onOpen(ticket.id)} className="flex min-w-0 flex-1 items-center gap-3 text-left">
          {body}
        </button>
      )}

      <div className="hidden items-center gap-1.5 md:flex">
        {ticket.creative_type && <CreativeTypeChip type={ticket.creative_type} />}
        {ticket.channels?.length > 0 && <ChannelIcons channels={ticket.channels} size={12} max={4} />}
      </div>

      {!proposed && ticket.in_alert && <AlertBadge reason={ticket.alert_reason} />}
      {!proposed && ticket.autopilot_running && <WorkingBadge />}

      {due && (
        <span className={cn('hidden items-center gap-1 rounded-md px-1.5 py-0.5 text-[10.5px] font-bold lg:inline-flex', TONE[due.tone] || TONE.muted)}>
          <CalendarClock size={11} strokeWidth={2.4} /> {due.text}
        </span>
      )}

      <span className="hidden xl:block"><StatusPill status={ticket.status} size="sm" /></span>
      <PriorityDot priority={ticket.priority} />

      {proposed ? (
        <span className={cn('shrink-0 rounded-full border border-dashed px-2 py-0.5 text-[11px] font-bold', ghostCls)}>
          {ghostLabel}
        </span>
      ) : (
        <>
          {pendingChange && (
            <span className={cn('shrink-0 rounded-full border border-dashed px-2 py-0.5 text-[11px] font-bold', PENDING_BADGE[pendingChange]?.[1])}>
              {PENDING_BADGE[pendingChange]?.[0]}
            </span>
          )}
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
        </>
      )}
    </div>
  )
}

export default TicketRow
