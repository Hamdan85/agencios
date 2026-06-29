import { Sparkles, Loader2, Wand2 } from 'lucide-react'
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

// The AI synthesis panel: "Gerar com IA" + the editable positioning statement.
// Reused by the creation wizard and the client-page editor.
export function AiStatementPanel({ statement, onStatement, onGenerate, generating }) {
  return (
    <div className="space-y-3.5">
      <div className="flex items-center justify-between gap-3 rounded-xl border border-brand/20 bg-brand-soft px-4 py-3">
        <div className="flex items-start gap-2.5">
          <Sparkles size={18} className="mt-0.5 shrink-0 text-brand" />
          <p className="text-sm text-ink-secondary">
            Deixe a IA sintetizar um posicionamento claro a partir das respostas — você pode editar antes de salvar.
          </p>
        </div>
        <Button type="button" variant="outline" size="sm" onClick={onGenerate} disabled={generating}>
          {generating ? <Loader2 className="animate-spin" /> : <Wand2 />}
          {generating ? 'Gerando…' : 'Gerar com IA'}
        </Button>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="pos-statement">Posicionamento</Label>
        <Textarea
          id="pos-statement"
          rows={6}
          value={statement || ''}
          onChange={(e) => onStatement(e.target.value)}
          placeholder="O statement de posicionamento aparece aqui. Gere com IA ou escreva manualmente."
        />
      </div>
    </div>
  )
}
