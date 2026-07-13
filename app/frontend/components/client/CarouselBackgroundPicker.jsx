import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Search, ImagePlus } from 'lucide-react'
import { useWorkspaceCreatives } from '@/hooks/useData'
import { useIsMobile } from '@/hooks/useMediaQuery'
import { isVideoUrl } from '@/lib/media'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog'
import { Sheet, SheetContent, SheetTitle, SheetDescription } from '@/components/ui/sheet'
import { Input } from '@/components/ui/input'
import { MediaThumb } from '@/components/ui/media-thumb'
import { Spinner, EmptyState } from '@/components/ui/feedback'

// Image creative types that make sense as a full-bleed carousel background.
const IMAGE_TYPES = ['feed_image', 'ad', 'thumbnail', 'cover', 'carousel', 'story']

// Grid picker over the workspace's platform creatives — the user chooses one
// image to use as the carousel background. Fetches lazily (only when open).
//
// This opens from INSIDE the client editor dialog. On desktop that's a second centered
// card — fine. On a phone it would be a second FULLSCREEN dialog stacked on the first:
// the editor vanishes, two blurred overlays composite, and the only way back is an X.
// So on mobile it becomes a bottom sheet — the editor stays visible behind it, which
// matches the mental model ("I'm picking, I didn't navigate away").
export default function CarouselBackgroundPicker({ open, onOpenChange, onSelect }) {
  const { t } = useTranslation('clients')
  const isMobile = useIsMobile()
  const [q, setQ] = useState('')
  const { data, isLoading } = useWorkspaceCreatives({ q, types: IMAGE_TYPES, per: 200 }, { enabled: open })
  const creatives = (data?.creatives || [])
    .map((c) => ({ ...c, image: c.asset_urls?.find((u) => !isVideoUrl(u)) }))
    .filter((c) => c.image)

  const pick = (c) => {
    onSelect({ id: c.id, url: c.image })
    onOpenChange(false)
  }

  const body = (
    <>
      <div className="relative shrink-0">
        <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
        <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t('backgroundPicker.searchPlaceholder')} className="pl-9" />
      </div>

      {/* This image becomes the FULL-BLEED background of a carousel — judging it at 98px
          (3 columns on a 360px phone) is impossible. Two columns doubles the thumb. */}
      <div className="mt-3 overflow-y-auto max-sm:min-h-0 max-sm:flex-1 max-sm:overscroll-contain sm:max-h-[52vh]">
        {isLoading ? (
          <div className="grid place-items-center py-12"><Spinner /></div>
        ) : creatives.length === 0 ? (
          <EmptyState icon={ImagePlus} title={t('backgroundPicker.emptyTitle')} description={t('backgroundPicker.emptyDescription')} />
        ) : (
          // 2-up on phones (a 3-up grid gave 98px thumbs — you can't judge a full-bleed
          // background at that size). Desktop keeps its original 4-up grid.
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
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
    </>
  )

  if (isMobile) {
    return (
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent side="bottom" className="flex flex-col gap-0 p-5 pb-[calc(env(safe-area-inset-bottom)+1.25rem)]">
          <div className="shrink-0 pb-3">
            <SheetTitle>{t('carousel.pickFromCreative')}</SheetTitle>
            <SheetDescription>{t('backgroundPicker.description')}</SheetDescription>
          </div>
          {body}
        </SheetContent>
      </Sheet>
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>{t('carousel.pickFromCreative')}</DialogTitle>
          <DialogDescription>{t('backgroundPicker.description')}</DialogDescription>
        </DialogHeader>
        {body}
      </DialogContent>
    </Dialog>
  )
}
