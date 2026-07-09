import { useQuery, keepPreviousData } from '@tanstack/react-query'
import { portalApi } from '@/api'
import { keys } from '@/api/queryKeys'

// The login-less client central. The path token is the credential.
export const usePortal = (token) =>
  useQuery({ queryKey: keys.portal(token), queryFn: () => portalApi.get(token), enabled: !!token })

export const usePortalBoard = (token, projectId) =>
  useQuery({
    queryKey: keys.portalBoard(token, projectId),
    queryFn: () => portalApi.board(token, projectId),
    enabled: !!token && !!projectId,
  })

// Metrics keep a modest refetch interval as a safety net; the PortalChannel push
// (usePortalChannel) invalidates this key for true real-time updates.
export const usePortalMetrics = (token, projectId) =>
  useQuery({
    queryKey: keys.portalMetrics(token, projectId),
    queryFn: () => portalApi.metrics(token, projectId),
    enabled: !!token && !!projectId,
    placeholderData: keepPreviousData,
    refetchInterval: 60_000,
  })

export const usePortalReport = (token, projectId) =>
  useQuery({
    queryKey: keys.portalReport(token, projectId),
    queryFn: () => portalApi.report(token, projectId),
    enabled: !!token && !!projectId,
    // While the deck is still generating, poll until it's ready.
    refetchInterval: (q) => (q.state.data?.status === 'generating' ? 4000 : false),
  })
