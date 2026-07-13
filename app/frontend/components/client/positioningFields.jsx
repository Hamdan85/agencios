import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useIsMobile } from '@/hooks/useMediaQuery'
import i18n from '@/i18n'
import { Sparkles, Wand2, Image as ImageIcon, UserCircle2, Globe, Check, Upload, Images, X } from 'lucide-react'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { InlineSpinner } from '@/components/ui/feedback'
import { cn } from '@/lib/utils'
import { maskPhone, maskDocument } from '@/lib/formatters'
import CarouselBackgroundPicker from './CarouselBackgroundPicker'

// Client contact fields — shared by the creation wizard and the edit dialog so the
// fields have ONE source of truth. Owns the phone/document input masks; `onField`
// receives the already-masked value.
export function ContactFields({ contact, onField }) {
  const { t } = useTranslation('clients')
  const set = (k) => (e) => onField(k, e.target.value)
  const masked = (k, mask) => (e) => onField(k, mask(e.target.value))
  return (
    <div className="space-y-3.5">
      <div className="space-y-1.5">
        <Label htmlFor="cl-name">{t('fields.name')}</Label>
        <Input id="cl-name" required value={contact.name || ''} onChange={set('name')} placeholder={t('fields.namePlaceholder')} />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="cl-company">{t('fields.company')}</Label>
        <Input id="cl-company" value={contact.company || ''} onChange={set('company')} placeholder={t('fields.companyPlaceholder')} />
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="cl-email">{t('fields.email')}</Label>
          <Input id="cl-email" type="email" value={contact.email || ''} onChange={set('email')} placeholder={t('fields.emailPlaceholder')} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="cl-phone">{t('fields.phone')}</Label>
          <Input id="cl-phone" type="tel" inputMode="numeric" value={contact.phone || ''} onChange={masked('phone', maskPhone)} placeholder={t('fields.phonePlaceholder')} />
        </div>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="cl-document">{t('fields.document')}</Label>
        <Input id="cl-document" inputMode="numeric" value={contact.document || ''} onChange={masked('document', maskDocument)} placeholder={t('fields.documentPlaceholder')} />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="cl-notes">{t('fields.notes')}</Label>
        <Textarea id="cl-notes" value={contact.notes || ''} onChange={set('notes')} placeholder={t('fields.notesPlaceholder')} />
      </div>
    </div>
  )
}

// content_pillars is stored as an array; the textarea edits one pillar per line.
export const pillarsToText = (arr) => (Array.isArray(arr) ? arr.join('\n') : arr || '')
export const textToPillars = (str) =>
  String(str || '')
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean)

// Renders a single positioning field by its declared type.
export function PositioningField({ field, value, onChange }) {
  const id = `pos-${field.key}`
  const isMobile = useIsMobile()
  const common = { id, placeholder: field.placeholder }
  // Textarea auto-grows to maxRows (18 ≈ 380px) and writes height/overflowY INLINE, so a
  // CSS max-height can't clamp it (the inline `overflow-y: hidden` would just hide the
  // overflow). An AI-filled field would then grow taller than the space above the
  // keyboard and push the cursor off-screen. Cap it via the prop; it scrolls internally.
  const area = { ...common, maxRows: isMobile ? 8 : undefined }

  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>{field.label}</Label>
      {field.type === 'text' ? (
        <Input {...common} value={value || ''} onChange={(e) => onChange(field.key, e.target.value)} />
      ) : field.type === 'pillars' ? (
        <Textarea
          {...area}
          rows={4}
          value={pillarsToText(value)}
          onChange={(e) => onChange(field.key, textToPillars(e.target.value))}
        />
      ) : (
        <Textarea {...area} value={value || ''} onChange={(e) => onChange(field.key, e.target.value)} />
      )}
    </div>
  )
}

// Renders the fields of one positioning step.
export function PositioningStepFields({ step, positioning, onField }) {
  return (
    <div className="space-y-3.5">
      {step.fields.map((field) => (
        <PositioningField key={field.key} field={field} value={positioning[field.key]} onChange={onField} />
      ))}
    </div>
  )
}

// Small color picker (native swatch + hex input) kept in sync.
function ColorField({ label, value, onChange }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      <div className="flex items-center gap-2">
        <input
          type="color"
          value={value || '#000000'}
          onChange={(e) => onChange(e.target.value)}
          className="size-10 shrink-0 cursor-pointer rounded-lg border border-border bg-surface p-1 max-sm:size-11"
        />
        <Input value={value || ''} onChange={(e) => onChange(e.target.value)} placeholder="#7C3AED" className="font-mono" />
      </div>
    </div>
  )
}

// Darken/lighten a #rrggbb hex by `pct` percent — mirrors the backend
// Creatives::CarouselSlideTemplate#shade so the preview matches the real slide.
function shade(hex, pct) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim())
  if (!m) return hex || '#7C3AED'
  const n = parseInt(m[1], 16)
  const adj = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) =>
    Math.min(255, Math.max(0, Math.round(c + (255 * pct) / 100))),
  )
  return `#${adj.map((c) => c.toString(16).padStart(2, '0')).join('')}`
}

// Labels resolve lazily (getters) so they follow the active locale — same
// pattern as the label maps in lib/constants.
const tr = (key) => i18n.t(`clients:${key}`)
export const CAROUSEL_STYLES = [
  { key: 'gradient', get label() { return tr('carousel.styles.gradient') } },
  { key: 'white', get label() { return tr('carousel.styles.white') } },
  { key: 'image', get label() { return tr('carousel.styles.image') } },
]
export const CAROUSEL_STYLE_LABEL = {
  get gradient() { return tr('carousel.styles.gradient') },
  get white() { return tr('carousel.styles.white') },
  get image() { return tr('carousel.styles.image') },
}

// A faithful miniature of a generated carousel slide using the client's real
// brand colors — mirrors Creatives::CarouselSlideTemplate so each option is a
// literal example of the actual output, not a mockup. For the `image` style it
// renders the chosen background photo behind a scrim (the has-image layout).
export function CarouselSlidePreview({ style, primary, secondary, imageUrl, className }) {
  const { t } = useTranslation('clients')
  const p = primary || '#7C3AED'
  const s = secondary || '#F59E0B'
  const white = style === 'white'
  const image = style === 'image'
  const bg = white
    ? '#ffffff'
    : image
      ? '#2b2730'
      : `radial-gradient(120% 120% at 0% 0%, ${p} 0%, ${shade(p, -28)} 70%)`
  const ink = white ? '#18161d' : '#ffffff'
  return (
    <div className={cn('relative aspect-4/5 w-full overflow-hidden rounded-lg', className)} style={{ background: bg, color: ink }}>
      {/* Image style shows the photo clean — no darkening lens (mirrors the
          backend CarouselSlideTemplate). Copy stays legible via text-shadow. */}
      {image && imageUrl && (
        <img src={imageUrl} alt="" className="absolute inset-0 size-full object-cover" />
      )}
      <div className={cn('relative p-3', image && '[text-shadow:0_1px_6px_rgba(0,0,0,.6)]')}>
        <div className="flex items-center gap-1.5">
          <span className="size-4 shrink-0 rounded-full" style={{ background: s }} />
          <div className="space-y-1">
            <span className="block h-1 w-9 rounded-full" style={{ background: ink, opacity: 0.9 }} />
            <span className="block h-1 w-5 rounded-full" style={{ background: ink, opacity: 0.45 }} />
          </div>
        </div>
        <div className="mt-4 space-y-1.5">
          <span className="block text-[11px] font-extrabold leading-tight">{t('carousel.previewHeadline')}</span>
          {!image && <span className="block h-1 w-6 rounded-full" style={{ background: s }} />}
        </div>
      </div>
      <span className="absolute bottom-2.5 left-3 z-10 text-[8px] font-bold" style={{ opacity: 0.8 }}>{t('example.swipe')}</span>
    </div>
  )
}

// Literal slide previews the user picks between; drives carousel generation.
function CarouselStyleField({ value, onChange, primary, secondary, imageUrl }) {
  const { t } = useTranslation('clients')
  const active = value || 'gradient'
  return (
    <div className="space-y-1.5">
      <Label>{t('carousel.styleLabel')}</Label>
      <p className="-mt-0.5 text-xs text-ink-faint">{t('carousel.styleHint')}</p>
      {/* The preview IS the decision surface for the client's visual identity. A fixed
          3-up grid squeezes it to ~84px on a phone (illegible), so below sm it becomes a
          snap rail with ~62%-wide cards — the peeking next card also signals there's more. */}
      <div className="max-sm:no-scrollbar max-sm:-mx-4 max-sm:flex max-sm:snap-x max-sm:snap-mandatory max-sm:overflow-x-auto max-sm:px-4 grid grid-cols-3 gap-2.5 max-sm:grid-cols-none">
        {CAROUSEL_STYLES.map((opt) => {
          const on = active === opt.key
          return (
            <button
              key={opt.key}
              type="button"
              onClick={() => onChange(opt.key)}
              className={cn('rounded-xl border p-1.5 text-left transition max-sm:w-[62%] max-sm:shrink-0 max-sm:snap-start', on ? 'border-brand ring-2 ring-brand/30' : 'border-border hover:border-brand/40')}
            >
              <CarouselSlidePreview style={opt.key} primary={primary} secondary={secondary} imageUrl={imageUrl} />
              <div className="mt-1.5 flex items-center gap-1 px-0.5">
                <span className={cn('grid size-3.5 shrink-0 place-items-center rounded-full border max-sm:size-5', on ? 'border-brand bg-brand text-white' : 'border-border')}>
                  {on && <Check size={10} strokeWidth={3} />}
                </span>
                <span className="truncate text-[11px] font-semibold text-ink-secondary max-sm:text-sm">{opt.label}</span>
              </div>
            </button>
          )
        })}
      </div>
    </div>
  )
}

// One image upload tile (logo or creator avatar). Shows the selected file name
// or the current saved image when editing.
function ImageField({ label, icon: Icon, file, currentUrl, onFile, rounded }) {
  const { t } = useTranslation('clients')
  const preview = file ? URL.createObjectURL(file) : currentUrl
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-dashed border-border bg-surface-muted/40 p-3 transition hover:border-brand/50">
        <div className={`grid size-12 shrink-0 place-items-center overflow-hidden bg-surface text-ink-faint ring-1 ring-border ${rounded ? 'rounded-full' : 'rounded-lg'}`}>
          {preview ? <img src={preview} alt="" className="size-full object-cover" /> : <Icon size={20} />}
        </div>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-ink-secondary">{file ? file.name : (currentUrl ? t('fields.currentImage') : t('fields.chooseImage'))}</p>
          <p className="text-xs text-ink-faint">{t('fields.imageFormats')}</p>
        </div>
        <input type="file" accept="image/*" className="hidden" onChange={(e) => onFile(e.target.files?.[0] || null)} />
      </label>
    </div>
  )
}

// The carousel background source chooser, shown when the `image` style is picked:
// upload a file or pick an existing platform creative. `bgCreative` = {id,url}.
function CarouselBackgroundChooser({ bgPreview, onFile, bgCreative, onBgCreative }) {
  const { t } = useTranslation('clients')
  const [pickerOpen, setPickerOpen] = useState(false)
  return (
    <div className="space-y-2 rounded-xl border border-border bg-surface-muted/40 p-3">
      <div className="flex items-center gap-3">
        <div className="grid size-14 shrink-0 place-items-center overflow-hidden rounded-lg bg-surface text-ink-faint ring-1 ring-border">
          {bgPreview ? <img src={bgPreview} alt="" className="size-full object-cover" /> : <ImageIcon size={20} />}
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-ink-secondary">
            {bgPreview ? t('carousel.bgSet') : t('carousel.bgChoose')}
          </p>
          <p className="text-xs text-ink-faint">{t('carousel.bgHint')}</p>
        </div>
        {bgPreview && (
          <button type="button" onClick={() => { onFile(null); onBgCreative(null) }} className="shrink-0 rounded-lg p-1.5 text-ink-faint transition hover:bg-surface hover:text-ink max-sm:p-3" title={t('actions.remove')}>
            <X size={16} />
          </button>
        )}
      </div>
      <div className="flex flex-wrap gap-2 max-sm:grid max-sm:grid-cols-2">
        <label className="inline-flex cursor-pointer items-center justify-center gap-1.5 rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-semibold text-ink-secondary transition hover:border-brand/50 max-sm:h-11 max-sm:text-sm">
          <Upload size={14} /> {t('carousel.uploadImage')}
          <input type="file" accept="image/*" className="hidden" onChange={(e) => onFile(e.target.files?.[0] || null)} />
        </label>
        <Button type="button" variant="outline" size="sm" onClick={() => setPickerOpen(true)} className="max-sm:h-11 max-sm:w-full max-sm:text-sm">
          <Images size={14} /> {t('carousel.pickFromCreative')}
        </Button>
      </div>
      <CarouselBackgroundPicker open={pickerOpen} onOpenChange={setPickerOpen} onSelect={onBgCreative} />
    </div>
  )
}

// A single derived-color swatch with its label.
function PaletteSwatch({ color, label }) {
  if (!color) return null
  return (
    <div className="flex items-center gap-1.5">
      <span className="size-6 rounded-md ring-1 ring-border" style={{ background: color }} />
      <div className="leading-tight">
        <span className="block text-[11px] font-semibold text-ink-secondary">{label}</span>
        <span className="block font-mono text-[10px] uppercase text-ink-faint">{color}</span>
      </div>
    </div>
  )
}

// The image-style carousel palette the AI derived from the background photo. This
// is READ-ONLY and intentionally SEPARATE from the brand colors — the image
// background has its own colors, distinct from the gradient/white backgrounds that
// use the brand palette. Only rendered by the edit dialog (which can re-analyze);
// the wizard omits the `palette` prop (analysis runs after the image is saved).
export function CarouselPaletteSwatches({ palette, hasBackground, onReanalyze, analyzing }) {
  const { t } = useTranslation('clients')
  const accent = palette?.accent
  const hasColors = !!(accent || palette?.text_color)
  return (
    <div className="space-y-2 rounded-xl border border-border bg-surface-muted/40 p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5">
          <Sparkles size={13} className="text-brand" />
          <Label className="mb-0">{t('palette.title')}</Label>
        </div>
        {hasBackground && onReanalyze && (
          <button
            type="button"
            onClick={onReanalyze}
            disabled={analyzing}
            className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold text-ink-secondary transition hover:bg-surface disabled:opacity-50 max-sm:h-10 max-sm:px-3"
          >
            {analyzing ? <InlineSpinner size={12} /> : <Wand2 size={12} />} {t('palette.reanalyze')}
          </button>
        )}
      </div>
      {hasColors ? (
        <div className="flex flex-wrap items-center gap-4">
          <PaletteSwatch color={accent} label={t('palette.accent')} />
          <PaletteSwatch color={palette.text_color} label={t('palette.text')} />
          {palette.scrim_opacity > 0 && (
            <span className="text-xs text-ink-faint">{t('palette.scrim', { pct: Math.round(palette.scrim_opacity * 100) })}</span>
          )}
        </div>
      ) : (
        <p className="text-xs text-ink-faint">
          {hasBackground
            ? t('palette.analyzing')
            : t('palette.noBackground')}
        </p>
      )}
      <p className="text-[11px] leading-snug text-ink-faint">
        {t('palette.note')}
      </p>
    </div>
  )
}

// Brand identity step: voice + @handle + colors + carousel style + logo/avatar uploads.
// `palette`/`onReanalyzePalette`/`analyzingPalette` are passed only by the edit
// dialog to surface the image-style derived palette; the wizard omits them.
export function BrandIdentityFields({
  brand, onBrand, assets, onAsset, logoUrl, avatarUrl, bgUrl, bgCreative, onBgCreative,
  palette, onReanalyzePalette, analyzingPalette,
}) {
  const { t } = useTranslation('clients')
  const carouselStyle = brand.carousel_style || 'gradient'
  const bgFileUrl = assets.carouselBackground ? URL.createObjectURL(assets.carouselBackground) : null
  const bgPreview = bgCreative?.url || bgFileUrl || bgUrl || null

  // Uploading a file and picking a creative are mutually exclusive sources.
  const setBgFile = (f) => { onAsset('carouselBackground', f); if (f) onBgCreative(null) }
  const setBgCreative = (sel) => { onBgCreative(sel); if (sel) onAsset('carouselBackground', null) }

  return (
    <div className="space-y-3.5">
      <div className="space-y-1.5">
        <Label htmlFor="brand-voice">{t('brand.voice')}</Label>
        <Textarea
          id="brand-voice"
          value={brand.brand_voice || ''}
          onChange={(e) => onBrand('brand_voice', e.target.value)}
          placeholder={t('brandFields.voicePlaceholder')}
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="brand-handle">{t('brandFields.handleLabel')}</Label>
        <Input
          id="brand-handle"
          value={brand.default_handle || ''}
          onChange={(e) => onBrand('default_handle', e.target.value.replace(/^@/, ''))}
          placeholder={t('brandFields.handlePlaceholder')}
        />
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <ColorField label={t('brand.primaryColor')} value={brand.brand_primary_color} onChange={(v) => onBrand('brand_primary_color', v)} />
        <ColorField label={t('brand.secondaryColor')} value={brand.brand_secondary_color} onChange={(v) => onBrand('brand_secondary_color', v)} />
      </div>
      <CarouselStyleField
        value={carouselStyle}
        onChange={(v) => onBrand('carousel_style', v)}
        primary={brand.brand_primary_color}
        secondary={brand.brand_secondary_color}
        imageUrl={bgPreview}
      />
      {carouselStyle === 'image' && (
        <>
          <CarouselBackgroundChooser
            bgPreview={bgPreview}
            onFile={setBgFile}
            bgCreative={bgCreative}
            onBgCreative={setBgCreative}
          />
          {palette !== undefined && (
            <CarouselPaletteSwatches
              palette={palette}
              hasBackground={!!bgPreview}
              onReanalyze={onReanalyzePalette}
              analyzing={analyzingPalette}
            />
          )}
        </>
      )}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <ImageField label="Logo" icon={ImageIcon} file={assets.logo} currentUrl={logoUrl} onFile={(f) => onAsset('logo', f)} />
        <ImageField label={t('brandFields.creatorAvatar')} icon={UserCircle2} rounded file={assets.defaultCreatorAvatar} currentUrl={avatarUrl} onFile={(f) => onAsset('defaultCreatorAvatar', f)} />
      </div>
    </div>
  )
}

// First step: import the whole client from the brand's site. The AI reads the
// page and fills name, contact, brand identity (logo + colors) and positioning.
export function SiteImportPanel({ url, onUrl, onImport, importing }) {
  const { t } = useTranslation('clients')
  const ready = String(url || '').trim().length > 0
  return (
    <div className="space-y-4">
      <div className="flex items-start gap-2.5 rounded-xl border border-brand/20 bg-brand-soft px-4 py-3">
        <Sparkles size={18} className="mt-0.5 shrink-0 text-brand" />
        <p className="text-sm text-ink-secondary">
          {t('siteImport.banner')}
        </p>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="brand-url">{t('siteImport.label')}</Label>
        <div className="flex gap-2 max-sm:flex-col">
          <Input
            id="brand-url"
            type="url"
            autoFocus
            value={url || ''}
            onChange={(e) => onUrl(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); if (!importing && ready) onImport() } }}
            placeholder={t('siteImport.placeholder')}
          />
          <Button type="button" onClick={onImport} disabled={importing || !ready} className="shrink-0 max-sm:h-11 max-sm:w-full">
            {importing ? <InlineSpinner /> : <Globe />}
            {importing ? t('siteImport.reading') : t('siteImport.import')}
          </Button>
        </div>
        <p className="text-xs text-ink-faint">
          {t('siteImport.hint')}
        </p>
      </div>
    </div>
  )
}

// AI-first brief: the client describes the brand in free text and the model fills
// the structured positioning fields below.
export function BriefPanel({ brief, onBrief, onGenerate, generating }) {
  const { t } = useTranslation('clients')
  return (
    <div className="space-y-3.5">
      <div className="flex items-start gap-2.5 rounded-xl border border-brand/20 bg-brand-soft px-4 py-3">
        <Sparkles size={18} className="mt-0.5 shrink-0 text-brand" />
        <p className="text-sm text-ink-secondary">
          {t('brief.banner')}
        </p>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="brand-brief">{t('brief.label')}</Label>
        <Textarea
          id="brand-brief"
          rows={7}
          value={brief || ''}
          onChange={(e) => onBrief(e.target.value)}
          placeholder={t('brief.placeholder')}
        />
      </div>
      <Button type="button" className="w-full" onClick={onGenerate} disabled={generating || !String(brief || '').trim()}>
        {generating ? <InlineSpinner /> : <Wand2 />}
        {generating ? t('brief.generating') : t('brief.generate')}
      </Button>
    </div>
  )
}

// Final review of the AI-synthesized one-paragraph statement (editable).
export function StatementPanel({ statement, onStatement, onRegenerate, generating, canRegenerate }) {
  const { t } = useTranslation('clients')
  return (
    <div className="space-y-3.5">
      <div className="space-y-1.5">
        <Label htmlFor="pos-statement">{t('statement.label')}</Label>
        <Textarea
          id="pos-statement"
          rows={6}
          value={statement || ''}
          onChange={(e) => onStatement(e.target.value)}
          placeholder={t('statement.placeholder')}
        />
      </div>
      {canRegenerate && (
        <Button type="button" variant="outline" size="sm" onClick={onRegenerate} disabled={generating}>
          {generating ? <InlineSpinner /> : <Sparkles />}
          {generating ? t('statement.generating') : t('statement.regenerate')}
        </Button>
      )}
    </div>
  )
}
