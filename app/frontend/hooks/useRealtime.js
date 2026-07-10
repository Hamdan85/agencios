import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { consumer } from '@/lib/cable'
import { keys } from '@/api/queryKeys'

export function useBoardChannel(workspaceId) {
  const qc = useQueryClient()
  useEffect(() => {
    if (!workspaceId) return
    const sub = consumer.subscriptions.create(
      { channel: 'BoardChannel', workspace_id: workspaceId },
      {
        received: () => {
          // Board events (card moves, autopilot start/step/done) also affect the
          // project list rows — refresh both so the "working" indicator and card
          // positions stay live on the board AND on a project page.
          qc.invalidateQueries({ queryKey: ['board'] })
          qc.invalidateQueries({ queryKey: ['projects'] })
        },
      },
    )
    return () => sub.unsubscribe()
  }, [workspaceId, qc])
}

// Login-less client central: subscribe to the client's portal stream (by token)
// and refresh the active campaign's metrics in real time on a metric_updated
// push. The channel authorizes purely by token (no session).
export function usePortalChannel(token, projectId, onEvent) {
  const qc = useQueryClient()
  useEffect(() => {
    if (!token) return
    const sub = consumer.subscriptions.create(
      { channel: 'PortalChannel', token },
      {
        received: (data) => {
          if (projectId) qc.invalidateQueries({ queryKey: keys.portalMetrics(token, projectId) })
          onEvent?.(data)
        },
      },
    )
    return () => sub.unsubscribe()
  }, [token, projectId, qc, onEvent])
}

export function useTicketChannel(ticketId, onEvent) {
  const qc = useQueryClient()
  useEffect(() => {
    if (!ticketId) return
    const sub = consumer.subscriptions.create(
      { channel: 'TicketChannel', ticket_id: ticketId },
      {
        received: (data) => {
          qc.invalidateQueries({ queryKey: keys.ticket(ticketId) })
          onEvent?.(data)
        },
      },
    )
    return () => sub.unsubscribe()
  }, [ticketId, qc, onEvent])
}

// Tracks the async "Atualizar campos com IA" rewrite for a ticket. The action is
// fire-and-forget (Tickets::AiFillJob); this subscribes to the ticket channel and
// flips a `filling` flag on the ai_fill_started/done/failed broadcasts, adopting
// the new fields (invalidate) + toasting when the job settles. Returns
// [filling, setFilling] so the initiating click can shimmer optimistically too.
//
// Watchdog: if the job dies without broadcasting (worker down, hard crash), the
// shimmer must not spin forever — after a generous window it clears itself and
// tells the user to retry.
const AI_FILL_TIMEOUT_MS = 150_000

export function useAiFillStatus(id) {
  const qc = useQueryClient()
  const [filling, setFilling] = useState(false)

  useEffect(() => {
    if (!filling) return undefined
    const t = setTimeout(() => {
      setFilling(false)
      toast.error('A IA está demorando mais que o normal. Tente atualizar novamente.')
    }, AI_FILL_TIMEOUT_MS)
    return () => clearTimeout(t)
  }, [filling])

  useEffect(() => {
    if (!id) return undefined
    const sub = consumer.subscriptions.create(
      { channel: 'TicketChannel', ticket_id: id },
      {
        received: (d) => {
          if (d?.event === 'ai_fill_started') setFilling(true)
          else if (d?.event === 'ai_fill_done') {
            setFilling(false)
            qc.invalidateQueries({ queryKey: keys.ticket(id) })
            qc.invalidateQueries({ queryKey: ['board'] })
            toast.success('IA atualizou o ticket ✨')
          } else if (d?.event === 'ai_fill_failed') {
            setFilling(false)
            toast.error('A IA não conseguiu atualizar os campos. Tente novamente.')
          }
        },
      },
    )
    return () => sub.unsubscribe()
  }, [id, qc])
  return [filling, setFilling]
}

// Per-session strategy-planning updates, pushed as the plan is built/revised off
// the request. `handlers` is { onStarted, onOutline(tickets), onDrafted(key, card),
// onRevising(key), onReady, onFailed } — each optional.
//   plan_started  → a batch build began (table loading)
//   plan_outline  → the empty skeleton rows [{ key, scheduled_at }]
//   ticket_drafted→ one card filled/updated { key, card }
//   ticket_revising→ one card is being re-generated { key }
//   plan_ready    → the batch finished
//   plan_failed   → the build produced nothing
//   additions_building → new ghosts are being appended (do NOT reset the table)
//   additions_ready    → the additive batch finished
//   turn_resolving → the off-request router is deciding what to do (keep "typing…")
//   turn_wait      → the turn resolved into nothing — settle the waiting state
//   assistant_note → an off-request assistant message { content } (append to chat)
export function useStrategyChannel(sessionId, handlers) {
  useEffect(() => {
    if (!sessionId) return
    const sub = consumer.subscriptions.create(
      { channel: 'StrategyChannel', session_id: sessionId },
      {
        received: (d) => {
          switch (d?.event) {
            case 'plan_started': return handlers?.onStarted?.()
            case 'plan_outline': return handlers?.onOutline?.(d.tickets || [])
            case 'ticket_drafted': return handlers?.onDrafted?.(d.key, d.card)
            case 'ticket_revising': return handlers?.onRevising?.(d.key)
            case 'plan_ready': return handlers?.onReady?.()
            case 'plan_failed': return handlers?.onFailed?.()
            case 'additions_building': return handlers?.onAdditionsBuilding?.()
            case 'additions_ready': return handlers?.onAdditionsReady?.()
            case 'turn_resolving': return handlers?.onResolving?.()
            case 'turn_wait': return handlers?.onWait?.()
            case 'assistant_note': return handlers?.onNote?.(d.content)
            default: return undefined
          }
        },
      },
    )
    return () => sub.unsubscribe()
  }, [sessionId, handlers])
}

// Live prepaid credit balance. Any wallet movement (debit on a generation,
// refund on a failed render, monthly grant, pack purchase, cost true-up) pushes
// `balance_changed` on the workspace credits stream. The drawer counter reads
// `me.workspace.credits_available`, so invalidate `me` (the badge) alongside the
// `credits` queries (usage/billing views) to keep every credit read fresh.
export function useCreditsChannel(workspaceId, onEvent) {
  const qc = useQueryClient()
  useEffect(() => {
    if (!workspaceId) return
    const sub = consumer.subscriptions.create(
      { channel: 'CreditsChannel', workspace_id: workspaceId },
      {
        received: (data) => {
          qc.invalidateQueries({ queryKey: keys.me() })
          qc.invalidateQueries({ queryKey: ['credits'] })
          qc.invalidateQueries({ queryKey: keys.billing() })
          onEvent?.(data)
        },
      },
    )
    return () => sub.unsubscribe()
  }, [workspaceId, qc, onEvent])
}

export function useGenerationsChannel(workspaceId, onEvent) {
  const qc = useQueryClient()
  useEffect(() => {
    if (!workspaceId) return
    const sub = consumer.subscriptions.create(
      { channel: 'GenerationsChannel', workspace_id: workspaceId },
      {
        received: (data) => {
          qc.invalidateQueries({ queryKey: keys.studio() })
          qc.invalidateQueries({ queryKey: ['generations'] })
          qc.invalidateQueries({ queryKey: ['creatives'] })
          onEvent?.(data)
        },
      },
    )
    return () => sub.unsubscribe()
  }, [workspaceId, qc, onEvent])
}
