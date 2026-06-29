import { lazy, Suspense, useRef, useState } from 'react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input, Textarea } from '@/components/ui/input'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'
import {
  Paperclip, UploadCloud, Download, MoreVertical, Pencil, Trash2, Play, FileUp,
} from 'lucide-react'
import { attachmentKindMeta } from '@/lib/constants'
import { fileSize } from '@/lib/formatters'
import { cn } from '@/lib/utils'

// Lazy: react-pdf + the lightbox (~half a MB) load only when a file is opened.
const MediaViewer = lazy(() => import('./MediaViewer'))

// One file in the grid: image/video preview when available, otherwise a colored
// icon tile. Clicking the body opens the media viewer; the ⋯ menu manages it.
function FileTile({ att, onOpen, onRename, onRemove }) {
  const meta = attachmentKindMeta(att.kind)
  const Icon = meta.icon
  const rawThumb = att.kind === 'image' ? (att.preview_url || att.url) : (att.kind === 'video' ? att.preview_url : null)
  // Fall back to a clean icon tile when there's no preview OR the image fails to
  // load (missing blob / unsupported type / broken URL).
  const [failed, setFailed] = useState(false)
  const thumb = rawThumb && !failed ? rawThumb : null

  return (
    <div className="group relative overflow-hidden rounded-2xl border border-border bg-surface transition-all lift">
      <button
        type="button"
        onClick={() => onOpen(att)}
        className="block w-full text-left"
        aria-label={`Abrir ${att.display_name}`}
      >
        <div className="relative aspect-[4/3] overflow-hidden" style={{ background: `${meta.color}12` }}>
          {thumb ? (
            <img
              src={thumb}
              alt={att.display_name}
              className="size-full object-cover"
              loading="lazy"
              onError={() => setFailed(true)}
            />
          ) : (
            <div className="flex size-full flex-col items-center justify-center gap-2 px-2 text-center">
              <div className="flex size-12 items-center justify-center rounded-2xl" style={{ background: `${meta.color}1F`, color: meta.color }}>
                <Icon size={24} strokeWidth={2.1} />
              </div>
              <span className="line-clamp-1 text-[11px] font-semibold uppercase tracking-wide" style={{ color: meta.color }}>
                {meta.label}
              </span>
            </div>
          )}
          {att.kind === 'video' && (
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="flex size-11 items-center justify-center rounded-full bg-black/55 text-white backdrop-blur">
                <Play size={20} className="ml-0.5" fill="currentColor" />
              </div>
            </div>
          )}
          <div className="absolute left-2 top-2">
            <Badge variant="muted" className="bg-white/85 text-ink shadow-sm backdrop-blur">{meta.label}</Badge>
          </div>
        </div>
      </button>

      {/* Per-file actions */}
      <div className="absolute right-2 top-2 opacity-0 transition group-hover:opacity-100 focus-within:opacity-100">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              className="flex size-7 items-center justify-center rounded-lg bg-white/90 text-ink-secondary shadow-sm backdrop-blur transition hover:text-ink"
              aria-label="Ações do arquivo"
            >
              <MoreVertical size={15} />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-40">
            <DropdownMenuItem asChild>
              <a href={att.url} download={att.filename} target="_blank" rel="noreferrer">
                <Download size={14} /> Baixar
              </a>
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => onRename(att)}>
              <Pencil size={14} /> Renomear
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={() => onRemove(att)} className="text-danger focus:text-danger">
              <Trash2 size={14} /> Excluir
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <div className="px-3 py-2.5">
        <p className="truncate text-xs font-semibold text-ink" title={att.display_name}>{att.display_name}</p>
        <p className="mt-0.5 text-[11px] text-ink-muted">{fileSize(att.byte_size)}</p>
      </div>
    </div>
  )
}

export default function AttachmentsPanel({
  attachments = [],
  onUpload,
  onRename,
  onRemove,
  uploading = false,
}) {
  const items = attachments || []
  const inputRef = useRef(null)
  const [dragging, setDragging] = useState(false)
  const [viewer, setViewer] = useState({ open: false, index: 0 })
  const [renaming, setRenaming] = useState(null) // attachment being renamed
  const [removing, setRemoving] = useState(null) // attachment pending delete

  const pick = () => inputRef.current?.click()

  const handleFiles = (fileList) => {
    const files = Array.from(fileList || [])
    if (files.length > 0) onUpload?.(files)
  }

  const onInputChange = (e) => {
    handleFiles(e.target.files)
    e.target.value = '' // allow re-selecting the same file
  }

  const onDrop = (e) => {
    e.preventDefault()
    setDragging(false)
    handleFiles(e.dataTransfer?.files)
  }

  const openViewer = (att) => {
    const index = items.findIndex((a) => a.id === att.id)
    setViewer({ open: true, index: Math.max(0, index) })
  }

  const submitRename = (e) => {
    e.preventDefault()
    const form = new FormData(e.currentTarget)
    onRename?.({
      attachmentId: renaming.id,
      data: { title: form.get('title')?.trim() || null, description: form.get('description')?.trim() || null },
    })
    setRenaming(null)
  }

  const confirmRemove = () => {
    onRemove?.(removing.id)
    setRemoving(null)
  }

  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border p-5">
        <div className="flex items-center gap-2.5">
          <div className="flex size-9 items-center justify-center rounded-xl" style={{ background: '#0EA5E918', color: '#0EA5E9' }}>
            <Paperclip size={18} strokeWidth={2.3} />
          </div>
          <div>
            <h3 className="font-display text-base font-bold text-ink">Arquivos</h3>
            <p className="text-xs text-ink-muted">
              {items.length > 0
                ? `${items.length} arquivo${items.length > 1 ? 's' : ''} neste ticket`
                : 'Anexe vídeos, imagens, PDFs e documentos.'}
            </p>
          </div>
        </div>
        <Button size="sm" variant="outline" onClick={pick} disabled={uploading}>
          {uploading ? <Spinner size={14} /> : <UploadCloud size={14} />}
          Enviar arquivo
        </Button>
        <input ref={inputRef} type="file" multiple hidden onChange={onInputChange} />
      </div>

      <div
        className={cn('p-5 transition-colors', dragging && 'bg-brand-soft/40')}
        onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
        onDragLeave={(e) => { e.preventDefault(); setDragging(false) }}
        onDrop={onDrop}
      >
        {items.length === 0 ? (
          <div
            role="button"
            tabIndex={0}
            onClick={pick}
            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick() } }}
            className="block w-full cursor-pointer rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-brand/30"
          >
            <EmptyState
              icon={dragging ? FileUp : Paperclip}
              title={dragging ? 'Solte para enviar' : 'Nenhum arquivo ainda'}
              description="Arraste arquivos para cá ou clique para enviar — vídeos, imagens, PDFs, planilhas e documentos."
              color="#0EA5E9"
            />
          </div>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
              {items.map((att) => (
                <FileTile
                  key={att.id}
                  att={att}
                  onOpen={openViewer}
                  onRename={setRenaming}
                  onRemove={setRemoving}
                />
              ))}
            </div>
            <div
              className={cn(
                'mt-3 flex items-center justify-center gap-2 rounded-2xl border border-dashed border-border py-4 text-xs font-medium text-ink-muted transition-colors',
                dragging && 'border-brand/50 text-brand',
              )}
            >
              <UploadCloud size={15} />
              Arraste mais arquivos para cá ou
              <button type="button" onClick={pick} className="font-semibold text-brand hover:underline">selecione</button>
            </div>
          </>
        )}
      </div>

      {/* Media viewer (lightbox / pdf / players) — loaded on first open */}
      {viewer.open && (
        <Suspense fallback={null}>
          <MediaViewer
            attachments={items}
            index={viewer.index}
            open
            onClose={() => setViewer((v) => ({ ...v, open: false }))}
          />
        </Suspense>
      )}

      {/* Rename / describe */}
      <Dialog open={!!renaming} onOpenChange={(o) => !o && setRenaming(null)}>
        <DialogContent>
          <form onSubmit={submitRename}>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2"><Pencil size={17} /> Renomear arquivo</DialogTitle>
              <DialogDescription>Defina um nome de exibição e uma descrição opcional.</DialogDescription>
            </DialogHeader>
            <div className="grid gap-3 py-3">
              <Input name="title" placeholder="Nome de exibição" defaultValue={renaming?.title || ''} autoFocus />
              <Textarea name="description" placeholder="Descrição (opcional)" defaultValue={renaming?.description || ''} />
            </div>
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="ghost" size="sm">Cancelar</Button>
              </DialogClose>
              <Button type="submit" size="sm">Salvar</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirm */}
      <Dialog open={!!removing} onOpenChange={(o) => !o && setRemoving(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-danger"><Trash2 size={17} /> Excluir arquivo</DialogTitle>
            <DialogDescription>
              Remover <strong className="text-ink">{removing?.display_name}</strong>? Esta ação não pode ser desfeita.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="ghost" size="sm">Cancelar</Button>
            </DialogClose>
            <Button type="button" variant="destructive" size="sm" onClick={confirmRemove}>Excluir</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  )
}
