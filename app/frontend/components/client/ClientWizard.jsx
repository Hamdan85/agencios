import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import i18n from '@/i18n'
import { Check, UserPlus, ArrowRight, ArrowLeft } from 'lucide-react'
import { POSITIONING_STEPS, EMPTY_POSITIONING, EMPTY_BRAND } from '@/lib/constants'
import { Button } from '@/components/ui/button'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'
import { maskPhone, maskDocument } from '@/lib/formatters'
import { ContactFields, PositioningStepFields, BrandIdentityFields, SiteImportPanel, BriefPanel, StatementPanel } from './positioningFields'

const ACCENT = '#6366F1'
const EMPTY_CONTACT = { name: '', company: '', email: '', phone: '', document: '', notes: '' }
const EMPTY_ASSETS = { logo: null, defaultCreatorAvatar: null, carouselBackground: null }

// Site import (AI fills everything) → contact → brand identity → free-text brief
// → review the structured positioning → final statement.
// Copy resolves lazily (getters) so it follows the active locale — same pattern
// as POSITIONING_STEPS in lib/constants.
const wizardStep = (key) => ({
  key,
  get title() { return i18n.t(`clients:wizard.steps.${key}.title`) },
  get description() { return i18n.t(`clients:wizard.steps.${key}.description`) },
})
const STEPS = [
  wizardStep('site'),
  wizardStep('contact'),
  wizardStep('brand'),
  wizardStep('brief'),
  ...POSITIONING_STEPS,
  wizardStep('statement'),
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
  const current = STEPS[step]
  return (
    <>
      {/* Mobile: nine 28px dots separated by ~2px connectors are impossible to hit, and
          each step's name only exists as a `title` attr — which never shows on touch. A
          labelled progress bar says where you are and how far is left. Desktop keeps the
          jumpable dot rail below, unchanged. */}
      <div className="shrink-0 space-y-1.5 sm:hidden">
        <div className="flex items-baseline justify-between gap-2">
          <span className="truncate text-sm font-semibold text-ink">{current.title}</span>
          <span className="shrink-0 font-mono text-xs font-semibold text-ink-faint">{step + 1}/{STEPS.length}</span>
        </div>
        <div className="h-1 overflow-hidden rounded-full bg-surface-muted">
          <div
            className="h-full rounded-full transition-all"
            style={{ width: `${((step + 1) / STEPS.length) * 100}%`, background: ACCENT }}
          />
        </div>
      </div>

    <div className="hidden shrink-0 items-center gap-1.5 overflow-x-auto no-scrollbar pb-1 sm:flex">
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
    </>
  )
}

export default function ClientWizard({ open, onOpenChange, editing, mutations }) {
  const { t } = useTranslation('clients')
  const isEdit = !!editing
  const [step, setStep] = useState(0)
  const [contact, setContact] = useState(EMPTY_CONTACT)
  const [brand, setBrand] = useState(EMPTY_BRAND)
  const [assets, setAssets] = useState(EMPTY_ASSETS)
  // Carousel background chosen from an existing platform creative: { id, url }.
  const [bgCreative, setBgCreative] = useState(null)
  const [brief, setBrief] = useState('')
  const [url, setUrl] = useState('')
  const [positioning, setPositioning] = useState(EMPTY_POSITIONING)

  const setContactField = (k, v) => setContact((c) => ({ ...c, [k]: v }))
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
    setBgCreative(null)
    setContact(isEdit
      ? { name: editing.name || '', company: editing.company || '', email: editing.email || '', phone: maskPhone(editing.phone || ''), document: maskDocument(editing.document || ''), notes: editing.notes || '' }
      : EMPTY_CONTACT)
    setBrand(isEdit
      ? {
          brand_voice: editing.brand_voice || '',
          default_handle: editing.default_handle || '',
          brand_primary_color: editing.brand_primary_color || EMPTY_BRAND.brand_primary_color,
          brand_secondary_color: editing.brand_secondary_color || EMPTY_BRAND.brand_secondary_color,
          carousel_style: editing.carousel_style || EMPTY_BRAND.carousel_style,
        }
      : EMPTY_BRAND)
    setPositioning(isEdit ? { ...EMPTY_POSITIONING, ...(editing.positioning || {}), content_pillars: editing.positioning?.content_pillars || [] } : EMPTY_POSITIONING)
  }

  const { create, update, synthesize, importFromUrl, uploadBrandAssets, setCarouselBackground } = mutations
  const saving = create?.isPending || update?.isPending || uploadBrandAssets?.isPending || setCarouselBackground?.isPending

  const close = () => { setSyncedKey(null); onOpenChange(false) }

  // After the client is saved: upload any chosen brand-asset files, then (if a
  // carousel background was picked from a creative) copy it, then close.
  const finishWith = (clientId) => {
    if (!clientId) return close()

    const copyBackground = () => {
      if (bgCreative?.id && setCarouselBackground) {
        setCarouselBackground.mutate({ id: clientId, creativeId: bgCreative.id }, { onSuccess: close, onError: close })
      } else {
        close()
      }
    }

    const hasUpload = assets.logo || assets.defaultCreatorAvatar || assets.carouselBackground
    if (hasUpload && uploadBrandAssets) {
      uploadBrandAssets.mutate({ id: clientId, assets }, { onSuccess: copyBackground, onError: close })
    } else {
      copyBackground()
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
      {/* On mobile the dialog is fullscreen: make it a flex column that owns its height so
          the body scrolls and the action bar stays put at the bottom. `overflow-hidden!` is
          needed to beat DialogContent's own `max-sm:overflow-y-auto` (only a max-sm: wins
          over a max-sm:) — otherwise we'd get two nested scrollers. */}
      <DialogContent className="max-w-xl max-sm:flex max-sm:flex-col max-sm:overflow-hidden!">
        <DialogHeader className="max-sm:shrink-0">
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: `${ACCENT}16`, color: ACCENT }}>
            <UserPlus size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>{isEdit ? t('show.editClient') : t('index.newClient')}</DialogTitle>
          <DialogDescription>
            {current.title} — {current.description}
          </DialogDescription>
        </DialogHeader>

        <WizardSteps step={step} onJump={(i) => { if (i <= 1 || contact.name.trim()) setStep(i) }} />

        {/* Step body — `vh` doesn't shrink when the iOS keyboard opens, so on mobile we let
            it flex instead of capping it. */}
        <div className="overflow-y-auto px-0.5 max-sm:min-h-0 max-sm:flex-1 max-sm:overscroll-contain sm:max-h-[52vh]">
          {isSite && (
            <SiteImportPanel
              url={url}
              onUrl={setUrl}
              onImport={importUrl}
              importing={importFromUrl?.isPending}
            />
          )}

          {isContact && <ContactFields contact={contact} onField={setContactField} />}

          {isBrand && (
            <BrandIdentityFields
              brand={brand}
              onBrand={setBrandField}
              assets={assets}
              onAsset={setAsset}
              logoUrl={editing?.logo_url}
              avatarUrl={editing?.default_creator_avatar_url}
              bgUrl={editing?.carousel_background_url}
              bgCreative={bgCreative}
              onBgCreative={setBgCreative}
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

        {/* DialogFooter is `flex-col-reverse` on mobile, which would put "Voltar" UNDER the
            thumb and push the primary action up. Force a row: secondary left, primary right. */}
        <DialogFooter className="max-sm:shrink-0 max-sm:flex-row max-sm:items-center max-sm:gap-2 sm:justify-between">
          {!isSite && (
            <Button
              type="button"
              variant="ghost"
              onClick={() => setStep((s) => s - 1)}
              className="max-sm:h-11 max-sm:flex-1"
            >
              <ArrowLeft /> {t('actions.back')}
            </Button>
          )}
          {/* sm:ml-auto — the Back button is now conditional (no phantom spacer div), so on the
              first step this is the only child and `justify-between` would pull it left. */}
          <div className="flex flex-col-reverse gap-2 max-sm:flex-1 max-sm:flex-row sm:ml-auto sm:flex-row">
            {/* "Criar rascunho" is a shortcut; three full-width CTAs don't fit a 320px bar. */}
            {isContact && (
              <Button type="button" variant="outline" onClick={submit} disabled={!contact.name.trim() || saving} className="max-sm:hidden">
                {isEdit ? t('wizard.save') : t('wizard.createDraft')}
              </Button>
            )}
            {!isStatement ? (
              <Button
                type="button"
                onClick={() => setStep((s) => s + 1)}
                disabled={!isSite && !contact.name.trim()}
                className="max-sm:h-11 max-sm:w-full"
              >
                {(isSite || isBrief) ? t('wizard.skip') : t('wizard.continue')} <ArrowRight />
              </Button>
            ) : (
              <Button
                type="button"
                onClick={submit}
                disabled={!contact.name.trim() || saving}
                className="max-sm:h-11 max-sm:w-full"
              >
                {saving ? t('wizard.saving') : isEdit ? t('wizard.saveClient') : t('wizard.createClient')}
              </Button>
            )}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
