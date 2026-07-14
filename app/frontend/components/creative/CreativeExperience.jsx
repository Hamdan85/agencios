import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { ChevronLeft, ChevronRight, Maximize2 } from 'lucide-react'
import { useLightbox } from '@/components/ui/lightbox'
import { creativeToMedia } from '@/lib/media'

// Renders a creative in its native form: a swipeable carousel, an inline video
// player, or an image. Reused by the post-detail page, the client portal and the
// approval page. Clicking the stage (or the zoom button) opens the shared
// lightbox on this creative's slides, starting from the one on screen.
// fit="square" (default) forces a 1:1 stage; fit="height" fills the available
// height (contain) so a tall reel letterboxes instead of overflowing the deck.
export default function CreativeExperience({ creative, fit = 'square' }) {
  const { t } = useTranslation('creative')
  const lightbox = useLightbox()
  const [idx, setIdx] = useState(0)

  const slides = creativeToMedia(creative)
  const stageShape = fit === 'height' ? 'h-full w-full' : 'aspect-square w-full'

  if (!slides.length) {
    return (
      <div className={`flex ${stageShape} items-center justify-center rounded-2xl bg-surface-muted text-sm text-ink-muted`}>
        {t('experience.noPreview')}
      </div>
    )
  }

  const current = slides[Math.min(idx, slides.length - 1)]
  const many = slides.length > 1
  const open = () => lightbox.open(slides, idx)

  return (
    <div className={`relative overflow-hidden rounded-2xl border border-border bg-black/3 ${fit === 'height' ? 'h-full w-full' : 'w-full'}`}>
      <div className={`relative flex ${stageShape} items-center justify-center`}>
        {current.kind === 'video' ? (
          // The inline player keeps its own controls — the lightbox is reached
          // through the zoom button so play/pause never fights fullscreen.
          <video src={current.url} controls playsInline className="size-full object-contain" />
        ) : (
          <button type="button" onClick={open} aria-label={t('experience.zoom')} className="size-full cursor-zoom-in">
            <img src={current.url} alt={current.name} className="size-full object-contain" />
          </button>
        )}

        <button
          type="button"
          onClick={open}
          className="absolute right-2 top-2 rounded-lg bg-black/50 p-1.5 text-white transition hover:bg-black/70"
          aria-label={t('experience.zoom')}
        >
          <Maximize2 size={16} />
        </button>

        {many && (
          <>
            <button
              type="button"
              onClick={() => setIdx((i) => (i - 1 + slides.length) % slides.length)}
              className="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-1.5 text-white transition hover:bg-black/70"
              aria-label={t('experience.previous')}
            >
              <ChevronLeft size={18} />
            </button>
            <button
              type="button"
              onClick={() => setIdx((i) => (i + 1) % slides.length)}
              className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-1.5 text-white transition hover:bg-black/70"
              aria-label={t('experience.next')}
            >
              <ChevronRight size={18} />
            </button>
            <div className="absolute bottom-2 left-1/2 -translate-x-1/2 rounded-full bg-black/50 px-2 py-0.5 text-xs text-white">
              {idx + 1} / {slides.length}
            </div>
          </>
        )}
      </div>
    </div>
  )
}
