import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import { toast } from 'sonner'
import { creativeMeta, CREATIVE_TYPE_META, GENERATION_KIND_META, uploadAcceptFor, fileMatchesCreativeType, uploadableTypesForTicket, generatableKindsForTicket } from '@/lib/constants'
import { useWorkspaceCreatives } from '@/hooks/useData'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/input'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import { CreativeTypeChip } from '@/components/ui/iconography'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import {
  ImagePlus, Sparkles, GalleryHorizontalEnd, Video, Image as ImageIcon, AlertCircle, CheckCircle2,
  Loader2, Trash2, ChevronDown, UploadCloud, LibraryBig,
} from 'lucide-react'

const MediaViewer = lazy(() => import('./MediaViewer'))

// Status badge per creative lifecycle state.
const CREATIVE_STATUS = {
  draft: { label: 'Rascunho', variant: 'muted', icon: ImageIcon },
  generating: { label: 'Gerando…', variant: 'warning', icon: Loader2 },
  ready: { label: 'Pronto', variant: 'success', icon: CheckCircle2 },
  failed: { label: 'Falhou', variant: 'danger', icon: AlertCircle },
}

// The three generatable kinds, each mapped to a sensible default creative type.
const GENERATABLE = [
  { kind: 'carousel', type: 'carousel', label: 'Carrossel', desc: 'Padrão viral com marca + @handle', icon: GalleryHorizontalEnd, color: CREATIVE_TYPE_META.carousel.color },
  { kind: 'video', type: 'ugc_video', label: 'Vídeo UGC', desc: 'Avatar narrando — HeyGen / HyperFrames', icon: Video, color: CREATIVE_TYPE_META.ugc_video.color },
  { kind: 'image', type: 'feed_image', label: 'Imagem', desc: 'Imagem única para o feed', icon: ImageIcon, color: CREATIVE_TYPE_META.feed_image.color },
]

// Convert a creative's asset_urls to MediaViewer attachment objects. A carousel
// is ONE creative with several slides — every slide shares the creative's name
// and is captioned "Slide i de N" so the viewer reads as a single carousel, not
// a pile of separate creatives.
function creativeToAttachments(creative) {
  const m = creativeMeta(creative?.creative_type)
  const urls = creative?.asset_urls || []
  const total = urls.length
  const isCarousel = creative?.creative_type === 'carousel' || total > 1

  return urls.map((url, i) => {
    const isVideo = /\.(mp4|mov|webm|avi)(\?|$)/i.test(url)
    return {
      id: `${creative.id}-${i}`,
      url,
      filename: isCarousel ? `${m.label}-${creative.id}-slide-${i + 1}` : `${m.label}-${creative.id}`,
      display_name: creative.name || m.label,
      kind: isVideo ? 'video' : 'image',
      content_type: isVideo ? 'video/mp4' : 'image/jpeg',
      // The lightbox Counter plugin already shows "i / N" — no extra slide label.
      description: creative.caption || undefined,
    }
  })
}

// ── Creative card (fixed square ratio, no size shift from title) ───
// Root is a clickable <div> (not a <button>) so the delete control can nest as
// a real <button> without invalid interactive-element nesting.
function CreativeCard({ creative, onClick, onDelete, deleting }) {
  const m = creativeMeta(creative?.creative_type)
  const st = CREATIVE_STATUS[creative?.status] || CREATIVE_STATUS.draft
  const StIcon = st.icon
  const thumb = creative?.asset_urls?.[0]
  const generating = creative?.status === 'generating'
  const hasAssets = (creative?.asset_urls?.length || 0) > 0
  const open = hasAssets ? onClick : undefined

  return (
    <div
      role={open ? 'button' : undefined}
      tabIndex={open ? 0 : undefined}
      onClick={open}
      onKeyDown={open ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open() } } : undefined}
      className={cn(
        'group relative w-full overflow-hidden rounded-2xl border border-border bg-surface text-left transition-all lift',
        hasAssets ? 'cursor-pointer hover:border-brand/40' : 'cursor-default',
      )}
    >
      {/* Fixed 1:1 thumbnail — uses padding-bottom trick so height never depends on content */}
      <div className="relative w-full" style={{ paddingBottom: '100%' }}>
        <div className="absolute inset-0 overflow-hidden" style={{ background: `${m.color}10` }}>
          {thumb ? (
            <img
              src={thumb}
              alt={m.label}
              className="size-full object-cover transition-transform group-hover:scale-105"
            />
          ) : (
            <div className="flex size-full flex-col items-center justify-center gap-2">
              <div className="flex size-14 items-center justify-center rounded-2xl" style={{ background: `${m.color}1F`, color: m.color }}>
                {generating ? <Loader2 size={26} className="animate-spin" /> : <m.icon size={26} strokeWidth={2.1} />}
              </div>
              <CreativeTypeChip type={creative?.creative_type} />
            </div>
          )}
          {/* Only surface a status badge when it carries information — a "ready"
              creative needs no label, just the thumbnail. */}
          {(generating || creative?.status === 'failed') && (
            <div className="absolute left-2 top-2">
              <Badge variant={st.variant} className="shadow-sm">
                <StIcon size={11} className={cn('mr-0.5', generating && 'animate-spin')} />
                {st.label}
              </Badge>
            </div>
          )}
          {/* Delete — top-right, revealed on hover/focus. Stops propagation so it
              never triggers the viewer. */}
          {onDelete && !generating && (
            <button
              type="button"
              aria-label="Excluir criativo"
              disabled={deleting}
              onClick={(e) => { e.stopPropagation(); onDelete(creative) }}
              className="absolute right-2 top-2 z-10 grid size-7 place-items-center rounded-full bg-white/90 text-ink-muted opacity-0 shadow-sm backdrop-blur transition focus:opacity-100 focus:outline-none group-hover:opacity-100 hover:bg-danger hover:text-white disabled:opacity-50"
            >
              <Trash2 size={14} />
            </button>
          )}
          {hasAssets && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/0 opacity-0 transition-all group-hover:bg-black/20 group-hover:opacity-100">
              <span className="rounded-full bg-white/90 px-3 py-1 text-xs font-bold text-ink shadow">Ver</span>
            </div>
          )}
        </div>
      </div>

      {/* Name row — fixed single line, no caption spill that resizes the card.
          The "IA" marker lives here (inline) so the thumbnail's top-right stays
          free for the delete control. */}
      <div className="flex items-center gap-1 px-3 py-2">
        {creative?.source === 'generated' && <Sparkles size={11} className="shrink-0 text-brand" />}
        <p className="truncate text-xs font-semibold text-ink">
          {creative?.name || m.label}
        </p>
      </div>
    </div>
  )
}

// The "Adicionar criativo" split action — generate / upload / use-from-studio.
function AddCreativeMenu({ trigger, onGenerateOpen, onUploadOpen, onPickerOpen }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>{trigger}</DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-56">
        <DropdownMenuItem onClick={onGenerateOpen}>
          <Sparkles size={14} /> Gerar com IA
        </DropdownMenuItem>
        <DropdownMenuItem onClick={onUploadOpen}>
          <UploadCloud size={14} /> Enviar arquivo
        </DropdownMenuItem>
        <DropdownMenuItem onClick={onPickerOpen}>
          <LibraryBig size={14} /> Usar do estúdio
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

// Upload dialog — attaches an image/video file straight to the ticket as a
// creative, picking the creative type up front (drives the network-fit spec).
function UploadDialog({ open, onOpenChange, onUpload, uploading, types = [] }) {
  // Only the types that make sense for this ticket; fall back to feed_image.
  const options = types.length ? types : ['feed_image']
  const [creativeType, setCreativeType] = useState(options[0])
  const [caption, setCaption] = useState('')
  const [files, setFiles] = useState([])
  const inputRef = useRef(null)

  useEffect(() => {
    if (open) { setCreativeType(options[0]); setCaption(''); setFiles([]) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const submit = (e) => {
    e.preventDefault()
    if (!files.length || uploading) return
    onUpload?.({ creativeType, caption: caption.trim() || undefined, files })
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <UploadCloud size={18} className="text-brand" /> Enviar arquivo
            </DialogTitle>
            <DialogDescription>Envie uma peça já pronta — imagem ou vídeo.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-3.5 py-2">
            <div className="space-y-1.5">
              <Label>Tipo de criativo</Label>
              {/* Switching type may make already-picked files incompatible — clear them. */}
              <Select value={creativeType} onValueChange={(v) => { setCreativeType(v); setFiles([]) }}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {options.map((key) => (
                    <SelectItem key={key} value={key}>{CREATIVE_TYPE_META[key]?.label || key}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Arquivo</Label>
              <input
                ref={inputRef}
                type="file"
                accept={uploadAcceptFor(creativeType)}
                multiple
                hidden
                onChange={(e) => {
                  const picked = Array.from(e.target.files || [])
                  const ok = picked.filter((f) => fileMatchesCreativeType(f, creativeType))
                  if (ok.length < picked.length) {
                    const label = CREATIVE_TYPE_META[creativeType]?.label || 'esse tipo'
                    toast.error(`Arquivo incompatível: ${label} não aceita esse formato.`)
                  }
                  setFiles(ok)
                }}
              />
              <button
                type="button"
                onClick={() => inputRef.current?.click()}
                className="flex w-full items-center justify-center gap-2 rounded-xl border border-dashed border-border py-3 text-sm font-medium text-ink-muted transition hover:border-brand/40 hover:text-brand"
              >
                <UploadCloud size={15} />
                {files.length > 0
                  ? `${files.length} arquivo${files.length > 1 ? 's' : ''} selecionado${files.length > 1 ? 's' : ''}`
                  : 'Selecionar imagem ou vídeo'}
              </button>
            </div>
            <div className="space-y-1.5">
              <Label>Legenda (opcional)</Label>
              <Textarea value={caption} onChange={(e) => setCaption(e.target.value)} rows={2} placeholder="Uma nota sobre esta peça…" />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="ghost" size="sm">Cancelar</Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={!files.length || uploading}>
              {uploading ? <Spinner size={14} className="border-white/30 border-t-white" /> : <UploadCloud size={14} />}
              Enviar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

// Studio picker — attaches a creative already generated in the Studio (and
// not yet used on any ticket) to this ticket.
function StudioPickerDialog({ open, onOpenChange, onAttach, attaching }) {
  const { data, isLoading } = useWorkspaceCreatives({ unassigned: true }, { enabled: open })
  const items = data?.creatives || []

  const select = (creative) => {
    if (attaching) return
    onAttach?.(creative.id)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <LibraryBig size={18} className="text-brand" /> Usar criativo do estúdio
          </DialogTitle>
          <DialogDescription>Anexe a este ticket uma peça já gerada no estúdio.</DialogDescription>
        </DialogHeader>
        {isLoading ? (
          <div className="flex justify-center py-10"><Spinner size={20} /></div>
        ) : items.length === 0 ? (
          <EmptyState
            icon={LibraryBig}
            title="Nada disponível"
            description="Todo criativo do estúdio já está em uso em algum ticket, ou você ainda não gerou nenhum."
            color="#7C3AED"
          />
        ) : (
          <div className="grid max-h-96 grid-cols-3 gap-2.5 overflow-y-auto py-1 sm:grid-cols-4">
            {items.map((c) => {
              const m = creativeMeta(c.creative_type)
              const thumb = c.asset_urls?.[0]
              return (
                <button
                  key={c.id}
                  type="button"
                  disabled={attaching}
                  onClick={() => select(c)}
                  className="group overflow-hidden rounded-xl border border-border bg-surface text-left transition-all hover:border-brand/40 disabled:opacity-50"
                >
                  <div className="relative w-full" style={{ paddingBottom: '100%' }}>
                    <div className="absolute inset-0 overflow-hidden" style={{ background: `${m.color}10` }}>
                      {thumb ? (
                        <img src={thumb} alt={m.label} className="size-full object-cover transition-transform group-hover:scale-105" />
                      ) : (
                        <div className="flex size-full items-center justify-center" style={{ color: m.color }}>
                          <m.icon size={22} strokeWidth={2.1} />
                        </div>
                      )}
                    </div>
                  </div>
                  <p className="truncate px-2 py-1.5 text-[11px] font-semibold text-ink">{c.name || m.label}</p>
                </button>
              )
            })}
          </div>
        )}
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="ghost" size="sm">Cancelar</Button>
          </DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export default function CreativesPanel({
  creatives = [], onGenerate, generating = false, onUpload, uploading = false,
  onAttach, attaching = false, onDelete, deleting = false,
  creativeTypes = [], channels = [],
}) {
  // Only offer uploading the types that make sense for this ticket (its scoped
  // types, fitting its channels) — a reel/TikTok ticket never offers a carousel.
  const uploadTypes = uploadableTypesForTicket(creativeTypes, channels)
  // Same narrowing for AI generation: only the generation kinds this ticket can
  // actually produce — a carousel ticket never offers video, a TikTok (video-only)
  // ticket never offers a carousel or image.
  const allowedKinds = generatableKindsForTicket(creativeTypes, channels)
  const generatable = GENERATABLE.filter((g) => allowedKinds.includes(g.kind))
  const [open, setOpen] = useState(false)
  const [selectedKind, setSelectedKind] = useState(null)
  // The type of a just-fired generation, so we can render a loading placeholder
  // card immediately — before the ticket query refetches the real (generating)
  // creative. Cleared once the mutation settles.
  const [pendingType, setPendingType] = useState(null)
  const [uploadOpen, setUploadOpen] = useState(false)
  const [pickerOpen, setPickerOpen] = useState(false)
  const [viewerOpen, setViewerOpen] = useState(false)
  const [viewerIndex, setViewerIndex] = useState(0)
  const [viewerAttachments, setViewerAttachments] = useState([])
  const [pendingDelete, setPendingDelete] = useState(null)
  const items = creatives || []
  const busy = generating || uploading || attaching

  // Drop the optimistic placeholder once the generation call settles — the real
  // (generating or ready) creative arrives from the refetched ticket query.
  useEffect(() => {
    if (!generating) setPendingType(null)
  }, [generating])

  // Show the real creatives plus, while a generation is in flight, a synthetic
  // loading card so the field reflects the work immediately.
  const displayItems = generating && pendingType
    ? [{ id: '__pending__', creative_type: pendingType, status: 'generating', source: 'generated' }, ...items]
    : items

  // Selecting a type is separate from firing — generation spends credits, so the
  // user picks a type first and confirms with the "Gerar" button.
  const openGenerate = (v) => {
    setOpen(v)
    if (!v) setSelectedKind(null)
  }

  const fire = () => {
    const item = GENERATABLE.find((g) => g.kind === selectedKind)
    if (!item) return
    setPendingType(item.type)
    onGenerate?.({ kind: item.kind, type: item.type, params: {} })
    openGenerate(false)
  }

  const openViewer = (creative) => {
    const atts = creativeToAttachments(creative)
    if (!atts.length) return
    setViewerAttachments(atts)
    setViewerIndex(0)
    setViewerOpen(true)
  }

  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border p-5">
        <div className="flex items-center gap-2.5">
          <div className="flex size-9 items-center justify-center rounded-xl" style={{ background: '#7C3AED18', color: '#7C3AED' }}>
            <ImagePlus size={18} strokeWidth={2.3} />
          </div>
          <div>
            <h3 className="font-display text-base font-bold text-ink">Criativos</h3>
            <p className="text-xs text-ink-muted">
              {items.length > 0 ? `${items.length} criativo${items.length > 1 ? 's' : ''}` : 'Gere, envie ou use uma peça do estúdio.'}
            </p>
          </div>
        </div>
        <AddCreativeMenu
          onGenerateOpen={() => setOpen(true)}
          onUploadOpen={() => setUploadOpen(true)}
          onPickerOpen={() => setPickerOpen(true)}
          trigger={(
            <Button size="sm" disabled={busy}>
              {busy ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Sparkles size={14} />}
              Adicionar criativo
              <ChevronDown size={13} />
            </Button>
          )}
        />
      </div>

      <div className="p-5">
        {displayItems.length === 0 ? (
          <EmptyState
            icon={ImagePlus}
            title="Nenhum criativo ainda"
            description="Gere com IA, envie um arquivo ou use uma peça já gerada no estúdio."
            color="#7C3AED"
            action={(
              <AddCreativeMenu
                onGenerateOpen={() => setOpen(true)}
                onUploadOpen={() => setUploadOpen(true)}
                onPickerOpen={() => setPickerOpen(true)}
                trigger={<Button size="sm" disabled={busy}><Sparkles size={14} /> Adicionar criativo <ChevronDown size={13} /></Button>}
              />
            )}
          />
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {displayItems.map((c) => {
              const pending = c.id === '__pending__'
              return (
                <CreativeCard
                  key={c.id}
                  creative={c}
                  onClick={pending ? undefined : () => openViewer(c)}
                  onDelete={onDelete && !pending ? setPendingDelete : undefined}
                  deleting={deleting}
                />
              )
            })}
          </div>
        )}
      </div>

      {/* MediaViewer lightbox */}
      <Suspense fallback={null}>
        <MediaViewer
          attachments={viewerAttachments}
          index={viewerIndex}
          open={viewerOpen}
          onClose={() => setViewerOpen(false)}
        />
      </Suspense>

      {/* Generate dialog */}
      <Dialog open={open} onOpenChange={openGenerate}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Sparkles size={18} className="text-brand" /> Gerar criativo
            </DialogTitle>
            <DialogDescription>Escolha o tipo de peça e confirme — a geração consome créditos.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-2.5">
            {generatable.length === 0 && (
              <p className="rounded-2xl border border-dashed border-border bg-surface px-4 py-6 text-center text-sm text-ink-muted">
                Nenhum tipo de peça gerável para os canais e tipos deste ticket. Envie um arquivo ou ajuste o escopo.
              </p>
            )}
            {generatable.map((g) => {
              const Icon = g.icon
              const kindMeta = GENERATION_KIND_META[g.kind]
              const active = selectedKind === g.kind
              return (
                <button
                  key={g.kind}
                  type="button"
                  aria-pressed={active}
                  onClick={() => setSelectedKind(g.kind)}
                  className={cn(
                    'flex items-center gap-3.5 rounded-2xl border p-4 text-left transition-all lift',
                    active
                      ? 'border-brand bg-brand-soft/50 ring-2 ring-brand/30'
                      : 'border-border bg-surface hover:border-brand/40 hover:bg-brand-soft/40',
                  )}
                >
                  <div className="flex size-12 shrink-0 items-center justify-center rounded-2xl" style={{ background: `${g.color}16`, color: g.color }}>
                    <Icon size={24} strokeWidth={2.1} />
                  </div>
                  <div className="flex-1">
                    <p className="font-display text-sm font-bold text-ink">{g.label}</p>
                    <p className="text-xs text-ink-muted">{g.desc}</p>
                  </div>
                  {active ? (
                    <CheckCircle2 size={20} className="shrink-0 text-brand" />
                  ) : (
                    kindMeta?.metered ? (
                      <span className="rounded-full bg-amber/15 px-2 py-0.5 text-[10px] font-bold text-[#B45309]">Metrado</span>
                    ) : (
                      <span className="rounded-full bg-emerald/15 px-2 py-0.5 text-[10px] font-bold text-emerald">Grátis</span>
                    )
                  )}
                </button>
              )
            })}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="ghost" size="sm">Cancelar</Button>
            </DialogClose>
            <Button size="sm" onClick={fire} disabled={!selectedKind || generating}>
              {generating ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Sparkles size={14} />}
              Gerar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Upload dialog */}
      <UploadDialog open={uploadOpen} onOpenChange={setUploadOpen} onUpload={onUpload} uploading={uploading} types={uploadTypes} />

      {/* Studio picker dialog */}
      <StudioPickerDialog open={pickerOpen} onOpenChange={setPickerOpen} onAttach={onAttach} attaching={attaching} />

      {/* Delete confirmation */}
      <Dialog open={!!pendingDelete} onOpenChange={(v) => { if (!v) setPendingDelete(null) }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Trash2 size={18} className="text-danger" /> Excluir criativo
            </DialogTitle>
            <DialogDescription>
              Esta ação não pode ser desfeita. O criativo “{pendingDelete?.name || creativeMeta(pendingDelete?.creative_type).label}” será removido permanentemente.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="ghost" size="sm">Cancelar</Button>
            </DialogClose>
            <Button
              variant="destructive"
              size="sm"
              disabled={deleting}
              onClick={() => { onDelete?.(pendingDelete.id); setPendingDelete(null) }}
            >
              {deleting ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Trash2 size={14} />}
              Excluir
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  )
}
