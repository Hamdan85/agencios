import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { User, Palette, Compass, Layers, Sparkles } from 'lucide-react'
import { SettingsDialog, SettingsPanel } from '@/components/ui/settings-dialog'
import { Button } from '@/components/ui/button'
import { SectionLabel } from '@/components/ui/section-label'
import { Spinner } from '@/components/ui/feedback'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { useClient } from '@/hooks/useData'
import { POSITIONING_STEPS, EMPTY_POSITIONING, EMPTY_BRAND } from '@/lib/constants'
import { maskPhone, maskDocument } from '@/lib/formatters'
import { ContactFields, BrandIdentityFields, PositioningStepFields, StatementPanel } from './positioningFields'

const ACCENT = '#6366F1'
const EMPTY_CONTACT = { name: '', company: '', email: '', phone: '', document: '', notes: '' }
const EMPTY_ASSETS = { logo: null, defaultCreatorAvatar: null, carouselBackground: null }

// Editing a client is NOT the creation wizard — jump straight to the section you
// want via a vertical tab rail (Contato · Marca · Posicionamento · Conteúdo ·
// Síntese). Reuses the same field components as the wizard (one source of truth);
// only the chrome (tabbed dialog vs. linear stepper) differs. Single global save.
//
// Posicionamento groups the identity/audience/differentiation steps; Conteúdo is
// the content step; both drive the Marca image-palette swatches.
const POS_MAIN = POSITIONING_STEPS.slice(0, 3)
const POS_CONTENT = POSITIONING_STEPS[3]

const seedContact = (c) => ({
  name: c.name || '', company: c.company || '', email: c.email || '',
  phone: maskPhone(c.phone || ''), document: maskDocument(c.document || ''), notes: c.notes || '',
})
const seedBrand = (c) => ({
  brand_voice: c.brand_voice || '',
  default_handle: c.default_handle || '',
  brand_primary_color: c.brand_primary_color || EMPTY_BRAND.brand_primary_color,
  brand_secondary_color: c.brand_secondary_color || EMPTY_BRAND.brand_secondary_color,
  carousel_style: c.carousel_style || EMPTY_BRAND.carousel_style,
})
const seedPositioning = (c) => ({
  ...EMPTY_POSITIONING, ...(c.positioning || {}), content_pillars: c.positioning?.content_pillars || [],
})

export default function ClientEditDialog({ open, onOpenChange, client, mutations }) {
  const { t } = useTranslation('clients')
  const [tab, setTab] = useState('contact')
  const [contact, setContact] = useState(EMPTY_CONTACT)
  const [brand, setBrand] = useState(EMPTY_BRAND)
  const [assets, setAssets] = useState(EMPTY_ASSETS)
  const [bgCreative, setBgCreative] = useState(null)
  const [positioning, setPositioning] = useState(EMPTY_POSITIONING)
  const [dirty, setDirty] = useState(false)

  const id = client?.id
  const palettePending = (c) =>
    c?.carousel_style === 'image' && !!c?.carousel_background_url && !c?.carousel_image_palette?.accent
  // Poll while an image background exists but its palette hasn't landed yet — the
  // derivation runs async in a background job.
  const { data, isLoading } = useClient(id, {
    poll: open ? (d) => (palettePending(d?.client) ? 4000 : false) : false,
  })
  const live = data?.client

  // Seed local form state from the fully-loaded client, once per open/client.
  const syncKey = open && live ? `${id}` : null
  const [synced, setSynced] = useState(null)
  if (syncKey && syncKey !== synced) {
    setSynced(syncKey)
    setTab('contact')
    setContact(seedContact(live))
    setBrand(seedBrand(live))
    setPositioning(seedPositioning(live))
    setAssets(EMPTY_ASSETS)
    setBgCreative(null)
    setDirty(false)
  }
  if (!open && synced) setSynced(null)

  const touch = () => setDirty(true)
  const setContactField = (k, v) => { setContact((c) => ({ ...c, [k]: v })); touch() }
  const setBrandField = (k, v) => { setBrand((b) => ({ ...b, [k]: v })); touch() }
  const setAsset = (k, v) => { setAssets((a) => ({ ...a, [k]: v })); touch() }
  const setBg = (v) => { setBgCreative(v); touch() }
  const setPosField = (k, v) => { setPositioning((p) => ({ ...p, [k]: v })); touch() }

  const { update, uploadBrandAssets, setCarouselBackground, reanalyzeCarouselPalette } = mutations
  const saving = update?.isPending || uploadBrandAssets?.isPending || setCarouselBackground?.isPending

  const confirm = useConfirm()

  // The close X is absolutely positioned over the tab rail on mobile, so a mistap while
  // scrolling the tabs is easy — and it used to discard every edit silently.
  const close = async () => {
    if (dirty && !(await confirm({
      title: t('editDialog.discardTitle'),
      description: t('editDialog.discardDescription'),
      confirmLabel: t('editDialog.discardConfirm'),
      destructive: true,
    }))) return
    onOpenChange(false)
  }

  // Single save: persist the text fields, then (if any) upload asset files, then
  // (if a creative was picked) copy the carousel background — mirrors the wizard.
  const save = () => {
    // Silently switching tabs reads as "the button did nothing" — especially on mobile,
    // where the target tab may be scrolled off the rail. Say what's wrong.
    if (!contact.name.trim()) {
      setTab('contact')
      toast.error(t('editDialog.nameRequired'))
      requestAnimationFrame(() => document.getElementById('cl-name')?.focus())
      return
    }
    const finish = () => { setDirty(false); close() }
    const copyBg = () => {
      if (bgCreative?.id && setCarouselBackground) {
        setCarouselBackground.mutate({ id, creativeId: bgCreative.id }, { onSuccess: finish, onError: finish })
      } else finish()
    }
    const afterFields = () => {
      const hasUpload = assets.logo || assets.defaultCreatorAvatar || assets.carouselBackground
      if (hasUpload && uploadBrandAssets) {
        uploadBrandAssets.mutate({ id, assets }, { onSuccess: copyBg, onError: finish })
      } else copyBg()
    }
    update.mutate({ id, data: { ...contact, ...brand, positioning } }, { onSuccess: afterFields })
  }

  const sections = [
    { key: 'contact', label: t('editDialog.sections.contact'), icon: User },
    { key: 'brand', label: t('editDialog.sections.brand'), icon: Palette, dirty },
    { key: 'positioning', label: t('editDialog.sections.positioning'), icon: Compass },
    { key: 'content', label: t('editDialog.sections.content'), icon: Layers },
    { key: 'statement', label: t('editDialog.sections.statement'), icon: Sparkles },
  ]

  return (
    <SettingsDialog
      open={open}
      onOpenChange={(v) => (v ? onOpenChange(true) : close())}
      title={t('show.editClient')}
      description={live?.name || client?.name}
      icon={User}
      accent={ACCENT}
      sections={sections}
      value={tab}
      onValueChange={setTab}
      footer={(
        <>
          <Button variant="ghost" onClick={close}>{t('actions.close')}</Button>
          <Button onClick={save} disabled={!dirty || saving}>
            {saving ? t('wizard.saving') : t('editDialog.saveChanges')}
          </Button>
        </>
      )}
    >
      {isLoading || !live ? (
        <div className="grid place-items-center py-16"><Spinner /></div>
      ) : (
        <>
          <SettingsPanel value="contact">
            <ContactFields contact={contact} onField={setContactField} />
          </SettingsPanel>

          <SettingsPanel value="brand">
            <BrandIdentityFields
              brand={brand}
              onBrand={setBrandField}
              assets={assets}
              onAsset={setAsset}
              logoUrl={live.logo_url}
              avatarUrl={live.default_creator_avatar_url}
              bgUrl={live.carousel_background_url}
              bgCreative={bgCreative}
              onBgCreative={setBg}
              palette={live.carousel_image_palette || {}}
              onReanalyzePalette={() => reanalyzeCarouselPalette?.mutate({ id })}
              analyzingPalette={reanalyzeCarouselPalette?.isPending}
            />
          </SettingsPanel>

          <SettingsPanel value="positioning" className="space-y-6">
            {POS_MAIN.map((step) => (
              <section key={step.key} className="space-y-3.5">
                <SectionLabel>{step.title}</SectionLabel>
                <PositioningStepFields step={step} positioning={positioning} onField={setPosField} />
              </section>
            ))}
          </SettingsPanel>

          <SettingsPanel value="content">
            {POS_CONTENT && (
              <PositioningStepFields step={POS_CONTENT} positioning={positioning} onField={setPosField} />
            )}
          </SettingsPanel>

          <SettingsPanel value="statement">
            <StatementPanel
              statement={positioning.statement}
              onStatement={(v) => setPosField('statement', v)}
              canRegenerate={false}
            />
          </SettingsPanel>
        </>
      )}
    </SettingsDialog>
  )
}
