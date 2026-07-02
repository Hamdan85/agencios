import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Sparkles, Send, CalendarClock, CheckCircle2, Loader2, X } from 'lucide-react'
import { Sheet, SheetContent, SheetTitle, SheetDescription } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/input'
import { Markdown } from '@/components/ui/markdown'
import { useStartStrategy, useApplyStrategy, useStrategyChat } from '@/hooks/useStrategy'

// A senior social-media agent that chats to turn a content cadence into
// scheduled tickets. Docked as a NON-MODAL right drawer so the project's list
// stays visible behind it — the proposed tickets show up there as dimmed
// previews (kept OUT of the chat, which stays purely conversational), and turn
// into real tickets on approval. Fixed height + internal scroll; mobile-first.
// `cards` + `generating` come from the page's useStrategyPlan (the table owns the
// live plan); the drawer is purely the chat + the approve control.
export function StrategyDrawer({ open, onOpenChange, projectId, session, cards = [], generating = false }) {
  const start = useStartStrategy(projectId)
  const apply = useApplyStrategy(projectId)
  const { messages, streaming, pending, send, reset } = useStrategyChat(projectId, session)
  const [input, setInput] = useState('')
  const [sessionId, setSessionId] = useState(session?.id || null)
  const scrollRef = useRef(null)
  const inputRef = useRef(null)

  // The plan awaiting a decision (shown inline + drives the approve button).
  const proposal = cards.length ? { tickets: cards, summary: session?.proposed_plan?.summary } : null

  // Return focus to the composer whenever a turn finishes, so the user can keep
  // typing without reaching for the mouse. (Focus on OPEN is handled by the
  // Sheet's onOpenAutoFocus below, which fires as the drawer mounts.)
  useEffect(() => {
    if (open && !streaming && !generating) inputRef.current?.focus()
  }, [streaming, generating, open])

  // Ensure a session exists whenever the drawer opens.
  useEffect(() => {
    if (!open) return
    if (session?.id) {
      setSessionId(session.id)
      reset(session)
      return
    }
    start.mutate(undefined, { onSuccess: (d) => { setSessionId(d.strategy_session.id); reset(d.strategy_session) } })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  // Always land at the bottom on open, then follow new content. The drawer
  // slides in (~300ms) and the transcript (markdown) reflows after mount, so a
  // single synchronous scroll lands short — snap across a few frames + a timeout.
  const jumpToBottom = (smooth) => {
    const el = scrollRef.current
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: smooth ? 'smooth' : 'auto' })
  }
  useLayoutEffect(() => {
    if (!open) return
    jumpToBottom(false)
    const r1 = requestAnimationFrame(() => {
      jumpToBottom(false)
      requestAnimationFrame(() => jumpToBottom(false))
    })
    const t = setTimeout(() => jumpToBottom(false), 320) // after the slide-in
    return () => { cancelAnimationFrame(r1); clearTimeout(t) }
  }, [open])
  useEffect(() => { if (open) jumpToBottom(true) }, [messages, pending, cards.length, streaming, open])

  // Once applied, the plan is materialized into real tickets — the approval flow
  // closes (a fresh proposal flips the session back to `proposed` and reopens it).
  const applied = session?.status === 'applied'

  // Block sending while a plan is being built off the request too, so a second
  // turn can't kick off a competing plan job on the same session.
  const busy = streaming || generating

  const submit = (e) => {
    e.preventDefault()
    const text = input.trim()
    if (!text || busy || !sessionId) return
    setInput('')
    send(text, sessionId)
  }

  // Enter sends; Shift+Enter inserts a newline.
  const onKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      submit(e)
    }
  }

  return (
    // modal=false → the page behind stays interactive; overlay dropped so the
    // board is visible while planning.
    <Sheet open={open} onOpenChange={onOpenChange} modal={false}>
      <SheetContent
        side="right"
        overlay={false}
        aria-describedby={undefined}
        className="w-full gap-0 p-0 sm:max-w-lg"
        onOpenAutoFocus={(e) => {
          // Focus the composer on open instead of Radix's default (the panel).
          e.preventDefault()
          requestAnimationFrame(() => inputRef.current?.focus())
        }}
      >
        {/* ── Sticky header ── */}
        <div className="flex shrink-0 items-start justify-between gap-3 border-b border-border px-5 py-4">
          <div className="flex items-start gap-3">
            <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-soft text-brand">
              <Sparkles size={18} strokeWidth={2.3} />
            </span>
            <div>
              <SheetTitle className="text-base">Planejar conteúdo com IA</SheetTitle>
              <SheetDescription className="mt-0.5 text-xs">
                Descreva a estratégia de conteúdo. O estrategista monta os tickets já agendados, com tarefas estimadas.
              </SheetDescription>
            </div>
          </div>
          <button
            type="button"
            onClick={() => onOpenChange(false)}
            className="rounded-lg p-1.5 text-ink-muted transition hover:bg-surface-muted hover:text-ink"
            aria-label="Fechar"
          >
            <X size={18} />
          </button>
        </div>

        {/* ── Scrollable conversation ── */}
        <div ref={scrollRef} className="scrollbar-subtle min-h-0 flex-1 space-y-3 overflow-y-auto px-5 py-4">
          {messages.length === 0 && !pending && (
            <p className="rounded-2xl bg-surface-muted/60 p-4 text-sm text-ink-muted">
              Ex.: “1 reel e 2 carrosséis por semana, começando semana que vem.” Diga a cadência e o período
              (um mês, uma campanha, contínuo…) — o resto o estrategista puxa do contexto do cliente.
            </p>
          )}

          {messages.map((m, i) => <Bubble key={i} role={m.role} content={m.content} />)}
          {pending && <Bubble role="assistant" content={pending} />}
          {/* "digitando…" — bounces the whole time the agent is working: while the
              reply streams AND while the plan builds off the request (pushed back
              over Action Cable), which streams no visible text. */}
          {busy && <TypingDots />}

          {proposal && !applied && (
            <div className="rounded-2xl border border-brand/30 bg-brand-soft/40 p-3.5 text-sm">
              <div className="flex items-center gap-2 font-semibold text-brand">
                <CalendarClock size={15} /> Plano pronto · {proposal.tickets.length} tickets
              </div>
              {proposal.summary && <p className="mt-1 text-ink-secondary">{proposal.summary}</p>}
              <p className="mt-1.5 text-xs text-ink-muted">
                Os tickets propostos aparecem na lista do projeto (esmaecidos). Revise e clique em aprovar abaixo.
              </p>
            </div>
          )}
        </div>

        {/* ── Sticky footer: apply + composer ── */}
        <div className="shrink-0 border-t border-border px-5 py-3">
          {proposal && !applied && (
            <Button
              type="button"
              className="mb-3 w-full"
              disabled={apply.isPending}
              onClick={() => apply.mutate(sessionId)}
            >
              {apply.isPending
                ? <><Loader2 size={16} className="mr-2 animate-spin" /> Criando tickets…</>
                : <><CheckCircle2 size={16} className="mr-2" /> Aprovar e criar {proposal.tickets.length} tickets</>}
            </Button>
          )}

          {applied && (
            <p className="mb-3 rounded-xl bg-emerald/12 p-3 text-center text-sm font-medium text-emerald">
              Plano aplicado — veja os tickets aparecendo no projeto.
            </p>
          )}

          <form onSubmit={submit} className="flex items-stretch gap-2">
            <Textarea
              ref={inputRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={onKeyDown}
              rows={2}
              maxRows={2}
              placeholder="Responda ao estrategista…  (Enter envia · Shift+Enter quebra linha)"
              className="h-[52px] flex-1 resize-none"
              disabled={busy}
            />
            <Button
              type="submit"
              className="h-auto w-[52px] shrink-0 self-stretch p-0"
              disabled={busy || !input.trim() || !sessionId}
            >
              {busy ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
            </Button>
          </form>
        </div>
      </SheetContent>
    </Sheet>
  )
}

function Bubble({ role, content, streaming }) {
  const isUser = role === 'user'
  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`max-w-[85%] cursor-text select-text rounded-2xl px-4 py-2.5 text-sm ${
          isUser ? 'whitespace-pre-wrap bg-brand text-white' : 'bg-surface-muted text-ink'
        }`}
      >
        {/* User text is plain; the agent replies in markdown (bold, lists, …). */}
        {isUser
          ? content
          : <Markdown className="prose-p:first:mt-0 prose-p:last:mb-0">{content}</Markdown>}
        {streaming && <span className="ml-0.5 inline-block h-3.5 w-1.5 animate-pulse bg-current align-middle" />}
      </div>
    </div>
  )
}

// Three bouncing dots — the agent is "thinking" (waiting for the first token, or
// building the plan tool-call, which streams no visible text).
function TypingDots() {
  return (
    <div className="flex justify-start">
      <div className="flex items-center gap-1 rounded-2xl bg-surface-muted px-4 py-3">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="size-1.5 animate-bounce rounded-full bg-ink-faint"
            style={{ animationDelay: `${i * 0.16}s` }}
          />
        ))}
      </div>
    </div>
  )
}

export default StrategyDrawer
