import { useState } from 'react'
import { Sparkles } from 'lucide-react'
import { POSITIONING_STEPS, EMPTY_POSITIONING } from '@/lib/constants'
import { Button } from '@/components/ui/button'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { PositioningStepFields, AiStatementPanel } from './positioningFields'

const ACCENT = '#6366F1'

const mergePillars = (current = [], incoming = []) => {
  const seen = new Set((current || []).map((p) => p.toLowerCase()))
  return [...(current || []), ...(incoming || []).filter((p) => p && !seen.has(p.toLowerCase()))]
}

// Single-screen positioning editor for the client detail page. Reuses the same
// field renderers + AI panel as the creation wizard.
export default function PositioningEditDialog({ open, onOpenChange, client, mutations }) {
  const [positioning, setPositioning] = useState(EMPTY_POSITIONING)
  const setField = (k, v) => setPositioning((p) => ({ ...p, [k]: v }))

  const openKey = `${open}:${client?.id ?? 'none'}`
  const [syncedKey, setSyncedKey] = useState(null)
  if (open && openKey !== syncedKey) {
    setSyncedKey(openKey)
    setPositioning({ ...EMPTY_POSITIONING, ...(client?.positioning || {}), content_pillars: client?.positioning?.content_pillars || [] })
  }

  const { synthesize, updatePositioning } = mutations
  const close = () => { setSyncedKey(null); onOpenChange(false) }

  const generate = () => {
    const { statement, ...inputs } = positioning // eslint-disable-line no-unused-vars
    synthesize.mutate({ name: client?.name, ...inputs }, {
      onSuccess: (res) => {
        const p = res?.positioning || {}
        setPositioning((cur) => ({
          ...cur,
          statement: p.statement || cur.statement,
          content_pillars: mergePillars(cur.content_pillars, p.content_pillars),
        }))
      },
    })
  }

  const save = () => updatePositioning.mutate({ id: client.id, positioning }, { onSuccess: close })

  return (
    <Dialog open={open} onOpenChange={(v) => (v ? onOpenChange(true) : close())}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: `${ACCENT}16`, color: ACCENT }}>
            <Sparkles size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>Posicionamento</DialogTitle>
          <DialogDescription>Defina o posicionamento de {client?.name} — usado como contexto pela IA em todos os tickets.</DialogDescription>
        </DialogHeader>

        <div className="max-h-[56vh] space-y-5 overflow-y-auto px-0.5">
          {POSITIONING_STEPS.map((step) => (
            <div key={step.key} className="space-y-3.5">
              <h4 className="text-xs font-bold uppercase tracking-wider text-ink-faint">{step.title}</h4>
              <PositioningStepFields step={step} positioning={positioning} onField={setField} />
            </div>
          ))}
          <div className="space-y-3.5 border-t border-border pt-5">
            <AiStatementPanel
              statement={positioning.statement}
              onStatement={(v) => setField('statement', v)}
              onGenerate={generate}
              generating={synthesize?.isPending}
            />
          </div>
        </div>

        <DialogFooter>
          <DialogClose asChild>
            <Button type="button" variant="ghost">Cancelar</Button>
          </DialogClose>
          <Button type="button" onClick={save} disabled={updatePositioning.isPending}>
            {updatePositioning.isPending ? 'Salvando…' : 'Salvar posicionamento'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
