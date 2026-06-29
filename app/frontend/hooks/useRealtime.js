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
          onEvent?.(data)
        },
      },
    )
    return () => sub.unsubscribe()
  }, [workspaceId, qc, onEvent])
}
