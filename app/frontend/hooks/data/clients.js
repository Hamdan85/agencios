import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { clientsApi, projectsApi, reportsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'
import { onErr } from './shared'

// ── Clients ────────────────────────────────────────────────────
export const useClients = (filters = {}) =>
  useQuery({ queryKey: keys.clients(filters), queryFn: () => clientsApi.list(filters), select: (d) => d.clients })
// `poll` keeps refetching while set: either an interval (ms) or a predicate over the
// fetched data returning one — used by the edit dialog to pick up the async
// image-palette once its background job lands it.
export const useClient = (id, { poll = false } = {}) =>
  useQuery({
    queryKey: keys.client(id),
    queryFn: () => clientsApi.get(id),
    enabled: !!id,
    refetchInterval: typeof poll === 'function' ? (q) => poll(q.state.data) || false : poll || false,
  })

export function useClientMutations() {
  const { t } = useTranslation('clients')
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['clients'] })
  return {
    create: useMutation({ mutationFn: clientsApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.CLIENT_CREATED); toast.success(t('toasts.create.success')) }, onError: onErr(t('toasts.create.error')) }),
    update: useMutation({ mutationFn: ({ id, data }) => clientsApi.update(id, data), onSuccess: () => { inv(); toast.success(t('toasts.update.success')) }, onError: onErr(t('toasts.update.error')) }),
    archive: useMutation({ mutationFn: clientsApi.archive, onSuccess: () => { inv(); toast.success(t('toasts.archive.success')) }, onError: onErr(t('toasts.genericError')) }),
    unarchive: useMutation({ mutationFn: clientsApi.unarchive, onSuccess: () => { inv(); toast.success(t('toasts.unarchive.success')) }, onError: onErr(t('toasts.unarchive.error')) }),
    rotatePortalLink: useMutation({ mutationFn: clientsApi.rotatePortalLink, onSuccess: () => { inv(); toast.success(t('toasts.rotatePortalLink.success')) }, onError: onErr(t('toasts.rotatePortalLink.error')) }),
    synthesize: useMutation({ mutationFn: clientsApi.synthesizePositioning, onError: onErr(t('toasts.synthesize.error')) }),
    importFromUrl: useMutation({ mutationFn: clientsApi.extractFromUrl, onError: onErr(t('toasts.importFromUrl.error')) }),
    updatePositioning: useMutation({ mutationFn: ({ id, positioning }) => clientsApi.updatePositioning(id, positioning), onSuccess: () => { inv(); toast.success(t('toasts.updatePositioning.success')) }, onError: onErr(t('toasts.updatePositioning.error')) }),
    uploadBrandAssets: useMutation({ mutationFn: ({ id, assets }) => clientsApi.uploadBrandAssets(id, assets), onSuccess: () => inv(), onError: onErr(t('toasts.uploadBrandAssets.error')) }),
    setCarouselBackground: useMutation({ mutationFn: ({ id, creativeId }) => clientsApi.setCarouselBackground(id, creativeId), onSuccess: () => { inv(); toast.success(t('toasts.setCarouselBackground.success')) }, onError: onErr(t('toasts.setCarouselBackground.error')) }),
    reanalyzeCarouselPalette: useMutation({ mutationFn: ({ id }) => clientsApi.reanalyzeCarouselPalette(id), onSuccess: () => { inv(); toast.success(t('toasts.reanalyzePalette.success')) }, onError: onErr(t('toasts.reanalyzePalette.error')) }),
  }
}

// ── Projects ───────────────────────────────────────────────────
export const useProjects = (filters = {}) =>
  useQuery({ queryKey: keys.projects(filters), queryFn: () => projectsApi.list(filters), select: (d) => d.projects })
export const useProject = (id, filters = {}) =>
  useQuery({ queryKey: keys.project(id, filters), queryFn: () => projectsApi.get(id, filters), enabled: !!id })

export function useProjectMutations() {
  const { t } = useTranslation('clients')
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['projects'] })
  return {
    create: useMutation({ mutationFn: projectsApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.PROJECT_CREATED); toast.success(t('toasts.projects.create.success')) }, onError: onErr(t('toasts.projects.create.error')) }),
    update: useMutation({ mutationFn: ({ id, data }) => projectsApi.update(id, data), onSuccess: inv, onError: onErr(t('toasts.genericError')) }),
    start: useMutation({ mutationFn: projectsApi.start, onSuccess: () => { inv(); toast.success(t('toasts.projects.start.success')) }, onError: onErr(t('toasts.projects.start.error')) }),
    finalize: useMutation({ mutationFn: projectsApi.finalize, onSuccess: () => { inv(); toast.success(t('toasts.projects.finalize.success')) }, onError: onErr(t('toasts.projects.finalize.error')) }),
    sendScope: useMutation({ mutationFn: ({ id, recipients }) => projectsApi.sendScope(id, recipients), onSuccess: () => toast.success(t('toasts.projects.sendScope.success')), onError: onErr(t('toasts.projects.sendScope.error')) }),
    destroy: useMutation({ mutationFn: projectsApi.destroy, onSuccess: () => { inv(); toast.success(t('toasts.projects.destroy.success')) }, onError: onErr(t('toasts.projects.destroy.error')) }),
    // Autopilot ("GO mode") over the whole project.
    autopilotEstimate: useMutation({ mutationFn: projectsApi.autopilotEstimate, onError: onErr(t('toasts.projects.autopilotEstimate.error')) }),
    autopilot: useMutation({ mutationFn: ({ id, payload }) => projectsApi.autopilotStart(id, payload), onSuccess: () => { inv(); qc.invalidateQueries({ queryKey: ['board'] }); toast.success(t('toasts.projects.autopilot.success')) }, onError: onErr(t('toasts.projects.autopilot.error')) }),
    updateSettings: useMutation({
      mutationFn: ({ id, settings }) => projectsApi.updateSettings(id, settings),
      onSuccess: () => { inv(); toast.success(t('toasts.projects.updateSettings.success')) },
      onError: onErr(t('toasts.projects.updateSettings.error')),
    }),
  }
}

// ── Project reports (the finalize audit deck) ───────────────────
export const useProjectReports = (projectId) =>
  useQuery({
    queryKey: keys.projectReports(projectId),
    queryFn: () => reportsApi.listByProject(projectId),
    select: (d) => d.reports,
    enabled: !!projectId,
  })

export const useReport = (id) =>
  useQuery({
    queryKey: keys.report(id),
    queryFn: () => reportsApi.get(id),
    select: (d) => d.report,
    enabled: !!id,
    // While the deck is being generated, poll until it's ready/failed.
    refetchInterval: (q) => (q.state.data?.report?.status === 'generating' ? 4000 : false),
  })

// Manually e-mail the finalized report (branded PDF) to the client. The response
// carries the updated report (with `sent_to_client_at`) → seed the cache.
export function useSendReport(id) {
  const { t } = useTranslation('clients')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => reportsApi.sendToClient(id),
    onSuccess: (d) => {
      if (d?.report) qc.setQueryData(keys.report(id), d)
      toast.success(t('toasts.report.sent'))
    },
    onError: onErr(t('toasts.report.error')),
  })
}
