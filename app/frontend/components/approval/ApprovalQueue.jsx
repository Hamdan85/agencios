import { useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Search, ImageIcon, CheckSquare } from 'lucide-react'
import { cn } from '@/lib/utils'
import { CreativeTypeChip, ChannelIcons } from '@/components/ui/iconography'
import { MediaThumb } from '@/components/ui/media-thumb'

// The first reviewable thumbnail across a ticket's slots — so each row shows the
// actual content, not just a title.
function firstThumb(ticket) {
  for (const s of ticket.slots || []) {
    for (const o of s.options || []) {
      const t = (o.asset_urls || [])[0] || o.preview_url
      if (t) return t
    }
  }
  return null
}

// A single rich, identifiable queue row: content thumbnail + title + campaign +
// format/channel chips + pending-count badge, with a left accent bar on the
// selected row (echoing the board card treatment).
function QueueRow({ ticket, on, accent, onPick }) {
  const thumb = firstThumb(ticket)
  const pending = (ticket.slots || []).filter((s) => s.state === 'pending').length
  const types = ticket.creative_types || []
  const channels = ticket.channels || []

  return (
    <button
      onClick={() => onPick(ticket.id)}
      className={cn(
        'group relative flex w-full items-center gap-3 overflow-hidden rounded-xl border p-2.5 text-left transition',
        on ? 'bg-surface shadow-sm' : 'border-border bg-surface/70 hover:-translate-y-0.5 hover:bg-surface hover:shadow-sm',
      )}
      style={on ? { borderColor: accent } : undefined}
    >
      <span className="absolute inset-y-0 left-0 w-1" style={{ background: on ? accent : 'transparent' }} />
      <div className="size-12 shrink-0 overflow-hidden rounded-lg border border-border bg-surface-muted">
        {thumb
          ? <MediaThumb url={thumb} alt={ticket.title} />
          : <div className="grid size-full place-items-center"><ImageIcon size={16} className="text-ink-faint" /></div>}
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-ink">{ticket.title}</p>
        {ticket.campaign && <p className="truncate text-xs text-ink-muted">{ticket.campaign}</p>}
        {(types.length > 0 || channels.length > 0) && (
          <div className="mt-1 flex flex-wrap items-center gap-1">
            {types.slice(0, 3).map((t) => <CreativeTypeChip key={t} type={t} />)}
            {channels.length > 0 && <ChannelIcons channels={channels} size={11} max={4} />}
          </div>
        )}
      </div>
      {pending > 0 && (
        <span className="shrink-0 rounded-full bg-amber/20 px-1.5 py-0.5 text-[11px] font-extrabold text-[#B45309]">
          {pending}
        </span>
      )}
    </button>
  )
}

// The approval queue, styled as a board column: a tinted header (icon + count),
// a search field, and a scrollable stack of rich rows. Reused by the standalone
// per-client approval portal and the portal's per-campaign Aprovações tab. The
// column owns its own scroll; `className` sizes it (full-height sidebar on
// desktop, a capped strip when stacked on mobile).
export default function ApprovalQueue({ tickets = [], currentId, onPick, accent = '#7C3AED', className }) {
  const { t } = useTranslation('portal')
  const [q, setQ] = useState('')
  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase()
    if (!term) return tickets
    return tickets.filter((tk) =>
      (tk.title || '').toLowerCase().includes(term) ||
      (tk.campaign || '').toLowerCase().includes(term))
  }, [tickets, q])

  return (
    <div className={cn('flex min-h-0 flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-[0_1px_2px_rgba(24,18,43,0.04),0_12px_30px_-20px_rgba(24,18,43,0.22)]', className)}>
      <div className="h-1.5 shrink-0" style={{ background: accent }} />
      <div className="shrink-0 border-b border-border px-3 py-3" style={{ background: `${accent}0D` }}>
        <div className="flex items-center justify-between gap-2">
          <div className="flex min-w-0 items-center gap-2">
            <span className="flex size-7 shrink-0 items-center justify-center rounded-lg" style={{ background: `${accent}1F`, color: accent }}>
              <CheckSquare size={15} strokeWidth={2.4} />
            </span>
            <p className="truncate font-display text-[13px] font-bold leading-tight text-ink">{t('queue.title')}</p>
          </div>
          <span className="flex h-6 min-w-6 items-center justify-center rounded-full px-1.5 text-[12px] font-extrabold" style={{ background: `${accent}1A`, color: accent }}>
            {tickets.length}
          </span>
        </div>
        <div className="relative mt-2.5">
          <Search size={14} className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-ink-faint" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('queue.searchPlaceholder')}
            className="w-full rounded-lg border border-border bg-surface py-1.5 pl-8 pr-2.5 text-sm text-ink placeholder:text-ink-faint focus:border-brand/50 focus:outline-none"
          />
        </div>
      </div>
      <div className="scrollbar-subtle flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto bg-surface-muted/35 p-2.5">
        {filtered.length === 0
          ? <p className="px-2 py-8 text-center text-sm text-ink-muted">{t('queue.noResults')}</p>
          : filtered.map((tk) => (
            <QueueRow key={tk.id} ticket={tk} on={tk.id === currentId} accent={accent} onPick={onPick} />
          ))}
      </div>
    </div>
  )
}
