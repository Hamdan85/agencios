import { useState } from 'react'
import { creativeMeta, CREATIVE_TYPE_META, GENERATION_KIND_META } from '@/lib/constants'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import { CreativeTypeChip } from '@/components/ui/iconography'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'
import { ImagePlus, Sparkles, GalleryHorizontalEnd, Video, Image as ImageIcon, AlertCircle, CheckCircle2, Loader2 } from 'lucide-react'

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

function CreativeCard({ creative }) {
  const m = creativeMeta(creative?.creative_type)
  const st = CREATIVE_STATUS[creative?.status] || CREATIVE_STATUS.draft
  const StIcon = st.icon
  const thumb = creative?.asset_urls?.[0]
  const generating = creative?.status === 'generating'

  return (
    <div className="group overflow-hidden rounded-2xl border border-border bg-surface transition-all lift">
      <div className="relative aspect-[4/5] overflow-hidden" style={{ background: `${m.color}10` }}>
        {thumb ? (
          <img src={thumb} alt={m.label} className="size-full object-cover" />
        ) : (
          <div className="flex size-full flex-col items-center justify-center gap-2">
            <div className="flex size-14 items-center justify-center rounded-2xl" style={{ background: `${m.color}1F`, color: m.color }}>
              {generating ? <Loader2 size={26} className="animate-spin" /> : <m.icon size={26} strokeWidth={2.1} />}
            </div>
            <CreativeTypeChip type={creative?.creative_type} />
          </div>
        )}
        <div className="absolute left-2 top-2">
          <Badge variant={st.variant} className="shadow-sm">
            <StIcon size={11} className={cn('mr-0.5', generating && 'animate-spin')} />
            {st.label}
          </Badge>
        </div>
        {creative?.source === 'generated' && (
          <div className="absolute right-2 top-2">
            <span className="inline-flex items-center gap-1 rounded-full bg-white/85 px-2 py-0.5 text-[10px] font-bold text-brand shadow-sm backdrop-blur">
              <Sparkles size={10} /> IA
            </span>
          </div>
        )}
      </div>
      {creative?.caption && (
        <p className="line-clamp-2 px-3 py-2.5 text-xs text-ink-secondary">{creative.caption}</p>
      )}
    </div>
  )
}

export default function CreativesPanel({ creatives = [], onGenerate, generating = false }) {
  const [open, setOpen] = useState(false)
  const items = creatives || []

  const fire = (item) => {
    onGenerate?.({ kind: item.kind, type: item.type, params: {} })
    setOpen(false)
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
              {items.length > 0 ? `${items.length} criativo${items.length > 1 ? 's' : ''}` : 'Gere ou anexe peças para este ticket.'}
            </p>
          </div>
        </div>
        <Button size="sm" onClick={() => setOpen(true)} disabled={generating}>
          {generating ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Sparkles size={14} />}
          Gerar criativo
        </Button>
      </div>

      <div className="p-5">
        {items.length === 0 ? (
          <EmptyState
            icon={ImagePlus}
            title="Nenhum criativo ainda"
            description="Gere um carrossel, vídeo UGC ou imagem com IA — ou anexe um arquivo."
            color="#7C3AED"
            action={<Button size="sm" onClick={() => setOpen(true)}><Sparkles size={14} /> Gerar criativo</Button>}
          />
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {items.map((c) => (
              <CreativeCard key={c.id} creative={c} />
            ))}
          </div>
        )}
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Sparkles size={18} className="text-brand" /> Gerar criativo
            </DialogTitle>
            <DialogDescription>Escolha o tipo de peça para a IA produzir.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-2.5">
            {GENERATABLE.map((g) => {
              const Icon = g.icon
              const kindMeta = GENERATION_KIND_META[g.kind]
              return (
                <button
                  key={g.kind}
                  type="button"
                  onClick={() => fire(g)}
                  className="flex items-center gap-3.5 rounded-2xl border border-border bg-surface p-4 text-left transition-all hover:border-brand/40 hover:bg-brand-soft/40 lift"
                >
                  <div className="flex size-12 shrink-0 items-center justify-center rounded-2xl" style={{ background: `${g.color}16`, color: g.color }}>
                    <Icon size={24} strokeWidth={2.1} />
                  </div>
                  <div className="flex-1">
                    <p className="font-display text-sm font-bold text-ink">{g.label}</p>
                    <p className="text-xs text-ink-muted">{g.desc}</p>
                  </div>
                  {kindMeta?.label && !['image'].includes(g.kind) && (
                    <span className="rounded-full bg-amber/15 px-2 py-0.5 text-[10px] font-bold text-[#B45309]">Metrado</span>
                  )}
                </button>
              )
            })}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="ghost" size="sm">Cancelar</Button>
            </DialogClose>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  )
}
