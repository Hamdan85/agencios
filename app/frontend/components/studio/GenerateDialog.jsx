import { useEffect, useState } from 'react'
import { Sparkles, Loader2, CheckCircle2, Wand2, AtSign } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'
import { ClientSelect } from '@/components/ui/entity-select'
import { GENERATION_KIND_META } from '@/lib/constants'
import { cn } from '@/lib/utils'

// Compact preview of the chosen client's brand — the content is generated in
// this brand's voice / colors / handle.
function BrandPreview({ client }) {
  const b = client.brand || {}
  return (
    <div className="flex items-center gap-3 rounded-xl border border-border bg-surface-muted/50 p-3">
      <div className="grid size-10 shrink-0 place-items-center overflow-hidden rounded-xl bg-white text-brand ring-1 ring-border">
        {b.logo_url ? <img src={b.logo_url} alt="" className="size-full object-contain p-0.5" /> : <AtSign size={18} />}
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-bold text-ink">{client.name}</p>
        <p className="truncate text-xs text-ink-muted">@{String(b.handle || client.name).replace(/^@/, '')}</p>
      </div>
      <div className="flex shrink-0 items-center gap-1.5">
        <span className="size-5 rounded-md ring-1 ring-border" style={{ background: b.primary || '#7C3AED' }} />
        <span className="size-5 rounded-md ring-1 ring-border" style={{ background: b.secondary || '#EC4899' }} />
      </div>
    </div>
  )
}

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

const SLIDE_OPTIONS = ['auto', 4, 5, 6, 7, 8, 10]
const slideLabel = (n) => (n === 'auto' ? 'Automático' : `${n} slides`)

const META = {
  carousel: {
    title: 'Gerar Carrossel',
    description: 'Um carrossel viral a partir de uma ideia, texto ou link — copy, slides e identidade da marca.',
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

// Carousel can be generated from three kinds of source.
const CAROUSEL_SOURCES = [
  { value: 'idea', label: 'Ideia' },
  { value: 'text', label: 'Texto' },
  { value: 'link', label: 'Link' },
]

const emptyForm = () => ({
  source_mode: 'idea', idea: '', text: '', url: '',
  slides: 'auto', objective: '',
  script: '', avatar: 'creator_default', voice: 'pt_br_warm',
  prompt: '',
})

const isHttpUrl = (v) => /^https?:\/\/\S+\.\S+/i.test(String(v || '').trim())

export function GenerateDialog({ kind, open, onOpenChange, generate, clients = [] }) {
  const [form, setForm] = useState(emptyForm)
  const [done, setDone] = useState(false)
  const [clientId, setClientId] = useState(null)
  const meta = META[kind] || META.carousel
  const kindMeta = GENERATION_KIND_META[kind] || GENERATION_KIND_META.carousel
  const KindIcon = kindMeta.icon
  const pending = generate?.isPending

  // Reset the form + default the client whenever the dialog (re)opens.
  useEffect(() => {
    if (open) {
      setForm(emptyForm())
      setDone(false)
      setClientId(clients[0]?.id ?? null)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, kind])

  const set = (key) => (val) => setForm((f) => ({ ...f, [key]: val }))

  const selectedClient = clients.find((c) => String(c.id) === String(clientId)) || null
  const clientOption = selectedClient
    ? { value: selectedClient.id, label: selectedClient.name, avatar: selectedClient.logo_url, avatarName: selectedClient.name }
    : null

  const carouselSourceValid = (
    form.source_mode === 'idea' ? form.idea.trim().length > 1 :
    form.source_mode === 'text' ? form.text.trim().length > 1 :
    isHttpUrl(form.url)
  )

  const isValid = !!clientId && (
    kind === 'carousel' ? carouselSourceValid :
    kind === 'video' ? form.script.trim().length > 1 :
    form.prompt.trim().length > 1
  )

  const buildParams = () => {
    // The generation carries the client it's FOR, so it uses the client's brand.
    const base = clientId ? { client_id: clientId } : {}
    if (kind === 'carousel') {
      const source =
        form.source_mode === 'idea' ? { topic: form.idea.trim() } :
        form.source_mode === 'text' ? { text: form.text.trim() } :
        { url: form.url.trim() }
      const slides = form.slides === 'auto' ? 'auto' : Number(form.slides) || 'auto'
      return { ...base, ...source, slides, objective: form.objective.trim() }
    }
    if (kind === 'video') return { ...base, script: form.script.trim(), avatar: form.avatar, voice: form.voice }
    return { ...base, prompt: form.prompt.trim() }
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
            <Field label="Cliente">
              <ClientSelect
                variant="field"
                value={clientId || ''}
                onChange={(v) => setClientId(v ? Number(v) : null)}
                initialOption={clientOption}
                placeholder="Para qual cliente?"
                emptyMessage="Crie um cliente primeiro."
              />
            </Field>
            {selectedClient && <BrandPreview client={selectedClient} />}

            {kind === 'carousel' && (
              <>
                <Field label="Fonte do conteúdo">
                  <div className="flex gap-1.5 rounded-xl bg-surface-muted/60 p-1">
                    {CAROUSEL_SOURCES.map((s) => (
                      <button
                        key={s.value} type="button" onClick={() => set('source_mode')(s.value)}
                        className={cn(
                          'flex-1 rounded-lg px-3 py-1.5 text-sm font-semibold transition',
                          form.source_mode === s.value ? 'bg-white text-ink shadow-sm' : 'text-ink-muted hover:text-ink',
                        )}
                      >
                        {s.label}
                      </button>
                    ))}
                  </div>
                </Field>

                {form.source_mode === 'idea' && (
                  <Field label="Ideia / tema" htmlFor="gen-idea">
                    <Input
                      id="gen-idea" value={form.idea} onChange={(e) => set('idea')(e.target.value)}
                      placeholder="Ex.: 5 erros ao começar no marketing de conteúdo" autoFocus
                    />
                  </Field>
                )}
                {form.source_mode === 'text' && (
                  <Field label="Texto base" htmlFor="gen-text">
                    <Textarea
                      id="gen-text" value={form.text} onChange={(e) => set('text')(e.target.value)}
                      placeholder="Cole o texto (artigo, roteiro, notas) que vira o carrossel…"
                      rows={5} autoFocus className="min-h-28"
                    />
                  </Field>
                )}
                {form.source_mode === 'link' && (
                  <Field label="Link" htmlFor="gen-url">
                    <Input
                      id="gen-url" type="url" value={form.url} onChange={(e) => set('url')(e.target.value)}
                      placeholder="https://exemplo.com/artigo" autoFocus
                    />
                  </Field>
                )}

                <div className="grid grid-cols-2 gap-3">
                  <Field label="Nº de slides">
                    <Select value={String(form.slides)} onValueChange={(v) => set('slides')(v === 'auto' ? 'auto' : Number(v))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {SLIDE_OPTIONS.map((n) => (
                          <SelectItem key={n} value={String(n)}>{slideLabel(n)}</SelectItem>
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
