import { useState } from 'react'
import { Check, UserPlus, ArrowRight, ArrowLeft } from 'lucide-react'
import { POSITIONING_STEPS, EMPTY_POSITIONING, EMPTY_BRAND } from '@/lib/constants'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'
import { maskPhone, maskDocument } from '@/lib/formatters'
import { PositioningStepFields, BrandIdentityFields, SiteImportPanel, BriefPanel, StatementPanel } from './positioningFields'

const ACCENT = '#6366F1'
const EMPTY_CONTACT = { name: '', company: '', email: '', phone: '', document: '', notes: '' }
const EMPTY_ASSETS = { logo: null, defaultCreatorAvatar: null }

// Site import (AI fills everything) → contact → brand identity → free-text brief
// → review the structured positioning → final statement.
const STEPS = [
  { key: 'site', title: 'Site', description: 'Importe tudo da landing page da marca.' },
  { key: 'contact', title: 'Contato', description: 'Quem é o cliente.' },
  { key: 'brand', title: 'Marca', description: 'Identidade visual e voz da marca.' },
  { key: 'brief', title: 'Descrição', description: 'Descreva a marca — a IA preenche o posicionamento.' },
  ...POSITIONING_STEPS,
  { key: 'statement', title: 'Posicionamento', description: 'Síntese final de marca.' },
]
const FIRST_POSITIONING = 4 // index of POSITIONING_STEPS[0] within STEPS
const LAST = STEPS.length - 1

// Converts a base64 data URL (the logo the backend extracted from the site) into
// a File so it previews and uploads through the same brand-assets path as a pick.
function dataUrlToFile(dataUrl, filename) {
  try {
    const [meta, b64] = String(dataUrl).split(',')
    if (!b64) return null
    const mime = meta.match(/data:(.*?);base64/)?.[1] || 'image/png'
    const bin = atob(b64)
    const arr = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i += 1) arr[i] = bin.charCodeAt(i)
    return new File([arr], filename || 'logo.png', { type: mime })
  } catch {
    return null
  }
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
  const [brand, setBrand] = useState(EMPTY_BRAND)
  const [assets, setAssets] = useState(EMPTY_ASSETS)
  const [brief, setBrief] = useState('')
  const [url, setUrl] = useState('')
  const [positioning, setPositioning] = useState(EMPTY_POSITIONING)

  const setC = (k) => (e) => setContact((c) => ({ ...c, [k]: e.target.value }))
  // Same as setC, but runs the typed value through a mask first.
  const setMaskedC = (k, mask) => (e) => setContact((c) => ({ ...c, [k]: mask(e.target.value) }))
  const setBrandField = (k, v) => setBrand((b) => ({ ...b, [k]: v }))
  const setAsset = (k, v) => setAssets((a) => ({ ...a, [k]: v }))
  const setField = (k, v) => setPositioning((p) => ({ ...p, [k]: v }))

  // Seed state when (re)opening — for create or for a given client.
  const openKey = `${open}:${editing?.id ?? 'new'}`
  const [syncedKey, setSyncedKey] = useState(null)
  if (open && openKey !== syncedKey) {
    setSyncedKey(openKey)
    setStep(isEdit ? 1 : 0) // editing: skip the site-import step, start at Contato
    setBrief('')
    setUrl('')
    setAssets(EMPTY_ASSETS)
    setContact(isEdit
      ? { name: editing.name || '', company: editing.company || '', email: editing.email || '', phone: maskPhone(editing.phone || ''), document: maskDocument(editing.document || ''), notes: editing.notes || '' }
      : EMPTY_CONTACT)
    setBrand(isEdit
      ? {
          brand_voice: editing.brand_voice || '',
          default_handle: editing.default_handle || '',
          brand_primary_color: editing.brand_primary_color || EMPTY_BRAND.brand_primary_color,
          brand_secondary_color: editing.brand_secondary_color || EMPTY_BRAND.brand_secondary_color,
        }
      : EMPTY_BRAND)
    setPositioning(isEdit ? { ...EMPTY_POSITIONING, ...(editing.positioning || {}), content_pillars: editing.positioning?.content_pillars || [] } : EMPTY_POSITIONING)
  }

  const { create, update, synthesize, importFromUrl, uploadBrandAssets } = mutations
  const saving = create?.isPending || update?.isPending || uploadBrandAssets?.isPending

  const close = () => { setSyncedKey(null); onOpenChange(false) }

  // Upload brand assets (if any were chosen) after the client is saved, then close.
  const finishWith = (clientId) => {
    if (clientId && (assets.logo || assets.defaultCreatorAvatar) && uploadBrandAssets) {
      uploadBrandAssets.mutate({ id: clientId, assets }, { onSuccess: close, onError: close })
    } else {
      close()
    }
  }

  const submit = () => {
    if (!contact.name.trim()) { setStep(0); return }
    const data = { ...contact, ...brand, positioning }
    if (isEdit) update.mutate({ id: editing.id, data }, { onSuccess: () => finishWith(editing.id) })
    else create.mutate(data, { onSuccess: (res) => finishWith(res?.client?.id) })
  }

  // Free-text brief → AI fills the structured positioning fields.
  const generate = () => {
    synthesize.mutate({ name: contact.name, brief }, {
      onSuccess: (res) => {
        const p = res?.positioning || {}
        setPositioning((cur) => ({ ...cur, ...p, content_pillars: p.content_pillars || cur.content_pillars || [] }))
        setStep(FIRST_POSITIONING)
      },
    })
  }

  // Site URL → AI extracts contact + brand identity (logo + colors) + positioning
  // in one shot. Anything the user already typed wins; positioning is replaced.
  // Lands on Contato so the user reviews the auto-filled fields from the top.
  const importUrl = () => {
    if (!url.trim() || !importFromUrl) return
    importFromUrl.mutate({ url: url.trim() }, {
      onSuccess: (res) => {
        const ex = res?.extracted || {}
        const c = ex.contact || {}
        const b = ex.brand || {}
        const p = ex.positioning || {}
        setContact((cur) => ({
          ...cur,
          name: cur.name || c.name || '',
          company: cur.company || c.company || '',
          email: cur.email || c.email || '',
          phone: cur.phone ? cur.phone : maskPhone(c.phone || ''),
        }))
        setBrand((cur) => ({
          ...cur,
          brand_voice: cur.brand_voice || b.brand_voice || '',
          default_handle: cur.default_handle || b.default_handle || '',
          brand_primary_color: b.brand_primary_color || cur.brand_primary_color,
          brand_secondary_color: b.brand_secondary_color || cur.brand_secondary_color,
        }))
        const logoFile = ex.logo?.data_url ? dataUrlToFile(ex.logo.data_url, ex.logo.filename) : null
        if (logoFile) setAssets((cur) => ({ ...cur, logo: cur.logo || logoFile }))
        setPositioning((cur) => ({ ...cur, ...p, content_pillars: p.content_pillars || cur.content_pillars || [] }))
        setStep(1)
      },
    })
  }

  const current = STEPS[step]
  const isSite = step === 0
  const isContact = step === 1
  const isBrand = step === 2
  const isBrief = step === 3
  const isStatement = step === LAST
  const positioningStep = step >= FIRST_POSITIONING && !isStatement ? POSITIONING_STEPS[step - FIRST_POSITIONING] : null

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

        <WizardSteps step={step} onJump={(i) => { if (i <= 1 || contact.name.trim()) setStep(i) }} />

        {/* Step body */}
        <div className="max-h-[52vh] overflow-y-auto px-0.5">
          {isSite && (
            <SiteImportPanel
              url={url}
              onUrl={setUrl}
              onImport={importUrl}
              importing={importFromUrl?.isPending}
            />
          )}

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
                  <Input id="cl-phone" type="tel" inputMode="numeric" value={contact.phone} onChange={setMaskedC('phone', maskPhone)} placeholder="(11) 99999-9999" />
                </div>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cl-document">Documento</Label>
                <Input id="cl-document" inputMode="numeric" value={contact.document} onChange={setMaskedC('document', maskDocument)} placeholder="CNPJ / CPF" />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cl-notes">Observações</Label>
                <Textarea id="cl-notes" value={contact.notes} onChange={setC('notes')} placeholder="Anotações sobre o cliente…" />
              </div>
            </div>
          )}

          {isBrand && (
            <BrandIdentityFields
              brand={brand}
              onBrand={setBrandField}
              assets={assets}
              onAsset={setAsset}
              logoUrl={editing?.logo_url}
              avatarUrl={editing?.default_creator_avatar_url}
            />
          )}

          {isBrief && (
            <BriefPanel brief={brief} onBrief={setBrief} onGenerate={generate} generating={synthesize?.isPending} />
          )}

          {positioningStep && (
            <PositioningStepFields step={positioningStep} positioning={positioning} onField={setField} />
          )}

          {isStatement && (
            <StatementPanel
              statement={positioning.statement}
              onStatement={(v) => setField('statement', v)}
              onRegenerate={generate}
              generating={synthesize?.isPending}
              canRegenerate={!!brief.trim()}
            />
          )}
        </div>

        <DialogFooter className="sm:justify-between">
          <div>
            {!isSite && (
              <Button type="button" variant="ghost" onClick={() => setStep((s) => s - 1)}>
                <ArrowLeft /> Voltar
              </Button>
            )}
          </div>
          <div className="flex flex-col-reverse gap-2 sm:flex-row">
            {isContact && (
              <Button type="button" variant="outline" onClick={submit} disabled={!contact.name.trim() || saving}>
                {isEdit ? 'Salvar' : 'Criar rascunho'}
              </Button>
            )}
            {!isStatement ? (
              <Button type="button" onClick={() => setStep((s) => s + 1)} disabled={!isSite && !contact.name.trim()}>
                {(isSite || isBrief) ? 'Pular' : 'Continuar'} <ArrowRight />
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
