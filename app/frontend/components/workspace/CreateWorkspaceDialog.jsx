import { useState } from 'react'
import { Building2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { useWorkspaceMutations } from '@/hooks/useData'

const ACCENT = '#6366F1'

// Minimal "new workspace" form — just a name. The backend bootstraps the owner
// membership, settings and a trialing subscription, switches the session into
// the new workspace, and the mutation hard-loads the dashboard.
export default function CreateWorkspaceDialog({ open, onOpenChange }) {
  const { create } = useWorkspaceMutations()
  const [name, setName] = useState('')

  const close = () => { setName(''); onOpenChange(false) }

  const submit = (e) => {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed || create.isPending) return
    create.mutate({ name: trimmed })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => (v ? onOpenChange(true) : close())}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: `${ACCENT}16`, color: ACCENT }}>
            <Building2 size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>Novo workspace</DialogTitle>
          <DialogDescription>
            Crie uma nova agência. Você será o owner e entrará nela automaticamente.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={submit} className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="ws-name">Nome do workspace</Label>
            <Input
              id="ws-name"
              autoFocus
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Minha Agência"
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={close}>Cancelar</Button>
            <Button type="submit" disabled={!name.trim() || create.isPending}>
              {create.isPending ? 'Criando…' : 'Criar workspace'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
