import { useMemo, useState } from 'react'
import { Check, MessageSquarePlus, FileText, CalendarClock, Star } from 'lucide-react'
import CreativeExperience from '@/components/creative/CreativeExperience'
import { Button } from '@/components/ui/button'
import { dt } from '@/lib/formatters'
import { pieceName, slotLabel } from '@/lib/creativeName'
import BriefSheet from './BriefSheet'

// One ticket, filling the deck with NO inner scroll: compact scope, an optional
// slot switcher (>1 media type), the creative stage (height-capped), an optional
// option rail (>1 option → pick the winner), and a pinned action bar. The brief
// opens in a Sheet OVER the deck so it never hides the actions.
export default function ApprovalTicketCard({ ticket, accent, fg, busy, onApproveSlot, onRequestChanges }) {
  const slots = ticket.slots || []
  // Focus the first slot that still needs a decision.
  const firstPending = Math.max(0, slots.findIndex((s) => s.state === 'pending'))
  const [slotIdx, setSlotIdx] = useState(firstPending)
  const [briefOpen, setBriefOpen] = useState(false)
  const slot = slots[slotIdx] || slots[0]
  const options = slot?.options || []

  // The option the client is viewing / has chosen as winner for this slot.
  const [chosenByType, setChosenByType] = useState({})
  const chosenId = chosenByType[slot?.creative_type] ?? (options.length === 1 ? options[0]?.id : slot?.chosen_creative_id)
  const [viewIdx, setViewIdx] = useState(0)
  const active = options[viewIdx] || options[0]

  const decided = slot?.state === 'approved' || slot?.state === 'changes_requested'
  const needsChoice = options.length > 1 && !chosenId
  const pendingCount = slots.filter((s) => s.state === 'pending').length

  const choose = (id) => setChosenByType((m) => ({ ...m, [slot.creative_type]: id }))

  const label = slot ? slotLabel(slot.creative_type) : ''
  const approveLabel = useMemo(() => {
    if (options.length > 1 && chosenId) {
      const i = options.findIndex((o) => o.id === chosenId)
      return `Aprovar Opção ${String.fromCharCode(65 + Math.max(0, i))}`
    }
    return slots.length > 1 ? `Aprovar ${label}` : 'Aprovar'
  }, [options, chosenId, slots.length, label])

  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-3xl border border-border bg-surface shadow-[0_12px_48px_-24px_rgba(24,18,43,0.3)]">
      {/* Scope (compact, fixed) */}
      <div className="shrink-0 px-5 pt-4">
        <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-ink-faint">{ticket.campaign}</p>
        <div className="flex items-start justify-between gap-3">
          <h2 className="font-display text-lg font-extrabold tracking-tight text-ink">{ticket.title}</h2>
          {(ticket.brief || ticket.objective) && (
            <button type="button" onClick={() => setBriefOpen(true)}
              className="mt-0.5 flex shrink-0 items-center gap-1 text-xs font-medium text-ink-muted hover:text-ink">
              <FileText size={13} /> Ver briefing
            </button>
          )}
        </div>
        {ticket.objective && <p className="mt-0.5 line-clamp-1 text-sm text-ink-secondary">{ticket.objective}</p>}
        <div className="mt-2 flex flex-wrap items-center gap-1.5 text-xs">
          {(ticket.channels || []).map((ch) => (
            <span key={ch} className="rounded-full bg-surface-muted px-2 py-0.5 font-medium capitalize text-ink-muted">{ch}</span>
          ))}
          {ticket.scheduled_at && (
            <span className="ml-auto flex items-center gap-1 text-ink-faint"><CalendarClock size={12} /> {dt(ticket.scheduled_at)}</span>
          )}
        </div>
      </div>

      {/* Slot switcher — only when the ticket has more than one media type */}
      {slots.length > 1 && (
        <div className="mt-3 flex shrink-0 gap-1.5 overflow-x-auto px-5" role="tablist">
          {slots.map((s, i) => {
            const done = s.state === 'approved' ? '✓' : (s.state === 'changes_requested' ? '✎' : '')
            const on = i === slotIdx
            return (
              <button key={s.creative_type} role="tab" aria-selected={on} onClick={() => { setSlotIdx(i); setViewIdx(0) }}
                className={`flex items-center gap-1 whitespace-nowrap rounded-xl border px-3 py-1.5 text-sm font-medium transition ${
                  on ? 'text-white' : 'border-border text-ink-muted hover:bg-surface-muted'}`}
                style={on ? { background: accent, borderColor: accent } : undefined}>
                {slotLabel(s.creative_type)} {done}
              </button>
            )
          })}
        </div>
      )}

      {/* Stage (dominant, height-capped so the deck never scrolls) */}
      <div className="flex min-h-0 flex-1 items-center justify-center px-5 py-3">
        {active
          ? <CreativeExperience key={active.id} creative={active} fit="height" />
          : <div className="h-full w-full rounded-2xl bg-surface-muted" />}
      </div>

      {/* Option rail — only when the focused slot has more than one option */}
      {options.length > 1 && (
        <div className="shrink-0 px-5">
          <p className="mb-1.5 text-xs text-ink-muted">
            Você está vendo {pieceName(active, { index: viewIdx, optionCount: options.length })} de {options.length}
          </p>
          <div className="flex items-center gap-2 overflow-x-auto pb-1" role="radiogroup">
            {options.map((o, i) => {
              const isChosen = o.id === chosenId
              const url = (o.asset_urls || [])[0]
              return (
                <button key={o.id} role="radio" aria-checked={isChosen}
                  onClick={() => { setViewIdx(i); choose(o.id) }}
                  className={`relative size-14 shrink-0 overflow-hidden rounded-lg border-2 transition ${
                    isChosen ? '' : 'border-transparent opacity-80 hover:opacity-100'}`}
                  style={isChosen ? { borderColor: accent } : undefined}
                  title={pieceName(o, { index: i, optionCount: options.length })}>
                  {url ? <img src={url} alt="" className="size-full object-cover" /> : <div className="size-full bg-surface-muted" />}
                  {isChosen && (
                    <span className="absolute bottom-0 right-0 flex size-4 items-center justify-center rounded-tl-md text-white" style={{ background: accent }}>
                      <Check size={11} />
                    </span>
                  )}
                </button>
              )
            })}
            {!chosenId && (
              <span className="ml-1 inline-flex items-center gap-1 text-xs font-medium text-ink-muted">
                <Star size={13} /> Escolha uma opção
              </span>
            )}
          </div>
        </div>
      )}

      {/* Actions (pinned, always visible) */}
      <div className="mt-2 shrink-0 border-t border-border p-4 pb-[calc(env(safe-area-inset-bottom)+1rem)]">
        {slots.length > 1 && pendingCount > 0 && (
          <p className="mb-2 text-center text-xs text-ink-muted">
            {pendingCount === 1 ? 'Última peça' : `Falta${pendingCount > 1 ? 'm' : ''} ${pendingCount} peças`} para concluir
          </p>
        )}
        <div className="flex gap-2">
          <Button
            className="h-12 flex-1 text-base"
            style={{ background: accent, color: fg }}
            disabled={busy || decided || needsChoice}
            onClick={() => onApproveSlot({ creativeType: slot.creative_type, creativeId: chosenId })}
          >
            <Check size={18} /> {approveLabel}
          </Button>
          <Button variant="outline" className="h-12 flex-1 text-base" disabled={busy}
            onClick={() => onRequestChanges(slot)}>
            <MessageSquarePlus size={18} /> Pedir ajustes
          </Button>
        </div>
      </div>

      <BriefSheet open={briefOpen} onOpenChange={setBriefOpen} ticket={ticket} />
    </div>
  )
}
