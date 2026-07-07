import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { boardApi, ticketsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { toast } from 'sonner'
import analytics, { EVENTS } from '@/lib/analytics'
import { invalidateTicketSurfaces } from './data/shared'

export function useBoard(filters = {}) {
  return useQuery({
    queryKey: keys.board(filters),
    queryFn: () => boardApi.get(filters),
    // Filtering / searching changes the query key. Keep the current board on
    // screen while the filtered result loads instead of dropping to a full-page
    // loader — `isLoading` then only fires on the very first load.
    placeholderData: keepPreviousData,
  })
}

export function useBoardMutations(filters = {}) {
  const qc = useQueryClient()
  const invalidate = () => invalidateTicketSurfaces(qc)

  const advance = useMutation({
    mutationFn: ({ id, toStatus, position }) => ticketsApi.advance(id, toStatus, position),
    onError: (err) => {
      toast.error(err.error || 'Não foi possível mover o ticket.')
      invalidate()
    },
  })

  const reorder = useMutation({
    mutationFn: ({ id, position }) => ticketsApi.reorder(id, position),
    onError: () => invalidate(),
  })

  const create = useMutation({
    mutationFn: (data) => ticketsApi.create(data),
    onSuccess: () => {
      // The hub's list view reads the global tickets list, not just the board.
      invalidateTicketSurfaces(qc, { ticketsList: true })
      analytics.track(EVENTS.TICKET_CREATED)
      toast.success('Ticket criado!')
    },
    onError: (err) => toast.error(err.error || 'Erro ao criar ticket.'),
  })

  const clearColumn = useMutation({
    mutationFn: (status) => ticketsApi.clearColumn(status),
    onSuccess: (res) => {
      invalidate()
      const n = res?.archived_count ?? 0
      toast.success(n > 0 ? `${n} ticket(s) arquivado(s).` : 'Nada para arquivar.')
    },
    onError: (err) => toast.error(err.error || 'Não foi possível limpar a coluna.'),
  })

  return { advance, reorder, create, clearColumn, invalidate }
}
