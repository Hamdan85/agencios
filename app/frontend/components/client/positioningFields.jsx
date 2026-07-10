import { useState } from 'react'
import { Sparkles, Wand2, Image as ImageIcon, UserCircle2, Globe, Check, Upload, Images, X } from 'lucide-react'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { InlineSpinner } from '@/components/ui/feedback'
import { cn } from '@/lib/utils'
import CarouselBackgroundPicker from './CarouselBackgroundPicker'

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
  const common = { id, placeholder: field.placeholder }

  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>{field.label}</Label>
      {field.type === 'text' ? (
        <Input {...common} value={value || ''} onChange={(e) => onChange(field.key, e.target.value)} />
      ) : field.type === 'pillars' ? (
        <Textarea
          {...common}
          rows={4}
          value={pillarsToText(value)}
          onChange={(e) => onChange(field.key, textToPillars(e.target.value))}
        />
      ) : (
        <Textarea {...common} value={value || ''} onChange={(e) => onChange(field.key, e.target.value)} />
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
          className="size-10 shrink-0 cursor-pointer rounded-lg border border-border bg-surface p-1"
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

export const CAROUSEL_STYLES = [
  { key: 'gradient', label: 'Fundo gradiente' },
  { key: 'white', label: 'Fundo branco' },
  { key: 'image', label: 'Imagem de fundo' },
]
export const CAROUSEL_STYLE_LABEL = { gradient: 'Fundo gradiente', white: 'Fundo branco', image: 'Imagem de fundo' }

// A faithful miniature of a generated carousel slide using the client's real
// brand colors — mirrors Creatives::CarouselSlideTemplate so each option is a
// literal example of the actual output, not a mockup. For the `image` style it
// renders the chosen background photo behind a scrim (the has-image layout).
export function CarouselSlidePreview({ style, primary, secondary, imageUrl, className }) {
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
      {image && imageUrl && (
        <>
          <img src={imageUrl} alt="" className="absolute inset-0 size-full object-cover" />
          <div className="absolute inset-0" style={{ background: 'linear-gradient(180deg, rgba(0,0,0,.35) 0%, rgba(0,0,0,.72) 100%)' }} />
        </>
      )}
      <div className="relative p-3">
        <div className="flex items-center gap-1.5">
          <span className="size-4 shrink-0 rounded-full" style={{ background: s }} />
          <div className="space-y-1">
            <span className="block h-1 w-9 rounded-full" style={{ background: ink, opacity: 0.9 }} />
            <span className="block h-1 w-5 rounded-full" style={{ background: ink, opacity: 0.45 }} />
          </div>
        </div>
        <div className="mt-4 space-y-1.5">
          <span className="block text-[11px] font-extrabold leading-tight">Sua headline aparece aqui</span>
          {!image && <span className="block h-1 w-6 rounded-full" style={{ background: s }} />}
        </div>
      </div>
      <span className="absolute bottom-2.5 left-3 z-10 text-[8px] font-bold" style={{ opacity: 0.8 }}>Arraste →</span>
    </div>
  )
}

// Literal slide previews the user picks between; drives carousel generation.
function CarouselStyleField({ value, onChange, primary, secondary, imageUrl }) {
  const active = value || 'gradient'
  return (
    <div className="space-y-1.5">
      <Label>Estilo do carrossel</Label>
      <p className="-mt-0.5 text-xs text-ink-faint">Fundo usado quando a IA gera carrosséis para este cliente.</p>
      <div className="grid grid-cols-3 gap-2.5">
        {CAROUSEL_STYLES.map((opt) => {
          const on = active === opt.key
          return (
            <button
              key={opt.key}
              type="button"
              onClick={() => onChange(opt.key)}
              className={cn('rounded-xl border p-1.5 text-left transition', on ? 'border-brand ring-2 ring-brand/30' : 'border-border hover:border-brand/40')}
            >
              <CarouselSlidePreview style={opt.key} primary={primary} secondary={secondary} imageUrl={imageUrl} />
              <div className="mt-1.5 flex items-center gap-1 px-0.5">
                <span className={cn('grid size-3.5 shrink-0 place-items-center rounded-full border', on ? 'border-brand bg-brand text-white' : 'border-border')}>
                  {on && <Check size={10} strokeWidth={3} />}
                </span>
                <span className="truncate text-[11px] font-semibold text-ink-secondary">{opt.label}</span>
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
  const preview = file ? URL.createObjectURL(file) : currentUrl
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-dashed border-border bg-surface-muted/40 p-3 transition hover:border-brand/50">
        <div className={`grid size-12 shrink-0 place-items-center overflow-hidden bg-surface text-ink-faint ring-1 ring-border ${rounded ? 'rounded-full' : 'rounded-lg'}`}>
          {preview ? <img src={preview} alt="" className="size-full object-cover" /> : <Icon size={20} />}
        </div>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-ink-secondary">{file ? file.name : (currentUrl ? 'Imagem atual' : 'Escolher imagem')}</p>
          <p className="text-xs text-ink-faint">PNG, JPG ou SVG</p>
        </div>
        <input type="file" accept="image/*" className="hidden" onChange={(e) => onFile(e.target.files?.[0] || null)} />
      </label>
    </div>
  )
}

// The carousel background source chooser, shown when the `image` style is picked:
// upload a file or pick an existing platform creative. `bgCreative` = {id,url}.
function CarouselBackgroundChooser({ bgPreview, onFile, bgCreative, onBgCreative }) {
  const [pickerOpen, setPickerOpen] = useState(false)
  return (
    <div className="space-y-2 rounded-xl border border-border bg-surface-muted/40 p-3">
      <div className="flex items-center gap-3">
        <div className="grid size-14 shrink-0 place-items-center overflow-hidden rounded-lg bg-surface text-ink-faint ring-1 ring-border">
          {bgPreview ? <img src={bgPreview} alt="" className="size-full object-cover" /> : <ImageIcon size={20} />}
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-ink-secondary">
            {bgPreview ? 'Imagem de fundo definida' : 'Escolha a imagem de fundo'}
          </p>
          <p className="text-xs text-ink-faint">Envie um arquivo ou selecione um criativo da plataforma.</p>
        </div>
        {bgPreview && (
          <button type="button" onClick={() => { onFile(null); onBgCreative(null) }} className="shrink-0 rounded-lg p-1.5 text-ink-faint transition hover:bg-surface hover:text-ink" title="Remover">
            <X size={16} />
          </button>
        )}
      </div>
      <div className="flex flex-wrap gap-2">
        <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-border bg-surface px-3 py-1.5 text-xs font-semibold text-ink-secondary transition hover:border-brand/50">
          <Upload size={14} /> Enviar imagem
          <input type="file" accept="image/*" className="hidden" onChange={(e) => onFile(e.target.files?.[0] || null)} />
        </label>
        <Button type="button" variant="outline" size="sm" onClick={() => setPickerOpen(true)}>
          <Images size={14} /> Escolher de um criativo
        </Button>
      </div>
      <CarouselBackgroundPicker open={pickerOpen} onOpenChange={setPickerOpen} onSelect={onBgCreative} />
    </div>
  )
}

// Brand identity step: voice + @handle + colors + carousel style + logo/avatar uploads.
export function BrandIdentityFields({ brand, onBrand, assets, onAsset, logoUrl, avatarUrl, bgUrl, bgCreative, onBgCreative }) {
  const carouselStyle = brand.carousel_style || 'gradient'
  const bgFileUrl = assets.carouselBackground ? URL.createObjectURL(assets.carouselBackground) : null
  const bgPreview = bgCreative?.url || bgFileUrl || bgUrl || null

  // Uploading a file and picking a creative are mutually exclusive sources.
  const setBgFile = (f) => { onAsset('carouselBackground', f); if (f) onBgCreative(null) }
  const setBgCreative = (sel) => { onBgCreative(sel); if (sel) onAsset('carouselBackground', null) }

  return (
    <div className="space-y-3.5">
      <div className="space-y-1.5">
        <Label htmlFor="brand-voice">Voz da marca</Label>
        <Textarea
          id="brand-voice"
          value={brand.brand_voice || ''}
          onChange={(e) => onBrand('brand_voice', e.target.value)}
          placeholder="Personalidade e tom (ex.: próxima, divertida, especialista)."
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="brand-handle">@handle padrão</Label>
        <Input
          id="brand-handle"
          value={brand.default_handle || ''}
          onChange={(e) => onBrand('default_handle', e.target.value.replace(/^@/, ''))}
          placeholder="marca_oficial"
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <ColorField label="Cor primária" value={brand.brand_primary_color} onChange={(v) => onBrand('brand_primary_color', v)} />
        <ColorField label="Cor secundária" value={brand.brand_secondary_color} onChange={(v) => onBrand('brand_secondary_color', v)} />
      </div>
      <CarouselStyleField
        value={carouselStyle}
        onChange={(v) => onBrand('carousel_style', v)}
        primary={brand.brand_primary_color}
        secondary={brand.brand_secondary_color}
        imageUrl={bgPreview}
      />
      {carouselStyle === 'image' && (
        <CarouselBackgroundChooser
          bgPreview={bgPreview}
          onFile={setBgFile}
          bgCreative={bgCreative}
          onBgCreative={setBgCreative}
        />
      )}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <ImageField label="Logo" icon={ImageIcon} file={assets.logo} currentUrl={logoUrl} onFile={(f) => onAsset('logo', f)} />
        <ImageField label="Avatar do criador (UGC)" icon={UserCircle2} rounded file={assets.defaultCreatorAvatar} currentUrl={avatarUrl} onFile={(f) => onAsset('defaultCreatorAvatar', f)} />
      </div>
    </div>
  )
}

// First step: import the whole client from the brand's site. The AI reads the
// page and fills name, contact, brand identity (logo + colors) and positioning.
export function SiteImportPanel({ url, onUrl, onImport, importing }) {
  const ready = String(url || '').trim().length > 0
  return (
    <div className="space-y-4">
      <div className="flex items-start gap-2.5 rounded-xl border border-brand/20 bg-brand-soft px-4 py-3">
        <Sparkles size={18} className="mt-0.5 shrink-0 text-brand" />
        <p className="text-sm text-ink-secondary">
          Cole o link do site / landing page da marca. A IA lê a página e preenche
          automaticamente nome, contato, identidade visual (logo e cores) e o
          posicionamento. Você revisa tudo antes de salvar.
        </p>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="brand-url">Site da marca</Label>
        <div className="flex gap-2">
          <Input
            id="brand-url"
            type="url"
            autoFocus
            value={url || ''}
            onChange={(e) => onUrl(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); if (!importing && ready) onImport() } }}
            placeholder="https://marca.com.br"
          />
          <Button type="button" onClick={onImport} disabled={importing || !ready} className="shrink-0">
            {importing ? <InlineSpinner /> : <Globe />}
            {importing ? 'Lendo…' : 'Importar'}
          </Button>
        </div>
        <p className="text-xs text-ink-faint">
          Preenche nome, e-mail, telefone, @, cores, logo e posicionamento — você pode pular e preencher manualmente.
        </p>
      </div>
    </div>
  )
}

// AI-first brief: the client describes the brand in free text and the model fills
// the structured positioning fields below.
export function BriefPanel({ brief, onBrief, onGenerate, generating }) {
  return (
    <div className="space-y-3.5">
      <div className="flex items-start gap-2.5 rounded-xl border border-brand/20 bg-brand-soft px-4 py-3">
        <Sparkles size={18} className="mt-0.5 shrink-0 text-brand" />
        <p className="text-sm text-ink-secondary">
          Descreva a marca com suas palavras — produtos, público, diferenciais, jeito de falar.
          A IA preenche o posicionamento estruturado e você revisa nas próximas etapas.
        </p>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="brand-brief">Descrição da marca</Label>
        <Textarea
          id="brand-brief"
          rows={7}
          value={brief || ''}
          onChange={(e) => onBrief(e.target.value)}
          placeholder="Ex.: Somos uma confeitaria artesanal premium em SP. Vendemos bolos e doces sob encomenda para festas. Nosso público são mães de classe média-alta que valorizam ingredientes naturais. A gente fala de um jeito caloroso e próximo…"
        />
      </div>
      <Button type="button" className="w-full" onClick={onGenerate} disabled={generating || !String(brief || '').trim()}>
        {generating ? <InlineSpinner /> : <Wand2 />}
        {generating ? 'Gerando posicionamento…' : 'Preencher posicionamento com IA'}
      </Button>
    </div>
  )
}

// Final review of the AI-synthesized one-paragraph statement (editable).
export function StatementPanel({ statement, onStatement, onRegenerate, generating, canRegenerate }) {
  return (
    <div className="space-y-3.5">
      <div className="space-y-1.5">
        <Label htmlFor="pos-statement">Posicionamento (síntese)</Label>
        <Textarea
          id="pos-statement"
          rows={6}
          value={statement || ''}
          onChange={(e) => onStatement(e.target.value)}
          placeholder="O parágrafo de posicionamento aparece aqui. Gere com IA na etapa de descrição ou escreva manualmente."
        />
      </div>
      {canRegenerate && (
        <Button type="button" variant="outline" size="sm" onClick={onRegenerate} disabled={generating}>
          {generating ? <InlineSpinner /> : <Sparkles />}
          {generating ? 'Gerando…' : 'Regerar com IA'}
        </Button>
      )}
    </div>
  )
}
