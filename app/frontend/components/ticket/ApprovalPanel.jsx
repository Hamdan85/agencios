import { ShieldCheck, Send, CheckCircle2, MessageSquareWarning, Undo2 } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { ticketsApi } from '@/api'
import { dt as formatDt } from '@/lib/formatters'
import { slotLabel } from '@/lib/creativeName'

// The approval widget, across the two stages it spans:
//
//   Produção  → the way out of the stage: "Enviar para aprovação" (the move IS the
//               request). When the client bounced the work back, it lists what they
//               asked for, and the button resubmits.
//   Aprovação → the stage's whole job: approve (on the client's behalf, or outright
//               on a project that gates approval internally) or send it back to
//               Produção. Plus resending the link while you wait.
//   Postagem  → just the "Aprovado por <actor>" badge, carried over.
//
// State comes from the ticket's creatives, not a flag.
export default function ApprovalPanel({ ticket, creatives = [], onChanged }) {
  const { t } = useTranslation('ticket')
  const confirm = useConfirm()
  const approval = ticket.approval || {}
  const status = ticket.status
  const sentAt = approval.requested_at ? formatDt(approval.requested_at) : null

  // The pieces the client asked to change (each carries its own feedback note).
  const changeRequests = (creatives || []).filter((c) => c.approval_state === 'changes_requested')
  const hasChanges = changeRequests.length > 0
  // Nothing ready to show the client yet — sending is meaningless (and the backend
  // refuses the transition).
  const hasReady = (creatives || []).some((c) => c.status === 'ready')

  const run = async (fn, { successKey, errorKey }) => {
    try { await fn(); toast.success(t(successKey)); onChanged?.() }
    catch (e) { toast.error(e?.error || t(errorKey)) }
  }

  const send = async () => {
    const ok = await confirm({
      title: t('approval.sendConfirmTitle'),
      description: t('approval.sendConfirmDescription'),
      confirmLabel: t('approval.sendConfirmLabel'),
    })
    if (!ok) return
    run(() => ticketsApi.requestApproval(ticket.id), { successKey: 'approval.sendSuccess', errorKey: 'approval.sendError' })
  }

  const resend = async () => {
    const ok = await confirm({
      title: t('approval.resendConfirmTitle'),
      description: t('approval.resendConfirmDescription'),
      confirmLabel: t('approval.resendConfirmLabel'),
    })
    if (!ok) return
    run(() => ticketsApi.requestApproval(ticket.id), { successKey: 'approval.resendSuccess', errorKey: 'approval.resendError' })
  }

  const approve = async () => {
    const ok = await confirm({
      title: t('approval.approveConfirmTitle'),
      description: t('approval.approveConfirmDescription'),
      confirmLabel: t('approval.approveConfirmLabel'),
    })
    if (!ok) return
    run(() => ticketsApi.approve(ticket.id), { successKey: 'approval.approveSuccess', errorKey: 'approval.approveError' })
  }

  const reject = async () => {
    const ok = await confirm({
      title: t('approval.rejectConfirmTitle'),
      description: t('approval.rejectConfirmDescription'),
      confirmLabel: t('approval.rejectConfirmLabel'),
      destructive: true,
    })
    if (!ok) return
    run(() => ticketsApi.advance(ticket.id, 'production'), { successKey: 'approval.rejectSuccess', errorKey: 'approval.rejectError' })
  }

  if (approval.fully_approved) {
    return (
      <Card className="flex items-center gap-2 p-4 text-emerald">
        <CheckCircle2 size={18} />
        <span className="font-semibold">{approval.actor_name ? t('approval.approvedBy', { name: approval.actor_name }) : t('approval.approved')}</span>
      </Card>
    )
  }

  // The client bounced it back: show exactly what they asked for. The ticket is in
  // Produção — address the notes, then resubmit.
  if (hasChanges) {
    return (
      <Card className="p-4">
        <div className="mb-1 flex items-center gap-2 text-amber-600">
          <MessageSquareWarning size={18} />
          <span className="font-semibold">{t('approval.changesTitle')}</span>
        </div>
        <p className="mb-3 text-xs text-ink-muted">{t('approval.changesHelp')}</p>
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
        <Button onClick={send} disabled={!hasReady}><Send size={16} /> {t('approval.resubmit')}</Button>
      </Card>
    )
  }

  // In Aprovação: the decision. Approve on the client's behalf, or send it back.
  if (status === 'approval') {
    return (
      <Card className="p-4">
        <div className="mb-3 flex items-center gap-2 text-ink">
          <ShieldCheck size={18} style={{ color: '#F97316' }} />
          <span className="font-semibold">{sentAt ? t('approval.awaiting') : t('approval.awaitingInternal')}</span>
        </div>
        {sentAt && <p className="mb-3 text-xs text-ink-muted">{t('approval.sentAt', { date: sentAt })}</p>}
        <div className="flex flex-wrap gap-2">
          <Button onClick={approve}><CheckCircle2 size={16} /> {t('approval.approve')}</Button>
          <Button variant="outline" onClick={reject}><Undo2 size={16} /> {t('approval.reject')}</Button>
          {sentAt && <Button variant="ghost" onClick={resend}><Send size={16} /> {t('approval.resendLink')}</Button>}
        </div>
      </Card>
    )
  }

  // In Produção: the one way forward.
  return (
    <Card className="p-4">
      <div className="mb-1 flex items-center gap-2 text-ink">
        <ShieldCheck size={18} className="text-brand" />
        <span className="font-semibold">{t('approval.readyTitle')}</span>
      </div>
      <p className="mb-3 text-xs text-ink-muted">
        {hasReady ? t('approval.readyHelp') : t('approval.needsCreative')}
      </p>
      <Button onClick={send} disabled={!hasReady}><Send size={16} /> {t('approval.send')}</Button>
    </Card>
  )
}
