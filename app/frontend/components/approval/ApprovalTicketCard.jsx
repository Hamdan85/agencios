import { useMemo, useState } from 'react'
import { Check, MessageSquarePlus, CalendarClock } from 'lucide-react'
import CreativeExperience from '@/components/creative/CreativeExperience'
import { Button } from '@/components/ui/button'
import { dt } from '@/lib/formatters'
import { pieceName, slotLabel } from '@/lib/creativeName'

// Two-pane review: LEFT = everything about the ticket (scope, full brief, the
// media-type slots + per-slot decision), RIGHT = a large media viewer of the
// focused option. On mobile it stacks (viewer on top, content below, actions
// pinned). The brief lives inline in the content column — no sheet that hides
// the actions.
export default function ApprovalTicketCard({ ticket, accent, fg, busy, onApproveSlot, onRequestChanges }) {
  const slots = ticket.slots || []
  const firstPending = Math.max(0, slots.findIndex((s) => s.state === 'pending'))
  const [slotIdx, setSlotIdx] = useState(firstPending)
  const slot = slots[slotIdx] || slots[0]
  const options = slot?.options || []

  const [chosenByType, setChosenByType] = useState({})
  const chosenId = chosenByType[slot?.creative_type] ?? (options.length === 1 ? options[0]?.id : slot?.chosen_creative_id)
  const [viewIdx, setViewIdx] = useState(0)
  const active = options[viewIdx] || options[0]

  const decided = slot?.state === 'approved' || slot?.state === 'changes_requested'
  const needsChoice = options.length > 1 && !chosenId
  const focusSlot = (i) => { setSlotIdx(i); setViewIdx(0) }
  const choose = (id) => setChosenByType((m) => ({ ...m, [slot.creative_type]: id }))

  const approveLabel = useMemo(() => {
    if (options.length > 1 && chosenId) {
      const i = options.findIndex((o) => o.id === chosenId)
      return `Aprovar Opção ${String.fromCharCode(65 + Math.max(0, i))}`
    }
    return slots.length > 1 ? `Aprovar ${slotLabel(slot?.creative_type)}` : 'Aprovar'
  }, [options, chosenId, slots.length, slot])

  const SLOT_STATE = {
    approved: ['✓', 'text-emerald-600'],
    changes_requested: ['✎', 'text-amber-600'],
    pending: ['', 'text-ink-faint'],
  }

  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-3xl border border-border bg-surface shadow-[0_12px_48px_-24px_rgba(24,18,43,0.3)] lg:grid lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
      {/* RIGHT PANE on desktop / TOP on mobile: the media viewer */}
      <div className="order-first flex min-h-0 flex-col bg-black/3 p-4 lg:order-last">
        <div className="flex min-h-0 flex-1 items-center justify-center">
          {active
            ? <CreativeExperience key={active.id} creative={active} fit="height" />
            : <div className="h-full w-full rounded-2xl bg-surface-muted" />}
        </div>
        {/* Option filmstrip — only when this slot has more than one candidate */}
        {options.length > 1 && (
          <div className="mt-3 shrink-0">
            <p className="mb-1.5 text-center text-xs text-ink-muted">
              {pieceName(active, { index: viewIdx, optionCount: options.length })} — {options.length} opções · toque para escolher
            </p>
            <div className="flex items-center justify-center gap-2 overflow-x-auto pb-1" role="radiogroup">
              {options.map((o, i) => {
                const isChosen = o.id === chosenId
                const url = (o.asset_urls || [])[0]
                return (
                  <button key={o.id} role="radio" aria-checked={isChosen} onClick={() => { setViewIdx(i); choose(o.id) }}
                    className={`relative size-16 shrink-0 overflow-hidden rounded-lg border-2 transition ${isChosen ? '' : i === viewIdx ? 'border-ink/20' : 'border-transparent opacity-70 hover:opacity-100'}`}
                    style={isChosen ? { borderColor: accent } : undefined}
                    title={pieceName(o, { index: i, optionCount: options.length })}>
                    {url ? <img src={url} alt="" className="size-full object-cover" /> : <div className="size-full bg-surface-muted" />}
                    {isChosen && <span className="absolute bottom-0 right-0 flex size-4 items-center justify-center rounded-tl-md text-white" style={{ background: accent }}><Check size={11} /></span>}
                  </button>
                )
              })}
            </div>
          </div>
        )}
      </div>

      {/* LEFT PANE on desktop / BOTTOM on mobile: content + decision */}
      <div className="flex min-h-0 flex-col lg:border-r lg:border-border">
        {/* Scrollable content (scope + full brief + slot picker) */}
        <div className="min-h-0 flex-1 overflow-y-auto p-5">
          <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-ink-faint">{ticket.campaign}</p>
          <h2 className="mt-0.5 font-display text-xl font-extrabold tracking-tight text-ink">{ticket.title}</h2>
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5 text-xs">
            {(ticket.channels || []).map((ch) => (
              <span key={ch} className="rounded-full bg-surface-muted px-2 py-0.5 font-medium capitalize text-ink-muted">{ch}</span>
            ))}
            {ticket.scheduled_at && <span className="flex items-center gap-1 text-ink-faint"><CalendarClock size={12} /> {dt(ticket.scheduled_at)}</span>}
          </div>

          {ticket.objective && (
            <div className="mt-4">
              <p className="text-[11px] font-bold uppercase tracking-wide text-ink-faint">Objetivo</p>
              <p className="mt-0.5 text-sm text-ink-secondary">{ticket.objective}</p>
            </div>
          )}
          {ticket.brief && (
            <div className="mt-4">
              <p className="text-[11px] font-bold uppercase tracking-wide text-ink-faint">Briefing</p>
              <p className="mt-0.5 whitespace-pre-wrap text-sm leading-relaxed text-ink-secondary">{ticket.brief}</p>
            </div>
          )}

          {/* Slot picker — the ticket's media types as a checklist; the focused one
              drives the viewer + the actions below. Only shown when >1 slot. */}
          {slots.length > 1 && (
            <div className="mt-5">
              <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-ink-faint">Peças ({slots.length})</p>
              <div className="flex flex-col gap-1.5">
                {slots.map((s, i) => {
                  const [icon, cls] = SLOT_STATE[s.state] || SLOT_STATE.pending
                  const on = i === slotIdx
                  return (
                    <button key={s.creative_type} onClick={() => focusSlot(i)}
                      className={`flex items-center justify-between rounded-xl border px-3 py-2 text-left text-sm transition ${on ? 'bg-surface-muted' : 'border-border hover:bg-surface-muted/60'}`}
                      style={on ? { borderColor: accent } : undefined}>
                      <span className="font-medium text-ink">{slotLabel(s.creative_type)}</span>
                      <span className={`text-xs font-bold ${cls}`}>{icon || (s.options.length > 1 ? `${s.options.length} opções` : '')}</span>
                    </button>
                  )
                })}
              </div>
            </div>
          )}
        </div>

        {/* Decision — pinned, always visible */}
        <div className="shrink-0 border-t border-border p-4 pb-[calc(env(safe-area-inset-bottom)+1rem)]">
          {slots.length > 1 && <p className="mb-2 text-xs font-medium text-ink-muted">Decisão: {slotLabel(slot?.creative_type)}</p>}
          {needsChoice && <p className="mb-2 text-xs text-ink-muted">Escolha uma opção ao lado para aprovar.</p>}
          {decided ? (
            <p className={`py-2 text-center text-sm font-semibold ${slot.state === 'approved' ? 'text-emerald-600' : 'text-amber-600'}`}>
              {slot.state === 'approved' ? '✓ Aprovado' : '✎ Ajustes enviados'}
            </p>
          ) : (
            <div className="flex gap-2">
              <Button className="h-12 flex-1 text-base" style={{ background: accent, color: fg }}
                disabled={busy || needsChoice}
                onClick={() => onApproveSlot({ creativeType: slot.creative_type, creativeId: chosenId })}>
                <Check size={18} /> {approveLabel}
              </Button>
              <Button variant="outline" className="h-12 flex-1 text-base" disabled={busy} onClick={() => onRequestChanges(slot)}>
                <MessageSquarePlus size={18} /> Pedir ajustes
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
