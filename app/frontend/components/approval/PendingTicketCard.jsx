import { useState } from 'react'
import { Check, MessageSquarePlus, FileText, CalendarClock } from 'lucide-react'
import CreativeExperience from '@/components/creative/CreativeExperience'
import { Button } from '@/components/ui/button'
import { dt } from '@/lib/formatters'

// One pending ticket, filling the deck: the scope the client needs to decide, the
// creative(s) to review (a thumb rail switches between multiple pieces), and the
// pinned decision actions. No inner scroll — the media is height-capped.
export default function PendingTicketCard({ ticket, accent, fg, onApprove, onRequestChanges, busy }) {
  const creatives = ticket.creatives || []
  const [activeId, setActiveId] = useState(creatives[0]?.id)
  const [briefOpen, setBriefOpen] = useState(false)
  const active = creatives.find((c) => c.id === activeId) || creatives[0]

  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-3xl border border-border bg-surface shadow-[0_12px_48px_-24px_rgba(24,18,43,0.3)]">
      {/* Scope */}
      <div className="shrink-0 px-5 pt-5">
        <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-ink-faint">{ticket.campaign}</p>
        <h2 className="mt-0.5 font-display text-xl font-extrabold tracking-tight text-ink">{ticket.title}</h2>
        {ticket.objective && <p className="mt-1 line-clamp-2 text-sm text-ink-secondary">{ticket.objective}</p>}
        <div className="mt-2 flex flex-wrap items-center gap-1.5 text-xs">
          {(ticket.channels || []).map((ch) => (
            <span key={ch} className="rounded-full bg-surface-muted px-2 py-0.5 font-medium capitalize text-ink-muted">{ch}</span>
          ))}
          {(ticket.creative_types || []).map((t) => (
            <span key={t} className="rounded-full px-2 py-0.5 font-medium" style={{ background: `${accent}18`, color: accent }}>{t}</span>
          ))}
          {ticket.scheduled_at && (
            <span className="ml-auto flex items-center gap-1 text-ink-faint"><CalendarClock size={12} /> {dt(ticket.scheduled_at)}</span>
          )}
        </div>
      </div>

      {/* Creative (dominant, height-capped so the deck never scrolls) */}
      <div className="flex min-h-0 flex-1 items-center justify-center px-5 py-3">
        {active ? <CreativeExperience creative={active} /> : <div className="aspect-square w-full rounded-2xl bg-surface-muted" />}
      </div>

      {/* Thumb rail (multiple pieces) + full brief toggle */}
      <div className="flex shrink-0 items-center gap-2 px-5">
        {creatives.length > 1 && creatives.map((c, i) => (
          <button
            key={c.id}
            type="button"
            onClick={() => setActiveId(c.id)}
            className={`size-9 rounded-lg border text-xs font-semibold transition ${
              c.id === active?.id ? 'text-white' : 'border-border text-ink-muted'
            }`}
            style={c.id === active?.id ? { background: accent, borderColor: accent } : undefined}
            title={c.creative_type}
          >
            {i + 1}
          </button>
        ))}
        {ticket.brief && (
          <button
            type="button"
            onClick={() => setBriefOpen((v) => !v)}
            className="ml-auto flex items-center gap-1 text-xs font-medium text-ink-muted hover:text-ink"
          >
            <FileText size={13} /> {briefOpen ? 'Ocultar briefing' : 'Ver briefing completo'}
          </button>
        )}
      </div>
      {briefOpen && ticket.brief && (
        <div className="mx-5 mt-2 max-h-28 shrink-0 overflow-y-auto rounded-xl bg-surface-muted/70 p-3 text-sm text-ink-secondary">
          {ticket.brief}
        </div>
      )}

      {/* Actions */}
      <div className="mt-3 flex shrink-0 gap-2 border-t border-border p-4 pb-[calc(env(safe-area-inset-bottom)+1rem)]">
        <Button
          className="h-12 flex-1 text-base"
          style={{ background: accent, color: fg }}
          onClick={onApprove}
          disabled={busy}
        >
          <Check size={18} /> Aprovar
        </Button>
        <Button variant="outline" className="h-12 flex-1 text-base" onClick={onRequestChanges} disabled={busy}>
          <MessageSquarePlus size={18} /> Pedir ajustes
        </Button>
      </div>
    </div>
  )
}
