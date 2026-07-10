import * as React from 'react'
import { Pencil } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

// Tiptap is heavy — only pull it in when the editor dialog actually opens.
const RichTextEditor = React.lazy(() => import('@/components/ui/rich-text'))

// True when the HTML carries real content (not just empty tags / whitespace).
const hasContent = (html) =>
  !!html && html.replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').trim().length > 0

// A rich-text FIELD: renders the stored HTML as read-only prose and exposes an
// "Editar" action that opens a wide dialog (full-screen on mobile via
// DialogContent) hosting the Tiptap editor. value(HTML) / onChange(HTML) mirrors
// `<Textarea rich />`, but view-first — the formatted content is shown at rest and
// only edited inside the focused modal. Save commits the draft; cancel discards it.
export function RichField({
  value = '', onChange, placeholder, title = 'Editar', disabled = false, readOnly = false,
}) {
  const [open, setOpen] = React.useState(false)
  const [draft, setDraft] = React.useState(value)
  const filled = hasContent(value)

  const openEditor = () => { setDraft(value || ''); setOpen(true) }
  const save = () => { onChange?.(draft); setOpen(false) }

  return (
    <>
      {filled ? (
        <div className="relative rounded-xl border border-border bg-surface-muted/40 px-3.5 py-3">
          <div
            className="prose prose-sm max-w-none text-ink-secondary prose-strong:text-ink prose-headings:text-ink prose-a:text-brand"
            dangerouslySetInnerHTML={{ __html: value }}
          />
          {!readOnly && (
            <button
              type="button"
              onClick={openEditor}
              disabled={disabled}
              className="absolute right-2 top-2 inline-flex items-center gap-1 rounded-lg border border-border bg-surface/90 px-2 py-1 text-xs font-semibold text-ink-muted shadow-sm backdrop-blur-sm transition hover:text-ink disabled:opacity-50"
            >
              <Pencil size={12} /> Editar
            </button>
          )}
        </div>
      ) : (
        <button
          type="button"
          onClick={openEditor}
          disabled={disabled || readOnly}
          className="flex w-full items-center gap-2 rounded-xl border border-dashed border-border bg-surface-muted/40 px-3.5 py-3 text-left text-sm text-ink-faint transition hover:border-brand/40 hover:text-ink-muted disabled:cursor-not-allowed disabled:opacity-60"
        >
          <Pencil size={14} /> {placeholder || 'Escrever…'}
        </button>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className={cn('sm:max-w-3xl sm:max-h-[85vh] sm:grid-rows-[auto_minmax(0,1fr)_auto]')}>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
          </DialogHeader>
          <div className="min-h-0 overflow-y-auto">
            <React.Suspense fallback={<div className="min-h-72 animate-pulse rounded-xl border border-border bg-surface-muted" />}>
              <RichTextEditor
                value={draft}
                onChange={setDraft}
                placeholder={placeholder}
                minHeight="20rem"
                autofocus
              />
            </React.Suspense>
          </div>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancelar</Button>
            <Button onClick={save}>Salvar</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}

export default RichField
