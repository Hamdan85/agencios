import { useEffect, useMemo, useRef, useState } from 'react'
import Lightbox from 'yet-another-react-lightbox'
import Zoom from 'yet-another-react-lightbox/plugins/zoom'
import VideoPlugin from 'yet-another-react-lightbox/plugins/video'
import Thumbnails from 'yet-another-react-lightbox/plugins/thumbnails'
import Counter from 'yet-another-react-lightbox/plugins/counter'
import Fullscreen from 'yet-another-react-lightbox/plugins/fullscreen'
import Captions from 'yet-another-react-lightbox/plugins/captions'
import Download from 'yet-another-react-lightbox/plugins/download'
import 'yet-another-react-lightbox/styles.css'
import 'yet-another-react-lightbox/plugins/thumbnails.css'
import 'yet-another-react-lightbox/plugins/captions.css'
import 'yet-another-react-lightbox/plugins/counter.css'

import { Document, Page, pdfjs } from 'react-pdf'
import 'react-pdf/dist/Page/AnnotationLayer.css'
import 'react-pdf/dist/Page/TextLayer.css'

import { Download as DownloadIcon, Loader2, AlertCircle } from 'lucide-react'
import { attachmentKindMeta } from '@/lib/constants'
import { fileSize } from '@/lib/formatters'

// Resolve the pdf.js worker through Vite (matches the bundled pdfjs-dist).
pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  'pdfjs-dist/build/pdf.worker.min.mjs',
  import.meta.url,
).toString()

// Measure a node's width so PDF pages render crisp at the container size.
function useElementWidth() {
  const ref = useRef(null)
  const [width, setWidth] = useState(0)
  useEffect(() => {
    const el = ref.current
    if (!el || typeof ResizeObserver === 'undefined') return undefined
    const ro = new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect?.width
      if (w) setWidth(w)
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  return [ref, width]
}

// Inline multi-page PDF reader used inside the lightbox.
function PdfView({ url, name }) {
  const [ref, width] = useElementWidth()
  const [pages, setPages] = useState(0)
  const [error, setError] = useState(false)
  const pageWidth = Math.min(width || 720, 900)

  return (
    <div className="flex h-full w-full justify-center overflow-auto py-6" onClick={(e) => e.stopPropagation()}>
      <div ref={ref} className="w-full max-w-3xl px-3">
        {error ? (
          <DownloadFallback url={url} name={name} kind="pdf" message="Não foi possível pré-visualizar este PDF." />
        ) : (
          <Document
            file={url}
            onLoadSuccess={({ numPages }) => setPages(numPages)}
            onLoadError={() => setError(true)}
            loading={<ViewerSpinner label="Carregando PDF…" />}
            className="flex flex-col items-center gap-4"
          >
            {Array.from({ length: pages }, (_, i) => (
              <Page
                key={i}
                pageNumber={i + 1}
                width={pageWidth > 0 ? pageWidth : undefined}
                className="overflow-hidden rounded-lg shadow-2xl"
                renderTextLayer
                renderAnnotationLayer
              />
            ))}
          </Document>
        )}
      </div>
    </div>
  )
}

function AudioView({ url, name }) {
  const meta = attachmentKindMeta('audio')
  const Icon = meta.icon
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-6 p-8" onClick={(e) => e.stopPropagation()}>
      <div className="flex size-24 items-center justify-center rounded-3xl" style={{ background: `${meta.color}22`, color: meta.color }}>
        <Icon size={44} />
      </div>
      <p className="max-w-md truncate text-center text-sm font-semibold text-white">{name}</p>
      {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
      <audio src={url} controls autoPlay className="w-full max-w-md" />
    </div>
  )
}

function ViewerSpinner({ label }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-16 text-white/80">
      <Loader2 className="animate-spin" size={28} />
      <span className="text-sm">{label}</span>
    </div>
  )
}

// Generic card for formats browsers can't preview (docx, xlsx, zip, …).
function DownloadFallback({ url, name, kind, message }) {
  const meta = attachmentKindMeta(kind)
  const Icon = meta.icon
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-5 p-8" onClick={(e) => e.stopPropagation()}>
      <div className="flex size-28 items-center justify-center rounded-3xl" style={{ background: `${meta.color}22`, color: meta.color }}>
        <Icon size={52} />
      </div>
      <div className="text-center">
        <p className="max-w-md truncate text-base font-bold text-white">{name}</p>
        <p className="mt-1 text-sm text-white/60">{message || `${meta.label} — pré-visualização indisponível neste formato.`}</p>
      </div>
      <a
        href={url}
        download={name}
        target="_blank"
        rel="noreferrer"
        className="inline-flex items-center gap-2 rounded-xl bg-white px-4 py-2.5 text-sm font-semibold text-ink shadow-lg transition hover:brightness-95"
      >
        <DownloadIcon size={16} /> Baixar arquivo
      </a>
    </div>
  )
}

// Map an attachment to a YARL slide. Built-in image/video slides are rendered
// by the library; pdf/audio/other are custom slides handled in render.slide.
function toSlide(att) {
  const download = { url: att.url, filename: att.filename }
  const base = { id: att.id, title: att.display_name, description: att.description || undefined, download }
  if (att.kind === 'image') return { ...base, type: 'image', src: att.url, alt: att.display_name }
  if (att.kind === 'video') {
    return {
      ...base,
      type: 'video',
      poster: att.preview_url || undefined,
      sources: [{ src: att.url, type: att.content_type || 'video/mp4' }],
    }
  }
  return { ...base, type: att.kind === 'pdf' ? 'pdf' : att.kind === 'audio' ? 'audio' : 'doc', attachment: att }
}

export default function MediaViewer({ attachments = [], index = 0, open, onClose }) {
  const slides = useMemo(() => attachments.map(toSlide), [attachments])

  if (!open) return null

  return (
    <Lightbox
      open={open}
      close={onClose}
      index={index}
      slides={slides}
      plugins={[Zoom, VideoPlugin, Thumbnails, Counter, Fullscreen, Captions, Download]}
      counter={{ container: { style: { top: 'unset', bottom: 0 } } }}
      thumbnails={{ vignette: false }}
      carousel={{ finite: slides.length <= 1, preload: 1 }}
      zoom={{ maxZoomPixelRatio: 4, scrollToZoom: true }}
      video={{ autoPlay: false, controls: true }}
      controller={{ closeOnBackdropClick: true }}
      styles={{ root: { '--yarl__color_backdrop': 'rgba(10, 8, 20, 0.94)' } }}
      render={{
        slide: ({ slide }) => {
          if (slide.type === 'pdf') return <PdfView url={slide.attachment.url} name={slide.attachment.display_name} />
          if (slide.type === 'audio') return <AudioView url={slide.attachment.url} name={slide.attachment.display_name} />
          if (slide.type === 'doc') {
            return <DownloadFallback url={slide.attachment.url} name={slide.attachment.display_name} kind={slide.attachment.kind} />
          }
          return undefined
        },
        // Custom thumbnails for non-image slides (icon tile instead of a broken img).
        thumbnail: ({ slide }) => {
          if (slide.type === 'image' || slide.type === 'video') return undefined
          const att = slide.attachment
          const meta = attachmentKindMeta(att?.kind)
          const Icon = meta.icon
          return (
            <div className="flex size-full flex-col items-center justify-center gap-1" style={{ background: `${meta.color}1F`, color: meta.color }}>
              <Icon size={22} />
              <span className="px-1 text-[9px] font-semibold uppercase tracking-wide">{meta.label}</span>
            </div>
          )
        },
      }}
      labels={{ Previous: 'Anterior', Next: 'Próximo', Close: 'Fechar', Download: 'Baixar' }}
    />
  )
}
