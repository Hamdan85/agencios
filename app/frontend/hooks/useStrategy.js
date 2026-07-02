import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { strategyApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { useStrategyChannel } from './useRealtime'

// The current (resumable) planning session for a project, or null when none.
export function useStrategySession(projectId, { enabled = true } = {}) {
  return useQuery({
    queryKey: keys.strategy(projectId),
    queryFn: () => strategyApi.show(projectId),
    enabled: !!projectId && enabled,
    select: (d) => d.strategy_session || null,
  })
}

// Start (or resume) a session — used when the user opens the planner.
export function useStartStrategy(projectId) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => strategyApi.start(projectId),
    onSuccess: (d) => qc.setQueryData(keys.strategy(projectId), d),
    onError: (err) => toast.error(err?.error || 'Erro ao iniciar o planejamento.'),
  })
}

// Approve the proposed plan → create the scheduled tickets + subtasks.
export function useApplyStrategy(projectId) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (sessionId) => strategyApi.apply(sessionId),
    onSuccess: (d) => {
      qc.setQueryData(keys.strategy(projectId), { strategy_session: d.strategy_session })
      qc.invalidateQueries({ queryKey: ['board'] })
      qc.invalidateQueries({ queryKey: keys.project(projectId) })
      qc.invalidateQueries({ queryKey: ['projects'] })
      toast.success(`${d.count} ticket(s) criado(s) a partir da estratégia ✨`)
    },
    onError: (err) => toast.error(err?.error || 'Erro ao aplicar o plano.'),
  })
}

// Discard a proposed plan (mark the session discarded) so it stops surfacing.
export function useDiscardStrategy(projectId) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (sessionId) => strategyApi.discard(sessionId),
    onSuccess: () => {
      qc.setQueryData(keys.strategy(projectId), { strategy_session: null })
      qc.invalidateQueries({ queryKey: keys.strategy(projectId) })
      toast.success('Plano descartado.')
    },
    onError: (err) => toast.error(err?.error || 'Erro ao descartar o plano.'),
  })
}

// The live proposed plan, owned by the PAGE (the table is the canvas). Seeds from
// the persisted `proposed_plan` and is patched by the Action Cable events as the
// plan builds/revises off the request — card by card, so the table fills in live.
//   cards      — [{ key, title?, creative_type?, channels?, scheduled_at, state }]
//   creating   — ephemeral: the batch started but the skeleton rows haven't landed
//   generating — a batch build OR a single-card revise is in flight
const seedCards = (s) => (
  s?.status === 'proposed' && Array.isArray(s?.proposed_plan?.tickets)
    ? s.proposed_plan.tickets.map((t) => ({ ...t, state: 'ready' }))
    : []
)

export function useStrategyPlan(projectId, session) {
  const qc = useQueryClient()
  const sessionId = session?.id
  const [cards, setCards] = useState(() => seedCards(session))
  const [creating, setCreating] = useState(false)
  const [generating, setGenerating] = useState(false)
  const revisingKey = useRef(null)

  // Reseed only when the session identity changes (mount / switch after apply):
  // within a session the live events own the cards, so a reseed can't clobber a
  // build in progress.
  useEffect(() => {
    setCards(seedCards(session))
    setCreating(false)
    setGenerating(false)
    revisingKey.current = null
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionId])

  const handlers = useMemo(() => ({
    onStarted: () => { setCards([]); setCreating(true); setGenerating(true) },
    onOutline: (tickets) => {
      setCreating(false)
      setCards(tickets.map((t) => ({ ...t, state: 'drafting' })))
    },
    onDrafted: (key, card) => {
      setCards((cs) => {
        const next = { ...card, key, state: 'ready' }
        return cs.some((c) => c.key === key) ? cs.map((c) => (c.key === key ? next : c)) : [...cs, next]
      })
      // A revise ends on its card's draft (no plan_ready follows) — release the UI.
      if (revisingKey.current === key) { revisingKey.current = null; setGenerating(false) }
    },
    onRevising: (key) => {
      revisingKey.current = key
      setGenerating(true)
      setCards((cs) => cs.map((c) => (c.key === key ? { ...c, state: 'revising' } : c)))
    },
    onReady: () => {
      setGenerating(false)
      // The persisted plan + the closed-drawer banner catch up from the query.
      qc.invalidateQueries({ queryKey: keys.strategy(projectId) })
    },
    onFailed: () => {
      setCreating(false)
      setGenerating(false)
      revisingKey.current = null
      toast.error('Não consegui montar o plano agora. Tente pedir novamente.')
    },
  }), [qc, projectId])
  useStrategyChannel(sessionId, handlers)

  return { cards, creating, generating }
}

// Drives the CHAT only: local transcript + streaming send. The plan/proposal is
// owned by useStrategyPlan (the table), fed by the same channel.
export function useStrategyChat(projectId, session) {
  const qc = useQueryClient()
  const [messages, setMessages] = useState(() => session?.messages || [])
  const [streaming, setStreaming] = useState(false)
  const [pending, setPending] = useState('') // the in-progress assistant bubble
  const abortRef = useRef(null)

  // Reset the transcript when switching to a different session (e.g. after apply).
  const reset = useCallback((s) => {
    setMessages(s?.messages || [])
    setPending('')
    setStreaming(false)
  }, [])

  const send = useCallback(async (content, sessionId) => {
    const text = content.trim()
    if (!text || streaming || !sessionId) return

    setMessages((m) => [...m, { role: 'user', content: text }])
    setStreaming(true)
    setPending('')
    let acc = ''
    const controller = new AbortController()
    abortRef.current = controller

    try {
      // Only the conversational reply streams here; the plan (and the "building…"
      // signal) arrive over Action Cable, handled by useStrategyPlan.
      await strategyApi.streamMessage(sessionId, text, {
        signal: controller.signal,
        onDelta: (chunk) => {
          acc += chunk
          setPending(acc)
        },
      })
      setMessages((m) => [...m, { role: 'assistant', content: acc || 'Certo! Deixa eu montar isso e já te trago a proposta.' }])
    } catch (err) {
      if (err?.name !== 'AbortError') {
        toast.error(err?.message || 'Erro no chat de estratégia.')
        setMessages((m) => [...m, { role: 'assistant', content: '⚠️ Ocorreu um erro. Tente novamente.' }])
      }
    } finally {
      setPending('')
      setStreaming(false)
      abortRef.current = null
      // The turn may have updated the project itself (update_project tool) — refresh
      // the project so its header/dates reflect immediately.
      qc.invalidateQueries({ queryKey: keys.project(projectId) })
    }
  }, [streaming, qc, projectId])

  return { messages, streaming, pending, send, reset }
}
