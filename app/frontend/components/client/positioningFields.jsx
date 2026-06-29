import { Sparkles, Loader2, Wand2, Image as ImageIcon, UserCircle2 } from 'lucide-react'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'

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

// Brand identity step: voice + @handle + colors + logo/avatar uploads.
export function BrandIdentityFields({ brand, onBrand, assets, onAsset, logoUrl, avatarUrl }) {
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
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <ImageField label="Logo" icon={ImageIcon} file={assets.logo} currentUrl={logoUrl} onFile={(f) => onAsset('logo', f)} />
        <ImageField label="Avatar do criador (UGC)" icon={UserCircle2} rounded file={assets.defaultCreatorAvatar} currentUrl={avatarUrl} onFile={(f) => onAsset('defaultCreatorAvatar', f)} />
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
        {generating ? <Loader2 className="animate-spin" /> : <Wand2 />}
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
          {generating ? <Loader2 className="animate-spin" /> : <Sparkles />}
          {generating ? 'Gerando…' : 'Regerar com IA'}
        </Button>
      )}
    </div>
  )
}
