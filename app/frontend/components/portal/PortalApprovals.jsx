import { useState } from 'react'
import { CheckCircle2 } from 'lucide-react'
import { toast } from 'sonner'
import { useQueryClient } from '@tanstack/react-query'
import { usePublicApproval } from '@/hooks/useData'
import { approvalsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { readableOn } from '@/lib/color'
import { burstConfetti } from '@/lib/confetti'
import { InlineSpinner } from '@/components/ui/feedback'
import ApprovalTicketCard from '@/components/approval/ApprovalTicketCard'
import RequestChangesDialog from '@/components/approval/RequestChangesDialog'

// The campaign's approval queue inside the central. Reuses the approval portal's
// card + change dialog, but scoped to one campaign (filters the client-wide queue
// by project_id). Same optimistic reconcile + 6s undo as the standalone portal.
export default function PortalApprovals({ token, campaignId, accent = '#7C3AED' }) {
  const { data, isLoading } = usePublicApproval(token)
  const qc = useQueryClient()
  const [busy, setBusy] = useState(false)
  const [changesFor, setChangesFor] = useState(null)
  const [focusId, setFocusId] = useState(null)
  const fg = readableOn(accent)

  const setQueue = (payload) => qc.setQueryData(keys.publicApproval(token), payload)
  const all = data?.tickets || []
  const tickets = all.filter((t) => String(t.project_id) === String(campaignId))
  const current = tickets.find((t) => t.id === focusId) || tickets[0]

  if (isLoading) {
    return <div className="flex justify-center py-16"><InlineSpinner size={24} style={{ color: accent }} /></div>
  }

  if (!current) {
    return (
      <div className="rounded-2xl border border-dashed border-border bg-surface py-16 text-center">
        <CheckCircle2 className="mx-auto mb-3" size={28} style={{ color: accent }} />
        <p className="font-semibold text-ink">Nada aguardando sua aprovação</p>
        <p className="mt-1 text-sm text-ink-muted">Avisaremos assim que houver conteúdo novo para revisar.</p>
      </div>
    )
  }

  const reconcile = (res, ticketId, { celebrate } = {}) => {
    const stillPending = (res.tickets || []).some((t) => t.id === ticketId)
    setQueue(res)
    if (!stillPending && celebrate) {
      burstConfetti(accent)
      if (navigator.vibrate) navigator.vibrate(15)
      toast.success('Conteúdo aprovado ✓', {
        action: {
          label: 'Desfazer',
          onClick: async () => {
            try { const undone = await approvalsApi.undo(token, ticketId); setFocusId(ticketId); setQueue(undone) }
            catch (e) { toast.error(e?.error || 'Não foi possível desfazer.') }
          },
        },
      })
    }
  }

  const approveSlot = async ({ creativeType, creativeId }) => {
    const ticketId = current.id
    setBusy(true)
    try {
      const res = await approvalsApi.approveSlot(token, ticketId, { creativeType, creativeId })
      reconcile(res, ticketId, { celebrate: true })
    } catch (e) { toast.error(e?.error || 'Erro ao aprovar.') }
    finally { setBusy(false) }
  }

  const submitChanges = async ({ creativeId, feedback }) => {
    const ticketId = current.id
    setBusy(true)
    try {
      const res = await approvalsApi.requestChanges(token, ticketId, { creativeId, feedback })
      setChangesFor(null)
      reconcile(res, ticketId)
      toast.success('Enviamos seu feedback à equipe 👍')
    } catch (e) { toast.error(e?.error || 'Erro ao enviar.') }
    finally { setBusy(false) }
  }

  return (
    <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
      {/* Left sidebar: the campaign's tickets awaiting approval. A scrollable
          list (vertical on desktop, a horizontal strip on mobile) — never an
          endless wall of wrapping pills. The selected ticket drives the view. */}
      {tickets.length > 1 && (
        <aside className="shrink-0 lg:sticky lg:top-4 lg:w-72">
          <p className="mb-2 hidden text-xs font-bold uppercase tracking-wider text-ink-faint lg:block">
            Aguardando aprovação ({tickets.length})
          </p>
          <div className="scrollbar-subtle flex gap-2 overflow-x-auto pb-1 lg:max-h-[70vh] lg:flex-col lg:gap-1.5 lg:overflow-y-auto lg:overflow-x-visible lg:pb-0">
            {tickets.map((t) => {
              const on = t.id === current.id
              const pendingCount = (t.slots || []).filter((s) => s.state === 'pending').length
              return (
                <button
                  key={t.id}
                  onClick={() => setFocusId(t.id)}
                  className={`flex w-56 shrink-0 items-center gap-2 rounded-xl border px-3 py-2.5 text-left text-sm font-semibold transition lg:w-full ${
                    on ? 'text-white shadow-sm' : 'border-border bg-surface text-ink-secondary hover:border-brand/40 hover:bg-surface-muted/60'
                  }`}
                  style={on ? { background: accent, borderColor: accent } : undefined}
                >
                  <span className="min-w-0 flex-1 truncate">{t.title}</span>
                  {pendingCount > 0 && (
                    <span
                      className={`flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[11px] font-extrabold ${on ? 'bg-white/25 text-white' : 'bg-amber/20 text-[#B45309]'}`}
                    >
                      {pendingCount}
                    </span>
                  )}
                </button>
              )
            })}
          </div>
        </aside>
      )}

      <div className="min-h-[520px] min-w-0 flex-1">
        <ApprovalTicketCard
          key={current.id}
          ticket={current}
          accent={accent}
          fg={fg}
          busy={busy}
          onApproveSlot={approveSlot}
          onRequestChanges={(slot) => setChangesFor(slot)}
        />
      </div>

      <RequestChangesDialog
        open={!!changesFor}
        onOpenChange={(o) => !o && setChangesFor(null)}
        slot={changesFor}
        accent={accent}
        pending={busy}
        onSubmit={submitChanges}
      />
    </div>
  )
}
