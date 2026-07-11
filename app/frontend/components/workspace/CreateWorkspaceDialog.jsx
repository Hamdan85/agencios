import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Building2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { IconTile } from '@/components/ui/icon-tile'
import { useWorkspaceMutations } from '@/hooks/useData'

const ACCENT = '#6366F1'

// Minimal "new workspace" form — just a name. The backend bootstraps the owner
// membership, settings and a trialing subscription, switches the session into
// the new workspace, and the mutation hard-loads the dashboard.
export default function CreateWorkspaceDialog({ open, onOpenChange }) {
  const { t } = useTranslation('billing')
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
          <IconTile icon={Building2} color={ACCENT} className="mb-1 size-11" iconSize={22} />
          <DialogTitle>{t('createWorkspace.title')}</DialogTitle>
          <DialogDescription>
            {t('createWorkspace.description')}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={submit} className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="ws-name">{t('createWorkspace.nameLabel')}</Label>
            <Input
              id="ws-name"
              autoFocus
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t('createWorkspace.namePlaceholder')}
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={close}>{t('createWorkspace.cancel')}</Button>
            <Button type="submit" disabled={!name.trim() || create.isPending}>
              {create.isPending ? t('createWorkspace.creating') : t('createWorkspace.create')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
