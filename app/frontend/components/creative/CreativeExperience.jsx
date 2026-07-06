import { Suspense, lazy, useState } from 'react'
import { ChevronLeft, ChevronRight, Maximize2 } from 'lucide-react'

const MediaViewer = lazy(() => import('@/components/ticket/MediaViewer'))
const isVideoUrl = (url) => /\.(mp4|mov|webm|avi)(\?|$)/i.test(url || '')

// Convert a creative to MediaViewer attachments (mirrors CreativesPanel).
function toAttachments(creative) {
  const urls = creative?.asset_urls || []
  const isCarousel = creative?.creative_type === 'carousel' || urls.length > 1
  return urls.map((url, i) => ({
    id: `${creative.id}-${i}`,
    url,
    filename: isCarousel ? `slide-${i + 1}` : String(creative.id),
    display_name: creative.name || creative.creative_type,
    kind: isVideoUrl(url) ? 'video' : 'image',
    content_type: isVideoUrl(url) ? 'video/mp4' : 'image/jpeg',
    description: creative.caption || undefined,
  }))
}

// Renders a creative in its native form: a swipeable carousel, an inline video
// player, or an image. Reused by the post-detail page and the client approval
// page. Click opens the MediaViewer lightbox for zoom.
export default function CreativeExperience({ creative }) {
  const [idx, setIdx] = useState(0)
  const [open, setOpen] = useState(false)
  const urls = creative?.asset_urls || []
  const cover = urls[0] || creative?.preview_url

  if (!urls.length && !cover) {
    return <div className="flex aspect-square w-full items-center justify-center rounded-2xl bg-surface-muted text-sm text-ink-muted">Sem prévia</div>
  }

  const current = urls[idx] || cover
  const many = urls.length > 1

  return (
    <div className="relative w-full overflow-hidden rounded-2xl border border-border bg-black/[0.03]">
      <div className="relative flex aspect-square w-full items-center justify-center">
        {isVideoUrl(current) ? (
          <video src={current} controls playsInline className="size-full object-contain" />
        ) : (
          <img src={current} alt={creative.name || ''} className="size-full object-contain" />
        )}

        <button type="button" onClick={() => setOpen(true)}
          className="absolute right-2 top-2 rounded-lg bg-black/50 p-1.5 text-white hover:bg-black/70" aria-label="Ampliar">
          <Maximize2 size={16} />
        </button>

        {many && (
          <>
            <button type="button" onClick={() => setIdx((i) => (i - 1 + urls.length) % urls.length)}
              className="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-1.5 text-white" aria-label="Anterior">
              <ChevronLeft size={18} />
            </button>
            <button type="button" onClick={() => setIdx((i) => (i + 1) % urls.length)}
              className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-1.5 text-white" aria-label="Próximo">
              <ChevronRight size={18} />
            </button>
            <div className="absolute bottom-2 left-1/2 -translate-x-1/2 rounded-full bg-black/50 px-2 py-0.5 text-xs text-white">
              {idx + 1} / {urls.length}
            </div>
          </>
        )}
      </div>

      <Suspense fallback={null}>
        <MediaViewer attachments={toAttachments(creative)} index={idx} open={open} onClose={() => setOpen(false)} />
      </Suspense>
    </div>
  )
}
