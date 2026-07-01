import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Rocket, Sparkles, Loader2, AlertTriangle, Wallet } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

// Human labels for a run's state (the chip while it walks itself).
const RUN_STATE_LABEL = {
  pending: 'Preparando…',
  scoping: 'Escrevendo o escopo…',
  generating: 'Gerando criativos…',
  awaiting_generation: 'Renderizando vídeo…',
  publishing: 'Agendando posts…',
  running: 'No piloto automático…',
}

const KIND_LABEL = { video: 'Vídeo', image: 'Imagem', carousel: 'Carrossel' }

// The "GO" action — estimates the credit cost, asks the user to confirm (once in
// motion the run generates everything and spends the credits), and on a shortfall
// points them to buy more. Data-source-agnostic: the ticket drawer and the project
// page both drive it via the same props.
//
// Props:
//   run        — { active, state } or null (an in-flight run shows a chip instead)
//   estimating — bool, the estimate request is pending
//   starting   — bool, the start request is pending
//   onEstimate — async () => estimate payload
//   onStart    — () => void (launch the run)
//   label      — button text (default "GO")
export default function AutopilotButton({ run, estimating, starting, onEstimate, onStart, label = 'GO' }) {
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [estimate, setEstimate] = useState(null)

  if (run?.active) {
    return (
      <span className="inline-flex items-center gap-2 rounded-xl border border-brand/30 bg-brand-soft px-3 py-1.5 text-xs font-bold text-brand">
        <Loader2 size={13} className="animate-spin" />
        {RUN_STATE_LABEL[run.state] || 'No piloto automático…'}
      </span>
    )
  }

  const openEstimate = async () => {
    try {
      const est = await onEstimate()
      setEstimate(est || null)
      setOpen(true)
    } catch {
      /* error toast handled by the mutation */
    }
  }

  const confirm = () => {
    onStart()
    setOpen(false)
  }

  const shortfall = estimate?.shortfall || 0
  const blocked = estimate && !estimate.eligible
  const breakdown = (estimate?.tickets || []).flatMap((t) => t.breakdown || [])

  return (
    <>
      <Button
        size="sm"
        onClick={openEstimate}
        disabled={estimating}
        className="text-white"
        style={{ background: 'linear-gradient(135deg, #7C3AED, #EC4899)' }}
      >
        {estimating ? <Loader2 size={14} className="animate-spin" /> : <Rocket size={14} />}
        {label}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <span
              className="mb-1 flex size-11 items-center justify-center rounded-2xl"
              style={{ background: '#7C3AED1A', color: '#7C3AED' }}
            >
              <Rocket size={22} strokeWidth={2.2} />
            </span>
            <DialogTitle>Iniciar no piloto automático?</DialogTitle>
            <DialogDescription>
              O agente vai preencher o briefing, gerar todos os criativos e agendar os posts em
              todas as redes. Uma vez iniciado, os créditos são consumidos mesmo que você ajuste o
              agendamento depois.
            </DialogDescription>
          </DialogHeader>

          {estimate && (
            <div className="space-y-3 text-sm">
              {breakdown.length > 0 && (
                <div className="rounded-2xl border border-border bg-surface-muted/50 p-3">
                  {breakdown.map((b, i) => (
                    <div key={i} className="flex items-center justify-between py-0.5">
                      <span className="text-ink-secondary">{KIND_LABEL[b.kind] || b.type}</span>
                      <span className="font-semibold">{b.credits === 0 ? 'incluso' : `${b.credits} créditos`}</span>
                    </div>
                  ))}
                  <div className="mt-2 flex items-center justify-between border-t border-border pt-2 font-bold">
                    <span>Total</span>
                    <span>{estimate.total_credits} créditos</span>
                  </div>
                </div>
              )}

              <div className="flex items-center justify-between text-xs text-ink-muted">
                <span className="inline-flex items-center gap-1.5"><Wallet size={13} /> Saldo disponível</span>
                <span className="font-semibold">{estimate.available} créditos</span>
              </div>

              {blocked && (
                <div className="flex items-start gap-2 rounded-xl bg-danger/10 p-3 text-xs font-semibold text-danger">
                  <AlertTriangle size={15} className="mt-0.5 shrink-0" />
                  <span>
                    Alguns tickets exigem criativos manuais e não podem rodar no modo GO:{' '}
                    {(estimate.blocking_tickets || []).map((t) => t.title).join(', ')}.
                  </span>
                </div>
              )}

              {!blocked && shortfall > 0 && (
                <div className="flex items-start gap-2 rounded-xl bg-amber-500/10 p-3 text-xs font-semibold text-amber-600">
                  <AlertTriangle size={15} className="mt-0.5 shrink-0" />
                  <span>Faltam {shortfall} créditos para este planejamento. Compre mais para continuar.</span>
                </div>
              )}
            </div>
          )}

          <DialogFooter>
            <Button variant="ghost" onClick={() => setOpen(false)} disabled={starting}>Cancelar</Button>
            {!blocked && shortfall > 0 ? (
              <Button onClick={() => { setOpen(false); navigate('/assinatura') }}>
                <Wallet size={15} /> Comprar créditos
              </Button>
            ) : (
              <Button
                onClick={confirm}
                disabled={blocked || starting}
                className="text-white"
                style={{ background: 'linear-gradient(135deg, #7C3AED, #EC4899)' }}
              >
                {starting ? <Loader2 size={15} className="animate-spin" /> : <Sparkles size={15} />}
                Iniciar agora
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
