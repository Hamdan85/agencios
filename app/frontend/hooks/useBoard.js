import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
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
  const { t } = useTranslation('board')
  const qc = useQueryClient()
  const invalidate = () => invalidateTicketSurfaces(qc)

  const advance = useMutation({
    mutationFn: ({ id, toStatus, position }) => ticketsApi.advance(id, toStatus, position),
    onError: (err) => {
      toast.error(err.error || t('toasts.moveError'))
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
      toast.success(t('toasts.createSuccess'))
    },
    onError: (err) => toast.error(err.error || t('toasts.createError')),
  })

  const clearColumn = useMutation({
    mutationFn: (status) => ticketsApi.clearColumn(status),
    onSuccess: (res) => {
      invalidate()
      const n = res?.archived_count ?? 0
      toast.success(n > 0 ? t('toasts.archivedCount', { count: n }) : t('toasts.nothingToArchive'))
    },
    onError: (err) => toast.error(err.error || t('toasts.clearColumnError')),
  })

  return { advance, reorder, create, clearColumn, invalidate }
}
