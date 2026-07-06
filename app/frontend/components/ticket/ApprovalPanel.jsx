import { ShieldCheck, Send, CheckCircle2 } from 'lucide-react'
import { toast } from 'sonner'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { ticketsApi } from '@/api'

// Production-step approval widget: shows derived status + two confirmed actions
// (resend the client link, approve internally), or "Aprovado por <actor>".
export default function ApprovalPanel({ ticket, onChanged }) {
  const confirm = useConfirm()
  const approval = ticket.approval || {}
  const dt = approval.requested_at ? new Date(approval.requested_at).toLocaleString('pt-BR') : null

  const resend = async () => {
    const ok = await confirm({ title: 'Reenviar link de aprovação?', description: 'O cliente receberá o link por e-mail novamente.', confirmLabel: 'Reenviar' })
    if (!ok) return
    try { await ticketsApi.requestApproval(ticket.id); toast.success('Link reenviado ao cliente!'); onChanged?.() }
    catch (e) { toast.error(e?.error || 'Erro ao reenviar.') }
  }

  const approve = async () => {
    const ok = await confirm({ title: 'Aprovar em nome do cliente?', description: 'Marca todos os criativos como aprovados.', confirmLabel: 'Aprovar' })
    if (!ok) return
    try { await ticketsApi.approve(ticket.id); toast.success('Conteúdo aprovado!'); onChanged?.() }
    catch (e) { toast.error(e?.error || 'Erro ao aprovar.') }
  }

  if (approval.fully_approved) {
    return (
      <Card className="flex items-center gap-2 p-4 text-emerald">
        <CheckCircle2 size={18} />
        <span className="font-semibold">Aprovado{approval.actor_name ? ` por ${approval.actor_name}` : ''}</span>
      </Card>
    )
  }

  return (
    <Card className="p-4">
      <div className="mb-3 flex items-center gap-2 text-ink">
        <ShieldCheck size={18} className="text-brand" />
        <span className="font-semibold">Aguardando aprovação do cliente</span>
      </div>
      {dt && <p className="mb-3 text-xs text-ink-muted">Link enviado em {dt}</p>}
      <div className="flex gap-2">
        <Button variant="outline" onClick={resend}><Send size={16} /> Reenviar link</Button>
        <Button onClick={approve}><CheckCircle2 size={16} /> Aprovar</Button>
      </div>
    </Card>
  )
}
