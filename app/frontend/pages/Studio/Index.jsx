import { lazy, Suspense, useState, useMemo, useCallback } from 'react'
import {
  Sparkles, GalleryHorizontalEnd, Video, Image as ImageIcon,
  Loader2, Images, Search, Filter, Pencil, Trash2, Check, X,
} from 'lucide-react'
import { useStudio, useGenerate, useWorkspaceCreatives, useCreativeMutations } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { useGenerationsChannel } from '@/hooks/useRealtime'
import { PageHeader } from '@/components/ui/page-header'
import { PageLoader, EmptyState, Spinner } from '@/components/ui/feedback'
import { Badge } from '@/components/ui/badge'
import { Page } from '@/components/ui/page'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'
import { CREATIVE_TYPE_META, creativeMeta } from '@/lib/constants'
import { GeneratorCard } from '@/components/studio/GeneratorCard'
import { GenerateDialog } from '@/components/studio/GenerateDialog'

const MediaViewer = lazy(() => import('@/components/ticket/MediaViewer'))

const HERO = '#F43F5E'

const GENERATORS = [
  { kind: 'carousel', icon: GalleryHorizontalEnd, title: 'Carrossel', subtitle: 'Viral · ideia, texto ou link', color: '#7C3AED' },
  { kind: 'video', icon: Video, title: 'Vídeo UGC', subtitle: 'Avatar + voz a partir do roteiro', color: '#F43F5E' },
  { kind: 'image', icon: ImageIcon, title: 'Imagem', subtitle: 'Imagem original via prompt', color: '#0EA5E9' },
]

const CREATIVE_STATUS_META = {
  generating: { label: 'Gerando…', variant: 'warning' },
  failed: { label: 'Falhou', variant: 'danger' },
}

export default function StudioIndex() {
  const { data: studio, isLoading } = useStudio()
  const { data: me } = useCurrentUser()
  const workspaceId = me?.workspace?.id
  useGenerationsChannel(workspaceId)

  const [dialogKind, setDialogKind] = useState(null)
  const generate = useGenerate()

  if (isLoading) return <PageLoader />

  const clients = studio?.clients || []

  return (
    <Page className="animate-rise">
      <PageHeader
        eyebrow="Criação"
        title="Estúdio"
        icon={Sparkles}
        color={HERO}
        description="Gere criativos com IA no padrão da marca do cliente e gerencie sua biblioteca."
      />

      {/* Generators — the primary action */}
      <section className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {GENERATORS.map((g) => (
          <GeneratorCard
            key={g.kind}
            icon={g.icon}
            title={g.title}
            subtitle={g.subtitle}
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
        clients={clients}
      />
    </Page>
  )
}

// ── Creatives gallery ──────────────────────────────────────────────
function CreativesGallery() {
  const [q, setQ] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [clientFilter, setClientFilter] = useState('')
  const [viewerOpen, setViewerOpen] = useState(false)
  const [viewerItems, setViewerItems] = useState([])
  const [editCreative, setEditCreative] = useState(null)

  const filters = useMemo(() => ({
    q: q || undefined,
    type: typeFilter || undefined,
    client_id: clientFilter || undefined,
  }), [q, typeFilter, clientFilter])

  const { data, isLoading } = useWorkspaceCreatives(filters)
  const mutations = useCreativeMutations()
  const creatives = data?.creatives || []
  const clients = data?.clients || []

  // Open the viewer on a SINGLE creative's slides (a carousel is one creative,
  // not a pile of separate items).
  const openViewer = useCallback((creative) => {
    const atts = creativeToAttachments(creative)
    if (!atts.length) return
    setViewerItems(atts)
    setViewerOpen(true)
  }, [])

  return (
    <div className="space-y-5">
      {/* Filters bar */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative min-w-50 flex-1">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por nome ou legenda…"
            className="pl-9"
          />
        </div>
        <Select value={typeFilter} onValueChange={setTypeFilter}>
          <SelectTrigger className="w-44">
            <Filter size={14} className="mr-1 text-ink-faint" />
            <SelectValue placeholder="Tipo" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">Todos os tipos</SelectItem>
            {Object.entries(CREATIVE_TYPE_META).map(([key, m]) => (
              <SelectItem key={key} value={key}>{m.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        {clients.length > 0 && (
          <Select value={clientFilter} onValueChange={setClientFilter}>
            <SelectTrigger className="w-44">
              <SelectValue placeholder="Cliente" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">Todos os clientes</SelectItem>
              {clients.map((c) => (
                <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
      </div>

      {/* Grid */}
      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner size={28} /></div>
      ) : creatives.length === 0 ? (
        <EmptyState
          icon={Images}
          color={HERO}
          title="Nenhum criativo ainda"
          description="Gere um carrossel, vídeo ou imagem com IA usando os geradores acima."
        />
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
          {creatives.map((c) => (
            <GalleryCard
              key={c.id}
              creative={c}
              onClick={() => openViewer(c)}
              onEdit={() => setEditCreative(c)}
              onDelete={() => mutations.destroy.mutate(c.id)}
            />
          ))}
        </div>
      )}

      {/* MediaViewer lightbox */}
      <Suspense fallback={null}>
        <MediaViewer
          attachments={viewerItems}
          index={0}
          open={viewerOpen}
          onClose={() => setViewerOpen(false)}
        />
      </Suspense>

      {/* Edit dialog */}
      {editCreative && (
        <EditCreativeDialog
          creative={editCreative}
          clients={clients}
          onClose={() => setEditCreative(null)}
          onSave={(payload) => {
            mutations.update.mutate({ id: editCreative.id, ...payload }, {
              onSuccess: () => setEditCreative(null),
            })
          }}
          saving={mutations.update.isPending}
        />
      )}
    </div>
  )
}

// One creative → its slide attachments. A carousel's slides share the creative's
// name and are captioned "Slide i de N", so the viewer reads as one carousel.
function creativeToAttachments(creative) {
  const m = creativeMeta(creative.creative_type)
  const urls = creative.asset_urls || []
  const total = urls.length
  const isCarousel = creative.creative_type === 'carousel' || total > 1

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

// ── Gallery card ───────────────────────────────────────────────────
function GalleryCard({ creative, onClick, onEdit, onDelete }) {
  const m = creativeMeta(creative.creative_type)
  const st = CREATIVE_STATUS_META[creative.status]
  const thumb = creative.asset_urls?.[0]
  const generating = creative.status === 'generating'

  return (
    <div className="group relative overflow-hidden rounded-2xl border border-border bg-surface lift">
      <button
        type="button"
        onClick={onClick}
        className="relative block w-full"
        style={{ paddingBottom: '100%' }}
        aria-label={`Ver ${m.label}`}
      >
        <div className="absolute inset-0 overflow-hidden" style={{ background: `${m.color}12` }}>
          {thumb ? (
            <img src={thumb} alt={m.label} className="size-full object-cover transition-transform group-hover:scale-105" />
          ) : (
            <div className="flex size-full flex-col items-center justify-center gap-2">
              <div className="flex size-12 items-center justify-center rounded-2xl" style={{ background: `${m.color}1F`, color: m.color }}>
                {generating ? <Loader2 size={22} className="animate-spin" /> : <m.icon size={22} strokeWidth={2.1} />}
              </div>
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
                <Sparkles size={9} /> IA
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

      <div className="absolute bottom-13 right-2 flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onEdit() }}
          className="flex size-7 items-center justify-center rounded-lg bg-surface/90 shadow backdrop-blur hover:bg-surface"
          title="Editar"
        >
          <Pencil size={13} className="text-ink-muted" />
        </button>
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onDelete() }}
          className="flex size-7 items-center justify-center rounded-lg bg-surface/90 shadow backdrop-blur hover:bg-danger/10"
          title="Remover"
        >
          <Trash2 size={13} className="text-danger" />
        </button>
      </div>
    </div>
  )
}

// ── Edit creative dialog ───────────────────────────────────────────
function EditCreativeDialog({ creative, clients, onClose, onSave, saving }) {
  const m = creativeMeta(creative.creative_type)
  const [name, setName] = useState(creative.name || '')
  const [clientId, setClientId] = useState(String(creative.client_id || ''))

  const submit = (e) => {
    e.preventDefault()
    onSave({ name: name.trim() || null, client_id: clientId || null })
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <div className="flex size-8 items-center justify-center rounded-xl" style={{ background: `${m.color}18`, color: m.color }}>
              <m.icon size={16} strokeWidth={2.2} />
            </div>
            Editar criativo
          </DialogTitle>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="cr-name">Nome</Label>
            <Input
              id="cr-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={m.label}
            />
          </div>
          {clients.length > 0 && (
            <div className="space-y-1.5">
              <Label>Cliente</Label>
              <Select value={clientId} onValueChange={setClientId}>
                <SelectTrigger>
                  <SelectValue placeholder="Nenhum cliente" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="">Nenhum cliente</SelectItem>
                  {clients.map((c) => (
                    <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="ghost" size="sm"><X size={15} /> Cancelar</Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={saving}>
              {saving ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Check size={15} />}
              Salvar
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
