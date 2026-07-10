import { useEffect, useMemo, useState } from 'react'
import { X, CheckSquare, ImageIcon, Inbox, CalendarClock } from 'lucide-react'
import { usePortalBoard } from '@/hooks/useData'
import { useUrlParam } from '@/hooks/useUrlState'
import { cn } from '@/lib/utils'
import { shortDt } from '@/lib/formatters'
import { WORKFLOW, statusMeta, creativeMeta } from '@/lib/constants'
import { ChannelIcons, CreativeTypeChip } from '@/components/ui/iconography'
import { SectionLabel } from '@/components/ui/section-label'
import { MediaThumb } from '@/components/ui/media-thumb'
import { InlineSpinner, EmptyState } from '@/components/ui/feedback'
import CreativeExperience from '@/components/creative/CreativeExperience'
import {
  Sheet, SheetContent, SheetClose, SheetTitle, SheetDescription,
} from '@/components/ui/sheet'

// Read-only status pill echoing StatusPill's look, but honoring the server's
// `status_label` text (the source of truth for the client-facing wording).
function ReadOnlyStatusPill({ status, label, size = 'md' }) {
  const m = statusMeta(status)
  const Icon = m.icon
  const sm = size === 'sm'
  return (
    <span
      className={cn('inline-flex items-center gap-1.5 rounded-full font-bold', sm ? 'px-2 py-0.5 text-[11px]' : 'px-2.5 py-1 text-xs')}
      style={{ background: `${m.color}1A`, color: m.color }}
    >
      <Icon size={sm ? 11 : 13} strokeWidth={2.5} />
      {label || m.label}
    </span>
  )
}

// A slim subtask-progress bar mirroring TicketCard's treatment.
function ProgressBar({ done, total, accent }) {
  const count = Number(total) || 0
  if (count <= 0) return null
  const complete = Number(done) || 0
  const progress = Math.round((complete / count) * 100)
  return (
    <div>
      <div className="mb-1 flex items-center justify-between text-[11px] font-bold text-ink-muted">
        <span className="inline-flex items-center gap-1">
          <CheckSquare size={11} strokeWidth={2.4} />
          {complete}/{count}
        </span>
        <span>{progress}%</span>
      </div>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
        <div className="h-full rounded-full transition-all" style={{ width: `${progress}%`, background: accent }} />
      </div>
    </div>
  )
}

// A single read-only card on the client board. No drag handles, no links —
// clicking surfaces the informational detail sheet via `onOpen`.
function PortalTicketCard({ ticket, accent, onOpen }) {
  if (!ticket) return null
  const channels = ticket.channels || []
  const creativeTypes = ticket.creative_types || []
  const creatives = Number(ticket.creatives_count) || 0
  const title = ticket.title || 'Sem título'

  return (
    <div
      onClick={() => onOpen(ticket)}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter') onOpen(ticket) }}
      className={cn(
        'group relative cursor-pointer overflow-hidden rounded-2xl border border-border bg-surface p-3.5 text-left',
        'shadow-[0_1px_2px_rgba(24,18,43,0.04)] transition-all',
        'hover:-translate-y-0.5 hover:border-strong hover:shadow-[0_14px_30px_-16px_rgba(24,18,43,0.3)]',
      )}
    >
      {/* left accent bar in the agency color */}
      <span className="absolute inset-y-0 left-0 w-1" style={{ background: accent }} />

      <h4 className="mb-2.5 pl-1.5 font-display text-[14px] font-semibold leading-snug text-ink line-clamp-2">
        {title}
      </h4>

      {(creativeTypes.length > 0 || channels.length > 0) && (
        <div className="mb-3 flex flex-wrap items-center gap-1.5 pl-1.5">
          {creativeTypes.map((t) => <CreativeTypeChip key={t} type={t} />)}
          {channels.length > 0 && <ChannelIcons channels={channels} size={12} max={5} />}
        </div>
      )}

      {Number(ticket.subtasks_count) > 0 && (
        <div className="mb-2.5 pl-1.5">
          <ProgressBar done={ticket.subtasks_done} total={ticket.subtasks_count} accent={accent} />
        </div>
      )}

      <div className="flex items-center justify-between gap-2 pl-1.5 pt-0.5">
        <div className="flex items-center gap-1.5">
          {ticket.scheduled_at && (
            <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-1.5 py-0.5 text-[10.5px] font-bold text-ink-muted">
              <CalendarClock size={11} strokeWidth={2.4} />
              {shortDt(ticket.scheduled_at)}
            </span>
          )}
          {creatives > 0 && (
            <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-1.5 py-0.5 text-[10.5px] font-bold text-ink-muted">
              <ImageIcon size={11} strokeWidth={2.4} />
              {creatives}
            </span>
          )}
        </div>
      </div>
    </div>
  )
}

// One read-only column: accent header, count chip, stacked cards.
function PortalColumn({ status, label, tickets, accent, onOpen }) {
  const m = statusMeta(status)
  const Icon = m.icon
  return (
    <div className="flex h-full w-[calc(100vw-3rem)] shrink-0 snap-start flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-[0_1px_2px_rgba(24,18,43,0.04),0_12px_30px_-20px_rgba(24,18,43,0.22)] sm:w-[280px] sm:snap-align-none">
      <div className="h-1.5 shrink-0" style={{ background: m.color }} />
      <div
        className="flex shrink-0 items-center justify-between gap-2 border-b border-border px-3.5 py-3"
        style={{ background: `${m.color}0D` }}
      >
        <div className="flex min-w-0 items-center gap-2">
          <span className="flex size-7 shrink-0 items-center justify-center rounded-lg" style={{ background: `${m.color}1F`, color: m.color }}>
            <Icon size={15} strokeWidth={2.4} />
          </span>
          <p className="truncate font-display text-[13px] font-bold leading-tight text-ink">{label || m.label}</p>
        </div>
        <span
          className="flex h-6 min-w-6 items-center justify-center rounded-full px-1.5 text-[12px] font-extrabold"
          style={{ background: `${accent}1A`, color: accent }}
        >
          {tickets.length}
        </span>
      </div>
      <div className="scrollbar-subtle flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto bg-surface-muted/35 p-2.5">
        {tickets.map((t) => (
          <PortalTicketCard key={t.id} ticket={t} accent={accent} onOpen={onOpen} />
        ))}
      </div>
    </div>
  )
}

// A read-only informational chunk: label + value, only rendered when present.
function DetailBlock({ label, children }) {
  return (
    <div>
      <SectionLabel className="mb-1.5">{label}</SectionLabel>
      {children}
    </div>
  )
}

// The deliverables pane: a large preview of the selected creative (native
// carousel/video/image via CreativeExperience, click to zoom) plus a filmstrip
// to switch between the ticket's pieces — the client sees the real output, not a
// thumbnail grid.
function CreativesStage({ creatives, accent }) {
  const [sel, setSel] = useState(0)
  const current = creatives[sel] || creatives[0]

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="flex min-h-0 flex-1 items-center justify-center">
        <CreativeExperience key={current.id} creative={current} fit="height" />
      </div>
      <p className="mt-2.5 shrink-0 text-center text-xs font-medium text-ink-muted">
        {current.name || creativeMeta(current.creative_type).label}
      </p>
      {creatives.length > 1 && (
        <div className="mt-2 flex shrink-0 items-center justify-center gap-2 overflow-x-auto pb-1">
          {creatives.map((c, i) => {
            const on = i === sel
            const m = creativeMeta(c.creative_type)
            const thumb = (c.asset_urls || [])[0] || c.preview_url
            return (
              <button
                key={c.id}
                type="button"
                onClick={() => setSel(i)}
                title={c.name || m.label}
                className={cn(
                  'relative size-14 shrink-0 overflow-hidden rounded-lg border-2 transition',
                  on ? '' : 'border-transparent opacity-70 hover:opacity-100',
                )}
                style={on ? { borderColor: accent } : undefined}
              >
                {thumb
                  ? <MediaThumb url={thumb} alt={c.name || m.label} />
                  : <div className="grid size-full place-items-center" style={{ background: `${m.color}12` }}><ImageIcon size={16} style={{ color: m.color }} /></div>}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

// The read-only ticket detail: a rich, app-quality view. On desktop it's a
// two-pane drawer — the deliverables (creatives) on the left, all the scope the
// client cares about on the right; on mobile it stacks. Purely informational
// (no edit affordances) — the client follows the work, they don't change it.
function PortalTicketSheet({ ticket, accent, open, onOpenChange }) {
  const t = ticket || {}
  const channels = t.channels || []
  const creativeTypes = t.creative_types || []
  const creatives = t.creatives || []
  const objective = (t.objective || '').trim()
  const brief = (t.brief || '').trim()
  const hasCreatives = creatives.length > 0

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="gap-0 p-0 sm:max-w-3xl">
        <div className="flex items-start justify-between gap-3 border-b border-border px-6 py-5">
          <div className="min-w-0">
            <SheetTitle className="text-lg leading-snug">{t.title || 'Sem título'}</SheetTitle>
            <SheetDescription className="sr-only">Detalhes da tarefa</SheetDescription>
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <ReadOnlyStatusPill status={t.status} label={t.status_label} size="sm" />
              {t.scheduled_at && (
                <span className="inline-flex items-center gap-1 text-xs font-semibold text-ink-muted">
                  <CalendarClock size={13} strokeWidth={2.4} /> {shortDt(t.scheduled_at)}
                </span>
              )}
            </div>
          </div>
          <SheetClose
            className="flex size-8 shrink-0 items-center justify-center rounded-lg text-ink-muted transition hover:bg-surface-muted hover:text-ink focus:outline-none"
            aria-label="Fechar"
          >
            <X size={18} />
          </SheetClose>
        </div>

        <div className="flex min-h-0 flex-1 flex-col lg:flex-row">
          {/* Deliverables pane */}
          {hasCreatives && (
            <div className="flex min-h-[42vh] shrink-0 flex-col justify-center bg-black/3 p-4 lg:min-h-0 lg:flex-1">
              <CreativesStage creatives={creatives} accent={accent} />
            </div>
          )}

          {/* Scope pane */}
          <div
            className={cn(
              'scrollbar-subtle min-h-0 flex-1 space-y-6 overflow-y-auto px-6 py-6',
              hasCreatives && 'lg:max-w-sm lg:border-l lg:border-border',
            )}
          >
            {!hasCreatives && (
              <div className="rounded-xl border border-dashed border-border bg-surface-muted/40 px-4 py-6 text-center text-sm text-ink-muted">
                Os criativos aparecem aqui assim que a equipe finalizar a produção.
              </div>
            )}

            {creativeTypes.length > 0 && (
              <DetailBlock label="Formatos">
                <div className="flex flex-wrap items-center gap-1.5">
                  {creativeTypes.map((ct) => <CreativeTypeChip key={ct} type={ct} />)}
                </div>
              </DetailBlock>
            )}

            {channels.length > 0 && (
              <DetailBlock label="Canais">
                <ChannelIcons channels={channels} size={16} max={8} />
              </DetailBlock>
            )}

            {objective && (
              <DetailBlock label="Objetivo">
                <p className="whitespace-pre-wrap text-sm leading-relaxed text-ink-secondary">{objective}</p>
              </DetailBlock>
            )}

            {brief && (
              <DetailBlock label="Briefing">
                <p className="whitespace-pre-wrap text-sm leading-relaxed text-ink-secondary">{brief}</p>
              </DetailBlock>
            )}

            {Number(t.subtasks_count) > 0 && (
              <DetailBlock label="Progresso">
                <ProgressBar done={t.subtasks_done} total={t.subtasks_count} accent={accent} />
              </DetailBlock>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}

// The login-less client portal board: a read-only, per-status Kanban of the
// campaign's tickets. No drag-and-drop — clicking a card opens an informational
// side panel. The open card lives in the URL (`?tarefa=<id>`) so the panel is
// shareable and the browser Back button closes it, mirroring the main app's
// `?ticket` drawer. Themed with the per-agency `accent` color.
export default function PortalBoard({ token, projectId, accent = '#7C3AED' }) {
  const { data, isLoading } = usePortalBoard(token, projectId)
  const [activeId, setActiveId] = useUrlParam('tarefa')

  // Resolve the open ticket from the board data by its id (supports deep links).
  const active = useMemo(() => {
    if (!activeId) return null
    for (const col of data?.columns || []) {
      const found = (col.tickets || []).find((t) => String(t.id) === String(activeId))
      if (found) return found
    }
    return null
  }, [data, activeId])

  // Keep the last opened ticket mounted so its content doesn't blank out mid
  // close animation once the URL param clears.
  const [shown, setShown] = useState(null)
  useEffect(() => { if (active) setShown(active) }, [active])

  const openTicket = (ticket) => setActiveId(ticket.id)
  const closeTicket = () => setActiveId(null, { replace: true })

  if (isLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <InlineSpinner size={26} className="text-brand" />
      </div>
    )
  }

  const columns = data?.columns || []
  // Keep only columns with content, ordered by the workflow funnel.
  const byStatus = new Map(columns.map((c) => [c.status, c]))
  const ordered = WORKFLOW
    .map((status) => byStatus.get(status))
    .filter((c) => c && (c.tickets || []).length > 0)

  if (ordered.length === 0) {
    return (
      <EmptyState
        icon={Inbox}
        title="Ainda não há conteúdo nesta campanha"
        description="Assim que a equipe começar a produzir, os cards aparecem aqui."
        color={accent}
      />
    )
  }

  return (
    <>
      <div className="scrollbar-subtle flex snap-x gap-3 overflow-x-auto pb-3" style={{ minHeight: '60vh' }}>
        {ordered.map((col) => (
          <PortalColumn
            key={col.status}
            status={col.status}
            label={col.label}
            tickets={col.tickets || []}
            accent={accent}
            onOpen={openTicket}
          />
        ))}
      </div>

      <PortalTicketSheet
        ticket={shown}
        accent={accent}
        open={!!active}
        onOpenChange={(v) => { if (!v) closeTicket() }}
      />
    </>
  )
}
