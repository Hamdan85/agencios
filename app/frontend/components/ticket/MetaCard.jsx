import { Link } from 'react-router-dom'
import { useWorkspaceMembers } from '@/hooks/useData'
import { PRIORITY_META } from '@/lib/constants'
import { Card } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { ChannelIcons, CreativeTypeChip } from '@/components/ui/iconography'
import { DateTimePicker } from '@/components/ui/date-picker'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'
import { date, relativeDay } from '@/lib/formatters'
import { cn } from '@/lib/utils'
import { User, Flag, CalendarClock, CalendarDays, Radio, Wand2, ChevronDown, Check, GitBranch } from 'lucide-react'

function Row({ icon: Icon, label, children }) {
  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3">
      <span className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-ink-muted">
        <Icon size={14} /> {label}
      </span>
      <div className="text-right">{children}</div>
    </div>
  )
}

export default function MetaCard({ ticket, onUpdate }) {
  const { data: members } = useWorkspaceMembers()
  const people = members || []
  const due = relativeDay(ticket?.due_date)

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border px-4 py-3">
        <h3 className="font-display text-sm font-bold text-ink">Detalhes</h3>
      </div>
      <div className="divide-y divide-border">
        {/* Assignee — inline editable */}
        <Row icon={User} label="Responsável">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button className="inline-flex items-center gap-2 rounded-lg px-1.5 py-1 transition hover:bg-surface-muted">
                {ticket?.assignee ? (
                  <>
                    <Avatar name={ticket.assignee.name} src={ticket.assignee.avatar_url} size={22} />
                    <span className="text-sm font-semibold text-ink">{ticket.assignee.name}</span>
                  </>
                ) : (
                  <span className="text-sm text-ink-faint">Atribuir…</span>
                )}
                <ChevronDown size={14} className="text-ink-muted" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuLabel>Atribuir a</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => onUpdate?.({ assignee_id: null })}>
                <span className="text-ink-muted">Sem responsável</span>
                {!ticket?.assignee && <Check size={14} className="ml-auto !text-brand" />}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              {people.map((p) => (
                <DropdownMenuItem key={p.id} onClick={() => onUpdate?.({ assignee_id: p.id })}>
                  <Avatar name={p.name} src={p.avatar_url} size={20} />
                  <span className="truncate">{p.name}</span>
                  {ticket?.assignee?.id === p.id && <Check size={14} className="ml-auto !text-brand" />}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </Row>

        {/* Priority — inline editable */}
        <Row icon={Flag} label="Prioridade">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                className="inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-sm font-bold transition hover:bg-surface-muted"
                style={{ color: (PRIORITY_META[ticket?.priority] || PRIORITY_META.medium).color }}
              >
                <span className="size-2 rounded-full" style={{ background: (PRIORITY_META[ticket?.priority] || PRIORITY_META.medium).dot }} />
                {(PRIORITY_META[ticket?.priority] || PRIORITY_META.medium).label}
                <ChevronDown size={14} className="text-ink-muted" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {Object.entries(PRIORITY_META).map(([key, m]) => (
                <DropdownMenuItem key={key} onClick={() => onUpdate?.({ priority: key })}>
                  <span className="size-2 rounded-full" style={{ background: m.dot }} />
                  <span style={{ color: m.color }} className="font-semibold">{m.label}</span>
                  {ticket?.priority === key && <Check size={14} className="ml-auto !text-brand" />}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </Row>

        <Row icon={CalendarDays} label="Prazo">
          <div className="flex items-center justify-end gap-2">
            <span className="text-sm font-medium text-ink-secondary">{date(ticket?.due_date)}</span>
            {due && (
              <span
                className={cn(
                  'rounded-full px-1.5 py-0.5 text-[10px] font-bold',
                  due.tone === 'danger' && 'bg-danger/12 text-danger',
                  due.tone === 'warning' && 'bg-amber/15 text-[#B45309]',
                  due.tone === 'muted' && 'bg-surface-muted text-ink-muted',
                )}
              >
                {due.text}
              </span>
            )}
          </div>
        </Row>

        {/* Agendado — always inline-editable; writes the ticket's scheduled_at
            column (the same value the "Postagem" step publishes at). */}
        <Row icon={CalendarClock} label="Agendado">
          <DateTimePicker
            align="end"
            placeholder="Agendar…"
            className="w-48"
            value={ticket?.scheduled_at ? String(ticket.scheduled_at).slice(0, 16) : ''}
            onChange={(v) => onUpdate?.({ scheduled_at: v || null })}
          />
        </Row>

        <Row icon={Radio} label="Canais">
          {ticket?.channels?.length ? <ChannelIcons channels={ticket.channels} size={14} /> : <span className="text-sm text-ink-faint">—</span>}
        </Row>

        <Row icon={Wand2} label="Criativo">
          {ticket?.creative_type ? <CreativeTypeChip type={ticket.creative_type} /> : <span className="text-sm text-ink-faint">—</span>}
        </Row>

        {ticket?.relations?.length > 0 && (
          <div className="px-4 py-3">
            <p className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-ink-muted">
              <GitBranch size={14} /> Relações
            </p>
            <div className="space-y-1">
              {ticket.relations.map((r) => (
                <Link
                  key={`${r.kind}-${r.ticket_id}`}
                  to={`/tickets/${r.ticket_id}`}
                  className="flex items-center gap-2 rounded-lg px-1.5 py-1.5 transition hover:bg-surface-muted"
                >
                  <span className="shrink-0 rounded-md bg-brand/12 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-brand">{r.label}</span>
                  <span className="truncate text-sm text-ink-secondary">{r.title}</span>
                </Link>
              ))}
            </div>
          </div>
        )}
      </div>
    </Card>
  )
}
