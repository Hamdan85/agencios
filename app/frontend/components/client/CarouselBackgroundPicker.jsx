import { useState } from 'react'
import { Search, ImagePlus } from 'lucide-react'
import { useWorkspaceCreatives } from '@/hooks/useData'
import { isVideoUrl } from '@/lib/media'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { MediaThumb } from '@/components/ui/media-thumb'
import { Spinner, EmptyState } from '@/components/ui/feedback'

// Image creative types that make sense as a full-bleed carousel background.
const IMAGE_TYPES = ['feed_image', 'ad', 'thumbnail', 'cover', 'carousel', 'story']

// Grid picker over the workspace's platform creatives — the user chooses one
// image to use as the carousel background. Fetches lazily (only when open).
export default function CarouselBackgroundPicker({ open, onOpenChange, onSelect }) {
  const [q, setQ] = useState('')
  const { data, isLoading } = useWorkspaceCreatives({ q, types: IMAGE_TYPES, per: 200 }, { enabled: open })
  const creatives = (data?.creatives || [])
    .map((c) => ({ ...c, image: c.asset_urls?.find((u) => !isVideoUrl(u)) }))
    .filter((c) => c.image)

  const pick = (c) => {
    onSelect({ id: c.id, url: c.image })
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Escolher de um criativo</DialogTitle>
          <DialogDescription>Use a imagem de um criativo da plataforma como fundo do carrossel.</DialogDescription>
        </DialogHeader>

        <div className="relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar criativos…" className="pl-9" />
        </div>

        <div className="mt-3 max-h-[52vh] overflow-y-auto">
          {isLoading ? (
            <div className="grid place-items-center py-12"><Spinner /></div>
          ) : creatives.length === 0 ? (
            <EmptyState icon={ImagePlus} title="Nenhum criativo com imagem" description="Gere ou envie um criativo de imagem para usá-lo como fundo." />
          ) : (
            <div className="grid grid-cols-3 gap-3 sm:grid-cols-4">
              {creatives.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => pick(c)}
                  title={c.name}
                  className="group relative aspect-4/5 overflow-hidden rounded-xl border border-border bg-surface-muted transition hover:border-brand hover:ring-2 hover:ring-brand/30"
                >
                  <MediaThumb url={c.image} alt={c.name} className="transition group-hover:scale-105" />
                </button>
              ))}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
