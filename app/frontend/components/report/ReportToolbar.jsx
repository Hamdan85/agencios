import { useState } from 'react'
import { Printer, Download } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { InlineSpinner } from '@/components/ui/feedback'

// Export/print actions for a report deck. Both stream the branded, chrome-free
// server-rendered PDF (an anchor / hidden iframe — same-origin, so the session
// cookie or portal token carries auth), so the printed & downloaded artifacts
// are identical and correctly paginated (A4) — far cleaner than printing the
// SPA. "Baixar PDF" downloads the file; "Imprimir" loads it into a hidden
// iframe and opens the browser print dialog on it. `accent` themes the primary
// action to match the agency color on the client portal.
export default function ReportToolbar({ pdfUrl, filename, accent }) {
  const [printing, setPrinting] = useState(false)
  if (!pdfUrl) return null

  const print = () => {
    setPrinting(true)
    const frame = document.createElement('iframe')
    frame.style.position = 'fixed'
    frame.style.right = '0'
    frame.style.bottom = '0'
    frame.style.width = '0'
    frame.style.height = '0'
    frame.style.border = '0'
    frame.src = pdfUrl
    let done = false
    const cleanup = () => { if (!done) { done = true; setPrinting(false); setTimeout(() => frame.remove(), 1000) } }
    frame.onload = () => {
      try {
        frame.contentWindow.focus()
        frame.contentWindow.print()
      } catch {
        toast.error('Não foi possível abrir a impressão. Baixe o PDF e imprima por lá.')
      } finally {
        cleanup()
      }
    }
    frame.onerror = () => { toast.error('Não foi possível gerar o PDF.'); cleanup() }
    document.body.appendChild(frame)
  }

  return (
    <div className="no-print flex items-center gap-2">
      <Button variant="outline" size="sm" onClick={print} disabled={printing}>
        {printing ? <InlineSpinner size={15} /> : <Printer size={15} />} Imprimir
      </Button>
      <Button asChild size="sm" style={accent ? { background: accent } : undefined}>
        <a href={pdfUrl} download={filename} target="_blank" rel="noreferrer">
          <Download size={15} /> Baixar PDF
        </a>
      </Button>
    </div>
  )
}
