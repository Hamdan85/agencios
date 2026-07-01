import { useCallback, useMemo, useRef, useState } from 'react'
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

// Drives the chat: local transcript + streaming send. Seeds from the persisted
// session and appends each turn as it streams in.
// A stored plan is "pending approval" only while the session is `proposed` — an
// `applied` session keeps its `proposed_plan` on record, but it must NOT reopen
// the approval flow (that would let it be applied twice → duplicate tickets).
const pendingProposal = (s) =>
  (s?.status === 'proposed' && s?.proposed_plan?.tickets?.length ? s.proposed_plan : null)

export function useStrategyChat(projectId, session) {
  const qc = useQueryClient()
  const [messages, setMessages] = useState(() => session?.messages || [])
  const [proposal, setProposal] = useState(() => pendingProposal(session))
  const [streaming, setStreaming] = useState(false)
  const [generating, setGenerating] = useState(false) // agent is building the plan
  const [pending, setPending] = useState('') // the in-progress assistant bubble
  const abortRef = useRef(null)

  // The plan is built off the request and pushed over Action Cable — a turn only
  // streams the conversational reply, then the proposal arrives here when ready.
  // This keeps working even with the drawer closed (the hook stays mounted), and
  // refreshing the strategy query surfaces the "plan pending" banner on the page.
  const channelHandlers = useMemo(() => ({
    onGenerating: () => { setProposal(null); setGenerating(true) },
    onProposal: (plan) => {
      if (plan?.tickets?.length) setProposal(plan)
      setGenerating(false)
      qc.invalidateQueries({ queryKey: keys.strategy(projectId) })
    },
    onFailed: () => {
      setGenerating(false)
      toast.error('Não consegui montar o plano agora. Tente pedir novamente.')
    },
  }), [qc, projectId])
  useStrategyChannel(session?.id, channelHandlers)

  // Reset local state when switching to a different session (e.g. after apply).
  const reset = useCallback((s) => {
    setMessages(s?.messages || [])
    setProposal(pendingProposal(s))
    setPending('')
    setStreaming(false)
    setGenerating(false)
  }, [])

  const send = useCallback(async (content, sessionId) => {
    const text = content.trim()
    if (!text || streaming || generating || !sessionId) return

    setMessages((m) => [...m, { role: 'user', content: text }])
    setStreaming(true)
    setGenerating(false)
    setPending('')
    let acc = ''
    const controller = new AbortController()
    abortRef.current = controller

    try {
      // Only the conversational reply streams here; the proposal (and the
      // "building…" signal) arrive over Action Cable via channelHandlers above.
      await strategyApi.streamMessage(sessionId, text, {
        signal: controller.signal,
        onDelta: (chunk) => {
          acc += chunk
          setPending(acc)
        },
      })
      // Commit the finished assistant bubble into the transcript.
      setMessages((m) => [...m, { role: 'assistant', content: acc || 'Certo! Deixa eu montar isso e já te trago a proposta.' }])
    } catch (err) {
      if (err?.name !== 'AbortError') {
        toast.error(err?.message || 'Erro no chat de estratégia.')
        setMessages((m) => [...m, { role: 'assistant', content: '⚠️ Ocorreu um erro. Tente novamente.' }])
      }
    } finally {
      setPending('')
      setStreaming(false)
      setGenerating(false)
      abortRef.current = null
      // The turn may have updated the project itself (update_project tool) —
      // refresh the project so its header/dates reflect immediately. Also refresh
      // the session: a turn can flip its status (applied → proposed after an
      // edit), which the approval gate reads on the next open.
      qc.invalidateQueries({ queryKey: keys.project(projectId) })
      qc.invalidateQueries({ queryKey: keys.strategy(projectId) })
    }
  }, [streaming, generating, qc, projectId])

  return { messages, proposal, streaming, generating, pending, send, reset, setProposal }
}
