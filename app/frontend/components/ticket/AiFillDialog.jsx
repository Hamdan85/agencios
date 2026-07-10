import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Wand2 } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/input'

// Asks "o que deve ser mudado?" before regenerating the current stage's fields.
// The instruction is OPTIONAL — submitting empty is a plain refill from the
// prior stages. On submit it hands the (possibly blank) instruction back up.
export default function AiFillDialog({ open, onOpenChange, onSubmit, pending = false, color = '#6366F1' }) {
  const { t } = useTranslation('ticket')
  const [instruction, setInstruction] = useState('')

  // Reset the field each time the dialog opens so a prior steer doesn't linger.
  useEffect(() => {
    if (open) setInstruction('')
  }, [open])

  const submit = (e) => {
    e.preventDefault()
    onSubmit?.(instruction.trim())
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: `${color}16`, color }}>
            <Wand2 size={20} strokeWidth={2.2} />
          </div>
          <DialogTitle>{t('aiFill.title')}</DialogTitle>
          <DialogDescription>
            {t('aiFill.description')}
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3.5">
          <div className="space-y-1.5">
            <Label>{t('aiFill.instructionLabel')} <span className="font-normal text-ink-muted">{t('aiFill.optional')}</span></Label>
            <Textarea
              value={instruction}
              onChange={(e) => setInstruction(e.target.value)}
              rows={3}
              autoFocus
              placeholder={t('aiFill.placeholder')}
            />
          </div>
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">{t('actions.cancel')}</Button></DialogClose>
            <Button type="submit" disabled={pending}>
              {pending ? t('aiFill.updating') : t('aiFill.submit')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
