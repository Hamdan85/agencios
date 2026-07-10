import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { clientsApi, projectsApi, reportsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'
import { onErr } from './shared'

// ── Clients ────────────────────────────────────────────────────
export const useClients = (filters = {}) =>
  useQuery({ queryKey: keys.clients(filters), queryFn: () => clientsApi.list(filters), select: (d) => d.clients })
export const useClient = (id) =>
  useQuery({ queryKey: keys.client(id), queryFn: () => clientsApi.get(id), enabled: !!id })

export function useClientMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['clients'] })
  return {
    create: useMutation({ mutationFn: clientsApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.CLIENT_CREATED); toast.success('Cliente criado!') }, onError: onErr('Erro ao criar cliente.') }),
    update: useMutation({ mutationFn: ({ id, data }) => clientsApi.update(id, data), onSuccess: () => { inv(); toast.success('Cliente atualizado!') }, onError: onErr('Erro ao atualizar.') }),
    archive: useMutation({ mutationFn: clientsApi.archive, onSuccess: () => { inv(); toast.success('Cliente arquivado.') }, onError: onErr('Erro.') }),
    unarchive: useMutation({ mutationFn: clientsApi.unarchive, onSuccess: () => { inv(); toast.success('Cliente reativado!') }, onError: onErr('Erro ao reativar.') }),
    rotatePortalLink: useMutation({ mutationFn: clientsApi.rotatePortalLink, onSuccess: () => { inv(); toast.success('Link do portal renovado. O link anterior deixou de funcionar.') }, onError: onErr('Erro ao renovar o link do portal.') }),
    synthesize: useMutation({ mutationFn: clientsApi.synthesizePositioning, onError: onErr('Erro ao gerar posicionamento com IA.') }),
    importFromUrl: useMutation({ mutationFn: clientsApi.extractFromUrl, onError: onErr('Não foi possível ler a landing page.') }),
    updatePositioning: useMutation({ mutationFn: ({ id, positioning }) => clientsApi.updatePositioning(id, positioning), onSuccess: () => { inv(); toast.success('Posicionamento atualizado!') }, onError: onErr('Erro ao salvar posicionamento.') }),
    uploadBrandAssets: useMutation({ mutationFn: ({ id, assets }) => clientsApi.uploadBrandAssets(id, assets), onSuccess: () => inv(), onError: onErr('Erro ao enviar imagens da marca.') }),
    setCarouselBackground: useMutation({ mutationFn: ({ id, creativeId }) => clientsApi.setCarouselBackground(id, creativeId), onSuccess: () => { inv(); toast.success('Fundo do carrossel definido!') }, onError: onErr('Erro ao definir o fundo do carrossel.') }),
  }
}

// ── Projects ───────────────────────────────────────────────────
export const useProjects = (filters = {}) =>
  useQuery({ queryKey: keys.projects(filters), queryFn: () => projectsApi.list(filters), select: (d) => d.projects })
export const useProject = (id, filters = {}) =>
  useQuery({ queryKey: keys.project(id, filters), queryFn: () => projectsApi.get(id, filters), enabled: !!id })

export function useProjectMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['projects'] })
  return {
    create: useMutation({ mutationFn: projectsApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.PROJECT_CREATED); toast.success('Campanha criada!') }, onError: onErr('Erro ao criar campanha.') }),
    update: useMutation({ mutationFn: ({ id, data }) => projectsApi.update(id, data), onSuccess: inv, onError: onErr('Erro.') }),
    start: useMutation({ mutationFn: projectsApi.start, onSuccess: () => { inv(); toast.success('Campanha iniciada!') }, onError: onErr('Erro ao iniciar a campanha.') }),
    finalize: useMutation({ mutationFn: projectsApi.finalize, onSuccess: () => { inv(); toast.success('Campanha finalizada! Gerando o relatório…') }, onError: onErr('Erro ao finalizar a campanha.') }),
    sendScope: useMutation({ mutationFn: ({ id, recipients }) => projectsApi.sendScope(id, recipients), onSuccess: () => toast.success('Escopo enviado ao cliente!'), onError: onErr('Erro ao enviar o escopo.') }),
    destroy: useMutation({ mutationFn: projectsApi.destroy, onSuccess: () => { inv(); toast.success('Campanha excluída.') }, onError: onErr('Erro ao excluir a campanha.') }),
    // Autopilot ("GO mode") over the whole project.
    autopilotEstimate: useMutation({ mutationFn: projectsApi.autopilotEstimate, onError: onErr('Erro ao estimar os créditos.') }),
    autopilot: useMutation({ mutationFn: ({ id, payload }) => projectsApi.autopilotStart(id, payload), onSuccess: () => { inv(); qc.invalidateQueries({ queryKey: ['board'] }); toast.success('Piloto automático iniciado 🚀') }, onError: onErr('Erro ao iniciar o piloto automático.') }),
    updateSettings: useMutation({
      mutationFn: ({ id, settings }) => projectsApi.updateSettings(id, settings),
      onSuccess: () => { inv(); toast.success('Configurações da campanha salvas!') },
      onError: onErr('Erro ao salvar as configurações.'),
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
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => reportsApi.sendToClient(id),
    onSuccess: (d) => {
      if (d?.report) qc.setQueryData(keys.report(id), d)
      toast.success('Relatório enviado ao cliente por e-mail 📧')
    },
    onError: onErr('Não foi possível enviar o relatório.'),
  })
}
