import { useEffect, useState } from 'react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

const QUICK_PICKS = ['Trocar as cores', 'Ajustar o texto', 'Mudar a imagem', 'Refazer do zero']

// Branded, in-UI change request (never a native prompt). When a ticket has more
// than one creative, the client points at the piece to redo — only that one is
// regenerated with the feedback.
export default function RequestChangesDialog({ open, onOpenChange, ticket, accent, onSubmit, pending }) {
  const creatives = ticket?.creatives || []
  const [creativeId, setCreativeId] = useState(creatives[0]?.id)
  const [feedback, setFeedback] = useState('')

  useEffect(() => {
    if (open) { setCreativeId(creatives[0]?.id); setFeedback('') }
  }, [open, ticket?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const addPick = (p) => setFeedback((f) => (f ? `${f}\n${p}` : p))
  const submit = () => feedback.trim() && onSubmit({ creativeId, feedback: feedback.trim() })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Pedir ajustes</DialogTitle>
          <p className="text-sm text-ink-muted">{ticket?.title}</p>
        </DialogHeader>

        {creatives.length > 1 && (
          <div>
            <label className="mb-1.5 block text-xs font-semibold text-ink-muted">Sobre qual peça?</label>
            <div className="flex flex-wrap gap-2">
              {creatives.map((c, i) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => setCreativeId(c.id)}
                  className={`rounded-xl border px-3 py-1.5 text-sm font-medium transition ${
                    creativeId === c.id ? 'text-white' : 'border-border text-ink hover:bg-surface-muted'
                  }`}
                  style={creativeId === c.id ? { background: accent, borderColor: accent } : undefined}
                >
                  {c.creative_type || `Peça ${i + 1}`}
                </button>
              ))}
            </div>
          </div>
        )}

        <div>
          <label className="mb-1.5 block text-xs font-semibold text-ink-muted">
            O que você gostaria de ajustar?
          </label>
          <textarea
            autoFocus
            rows={4}
            value={feedback}
            onChange={(e) => setFeedback(e.target.value)}
            placeholder="Descreva os ajustes que a equipe deve fazer…"
            className="w-full resize-none rounded-xl border border-border bg-surface px-3 py-2 text-sm text-ink outline-none focus:ring-2"
            style={{ '--tw-ring-color': accent }}
          />
          <div className="mt-2 flex flex-wrap gap-1.5">
            {QUICK_PICKS.map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => addPick(p)}
                className="rounded-full border border-border px-2.5 py-1 text-xs text-ink-muted transition hover:bg-surface-muted"
              >
                {p}
              </button>
            ))}
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>Cancelar</Button>
          <Button onClick={submit} disabled={pending || !feedback.trim()} style={{ background: accent }}>
            {pending ? 'Enviando…' : 'Enviar ajuste'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
