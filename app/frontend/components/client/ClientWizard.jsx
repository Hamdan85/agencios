import { useState } from 'react'
import { Check, UserPlus, ArrowRight, ArrowLeft } from 'lucide-react'
import { POSITIONING_STEPS, EMPTY_POSITIONING } from '@/lib/constants'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'
import { PositioningStepFields, AiStatementPanel } from './positioningFields'

const ACCENT = '#6366F1'
const EMPTY_CONTACT = { name: '', company: '', email: '', phone: '', document: '', notes: '' }

// Contact step first, then the positioning framework steps, then the AI step.
const STEPS = [
  { key: 'contact', title: 'Contato', description: 'Quem é o cliente.' },
  ...POSITIONING_STEPS,
  { key: 'statement', title: 'Posicionamento', description: 'Síntese de marca com IA.' },
]
const LAST = STEPS.length - 1

const mergePillars = (current = [], incoming = []) => {
  const seen = new Set((current || []).map((p) => p.toLowerCase()))
  const extra = (incoming || []).filter((p) => p && !seen.has(p.toLowerCase()))
  return [...(current || []), ...extra]
}

// Compact horizontal step indicator.
function WizardSteps({ step, onJump }) {
  return (
    <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar pb-1">
      {STEPS.map((s, i) => {
        const done = i < step
        const current = i === step
        return (
          <div key={s.key} className="flex flex-1 items-center gap-1.5">
            <button
              type="button"
              onClick={() => onJump(i)}
              title={s.title}
              className={cn(
                'flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-bold transition-all',
                !current && !done && 'bg-surface-muted text-ink-faint',
              )}
              style={current || done ? { background: done ? ACCENT : `${ACCENT}1A`, color: done ? '#fff' : ACCENT } : undefined}
            >
              {done ? <Check size={14} strokeWidth={3} /> : i + 1}
            </button>
            {i < LAST && <span className="h-0.5 flex-1 rounded-full" style={{ background: i < step ? ACCENT : 'var(--ag-connector, #E7E3F0)' }} />}
          </div>
        )
      })}
    </div>
  )
}

export default function ClientWizard({ open, onOpenChange, editing, mutations }) {
  const isEdit = !!editing
  const [step, setStep] = useState(0)
  const [contact, setContact] = useState(EMPTY_CONTACT)
  const [positioning, setPositioning] = useState(EMPTY_POSITIONING)

  const setC = (k) => (e) => setContact((c) => ({ ...c, [k]: e.target.value }))
  const setField = (k, v) => setPositioning((p) => ({ ...p, [k]: v }))

  // Seed state when (re)opening — for create or for a given client.
  const openKey = `${open}:${editing?.id ?? 'new'}`
  const [syncedKey, setSyncedKey] = useState(null)
  if (open && openKey !== syncedKey) {
    setSyncedKey(openKey)
    setStep(0)
    setContact(isEdit
      ? { name: editing.name || '', company: editing.company || '', email: editing.email || '', phone: editing.phone || '', document: editing.document || '', notes: editing.notes || '' }
      : EMPTY_CONTACT)
    setPositioning(isEdit ? { ...EMPTY_POSITIONING, ...(editing.positioning || {}), content_pillars: editing.positioning?.content_pillars || [] } : EMPTY_POSITIONING)
  }

  const create = mutations.create
  const update = mutations.update
  const synthesize = mutations.synthesize
  const saving = create?.isPending || update?.isPending

  const close = () => { setSyncedKey(null); onOpenChange(false) }

  const submit = () => {
    if (!contact.name.trim()) { setStep(0); return }
    const data = { ...contact, positioning }
    const onSuccess = close
    if (isEdit) update.mutate({ id: editing.id, data }, { onSuccess })
    else create.mutate(data, { onSuccess })
  }

  const generate = () => {
    const { statement, ...inputs } = positioning // eslint-disable-line no-unused-vars
    synthesize.mutate({ name: contact.name, ...inputs }, {
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

  const current = STEPS[step]
  const isContact = step === 0
  const isStatement = step === LAST
  const positioningStep = !isContact && !isStatement ? POSITIONING_STEPS[step - 1] : null

  return (
    <Dialog open={open} onOpenChange={(v) => (v ? onOpenChange(true) : close())}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: `${ACCENT}16`, color: ACCENT }}>
            <UserPlus size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>{isEdit ? 'Editar cliente' : 'Novo cliente'}</DialogTitle>
          <DialogDescription>
            {current.title} — {current.description}
          </DialogDescription>
        </DialogHeader>

        <WizardSteps step={step} onJump={(i) => { if (contact.name.trim() || i === 0) setStep(i) }} />

        {/* Step body */}
        <div className="max-h-[52vh] overflow-y-auto px-0.5">
          {isContact && (
            <div className="space-y-3.5">
              <div className="space-y-1.5">
                <Label htmlFor="cl-name">Nome</Label>
                <Input id="cl-name" autoFocus required value={contact.name} onChange={setC('name')} placeholder="Nome do contato" />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cl-company">Empresa</Label>
                <Input id="cl-company" value={contact.company} onChange={setC('company')} placeholder="Nome da empresa" />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label htmlFor="cl-email">E-mail</Label>
                  <Input id="cl-email" type="email" value={contact.email} onChange={setC('email')} placeholder="contato@empresa.com" />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="cl-phone">Telefone</Label>
                  <Input id="cl-phone" value={contact.phone} onChange={setC('phone')} placeholder="(11) 99999-9999" />
                </div>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cl-document">Documento</Label>
                <Input id="cl-document" value={contact.document} onChange={setC('document')} placeholder="CNPJ / CPF" />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cl-notes">Observações</Label>
                <Textarea id="cl-notes" value={contact.notes} onChange={setC('notes')} placeholder="Anotações sobre o cliente…" />
              </div>
            </div>
          )}

          {positioningStep && (
            <PositioningStepFields step={positioningStep} positioning={positioning} onField={setField} />
          )}

          {isStatement && (
            <AiStatementPanel
              statement={positioning.statement}
              onStatement={(v) => setField('statement', v)}
              onGenerate={generate}
              generating={synthesize?.isPending}
            />
          )}
        </div>

        <DialogFooter className="sm:justify-between">
          <div>
            {!isContact && (
              <Button type="button" variant="ghost" onClick={() => setStep((s) => s - 1)}>
                <ArrowLeft /> Voltar
              </Button>
            )}
          </div>
          <div className="flex flex-col-reverse gap-2 sm:flex-row">
            {isContact && (
              <Button type="button" variant="outline" onClick={submit} disabled={!contact.name.trim() || saving}>
                {isEdit ? 'Salvar' : 'Criar sem posicionamento'}
              </Button>
            )}
            {!isStatement ? (
              <Button type="button" onClick={() => setStep((s) => s + 1)} disabled={!contact.name.trim()}>
                Continuar <ArrowRight />
              </Button>
            ) : (
              <Button type="button" onClick={submit} disabled={!contact.name.trim() || saving}>
                {saving ? 'Salvando…' : isEdit ? 'Salvar cliente' : 'Criar cliente'}
              </Button>
            )}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
