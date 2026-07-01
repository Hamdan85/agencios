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
      { received: () => qc.invalidateQueries({ queryKey: ['board'] }) },
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

// Per-session strategy-planning updates. The plan is built off the request and
// pushed here: `plan_generating` (a plan is being built → show skeletons),
// `proposal_ready` (the finished plan), `plan_failed` (readiness said yes but the
// build produced nothing). `handlers` is an object of { onGenerating, onProposal,
// onFailed } callbacks.
export function useStrategyChannel(sessionId, handlers) {
  useEffect(() => {
    if (!sessionId) return
    const sub = consumer.subscriptions.create(
      { channel: 'StrategyChannel', session_id: sessionId },
      {
        received: (data) => {
          if (data?.event === 'plan_generating') handlers?.onGenerating?.()
          else if (data?.event === 'proposal_ready') handlers?.onProposal?.(data.plan)
          else if (data?.event === 'plan_failed') handlers?.onFailed?.()
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
