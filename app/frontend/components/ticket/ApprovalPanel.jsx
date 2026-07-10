import { ShieldCheck, Send, CheckCircle2, MessageSquareWarning } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { ticketsApi } from '@/api'
import { dt as formatDt } from '@/lib/formatters'
import { slotLabel } from '@/lib/creativeName'

// Production-step approval widget. Derives its state from the ticket's creatives:
//   - fully approved              → "Aprovado por <actor>"
//   - client requested changes    → the requested-changes state, listing what the
//                                    client asked for; internal approval is blocked
//                                    (you address the notes, then resend the link)
//   - otherwise                   → awaiting the client, with resend + approve.
export default function ApprovalPanel({ ticket, creatives = [], onChanged }) {
  const { t } = useTranslation('ticket')
  const confirm = useConfirm()
  const approval = ticket.approval || {}
  const sentAt = approval.requested_at ? formatDt(approval.requested_at) : null

  // The pieces the client asked to change (each carries its own feedback note).
  const changeRequests = (creatives || []).filter((c) => c.approval_state === 'changes_requested')
  const hasChanges = changeRequests.length > 0

  const resend = async () => {
    const ok = await confirm({ title: t('approval.resendConfirmTitle'), description: t('approval.resendConfirmDescription'), confirmLabel: t('approval.resendConfirmLabel') })
    if (!ok) return
    try { await ticketsApi.requestApproval(ticket.id); toast.success(t('approval.resendSuccess')); onChanged?.() }
    catch (e) { toast.error(e?.error || t('approval.resendError')) }
  }

  const approve = async () => {
    const ok = await confirm({ title: t('approval.approveConfirmTitle'), description: t('approval.approveConfirmDescription'), confirmLabel: t('approval.approveConfirmLabel') })
    if (!ok) return
    try { await ticketsApi.approve(ticket.id); toast.success(t('approval.approveSuccess')); onChanged?.() }
    catch (e) { toast.error(e?.error || t('approval.approveError')) }
  }

  if (approval.fully_approved) {
    return (
      <Card className="flex items-center gap-2 p-4 text-emerald">
        <CheckCircle2 size={18} />
        <span className="font-semibold">{approval.actor_name ? t('approval.approvedBy', { name: approval.actor_name }) : t('approval.approved')}</span>
      </Card>
    )
  }

  // Client requested changes on at least one piece: show what they asked for and
  // withhold the internal "Aprovar" — you can't approve content with open change
  // requests. Address the notes, then resend the link to reopen it for approval.
  if (hasChanges) {
    return (
      <Card className="p-4">
        <div className="mb-1 flex items-center gap-2 text-amber-600">
          <MessageSquareWarning size={18} />
          <span className="font-semibold">{t('approval.changesTitle')}</span>
        </div>
        <p className="mb-3 text-xs text-ink-muted">
          {t('approval.changesHelp')}
        </p>
        <ul className="mb-3 flex flex-col gap-2">
          {changeRequests.map((c) => (
            <li key={c.id} className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-3">
              <div className="mb-1 flex items-center justify-between gap-2">
                <span className="text-xs font-bold uppercase tracking-wide text-amber-600">{slotLabel(c.creative_type)}</span>
                {c.decided_at && <span className="text-[11px] text-ink-faint">{formatDt(c.decided_at)}</span>}
              </div>
              {c.client_feedback
                ? <p className="whitespace-pre-wrap text-sm leading-relaxed text-ink-secondary">{c.client_feedback}</p>
                : <p className="text-sm italic text-ink-faint">{t('approval.noDetails')}</p>}
            </li>
          ))}
        </ul>
        <Button variant="outline" onClick={resend}><Send size={16} /> {t('approval.resendLink')}</Button>
      </Card>
    )
  }

  return (
    <Card className="p-4">
      <div className="mb-3 flex items-center gap-2 text-ink">
        <ShieldCheck size={18} className="text-brand" />
        <span className="font-semibold">{t('approval.awaiting')}</span>
      </div>
      {sentAt && <p className="mb-3 text-xs text-ink-muted">{t('approval.sentAt', { date: sentAt })}</p>}
      <div className="flex gap-2">
        <Button variant="outline" onClick={resend}><Send size={16} /> {t('approval.resendLink')}</Button>
        <Button onClick={approve}><CheckCircle2 size={16} /> {t('approval.approve')}</Button>
      </div>
    </Card>
  )
}
