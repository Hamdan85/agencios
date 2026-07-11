import { useInfiniteQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { ticketsApi, workspaceApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { useCurrentUser } from '@/hooks/useAuth'
import { onErr, invalidateTicketSurfaces } from './shared'

// Opens a ticket that may live in another team (the cross-team Você views). If the
// ticket belongs to the active workspace, navigates within the SPA; otherwise it
// switches the session into that workspace first, then hard-loads the ticket so it
// resolves under the right tenant.
export function useOpenTicket() {
  const navigate = useNavigate()
  const { data: me } = useCurrentUser()
  return async (ticketId, workspaceId) => {
    if (!ticketId) return
    if (workspaceId && workspaceId !== me?.workspace?.id) {
      try { await workspaceApi.switch(workspaceId) } catch { /* fall through to a fresh load */ }
      window.location.href = `/tickets/${ticketId}`
      return
    }
    navigate(`/tickets/${ticketId}`)
  }
}

// ── Tickets (global list) ──────────────────────────────────────
// Paginated, infinite-scroll list across the whole workspace. `filters` carries
// the board filter set plus `q` (search), `status`, `priority` and `view`
// (active | archived | all).
export const useTicketsList = (filters = {}) =>
  useInfiniteQuery({
    queryKey: keys.ticketsList(filters),
    queryFn: ({ pageParam = 1 }) => ticketsApi.list({ ...filters, page: pageParam, per: 30 }),
    initialPageParam: 1,
    getNextPageParam: (last, pages) => (last?.meta?.has_more ? pages.length + 1 : undefined),
    // Filtering / searching re-keys the query — keep the current rows visible
    // while the filtered page loads instead of clearing to a spinner.
    placeholderData: keepPreviousData,
  })

export function useTicketArchiveMutations() {
  const { t } = useTranslation('tickets')
  const qc = useQueryClient()
  const inv = () => invalidateTicketSurfaces(qc, { ticketsList: true, projects: true })
  return {
    archive: useMutation({ mutationFn: ticketsApi.archive, onSuccess: () => { inv(); toast.success(t('toasts.archived')) }, onError: onErr(t('toasts.archiveError')) }),
    unarchive: useMutation({ mutationFn: ticketsApi.unarchive, onSuccess: () => { inv(); toast.success(t('toasts.restored')) }, onError: onErr(t('toasts.restoreError')) }),
    assign: useMutation({
      mutationFn: ({ id, assigneeId }) => ticketsApi.update(id, { assignee_id: assigneeId }),
      onSuccess: inv,
      onError: onErr(t('toasts.assignError')),
    }),
  }
}

// Permanently delete a set of tickets (hard delete). Refreshes every surface a
// ticket can appear on — the global list, the board, and project detail.
export function useTicketBulkDelete() {
  const { t } = useTranslation('tickets')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (ids) => ticketsApi.bulkDestroy(ids),
    onSuccess: (data) => {
      invalidateTicketSurfaces(qc, { ticketsList: true, projects: true })
      const n = data?.deleted_count ?? 0
      toast.success(t('toasts.deleted', { count: n }))
    },
    onError: onErr(t('toasts.deleteError')),
  })
}
