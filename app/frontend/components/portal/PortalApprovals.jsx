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
    <div>
      {tickets.length > 1 && (
        <div className="mb-4 flex flex-wrap gap-2">
          {tickets.map((t) => {
            const on = t.id === current.id
            return (
              <button key={t.id} onClick={() => setFocusId(t.id)}
                className={`rounded-full border px-3 py-1.5 text-sm font-semibold transition ${on ? 'text-white' : 'border-border bg-surface text-ink-muted hover:border-brand/40'}`}
                style={on ? { background: accent, borderColor: accent } : undefined}>
                {t.title}
              </button>
            )
          })}
        </div>
      )}

      <div className="min-h-[520px]">
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
