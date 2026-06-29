import { useEffect, useState } from 'react'
import { Sparkles, Loader2, CheckCircle2, Wand2 } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'
import { GENERATION_KIND_META } from '@/lib/constants'

// Static demo options for the video generator (avatar/voice).
const AVATARS = [
  { value: 'creator_default', label: 'Avatar padrão da marca' },
  { value: 'studio_anna', label: 'Anna · Estúdio' },
  { value: 'studio_leo', label: 'Léo · Estúdio' },
]
const VOICES = [
  { value: 'pt_br_warm', label: 'PT-BR · Acolhedora' },
  { value: 'pt_br_energetic', label: 'PT-BR · Energética' },
  { value: 'pt_br_pro', label: 'PT-BR · Profissional' },
]

const SLIDE_OPTIONS = [4, 5, 6, 7, 8, 10]

const META = {
  carousel: {
    title: 'Gerar Carrossel',
    description: 'Um carrossel viral a partir do tema — copy, slides e identidade da marca.',
  },
  video: {
    title: 'Gerar Vídeo UGC',
    description: 'Um vídeo UGC com avatar e voz a partir do seu roteiro.',
  },
  image: {
    title: 'Gerar Imagem',
    description: 'Uma imagem original a partir do seu prompt criativo.',
  },
}

const emptyForm = () => ({
  topic: '', slides: 6, objective: '',
  script: '', avatar: 'creator_default', voice: 'pt_br_warm',
  prompt: '',
})

export function GenerateDialog({ kind, open, onOpenChange, generate }) {
  const [form, setForm] = useState(emptyForm)
  const [done, setDone] = useState(false)
  const meta = META[kind] || META.carousel
  const kindMeta = GENERATION_KIND_META[kind] || GENERATION_KIND_META.carousel
  const KindIcon = kindMeta.icon
  const pending = generate?.isPending

  // Reset the form whenever the dialog (re)opens for a kind.
  useEffect(() => {
    if (open) {
      setForm(emptyForm())
      setDone(false)
    }
  }, [open, kind])

  const set = (key) => (val) => setForm((f) => ({ ...f, [key]: val }))

  const isValid =
    kind === 'carousel' ? form.topic.trim().length > 1 :
    kind === 'video' ? form.script.trim().length > 1 :
    form.prompt.trim().length > 1

  const buildParams = () => {
    if (kind === 'carousel') return { topic: form.topic.trim(), slides: Number(form.slides) || 6, objective: form.objective.trim() }
    if (kind === 'video') return { script: form.script.trim(), avatar: form.avatar, voice: form.voice }
    return { prompt: form.prompt.trim() }
  }

  const submit = (e) => {
    e?.preventDefault?.()
    if (!isValid || pending) return
    generate.mutate(
      { kind, params: buildParams() },
      {
        onSuccess: () => {
          setDone(true)
          setTimeout(() => onOpenChange?.(false), 1100)
        },
      },
    )
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !pending && onOpenChange?.(o)}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <div className="mb-1 flex items-center gap-3">
            <div
              className="grid size-11 place-items-center rounded-2xl text-white shadow-sm"
              style={{ background: `linear-gradient(135deg, ${kindMeta.color}, ${kindMeta.color}cc)` }}
            >
              <KindIcon size={22} strokeWidth={2.2} />
            </div>
            <span
              className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide"
              style={{ background: `${kindMeta.color}1A`, color: kindMeta.color }}
            >
              {kindMeta.label}
            </span>
          </div>
          <DialogTitle>{meta.title}</DialogTitle>
          <DialogDescription>{meta.description}</DialogDescription>
        </DialogHeader>

        {done ? (
          <SuccessState />
        ) : pending ? (
          <GeneratingState color={kindMeta.color} label={kindMeta.label} />
        ) : (
          <form onSubmit={submit} className="space-y-4">
            {kind === 'carousel' && (
              <>
                <Field label="Tema" htmlFor="gen-topic">
                  <Input
                    id="gen-topic" value={form.topic} onChange={(e) => set('topic')(e.target.value)}
                    placeholder="Ex.: 5 erros ao começar no marketing de conteúdo" autoFocus
                  />
                </Field>
                <div className="grid grid-cols-2 gap-3">
                  <Field label="Nº de slides">
                    <Select value={String(form.slides)} onValueChange={(v) => set('slides')(Number(v))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {SLIDE_OPTIONS.map((n) => (
                          <SelectItem key={n} value={String(n)}>{n} slides</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </Field>
                  <Field label="Objetivo">
                    <Select value={form.objective || 'engagement'} onValueChange={set('objective')}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="engagement">Engajamento</SelectItem>
                        <SelectItem value="reach">Alcance</SelectItem>
                        <SelectItem value="conversion">Conversão</SelectItem>
                        <SelectItem value="education">Educação</SelectItem>
                      </SelectContent>
                    </Select>
                  </Field>
                </div>
              </>
            )}

            {kind === 'video' && (
              <>
                <Field label="Roteiro" htmlFor="gen-script">
                  <Textarea
                    id="gen-script" value={form.script} onChange={(e) => set('script')(e.target.value)}
                    placeholder="Escreva o roteiro que o avatar vai narrar…" rows={5} autoFocus
                    className="min-h-28"
                  />
                </Field>
                <div className="grid grid-cols-2 gap-3">
                  <Field label="Avatar">
                    <Select value={form.avatar} onValueChange={set('avatar')}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {AVATARS.map((a) => <SelectItem key={a.value} value={a.value}>{a.label}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </Field>
                  <Field label="Voz">
                    <Select value={form.voice} onValueChange={set('voice')}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {VOICES.map((v) => <SelectItem key={v.value} value={v.value}>{v.label}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </Field>
                </div>
              </>
            )}

            {kind === 'image' && (
              <Field label="Prompt" htmlFor="gen-prompt">
                <Textarea
                  id="gen-prompt" value={form.prompt} onChange={(e) => set('prompt')(e.target.value)}
                  placeholder="Descreva a imagem que você quer gerar — estilo, cena, cores, atmosfera…"
                  rows={5} autoFocus className="min-h-28"
                />
              </Field>
            )}

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={() => onOpenChange?.(false)}>Cancelar</Button>
              <Button type="submit" disabled={!isValid}>
                <Wand2 size={16} /> Gerar agora
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}

function Field({ label, htmlFor, children }) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor}>{label}</Label>
      {children}
    </div>
  )
}

function GeneratingState({ color, label }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-10 text-center">
      <div className="relative grid size-16 place-items-center rounded-2xl" style={{ background: `${color}14`, color }}>
        <Loader2 size={30} className="animate-spin" strokeWidth={2.4} />
        <Sparkles size={14} className="absolute right-2 top-2 animate-pulse" />
      </div>
      <p className="font-display text-lg font-bold text-ink">Gerando {label.toLowerCase()}…</p>
      <p className="max-w-xs text-sm text-ink-muted">A IA está criando seu criativo. Isso leva alguns instantes.</p>
    </div>
  )
}

function SuccessState() {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-10 text-center">
      <div className="grid size-16 place-items-center rounded-2xl bg-emerald/12 text-emerald">
        <CheckCircle2 size={32} strokeWidth={2.4} />
      </div>
      <p className="font-display text-lg font-bold text-ink">Geração enviada!</p>
      <p className="max-w-xs text-sm text-ink-muted">Acompanhe o progresso em “Gerações recentes”.</p>
    </div>
  )
}
