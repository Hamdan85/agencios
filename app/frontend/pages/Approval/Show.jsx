import { useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Loader2, CheckCircle2, PartyPopper } from 'lucide-react'
import { toast } from 'sonner'
import { useQueryClient } from '@tanstack/react-query'
import { usePublicApproval } from '@/hooks/useData'
import { approvalsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { readableOn, tint } from '@/lib/color'
import { burstConfetti } from '@/lib/confetti'
import ApprovalTicketCard from '@/components/approval/ApprovalTicketCard'
import RequestChangesDialog from '@/components/approval/RequestChangesDialog'

// Per-client approval portal. Mobile: a no-scroll deck (one ticket at a time).
// Desktop: a queue index (all pending tickets + scope) beside the focused ticket.
export default function ApprovalShow() {
  const { token } = useParams()
  const { data, isLoading, isError } = usePublicApproval(token)
  const qc = useQueryClient()
  const [busy, setBusy] = useState(false)
  const [changesFor, setChangesFor] = useState(null) // a slot
  const [focusId, setFocusId] = useState(null)
  const decidedRef = useRef(0)
  const totalRef = useRef(null)

  const tickets = data?.tickets || []
  const agency = data?.agency || {}
  const accent = agency.primary_color || '#7C3AED'
  const fg = useMemo(() => readableOn(accent), [accent])
  const current = tickets.find((t) => t.id === focusId) || tickets[0]

  if (totalRef.current === null && data) totalRef.current = tickets.length
  const setQueue = (payload) => qc.setQueryData(keys.publicApproval(token), payload)

  if (isLoading) {
    return <Shell accent={accent} fg={fg} agency={agency}>
      <div className="flex flex-1 items-center justify-center"><Loader2 className="animate-spin" style={{ color: accent }} /></div>
    </Shell>
  }
  if (isError || !data) {
    return <Shell accent={accent} fg={fg} agency={agency}>
      <div className="flex flex-1 items-center justify-center px-6 text-center text-ink-muted">
        Este link não é mais válido. Fale com sua agência para receber um novo.
      </div>
    </Shell>
  }

  // Reconcile after any decision: if the acted-on ticket left the queue it was
  // fully approved → celebrate + offer undo; else a slot was decided in place.
  const reconcile = (res, ticketId, { celebrate } = {}) => {
    const stillPending = (res.tickets || []).some((t) => t.id === ticketId)
    setQueue(res)
    if (!stillPending && celebrate) {
      decidedRef.current += 1
      burstConfetti(accent)
      if (navigator.vibrate) navigator.vibrate(15)
      toast.success('Conteúdo aprovado ✓', {
        action: {
          label: 'Desfazer',
          onClick: async () => {
            try { const undone = await approvalsApi.undo(token, ticketId); decidedRef.current -= 1; setFocusId(ticketId); setQueue(undone) }
            catch (e) { toast.error(e?.error || 'Não foi possível desfazer.') }
          },
        },
      })
    }
  }

  const approveSlot = async ({ creativeType, creativeId }) => {
    if (!current) return
    const ticketId = current.id
    setBusy(true)
    try {
      const res = await approvalsApi.approveSlot(token, ticketId, { creativeType, creativeId })
      reconcile(res, ticketId, { celebrate: true })
    } catch (e) { toast.error(e?.error || 'Erro ao aprovar.') }
    finally { setBusy(false) }
  }

  const submitChanges = async ({ creativeId, feedback }) => {
    const ticketId = current.id
    setBusy(true)
    try {
      const res = await approvalsApi.requestChanges(token, ticketId, { creativeId, feedback })
      setChangesFor(null)
      reconcile(res, ticketId)
      toast.success('Enviamos seu feedback à equipe 👍')
    } catch (e) { toast.error(e?.error || 'Erro ao enviar.') }
    finally { setBusy(false) }
  }

  const position = Math.min(decidedRef.current + 1, totalRef.current || 1)

  const card = current && (
    <ApprovalTicketCard
      key={current.id}
      ticket={current}
      accent={accent}
      fg={fg}
      busy={busy}
      onApproveSlot={approveSlot}
      onRequestChanges={(slot) => setChangesFor(slot)}
    />
  )

  return (
    <Shell accent={accent} fg={fg} agency={agency} progress={current ? { position, total: totalRef.current } : null}>
      {current ? (
        <div className="flex min-h-0 flex-1">
          {/* Desktop: queue index */}
          {tickets.length > 1 && (
            <aside className="hidden w-72 shrink-0 overflow-y-auto border-r border-border/60 p-3 lg:block">
              <p className="mb-2 px-1 text-xs font-bold uppercase tracking-wide text-ink-faint">Fila ({tickets.length})</p>
              <QueueList tickets={tickets} currentId={current.id} accent={accent} onPick={setFocusId} />
            </aside>
          )}
          <div className="flex min-h-0 flex-1 items-stretch justify-center p-3">
            <div className="flex h-full w-full max-w-5xl flex-col">{card}</div>
          </div>
        </div>
      ) : (
        <Terminal done={decidedRef.current > 0} count={decidedRef.current} agency={agency} accent={accent} />
      )}

      <RequestChangesDialog
        open={!!changesFor}
        onOpenChange={(o) => !o && setChangesFor(null)}
        slot={changesFor}
        accent={accent}
        pending={busy}
        onSubmit={submitChanges}
      />
    </Shell>
  )
}

function QueueList({ tickets, currentId, accent, onPick }) {
  return (
    <div className="flex flex-col gap-1.5">
      {tickets.map((t) => {
        const on = t.id === currentId
        const pending = (t.slots || []).filter((s) => s.state === 'pending').length
        return (
          <button key={t.id} onClick={() => onPick(t.id)}
            className={`rounded-xl border p-2.5 text-left transition ${on ? 'bg-surface-muted' : 'border-transparent hover:bg-surface-muted/60'}`}
            style={on ? { borderColor: accent } : undefined}>
            <p className="truncate text-sm font-semibold text-ink">{t.title}</p>
            <p className="truncate text-xs text-ink-muted">{t.campaign} · {(t.slots || []).length} peça(s)</p>
            {pending > 0 && <p className="mt-0.5 text-[11px] font-medium" style={{ color: accent }}>{pending} pendente(s)</p>}
          </button>
        )
      })}
    </div>
  )
}

function Shell({ accent, fg, agency, progress, children }) {
  return (
    <div className="flex h-dvh flex-col overflow-hidden" style={{ background: tint(accent, 6), '--agency': accent }}>
      <header className="shrink-0 px-5 py-3.5" style={{ background: accent, color: fg }}>
        <div className="mx-auto flex max-w-5xl items-center gap-3">
          {agency.logo_url
            ? <img src={agency.logo_url} alt={agency.name} className="size-9 rounded-lg bg-white object-cover" />
            : <div className="flex size-9 items-center justify-center rounded-lg bg-white/20 font-bold">{agency.name?.[0] || 'A'}</div>}
          <span className="font-display text-base font-bold">{agency.name}</span>
          {progress && <span className="ml-auto text-sm font-medium opacity-90">Conteúdo {progress.position} de {progress.total}</span>}
        </div>
        {progress && (
          <div className="mx-auto mt-2.5 h-1 max-w-5xl overflow-hidden rounded-full bg-black/15">
            <div className="h-full rounded-full bg-white/90 transition-all duration-500"
              style={{ width: `${((progress.position - 1) / Math.max(progress.total, 1)) * 100}%` }} />
          </div>
        )}
      </header>

      <main className="flex min-h-0 flex-1 flex-col">{children}</main>

      <footer className="shrink-0 py-2 text-center">
        <a href="https://agencios.app" target="_blank" rel="noreferrer" className="text-[11px] font-medium text-ink-faint hover:text-ink-muted">
          feito com <span style={{ color: '#7C3AED' }}>✳</span> Agencios
        </a>
      </footer>
    </div>
  )
}

function Terminal({ done, count, agency, accent }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-8 text-center">
      <div className="flex size-20 items-center justify-center rounded-full" style={{ background: `${accent}18`, color: accent }}>
        {done ? <PartyPopper size={40} /> : <CheckCircle2 size={40} />}
      </div>
      <h1 className="mt-5 font-display text-2xl font-extrabold text-ink">{done ? 'Tudo aprovado!' : 'Nada pendente por aqui'}</h1>
      <p className="mt-2 max-w-sm text-ink-muted">
        {done
          ? `Você revisou ${count} ${count === 1 ? 'conteúdo' : 'conteúdos'}. A equipe da ${agency.name} já foi avisada. ✨`
          : 'Tudo em dia! Avisaremos assim que houver algo novo para revisar.'}
      </p>
    </div>
  )
}
