import { useEffect, useState } from 'react'
import { Send } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { ChipsInput } from '@/components/ui/chips-input'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// Emails the read-only content-scope summary for `project` to whichever
// addresses the manager types in (pre-filled with the client's own email,
// still editable/removable — it doesn't have to be the client's registered
// address).
export function SendScopeDialog({ open, onOpenChange, project, mutation }) {
  const [recipients, setRecipients] = useState([])

  useEffect(() => {
    if (open) setRecipients(project?.client_email ? [project.client_email] : [])
  }, [open, project?.client_email])

  const valid = recipients.filter((r) => EMAIL_RE.test(r))

  const submit = (e) => {
    e.preventDefault()
    if (!valid.length) return
    mutation.mutate({ id: project.id, recipients: valid }, { onSuccess: () => onOpenChange(false) })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: '#0EA5E916', color: '#0EA5E9' }}>
            <Send size={20} strokeWidth={2.2} />
          </div>
          <DialogTitle>Enviar escopo ao cliente</DialogTitle>
          <DialogDescription>
            Envia por e-mail um resumo dos tickets do projeto (nomes, tipos e datas) — sem detalhes internos.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3.5">
          <div className="space-y-1.5">
            <Label>Destinatários</Label>
            <ChipsInput value={recipients} onChange={setRecipients} placeholder="email@cliente.com" />
          </div>
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">Cancelar</Button></DialogClose>
            <Button type="submit" disabled={!valid.length || mutation.isPending}>
              {mutation.isPending ? 'Enviando…' : 'Enviar'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export default SendScopeDialog
