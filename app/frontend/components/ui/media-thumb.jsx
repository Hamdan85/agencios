import { cn } from '@/lib/utils'
import { isVideoUrl } from '@/lib/media'

// Thumbnail for a creative/post asset URL — a first-frame <video> for video
// files (#t=0.1 + preload="metadata" paints the frame without playing), an
// <img> otherwise. The parent owns the frame (aspect, rounding, background);
// this fills it.
export function MediaThumb({ url, alt = '', className }) {
  if (!url) return null
  return isVideoUrl(url)
    ? <video src={`${url}#t=0.1`} muted playsInline preload="metadata" className={cn('size-full object-cover', className)} />
    : <img src={url} alt={alt} className={cn('size-full object-cover', className)} />
}
