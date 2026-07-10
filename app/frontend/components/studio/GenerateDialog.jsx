import { useEffect, useRef, useState } from 'react'
import { toast } from 'sonner'
import { Sparkles, CheckCircle2, Wand2, AtSign, Plus, X, MessageSquare } from 'lucide-react'
import { studioApi, uploadsApi } from '@/api'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { ColorBadge } from '@/components/ui/badge'
import { InlineSpinner, Skeleton } from '@/components/ui/feedback'
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
function BrandPreview({ client, className }) {
  const b = client.brand || {}
  return (
    <div className={cn('flex h-10 items-center gap-2.5 rounded-xl border border-border bg-surface-muted/50 px-2.5', className)}>
      <div className="grid size-7 shrink-0 place-items-center overflow-hidden rounded-lg bg-white text-brand ring-1 ring-border">
        {b.logo_url ? <img src={b.logo_url} alt="" className="size-full object-contain p-0.5" /> : <AtSign size={15} />}
      </div>
      <div className="min-w-0 flex-1 leading-tight">
        <p className="truncate text-[13px] font-bold text-ink">{client.name}</p>
        <p className="truncate text-[11px] text-ink-muted">@{String(b.handle || client.name).replace(/^@/, '')}</p>
      </div>
      <div className="flex shrink-0 items-center gap-1.5">
        <span className="size-4 rounded ring-1 ring-border" style={{ background: b.primary || '#7C3AED' }} />
        <span className="size-4 rounded ring-1 ring-border" style={{ background: b.secondary || '#EC4899' }} />
      </div>
    </div>
  )
}

// 9:16 default (reel). Format is a visual choice, not a dropdown.
const VIDEO_FORMATS = [
  { value: '9:16', label: '9:16', hint: 'Reels' },
  { value: '1:1', label: '1:1', hint: 'Feed' },
  { value: '16:9', label: '16:9', hint: 'YouTube' },
]
const VIDEO_DURATIONS = [
  { value: 8, label: 'Curto', hint: '8s' },
  { value: 16, label: 'Médio', hint: '16s' },
  { value: 30, label: 'Longo', hint: '30s' },
]
// Native model audio (Veo 3.1 generates speech/ambient). On by default.
const SOUND_OPTIONS = [
  { value: true, label: 'Com som', hint: 'fala + ambiente' },
  { value: false, label: 'Sem som', hint: 'silencioso' },
]

// Max input lengths per prompt field. Mirror the backend `copy_limits` where
// they exist (ugc_video script = 1200); the rest are sensible prompt caps so a
// runaway paste can't balloon the dialog or the generation payload.
const LIMITS = {
  script: 1200,
  video_brief: 1000,
  image_prompt: 1000,
  carousel_idea: 200,
  carousel_text: 4000,
}

const SLIDE_OPTIONS = ['auto', 4, 5, 6, 7, 8, 10]
const slideLabel = (n) => (n === 'auto' ? 'Automático' : `${n} slides`)

const META = {
  carousel: {
    title: 'Gerar Carrossel',
    description: 'Um carrossel viral a partir de uma ideia, texto ou link — copy, slides e identidade da marca.',
  },
  video: {
    title: 'Novo vídeo',
    description: 'Diga o essencial e gere o rascunho — estilo, referências e ajustes você faz conversando no editor.',
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
  // video — a single brief; the director infers the type. voice keeps the warm
  // default for whenever it lands on a talking-head.
  video_brief: '', reference_urls: [],
  voice: 'pt_br_warm', aspect_ratio: '9:16', duration: 16, with_audio: true,
  prompt: '',
})

const isHttpUrl = (v) => /^https?:\/\/\S+\.\S+/i.test(String(v || '').trim())

export function GenerateDialog({ kind, open, onOpenChange, generate, startVideo, clients = [], onGenerated }) {
  const [form, setForm] = useState(emptyForm)
  const [done, setDone] = useState(false)
  const [clientId, setClientId] = useState(null)
  const [improving, setImproving] = useState(false) // false | 'thinking' | 'typing'
  const typeTimer = useRef(null)
  const meta = META[kind] || META.carousel
  const kindMeta = GENERATION_KIND_META[kind] || GENERATION_KIND_META.carousel
  const KindIcon = kindMeta.icon
  // Video opens an interview (startVideo); the other kinds generate directly.
  const pending = kind === 'video' ? startVideo?.isPending : generate?.isPending

  // Reset the form + default the client whenever the dialog (re)opens.
  useEffect(() => {
    if (open) {
      setForm(emptyForm())
      setDone(false)
      setClientId(clients[0]?.id ?? null)
      setImproving(false)
      clearTimeout(typeTimer.current)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, kind])

  const set = (key) => (val) => setForm((f) => ({ ...f, [key]: val }))

  // ── "Melhorar esse prompt" wand ─────────────────────────────────────
  // Erases the draft (shimmer while the AI thinks with the full video context —
  // client, brand, mode, format, voice, assets) and streams the improved prompt
  // back into the field.
  useEffect(() => () => clearTimeout(typeTimer.current), [])

  const improvePrompt = async () => {
    const field = 'video_brief'
    const original = form[field]
    if (original.trim().length < 2 || improving || pending) return
    setImproving('thinking')
    set(field)('')
    try {
      const { prompt } = await studioApi.improvePrompt({
        client_id: clientId,
        // No mode from the form — the backend improver uses a neutral default;
        // the director picks the real mode from the brief.
        prompt: original,
        aspect_ratio: form.aspect_ratio,
        duration: form.duration,
        with_audio: form.with_audio,
        reference_count: form.reference_urls.length,
      })
      const text = String(prompt || '').slice(0, LIMITS[field])
      setImproving('typing')
      let i = 0
      const step = () => {
        i = Math.min(text.length, i + 3)
        set(field)(text.slice(0, i))
        if (i < text.length) typeTimer.current = setTimeout(step, 18)
        else setImproving(false)
      }
      step()
    } catch {
      set(field)(original)
      setImproving(false)
      toast.error('Não foi possível melhorar o prompt. Tente de novo.')
    }
  }

  // Product reference photos: upload on pick → keep their public URLs in the form.
  const fileRef = useRef(null)
  const [uploading, setUploading] = useState(false)
  const MAX_REFS = 3

  const pickRefs = async (e) => {
    const files = Array.from(e.target.files || [])
    e.target.value = ''
    if (!files.length) return
    const room = MAX_REFS - form.reference_urls.length
    if (room <= 0) { toast.error(`Máximo de ${MAX_REFS} fotos.`); return }
    setUploading(true)
    try {
      const { references: uploaded } = await uploadsApi.references(files.slice(0, room))
      setForm((f) => ({ ...f, reference_urls: [...f.reference_urls, ...uploaded].slice(0, MAX_REFS) }))
    } catch {
      toast.error('Não foi possível enviar a foto. Tente outra imagem (JPG, PNG ou WEBP).')
    } finally {
      setUploading(false)
    }
  }

  const removeRef = (url) => setForm((f) => ({ ...f, reference_urls: f.reference_urls.filter((r) => r.url !== url) }))
  const describeRef = (url, description) => setForm((f) => ({
    ...f, reference_urls: f.reference_urls.map((r) => (r.url === url ? { ...r, description } : r)),
  }))

  const selectedClient = clients.find((c) => String(c.id) === String(clientId)) || null
  const clientOption = selectedClient
    ? { value: selectedClient.id, label: selectedClient.name, avatar: selectedClient.logo_url, avatarName: selectedClient.name }
    : null

  const carouselSourceValid = (
    form.source_mode === 'idea' ? form.idea.trim().length > 1 :
    form.source_mode === 'text' ? form.text.trim().length > 1 :
    isHttpUrl(form.url)
  )

  const videoValid = form.video_brief.trim().length > 1

  const isValid = !!clientId && (
    kind === 'carousel' ? carouselSourceValid :
    kind === 'video' ? videoValid :
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
    const refUrls = form.reference_urls.map((r) => r.url).filter(Boolean)
    if (kind === 'video') {
      // No `mode` — the backend infers it (references present ⇒ product-leaning)
      // and the storyboard director makes the final call. `voice` keeps the
      // warm default for whenever the director lands on a talking-head. Each
      // reference carries the user's description ({ url => "what is this?" }) so
      // the director knows how to use it.
      const referenceDescriptions = Object.fromEntries(
        form.reference_urls.filter((r) => r.url && (r.description || '').trim()).map((r) => [r.url, r.description.trim()]),
      )
      return {
        ...base, aspect_ratio: form.aspect_ratio, duration: form.duration,
        with_audio: form.with_audio, reference_image_urls: refUrls,
        reference_descriptions: referenceDescriptions,
        prompt: form.video_brief.trim(), voice: form.voice,
      }
    }
    return { ...base, prompt: form.prompt.trim(), ref_images: refUrls }
  }

  const submit = (e) => {
    e?.preventDefault?.()
    if (!isValid || pending) return

    // Video does NOT generate here — it opens the editor as a chat INTERVIEW;
    // the agent gathers context and decides when to build.
    if (kind === 'video') {
      startVideo.mutate(
        { params: buildParams() },
        {
          onSuccess: (data) => {
            onOpenChange?.(false)
            onGenerated?.({ kind: 'video', creative_id: data?.creative?.id })
          },
        },
      )
      return
    }

    // Image/carousel: close the dialog right away and let the gallery show the
    // "Gerando…" card (the op broadcasts `generation_progress` on start). The
    // mutation keeps running in the background — its success/error toast lands
    // whenever it finishes. This is what makes creations appear as processing
    // immediately instead of blocking behind the dialog spinner.
    generate.mutate(
      { kind, params: buildParams() },
      { onSuccess: (data) => { if (onGenerated && data?.generation) onGenerated(data.generation) } },
    )
    onOpenChange?.(false)
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !pending && onOpenChange?.(o)}>
      <DialogContent className={cn(kind === 'image' ? 'sm:max-w-lg' : 'sm:max-w-2xl')}>
        <DialogHeader>
          <div className="mb-1 flex items-center gap-3">
            <div
              className="grid size-11 place-items-center rounded-2xl text-white shadow-sm"
              style={{ background: `linear-gradient(135deg, ${kindMeta.color}, ${kindMeta.color}cc)` }}
            >
              <KindIcon size={22} strokeWidth={2.2} />
            </div>
            <ColorBadge color={kindMeta.color} className="py-1 text-[11px] uppercase tracking-wide">
              {kindMeta.label}
            </ColorBadge>
          </div>
          <DialogTitle>{meta.title}</DialogTitle>
          <DialogDescription>{meta.description}</DialogDescription>
        </DialogHeader>

        {done ? (
          <SuccessState />
        ) : pending ? (
          <GeneratingState color={kindMeta.color} label={kindMeta.label} video={kind === 'video'} />
        ) : (
          <form onSubmit={submit} className="space-y-5">
            <div className="grid gap-4 sm:grid-cols-2">
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
              {selectedClient && (
                <Field label="Marca">
                  <BrandPreview client={selectedClient} className="w-full" />
                </Field>
              )}
            </div>

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
                  <Field label="Ideia / tema" htmlFor="gen-idea" count={form.idea.length} max={LIMITS.carousel_idea}>
                    <Input
                      id="gen-idea" value={form.idea} onChange={(e) => set('idea')(e.target.value)}
                      placeholder="Ex.: 5 erros ao começar no marketing de conteúdo" maxLength={LIMITS.carousel_idea} autoFocus
                    />
                  </Field>
                )}
                {form.source_mode === 'text' && (
                  <Field label="Texto base" htmlFor="gen-text" count={form.text.length} max={LIMITS.carousel_text}>
                    <Textarea
                      id="gen-text" value={form.text} onChange={(e) => set('text')(e.target.value)}
                      placeholder="Cole o texto (artigo, roteiro, notas) que vira o carrossel…"
                      rows={4} maxRows={6} maxLength={LIMITS.carousel_text} autoFocus className="min-h-24"
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

                <div className="grid gap-4 sm:grid-cols-2">
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
                {/* No "tipo" pick — the director infers avatar / product / scene /
                    character from what you describe (part of the interview). */}
                <Field
                  label="O que é o vídeo?" htmlFor="gen-vbrief" count={form.video_brief.length} max={LIMITS.video_brief}
                  action={<ImproveWand onClick={improvePrompt} improving={improving} disabled={form.video_brief.trim().length < 2 || pending} />}
                >
                  <div className="relative">
                    <Textarea
                      id="gen-vbrief" value={form.video_brief} onChange={(e) => set('video_brief')(e.target.value)}
                      placeholder={improving ? '' : 'Descreva o vídeo: quem/o que aparece, o que deve dizer, o clima. Pode colar um roteiro. O resto você ajusta conversando no editor.'}
                      rows={4} maxRows={6} maxLength={LIMITS.video_brief} autoFocus className="min-h-24"
                      readOnly={!!improving}
                    />
                    {improving === 'thinking' && <PromptShimmer />}
                  </div>
                </Field>
                {/* Optional references — product photos (kept faithful), a style
                    or a person to feature. The director types each; anything else
                    is refined by chatting in the editor. */}
                <RefUploader
                  urls={form.reference_urls} fileRef={fileRef} uploading={uploading}
                  onPick={() => fileRef.current?.click()} onRemove={removeRef} onFiles={pickRefs}
                  describe onDescribe={describeRef}
                  label="Referências (opcional)"
                  hint={`Até ${MAX_REFS} — diga o que é cada arquivo para o vídeo usar do jeito certo.`}
                />

                <div className="grid gap-4 sm:grid-cols-3">
                  <Field label="Formato">
                    <PillGroup options={VIDEO_FORMATS} value={form.aspect_ratio} onChange={set('aspect_ratio')} />
                  </Field>
                  <Field label="Duração">
                    <PillGroup options={VIDEO_DURATIONS} value={form.duration} onChange={set('duration')} />
                  </Field>
                  <Field label="Som">
                    <PillGroup options={SOUND_OPTIONS} value={form.with_audio} onChange={set('with_audio')} />
                  </Field>
                </div>
              </>
            )}

            {kind === 'image' && (
              <>
                <Field label="Prompt" htmlFor="gen-prompt" count={form.prompt.length} max={LIMITS.image_prompt}>
                  <Textarea
                    id="gen-prompt" value={form.prompt} onChange={(e) => set('prompt')(e.target.value)}
                    placeholder="Descreva a imagem que você quer gerar — estilo, cena, cores, atmosfera…"
                    rows={5} maxRows={7} maxLength={LIMITS.image_prompt} autoFocus className="min-h-28"
                  />
                </Field>
                <RefUploader
                  urls={form.reference_urls} fileRef={fileRef} uploading={uploading}
                  onPick={() => fileRef.current?.click()} onRemove={removeRef} onFiles={pickRefs}
                  label="Imagens de referência (opcional)"
                  hint={`Até ${MAX_REFS} — estilo, objeto ou composição de referência.`}
                />
              </>
            )}

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={() => onOpenChange?.(false)}>Cancelar</Button>
              <Button type="submit" disabled={!isValid || !!improving}>
                {/* Video doesn't generate here — it opens the chat editor to refine first. */}
                {kind === 'video'
                  ? <><MessageSquare size={16} /> Continuar no editor</>
                  : <><Wand2 size={16} /> Gerar agora</>}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}

// A compact segmented pill row (format / duration). Each option shows a label
// with a small sub-hint, matching the app's chip vocabulary.
function PillGroup({ options, value, onChange }) {
  return (
    <div className="flex h-10 gap-1 rounded-xl bg-surface-muted/60 p-1">
      {options.map((o) => {
        const active = String(value) === String(o.value)
        return (
          <button
            key={o.value} type="button" onClick={() => onChange(o.value)}
            className={cn(
              'flex flex-1 flex-col items-center justify-center rounded-lg px-1 leading-none transition',
              active ? 'bg-white text-brand shadow-sm' : 'text-ink-muted hover:text-ink',
            )}
          >
            <span className="text-[13px] font-bold">{o.label}</span>
            {o.hint && <span className="mt-0.5 text-[9px] font-medium opacity-70">{o.hint}</span>}
          </button>
        )
      })}
    </div>
  )
}

// Reference-image attach affordance for a prompt field — thumbnails + an add
// tile. Shared by product/avatar video and image generation; the uploaded URLs
// ride along as reference images the generator can draw on. When `describe` is
// set (video), each reference asks "what is this file?" so the storyboard
// director knows how to use it (its name + the user's words).
function RefUploader({ urls, fileRef, uploading, onPick, onRemove, onFiles, onDescribe, describe = false, label, hint }) {
  return (
    <Field label={label}>
      <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" multiple hidden onChange={onFiles} />
      {describe ? (
        <div className="space-y-2">
          {urls.map((r) => (
            <div key={r.url} className="flex items-center gap-2.5">
              <div className="relative size-14 shrink-0 overflow-hidden rounded-xl border border-border">
                <img src={r.url} alt="Referência" className="size-full object-cover" />
              </div>
              <input
                value={r.description || ''}
                onChange={(e) => onDescribe?.(r.url, e.target.value)}
                placeholder="O que é este arquivo? (ex.: foto do produto, personagem, estilo…)"
                className="h-10 min-w-0 flex-1 rounded-xl border border-border bg-surface px-3 text-sm text-ink placeholder:text-ink-faint focus:border-brand focus:outline-none"
              />
              <button
                type="button" onClick={() => onRemove(r.url)} aria-label="Remover"
                className="grid size-7 shrink-0 place-items-center rounded-lg text-ink-muted transition hover:text-danger"
              >
                <X size={15} />
              </button>
            </div>
          ))}
          {urls.length < 3 && (
            <button
              type="button" onClick={onPick} disabled={uploading}
              className="flex h-11 w-full items-center justify-center gap-1.5 rounded-xl border border-dashed border-border-strong text-sm font-semibold text-ink-muted transition hover:border-brand hover:text-brand disabled:opacity-50"
            >
              {uploading ? <InlineSpinner size={18} /> : <><Plus size={16} /> Adicionar referência</>}
            </button>
          )}
          <p className="text-xs text-ink-muted">{hint}</p>
        </div>
      ) : (
        <div className="flex flex-wrap items-center gap-2.5">
          {urls.map((r) => (
            <div key={r.url} className="relative size-16 overflow-hidden rounded-xl border border-border">
              <img src={r.url} alt="Referência" className="size-full object-cover" />
              <button
                type="button" onClick={() => onRemove(r.url)} aria-label="Remover"
                className="absolute right-1 top-1 grid size-5 place-items-center rounded-md bg-black/55 text-white backdrop-blur"
              >
                <X size={12} />
              </button>
            </div>
          ))}
          {urls.length < 3 && (
            <button
              type="button" onClick={onPick} disabled={uploading}
              className="grid size-16 place-items-center gap-0.5 rounded-xl border border-dashed border-border-strong text-ink-muted transition hover:border-brand hover:text-brand disabled:opacity-50"
            >
              {uploading ? <InlineSpinner size={18} /> : <Plus size={18} />}
              <span className="text-[10px] font-bold">Imagem</span>
            </button>
          )}
          <p className="ml-1 text-xs text-ink-muted">{hint}</p>
        </div>
      )}
    </Field>
  )
}

function Field({ label, htmlFor, count, max, action, children }) {
  const showCount = typeof max === 'number'
  const near = showCount && count >= max * 0.9
  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between gap-2">
        <Label htmlFor={htmlFor}>{label}</Label>
        <div className="flex items-baseline gap-2.5">
          {action}
          {showCount && (
            <span className={cn('text-[11px] font-semibold tabular-nums', near ? 'text-danger' : 'text-ink-faint')}>
              {count}/{max}
            </span>
          )}
        </div>
      </div>
      {children}
    </div>
  )
}

// The prompt wand: hands the draft + full video context to the AI and streams
// a sharper prompt back into the field.
function ImproveWand({ onClick, improving, disabled }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled || !!improving}
      title="Melhorar esse prompt"
      className="inline-flex items-center gap-1 text-[11px] font-bold text-brand transition hover:opacity-80 disabled:cursor-not-allowed disabled:opacity-40"
    >
      {improving ? <InlineSpinner size={12} /> : <Wand2 size={12} />}
      {improving === 'thinking' ? 'Melhorando…' : improving === 'typing' ? 'Escrevendo…' : 'Melhorar'}
    </button>
  )
}

// Skeleton lines over the emptied prompt while the improved one is thought up.
function PromptShimmer() {
  return (
    <div className="pointer-events-none absolute inset-x-3.5 top-3.5 space-y-2.5">
      <Skeleton className="h-3 w-11/12 rounded-md bg-brand/15" />
      <Skeleton className="h-3 w-2/3 rounded-md bg-brand/10" />
      <Skeleton className="h-3 w-4/5 rounded-md bg-brand/15" />
    </div>
  )
}

function GeneratingState({ color, label, video = false }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-10 text-center">
      <div className="relative grid size-16 place-items-center rounded-2xl" style={{ background: `${color}14`, color }}>
        <InlineSpinner size={30} strokeWidth={2.4} />
        <Sparkles size={14} className="absolute right-2 top-2 animate-pulse" />
      </div>
      {/* Video opens an interview (no generation yet) — don't say "gerando". */}
      <p className="font-display text-lg font-bold text-ink">
        {video ? 'Abrindo o editor…' : `Gerando ${label.toLowerCase()}…`}
      </p>
      <p className="max-w-xs text-sm text-ink-muted">
        {video ? 'Vou fazer algumas perguntas para acertar o vídeo.' : 'A IA está criando seu criativo. Isso leva alguns instantes.'}
      </p>
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
