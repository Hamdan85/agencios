import { useEffect, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Document, Page, pdfjs } from 'react-pdf'
import 'react-pdf/dist/Page/AnnotationLayer.css'
import 'react-pdf/dist/Page/TextLayer.css'

// react-pdf + pdfjs is ~half a megabyte. It lives in its own chunk so it only
// downloads when someone actually opens a PDF in the lightbox.

// Resolve the pdf.js worker through Vite (matches the bundled pdfjs-dist).
pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  'pdfjs-dist/build/pdf.worker.min.mjs',
  import.meta.url,
).toString()

// Measure the scroller so pages render crisp at their real display width.
function useElementWidth() {
  const ref = useRef(null)
  const [width, setWidth] = useState(0)
  useEffect(() => {
    const el = ref.current
    if (!el) return undefined
    setWidth(el.clientWidth)
    const ro = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  return [ref, width]
}

// A scrollable multi-page PDF reader. data-lb-nodrag: the scroll gesture is the
// document's, not the lightbox's — a swipe here pages the PDF, not the deck.
export default function PdfSlide({ item, fallback = null }) {
  const { t } = useTranslation('media')
  const [ref, width] = useElementWidth()
  const [pages, setPages] = useState(0)
  const [failed, setFailed] = useState(false)

  if (failed) return fallback

  return (
    <div data-lb-media data-lb-nodrag className="scrollbar-subtle h-full w-full overflow-y-auto overscroll-contain">
      <div ref={ref} className="mx-auto w-full max-w-3xl">
        <Document
          file={item.url}
          onLoadSuccess={({ numPages }) => setPages(numPages)}
          onLoadError={() => setFailed(true)}
          loading={(
            <div className="flex flex-col items-center gap-3 py-16 text-white/70">
              <span className="size-8 animate-spin rounded-full border-2 border-white/20 border-t-white/80" />
              <span className="text-sm">{t('loadingPdf')}</span>
            </div>
          )}
          className="flex flex-col items-center gap-4"
        >
          {Array.from({ length: pages }, (_, i) => (
            <Page
              key={i}
              pageNumber={i + 1}
              width={width ? Math.min(width, 900) : undefined}
              className="overflow-hidden rounded-lg shadow-2xl"
              renderTextLayer
              renderAnnotationLayer
            />
          ))}
        </Document>
      </div>
    </div>
  )
}
