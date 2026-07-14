// The media layer: URL kind detection + the one canonical media item shape the
// lightbox speaks. Every surface that shows a creative, an attachment or a bare
// asset URL maps into `MediaItem` here — no local copies of this logic.
//
//   MediaItem = {
//     id, url, kind, name, caption, poster, contentType, downloadName, byteSize
//   }
//   kind = image | video | audio | pdf | <attachment kind> (document, archive, …)
import { creativeMeta } from '@/lib/constants'

// ActiveStorage blob URLs keep the original filename (…/video-80.mp4), so the
// extension is the only signal we have for a creative's assets. The query/hash
// tail is matched so signed URLs and #t=0.1 thumb fragments still resolve.
const VIDEO_RE = /\.(mp4|mov|webm|m4v|avi|mkv|ogv)(\?|#|$)/i
const AUDIO_RE = /\.(mp3|wav|ogg|oga|m4a|aac|flac)(\?|#|$)/i
const PDF_RE = /\.pdf(\?|#|$)/i

export const isVideoUrl = (url) => VIDEO_RE.test(String(url || ''))
export const isAudioUrl = (url) => AUDIO_RE.test(String(url || ''))
export const isPdfUrl = (url) => PDF_RE.test(String(url || ''))

export function mediaKindFromUrl(url) {
  if (isVideoUrl(url)) return 'video'
  if (isAudioUrl(url)) return 'audio'
  if (isPdfUrl(url)) return 'pdf'
  return 'image'
}

// A filesystem-safe stem for the download attribute ("Carrossel de lançamento"
// → "carrossel-de-lancamento"). NFD splits an accented letter into its base +
// a combining mark, and the non-alphanumeric pass then drops the mark — so the
// letter survives instead of the whole word being mangled.
function slug(text) {
  return String(text || 'media')
    .normalize('NFD')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60) || 'media'
}

// A bare URL (a video-scene reference, a chat attachment, a generated frame).
export function urlToMedia(url, { id, name, caption, poster } = {}) {
  return {
    id: id ?? url,
    url,
    kind: mediaKindFromUrl(url),
    name: name || '',
    caption: caption || '',
    poster: poster || null,
    contentType: null,
    downloadName: name ? slug(name) : undefined,
  }
}

// An Attachment record (AttachmentSerializer) — the richest source: the backend
// already derived `kind` from the blob content type and built an image preview.
export function attachmentToMedia(att) {
  return {
    id: att.id,
    url: att.url,
    kind: att.kind || mediaKindFromUrl(att.url),
    name: att.display_name || att.filename,
    caption: att.description || '',
    poster: att.preview_url || null,
    contentType: att.content_type || null,
    downloadName: att.filename,
    byteSize: att.byte_size,
  }
}

// A Creative → its slides. A carousel is ONE creative with several assets, so it
// becomes several media items that share the creative's name and caption — the
// lightbox then reads as a single carousel, not a pile of separate creatives.
// While a video is still generating it has no assets yet; `preview_url` (the
// first rendered scene) stands in so there is always something to open.
export function creativeToMedia(creative) {
  if (!creative) return []
  const meta = creativeMeta(creative.creative_type)
  const urls = creative.asset_urls?.length
    ? creative.asset_urls
    : (creative.preview_url ? [creative.preview_url] : [])
  const name = creative.name || meta.label
  const many = urls.length > 1

  return urls.map((url, i) => {
    const kind = mediaKindFromUrl(url)
    return {
      id: `${creative.id}-${i}`,
      url,
      kind,
      name,
      caption: creative.caption || '',
      poster: null,
      contentType: kind === 'video' ? 'video/mp4' : 'image/jpeg',
      downloadName: many ? `${slug(name)}-${i + 1}` : slug(name),
    }
  })
}
