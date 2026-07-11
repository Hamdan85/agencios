import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import i18n from '@/i18n'
import { toast } from 'sonner'
import { creativeMeta, CREATIVE_TYPE_META, GENERATION_KIND_META, uploadAcceptFor, fileMatchesCreativeType, uploadableTypesForTicket, generatableKindsForTicket } from '@/lib/constants'
import { useWorkspaceCreatives, usePricing } from '@/hooks/useData'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { IconTile } from '@/components/ui/icon-tile'
import { Label } from '@/components/ui/label'
import { MediaThumb } from '@/components/ui/media-thumb'
import { Textarea } from '@/components/ui/input'
import { Spinner, InlineSpinner, EmptyState } from '@/components/ui/feedback'
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
  Trash2, ChevronDown, UploadCloud, LibraryBig, Film, Search,
} from 'lucide-react'
import { VideoScenesDialog } from './VideoScenesDialog'

const MediaViewer = lazy(() => import('./MediaViewer'))

// A generated video is scene-editable (reel / ugc_video).
const isSceneEditable = (c) => c?.source === 'generated' && ['ugc_video', 'reel'].includes(c?.creative_type)

// The three generatable kinds, each mapped to a sensible default creative type.
// Copy is resolved lazily (getters) so it follows the active locale.
const tr = (key) => i18n.t(`ticket:${key}`)
const GENERATABLE = [
  { kind: 'carousel', type: 'carousel', get label() { return tr('creatives.kinds.carousel.label') }, get desc() { return tr('creatives.kinds.carousel.desc') }, icon: GalleryHorizontalEnd, color: CREATIVE_TYPE_META.carousel.color },
  { kind: 'video', type: 'ugc_video', get label() { return tr('creatives.kinds.video.label') }, get desc() { return tr('creatives.kinds.video.desc') }, icon: Video, color: CREATIVE_TYPE_META.ugc_video.color },
  { kind: 'image', type: 'feed_image', get label() { return tr('creatives.kinds.image.label') }, get desc() { return tr('creatives.kinds.image.desc') }, icon: ImageIcon, color: CREATIVE_TYPE_META.feed_image.color },
]

// The probable credit cost of generating a given kind, read from the server
// pricing catalog (credit_costs). Video is cost-based, so its figure is an
// ESTIMATE for a standard clip (video_15s) — trued-up to the real duration at
// compose. Returns null while pricing is still loading.
function creditsForKind(kind, creditCosts) {
  if (!creditCosts) return null
  const value = kind === 'video' ? creditCosts.video_15s : creditCosts[kind]
  return Number.isFinite(value) ? value : null
}

// "1 crédito" / "3 créditos"; video is prefixed "~" since it's an estimate.
function creditBadgeLabel(kind, credits) {
  return tr(kind === 'video' ? 'creatives.creditBadgeEstimate' : 'creatives.creditBadge', { count: credits })
}

// A generated asset is a video when its URL carries a video extension (the
// ActiveStorage blob URL keeps the original filename, e.g. .../video-80.mp4).
const isVideoUrl = (url) => /\.(mp4|mov|webm|avi)(\?|$)/i.test(url || '')

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
    const isVideo = isVideoUrl(url)
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
function CreativeCard({ creative, onClick, onDelete, onEditScenes, deleting }) {
  const { t } = useTranslation('ticket')
  const m = creativeMeta(creative?.creative_type)
  // While generating, the first rendered scene stands in (preview_url) so the
  // card shows the video taking shape instead of a blind spinner.
  const thumb = creative?.asset_urls?.[0] || creative?.preview_url
  const generating = creative?.status === 'generating'
  const failed = creative?.status === 'failed'
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
            <MediaThumb url={thumb} alt={m.label} className="transition-transform group-hover:scale-105" />
          ) : (
            // No thumbnail yet — one calm, status-aware placeholder. The type name
            // already lives in the footer, so we never repeat it here; the state
            // (generating / failed) is the only thing worth surfacing.
            <div className="flex size-full flex-col items-center justify-center gap-2 px-2 text-center">
              <div
                className="flex size-11 items-center justify-center rounded-2xl"
                style={failed ? { background: '#EF444414', color: '#EF4444' } : { background: `${m.color}14`, color: m.color }}
              >
                {generating ? <InlineSpinner size={20} />
                  : failed ? <AlertCircle size={20} strokeWidth={2.1} />
                  : <m.icon size={20} strokeWidth={2.1} />}
              </div>
              {(generating || failed) && (
                <span className={cn('text-[11px] font-medium', failed ? 'text-danger' : 'text-ink-muted')}>
                  {generating ? t('creatives.generating') : t('creatives.failed')}
                </span>
              )}
            </div>
          )}
          {/* Delete — top-right, revealed on hover/focus. Stops propagation so it
              never triggers the viewer. */}
          {onDelete && !generating && (
            <button
              type="button"
              aria-label={t('creatives.deleteAria')}
              disabled={deleting}
              onClick={(e) => { e.stopPropagation(); onDelete(creative) }}
              className="absolute right-2 top-2 z-10 grid size-7 place-items-center rounded-full bg-white/90 text-ink-muted opacity-100 shadow-sm backdrop-blur transition focus:opacity-100 focus:outline-none hover:bg-danger hover:text-white disabled:opacity-50 sm:opacity-0 sm:group-hover:opacity-100"
            >
              <Trash2 size={14} />
            </button>
          )}
          {/* Scenes editor — video creatives only. Top-left so it never overlaps
              the delete control. Available WHILE generating too: the editor is
              where the live progress (and the chat) lives. */}
          {onEditScenes && (
            <button
              type="button"
              aria-label={t('creatives.editScenesAria')}
              onClick={(e) => { e.stopPropagation(); onEditScenes(creative) }}
              className="absolute left-2 top-2 z-10 inline-flex items-center gap-1 rounded-full bg-brand px-2.5 py-1 text-[11px] font-bold text-white shadow-sm transition hover:bg-brand/90"
            >
              <Film size={12} /> {t('creatives.scenes')}
            </button>
          )}
          {hasAssets && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/0 opacity-0 transition-all group-hover:bg-black/20 group-hover:opacity-100">
              <Badge className="bg-white/90 px-3 py-1 tracking-normal text-ink shadow">{t('creatives.view')}</Badge>
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
  const { t } = useTranslation('ticket')
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>{trigger}</DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-56">
        <DropdownMenuItem onClick={onGenerateOpen}>
          <Sparkles size={14} /> {t('creatives.generateWithAi')}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={onUploadOpen}>
          <UploadCloud size={14} /> {t('creatives.uploadFile')}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={onPickerOpen}>
          <LibraryBig size={14} /> {t('creatives.useFromStudio')}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

// Upload dialog — attaches an image/video file straight to the ticket as a
// creative, picking the creative type up front (drives the network-fit spec).
function UploadDialog({ open, onOpenChange, onUpload, uploading, types = [] }) {
  const { t } = useTranslation('ticket')
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
              <UploadCloud size={18} className="text-brand" /> {t('creatives.upload.title')}
            </DialogTitle>
            <DialogDescription>{t('creatives.upload.description')}</DialogDescription>
          </DialogHeader>
          <div className="grid gap-3.5 py-2">
            <div className="space-y-1.5">
              <Label>{t('creatives.upload.typeLabel')}</Label>
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
              <Label>{t('creatives.upload.fileLabel')}</Label>
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
                    const label = CREATIVE_TYPE_META[creativeType]?.label || t('creatives.upload.thatType')
                    toast.error(t('creatives.upload.incompatible', { label }))
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
                  ? t('creatives.upload.selected', { count: files.length })
                  : t('creatives.upload.select')}
              </button>
            </div>
            <div className="space-y-1.5">
              <Label>{t('creatives.upload.captionLabel')}</Label>
              <Textarea value={caption} onChange={(e) => setCaption(e.target.value)} rows={2} placeholder={t('creatives.upload.captionPlaceholder')} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="ghost" size="sm">{t('actions.cancel')}</Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={!files.length || uploading}>
              {uploading ? <Spinner size={14} className="border-white/30 border-t-white" /> : <UploadCloud size={14} />}
              {t('creatives.upload.submit')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

// Studio picker — attaches a creative already generated in the Studio (unassigned)
// to this ticket. Searchable by name/caption and restricted to the ticket's
// SUPPORTED types, so unsupported pieces never appear as choices.
function StudioPickerDialog({ open, onOpenChange, onAttach, attaching, supportedTypes = [] }) {
  const { t } = useTranslation('ticket')
  const [q, setQ] = useState('')
  const filters = {
    unassigned: true,
    q: q.trim() || undefined,
    types: supportedTypes.length ? supportedTypes : undefined,
    per: 200,
  }
  const { data, isLoading } = useWorkspaceCreatives(filters, { enabled: open })
  const items = data?.creatives || []

  const select = (creative) => {
    if (attaching) return
    onAttach?.(creative.id)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <LibraryBig size={18} className="text-brand" /> {t('creatives.picker.title')}
          </DialogTitle>
          <DialogDescription>{t('creatives.picker.description')}</DialogDescription>
        </DialogHeader>

        <div className="relative">
          <Search size={15} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t('creatives.picker.searchPlaceholder')}
            className="w-full rounded-xl border border-border bg-surface py-2 pl-9 pr-3 text-sm text-ink outline-none focus:ring-2 focus:ring-brand/40"
          />
        </div>

        {isLoading ? (
          <div className="flex justify-center py-10"><Spinner size={20} /></div>
        ) : items.length === 0 ? (
          <EmptyState
            icon={LibraryBig}
            title={q ? t('creatives.picker.emptySearchTitle') : t('creatives.picker.emptyTitle')}
            description={q
              ? t('creatives.picker.emptySearchDescription')
              : t('creatives.picker.emptyDescription')}
            color="#7C3AED"
          />
        ) : (
          <div className="grid max-h-104 grid-cols-3 gap-2.5 overflow-y-auto py-1 sm:grid-cols-4">
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
                        <MediaThumb url={thumb} alt={m.label} className="transition-transform group-hover:scale-105" />
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
            <Button variant="ghost" size="sm">{t('actions.cancel')}</Button>
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
  const { t } = useTranslation('ticket')
  // Only offer uploading the types that make sense for this ticket (its scoped
  // types, fitting its channels) — a reel/TikTok ticket never offers a carousel.
  const uploadTypes = uploadableTypesForTicket(creativeTypes, channels)
  // Same narrowing for AI generation: only the generation kinds this ticket can
  // actually produce — a carousel ticket never offers video, a TikTok (video-only)
  // ticket never offers a carousel or image.
  const allowedKinds = generatableKindsForTicket(creativeTypes, channels)
  const generatable = GENERATABLE.filter((g) => allowedKinds.includes(g.kind))
  // Per-kind credit estimate shown on each generation option (replaces the old
  // binary "Metrado" badge) so the team sees roughly what a generation will cost.
  const { data: pricing } = usePricing()
  const creditCosts = pricing?.credit_costs
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
  // Deep link: ?creative=<id> opens that video's editor (it shows its own
  // loading state while it fetches), so a reload reopens the dialog.
  const [urlParams] = useSearchParams()
  const deepId = urlParams.get('creative')
  const [scenesFor, setScenesFor] = useState(deepId ? { id: Number(deepId) } : null)
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
          <IconTile icon={ImagePlus} size="sm" tint="18" strokeWidth={2.3} />
          <div>
            <h3 className="font-display text-base font-bold text-ink">{t('creatives.title')}</h3>
            <p className="text-xs text-ink-muted">
              {items.length > 0 ? t('creatives.count', { count: items.length }) : t('creatives.hint')}
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
              {t('creatives.add')}
              <ChevronDown size={13} />
            </Button>
          )}
        />
      </div>

      <div className="p-5">
        {displayItems.length === 0 ? (
          <EmptyState
            icon={ImagePlus}
            title={t('creatives.empty.title')}
            description={t('creatives.empty.description')}
            color="#7C3AED"
            action={(
              <AddCreativeMenu
                onGenerateOpen={() => setOpen(true)}
                onUploadOpen={() => setUploadOpen(true)}
                onPickerOpen={() => setPickerOpen(true)}
                trigger={<Button size="sm" disabled={busy}><Sparkles size={14} /> {t('creatives.add')} <ChevronDown size={13} /></Button>}
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
                  onEditScenes={!pending && isSceneEditable(c) ? setScenesFor : undefined}
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
              <Sparkles size={18} className="text-brand" /> {t('creatives.generateTitle')}
            </DialogTitle>
            <DialogDescription>{t('creatives.generateDescription')}</DialogDescription>
          </DialogHeader>
          <div className="grid gap-2.5">
            {generatable.length === 0 && (
              <p className="rounded-2xl border border-dashed border-border bg-surface px-4 py-6 text-center text-sm text-ink-muted">
                {t('creatives.nothingGeneratable')}
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
                  <IconTile icon={Icon} color={g.color} strokeWidth={2.1} />
                  <div className="flex-1">
                    <p className="font-display text-sm font-bold text-ink">{g.label}</p>
                    <p className="text-xs text-ink-muted">{g.desc}</p>
                  </div>
                  {active ? (
                    <CheckCircle2 size={20} className="shrink-0 text-brand" />
                  ) : (() => {
                    const credits = creditsForKind(g.kind, creditCosts)
                    if (credits === null) {
                      // Pricing still loading — fall back to the metered/free hint.
                      return kindMeta?.metered
                        ? <Badge variant="warning" className="px-2 text-[10px] tracking-normal">{t('creatives.metered')}</Badge>
                        : <Badge variant="success" className="bg-emerald/15 px-2 text-[10px] tracking-normal">{t('creatives.free')}</Badge>
                    }
                    if (credits <= 0) {
                      return <Badge variant="success" className="bg-emerald/15 px-2 text-[10px] tracking-normal">{t('creatives.free')}</Badge>
                    }
                    return (
                      <Badge variant="warning" className="whitespace-nowrap px-2 text-[10px] tracking-normal">
                        {creditBadgeLabel(g.kind, credits)}
                      </Badge>
                    )
                  })()}
                </button>
              )
            })}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="ghost" size="sm">{t('actions.cancel')}</Button>
            </DialogClose>
            <Button size="sm" onClick={fire} disabled={!selectedKind || generating}>
              {generating ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Sparkles size={14} />}
              {t('creatives.generate')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Upload dialog */}
      <UploadDialog open={uploadOpen} onOpenChange={setUploadOpen} onUpload={onUpload} uploading={uploading} types={uploadTypes} />

      {/* Studio picker dialog */}
      <StudioPickerDialog open={pickerOpen} onOpenChange={setPickerOpen} onAttach={onAttach} attaching={attaching} supportedTypes={uploadTypes} />

      {/* Video scenes editor */}
      <VideoScenesDialog creative={scenesFor} open={!!scenesFor} onOpenChange={(v) => { if (!v) setScenesFor(null) }} />

      {/* Delete confirmation */}
      <Dialog open={!!pendingDelete} onOpenChange={(v) => { if (!v) setPendingDelete(null) }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Trash2 size={18} className="text-danger" /> {t('creatives.deleteTitle')}
            </DialogTitle>
            <DialogDescription>
              {t('creatives.deleteDescription', { name: pendingDelete?.name || creativeMeta(pendingDelete?.creative_type).label })}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="ghost" size="sm">{t('actions.cancel')}</Button>
            </DialogClose>
            <Button
              variant="destructive"
              size="sm"
              disabled={deleting}
              onClick={() => { onDelete?.(pendingDelete.id); setPendingDelete(null) }}
            >
              {deleting ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Trash2 size={14} />}
              {t('actions.delete')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  )
}
