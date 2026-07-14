import { useState } from 'react'
import { useTranslation } from 'react-i18next'
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
import ApprovalQueue from '@/components/approval/ApprovalQueue'
import RequestChangesDialog from '@/components/approval/RequestChangesDialog'

// The campaign's approval queue inside the central. Reuses the approval portal's
// card + change dialog, but scoped to one campaign (filters the client-wide queue
// by project_id). Same optimistic reconcile + 6s undo as the standalone portal.
export default function PortalApprovals({ token, campaignId, accent = '#7C3AED' }) {
  const { t } = useTranslation('portal')
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
    return <div className="flex min-h-0 flex-1 items-center justify-center"><InlineSpinner size={24} style={{ color: accent }} /></div>
  }

  if (!current) {
    return (
      <div className="flex min-h-0 flex-1 items-center justify-center p-4">
        <div className="w-full max-w-md rounded-2xl border border-dashed border-border bg-surface py-16 text-center">
          <CheckCircle2 className="mx-auto mb-3" size={28} style={{ color: accent }} />
          <p className="font-semibold text-ink">{t('approvals.emptyTitle')}</p>
          <p className="mt-1 text-sm text-ink-muted">{t('approvals.emptyBody')}</p>
        </div>
      </div>
    )
  }

  const reconcile = (res, ticketId, { celebrate } = {}) => {
    const stillPending = (res.tickets || []).some((t) => t.id === ticketId)
    setQueue(res)
    if (!stillPending && celebrate) {
      burstConfetti(accent)
      if (navigator.vibrate) navigator.vibrate(15)
      toast.success(t('toasts.approved'), {
        action: {
          label: t('toasts.undo'),
          onClick: async () => {
            try { const undone = await approvalsApi.undo(token, ticketId); setFocusId(ticketId); setQueue(undone) }
            catch (e) { toast.error(e?.error || t('toasts.undoError')) }
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
    } catch (e) { toast.error(e?.error || t('toasts.approveError')) }
    finally { setBusy(false) }
  }

  const submitChanges = async ({ creativeId, feedback }) => {
    const ticketId = current.id
    setBusy(true)
    try {
      const res = await approvalsApi.requestChanges(token, ticketId, { creativeId, feedback })
      setChangesFor(null)
      reconcile(res, ticketId)
      toast.success(t('toasts.feedbackSent'))
    } catch (e) { toast.error(e?.error || t('toasts.sendError')) }
    finally { setBusy(false) }
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 p-3 sm:px-6 sm:py-4 lg:flex-row">
      {/* The campaign's approval queue as a board-style column: rich, searchable
          rows that make each pending piece easy to identify. Desktop only — on a
          phone the review card needs the whole screen, and deciding a ticket pops
          it off the queue and lands on the next one (same as the approval portal). */}
      {tickets.length > 1 && (
        <ApprovalQueue
          className="hidden shrink-0 lg:flex lg:h-full lg:w-72"
          tickets={tickets}
          currentId={current.id}
          onPick={setFocusId}
          accent={accent}
        />
      )}

      <div className="min-h-0 min-w-0 flex-1">
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
