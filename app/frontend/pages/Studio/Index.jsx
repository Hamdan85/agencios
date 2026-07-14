import { useState, useMemo, useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import {
  Sparkles, GalleryHorizontalEnd, Video, Image as ImageIcon,
  Images, Trash2,
} from 'lucide-react'
import i18n from '@/i18n'
import { useStudio, useGenerate, useStartVideo, useWorkspaceCreativesInfinite, useCreativeMutations } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { useGenerationsChannel } from '@/hooks/useRealtime'
import { useInfiniteScroll } from '@/hooks/useInfiniteScroll'
import { PageHeader } from '@/components/ui/page-header'
import { PageLoader, EmptyState, Spinner, InlineSpinner } from '@/components/ui/feedback'
import { IconTile } from '@/components/ui/icon-tile'
import { MediaThumb } from '@/components/ui/media-thumb'
import { useLightbox } from '@/components/ui/lightbox'
import { creativeToMedia } from '@/lib/media'
import { Badge } from '@/components/ui/badge'
import { Page } from '@/components/ui/page'
import { FilterBar } from '@/components/ui/filter-bar'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { CREATIVE_TYPE_META, creativeMeta } from '@/lib/constants'
import { GeneratorCard } from '@/components/studio/GeneratorCard'
import { GenerateDialog } from '@/components/studio/GenerateDialog'
import { VideoScenesDialog } from '@/components/ticket/VideoScenesDialog'

// A generated video is scene-editable (reel / ugc_video) — its scenes can be
// re-rendered one at a time in the scenes editor.
const isSceneEditable = (c) => c?.source === 'generated' && ['ugc_video', 'reel'].includes(c?.creative_type)

const HERO = '#F43F5E'

const GENERATORS = [
  { kind: 'carousel', icon: GalleryHorizontalEnd, color: '#7C3AED' },
  { kind: 'video', icon: Video, color: '#F43F5E' },
  { kind: 'image', icon: ImageIcon, color: '#0EA5E9' },
]

const CREATIVE_STATUS_META = {
  generating: { get label() { return i18n.t('studio:gallery.status.generating') }, variant: 'warning' },
  failed: { get label() { return i18n.t('studio:gallery.status.failed') }, variant: 'danger' },
}

export default function StudioIndex() {
  const { t } = useTranslation('studio')
  const { data: studio, isLoading } = useStudio()
  const { data: me } = useCurrentUser()
  const workspaceId = me?.workspace?.id
  useGenerationsChannel(workspaceId)

  const [dialogKind, setDialogKind] = useState(null)
  // The active video editor (chat + timeline) — opened by a just-generated video
  // OR by a ?creative=<id> deep link. It shows its own loading state while it
  // fetches, so on a reload the dialog opens immediately (even before the studio
  // page finishes loading below).
  const [params] = useSearchParams()
  const deepId = params.get('creative')
  const [editorCreative, setEditorCreative] = useState(deepId ? { id: Number(deepId) } : null)
  const generate = useGenerate()
  const startVideo = useStartVideo()

  const videoEditor = (
    <VideoScenesDialog
      creative={editorCreative}
      open={!!editorCreative}
      onOpenChange={(v) => { if (!v) setEditorCreative(null) }}
    />
  )

  // Reload with a deep link: open the editor over the page loader right away.
  if (isLoading) return <>{<PageLoader />}{videoEditor}</>

  const clients = studio?.clients || []

  return (
    <Page className="animate-rise">
      <PageHeader
        eyebrow={t('page.eyebrow')}
        title={t('page.title')}
        icon={Sparkles}
        color={HERO}
        description={t('page.description')}
      />

      {/* Generators — the primary action */}
      <section className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {GENERATORS.map((g) => (
          <GeneratorCard
            key={g.kind}
            icon={g.icon}
            title={t(`generators.${g.kind}.title`)}
            subtitle={t(`generators.${g.kind}.subtitle`)}
            color={g.color}
            onClick={() => setDialogKind(g.kind)}
          />
        ))}
      </section>

      {/* Creative library */}
      <section className="mt-9">
        <CreativesGallery />
      </section>

      <GenerateDialog
        kind={dialogKind}
        open={!!dialogKind}
        onOpenChange={(o) => !o && setDialogKind(null)}
        generate={generate}
        startVideo={startVideo}
        clients={clients}
        onGenerated={(gen) => {
          if (gen?.kind === 'video' && gen?.creative_id) setEditorCreative({ id: gen.creative_id })
        }}
      />

      {/* Editor for a just-generated OR deep-linked video */}
      {videoEditor}
    </Page>
  )
}

// ── Creatives gallery ──────────────────────────────────────────────
function CreativesGallery() {
  const { t } = useTranslation('studio')
  const lightbox = useLightbox()
  const [q, setQ] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [clientFilter, setClientFilter] = useState('')
  // A generated video opens the EDITOR on click; everything else opens the viewer.
  const [editorCreative, setEditorCreative] = useState(null)

  const filters = useMemo(() => ({
    q: q || undefined,
    type: typeFilter || undefined,
    client_id: clientFilter || undefined,
  }), [q, typeFilter, clientFilter])

  const {
    data, isLoading, hasNextPage, isFetchingNextPage, fetchNextPage,
  } = useWorkspaceCreativesInfinite(filters)
  const mutations = useCreativeMutations()
  const confirm = useConfirm()
  const pages = data?.pages || []
  const creatives = pages.flatMap((p) => p.creatives || [])
  const clients = pages[0]?.clients || []
  const sentinelRef = useInfiniteScroll({
    hasNextPage, isFetchingNextPage, fetchNextPage, deps: [creatives.length],
  })

  const handleDelete = async (creative) => {
    const ok = await confirm({
      title: t('gallery.deleteTitle'),
      description: t('gallery.deleteDescription'),
      confirmLabel: t('gallery.deleteConfirm'),
      destructive: true,
    })
    if (ok) mutations.destroy.mutate(creative.id)
  }

  // Open the viewer on a SINGLE creative's slides (a carousel is one creative,
  // not a pile of separate items).
  const openViewer = useCallback((creative) => lightbox.open(creativeToMedia(creative)), [lightbox])

  const typeOptions = Object.entries(CREATIVE_TYPE_META).map(([key, m]) => ({ value: key, label: m.label, icon: m.icon, color: m.color }))
  const filterSpec = [
    { key: 'type', type: 'options', label: t('gallery.filterType'), options: typeOptions },
    ...(clients.length > 0
      ? [{ key: 'client_id', type: 'options', label: t('gallery.filterClient'), options: clients.map((c) => ({ value: String(c.id), label: c.name })) }]
      : []),
  ]
  const filterValues = { type: typeFilter || undefined, client_id: clientFilter || undefined }
  const onFilterChange = (key, value) => {
    if (key === 'type') setTypeFilter(value || '')
    else if (key === 'client_id') setClientFilter(value || '')
  }
  const clearFilters = () => { setTypeFilter(''); setClientFilter('') }

  return (
    <div className="space-y-5">
      {/* Filters bar — shared FilterBar (search inline, filters collapse to a
          bottom sheet on mobile), consistent with the board/tickets listings. */}
      <FilterBar
        search
        searchValue={q}
        onSearch={(v) => setQ(v || '')}
        searchPlaceholder={t('gallery.searchPlaceholder')}
        filters={filterSpec}
        values={filterValues}
        onChange={onFilterChange}
        onClear={clearFilters}
      />

      {/* Grid */}
      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner size={28} /></div>
      ) : creatives.length === 0 ? (
        <EmptyState
          icon={Images}
          color={HERO}
          title={t('gallery.empty.title')}
          description={t('gallery.empty.description')}
        />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
            {creatives.map((c) => (
              <GalleryCard
                key={c.id}
                creative={c}
                onClick={() => (isSceneEditable(c) ? setEditorCreative(c) : openViewer(c))}
                onDelete={() => handleDelete(c)}
              />
            ))}
          </div>
          {/* Infinite-scroll sentinel — loads the next page as it nears view. */}
          <div ref={sentinelRef} className="h-1" />
          {isFetchingNextPage && (
            <div className="flex justify-center py-6"><Spinner size={22} /></div>
          )}
        </>
      )}

      {/* Video editor — opened by clicking a generated video card */}
      <VideoScenesDialog
        creative={editorCreative}
        open={!!editorCreative}
        onOpenChange={(v) => { if (!v) setEditorCreative(null) }}
      />
    </div>
  )
}

// ── Gallery card ───────────────────────────────────────────────────
function GalleryCard({ creative, onClick, onDelete }) {
  const { t } = useTranslation('studio')
  const m = creativeMeta(creative.creative_type)
  const st = CREATIVE_STATUS_META[creative.status]
  // While a video is still generating, the first rendered scene stands in as the
  // early preview (preview_url) so the card never sits on a blind spinner.
  const thumb = creative.asset_urls?.[0] || creative.preview_url
  const generating = creative.status === 'generating'

  return (
    <div className="group relative overflow-hidden rounded-2xl border border-border bg-surface lift">
      <button
        type="button"
        onClick={onClick}
        className="relative block w-full"
        style={{ paddingBottom: '100%' }}
        aria-label={t('gallery.view', { type: m.label })}
      >
        <div className="absolute inset-0 overflow-hidden" style={{ background: `${m.color}12` }}>
          {thumb ? (
            <MediaThumb url={thumb} alt={m.label} className="transition-transform group-hover:scale-105" />
          ) : (
            <div className="flex size-full flex-col items-center justify-center gap-2">
              <IconTile
                icon={generating ? InlineSpinner : m.icon}
                color={m.color}
                tint="1F"
                iconSize={22}
                strokeWidth={generating ? 2 : 2.1}
              />
            </div>
          )}
          {/* Only show a status badge when it carries information. */}
          {st && (
            <div className="absolute left-2 top-2">
              <Badge variant={st.variant} className="shadow-sm text-[10px]">{st.label}</Badge>
            </div>
          )}
          {creative.source === 'generated' && (
            <div className="absolute right-2 top-2">
              <span className="inline-flex items-center gap-1 rounded-full bg-white/85 px-1.5 py-0.5 text-[10px] font-bold text-brand shadow-sm backdrop-blur">
                <Sparkles size={9} /> {t('gallery.aiBadge')}
              </span>
            </div>
          )}
        </div>
      </button>

      <div className="p-2.5">
        <p className="truncate text-[12px] font-semibold text-ink">{creative.name || m.label}</p>
        {creative.client_name && (
          <p className="truncate text-[11px] text-ink-faint">{creative.client_name}</p>
        )}
      </div>

      <div className="absolute bottom-13 right-2 flex gap-1 opacity-100 transition-opacity sm:opacity-0 sm:group-hover:opacity-100">
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onDelete() }}
          className="flex size-7 items-center justify-center rounded-lg bg-surface/90 shadow backdrop-blur hover:bg-danger/10"
          title={t('gallery.remove')}
        >
          <Trash2 size={13} className="text-danger" />
        </button>
      </div>
    </div>
  )
}

