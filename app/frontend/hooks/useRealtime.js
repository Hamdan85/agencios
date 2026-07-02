import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
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

// Per-session strategy-planning updates, pushed as the plan is built/revised off
// the request. `handlers` is { onStarted, onOutline(tickets), onDrafted(key, card),
// onRevising(key), onReady, onFailed } — each optional.
//   plan_started  → a batch build began (table loading)
//   plan_outline  → the empty skeleton rows [{ key, scheduled_at }]
//   ticket_drafted→ one card filled/updated { key, card }
//   ticket_revising→ one card is being re-generated { key }
//   plan_ready    → the batch finished
//   plan_failed   → the build produced nothing
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
            default: return undefined
          }
        },
      },
    )
    return () => sub.unsubscribe()
  }, [sessionId, handlers])
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
