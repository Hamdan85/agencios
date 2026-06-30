import { useQuery, useInfiniteQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  dashboardApi, calendarApi, tasksApi, ticketsApi, clientsApi, projectsApi, studioApi,
  generationsApi, socialApi, meetingsApi, invoicesApi, settingsApi, billingApi,
  workspaceApi, subtasksApi, connectionsApi, connectorApi,
} from '@/api'
import { keys } from '@/api/queryKeys'
import { useCurrentUser } from '@/hooks/useAuth'
import analytics, { EVENTS } from '@/lib/analytics'

const onErr = (msg) => (err) => toast.error(err?.error || msg)

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

// ── Dashboard ──────────────────────────────────────────────────
export const useDashboard = () =>
  useQuery({ queryKey: keys.dashboard(), queryFn: dashboardApi.get })

// ── Calendar ───────────────────────────────────────────────────
// keepPreviousData: navigating months / toggling scope re-keys the query, but
// we keep the current grid on screen while refetching instead of flashing a
// full-page loader.
export const useCalendar = (filters = {}) =>
  useQuery({ queryKey: keys.calendar(filters), queryFn: () => calendarApi.get(filters), placeholderData: keepPreviousData })

// ── My Tasks (paginated, infinite scroll) ──────────────────────
// `filters` carries scope / tab / q. Each page returns { tasks, counts, meta };
// counts come from the first page (they reflect the active search).
export const useTasks = (filters = {}) =>
  useInfiniteQuery({
    queryKey: keys.tasks(filters),
    queryFn: ({ pageParam = 1 }) => tasksApi.list({ ...filters, page: pageParam }),
    initialPageParam: 1,
    getNextPageParam: (lastPage, pages) => (lastPage?.meta?.has_more ? pages.length + 1 : undefined),
    placeholderData: keepPreviousData,
  })

export function useTaskMutations() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }) => subtasksApi.update(id, data),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks'] }),
    onError: onErr('Erro ao atualizar tarefa.'),
  })
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
  const qc = useQueryClient()
  const inv = () => {
    qc.invalidateQueries({ queryKey: ['tickets'] })
    qc.invalidateQueries({ queryKey: ['board'] })
  }
  return {
    archive: useMutation({ mutationFn: ticketsApi.archive, onSuccess: () => { inv(); toast.success('Ticket arquivado.') }, onError: onErr('Erro ao arquivar.') }),
    unarchive: useMutation({ mutationFn: ticketsApi.unarchive, onSuccess: () => { inv(); toast.success('Ticket restaurado.') }, onError: onErr('Erro ao restaurar.') }),
  }
}

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
    synthesize: useMutation({ mutationFn: clientsApi.synthesizePositioning, onError: onErr('Erro ao gerar posicionamento com IA.') }),
    updatePositioning: useMutation({ mutationFn: ({ id, positioning }) => clientsApi.updatePositioning(id, positioning), onSuccess: () => { inv(); toast.success('Posicionamento atualizado!') }, onError: onErr('Erro ao salvar posicionamento.') }),
    uploadBrandAssets: useMutation({ mutationFn: ({ id, assets }) => clientsApi.uploadBrandAssets(id, assets), onSuccess: () => inv(), onError: onErr('Erro ao enviar imagens da marca.') }),
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
    create: useMutation({ mutationFn: projectsApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.PROJECT_CREATED); toast.success('Projeto criado!') }, onError: onErr('Erro ao criar projeto.') }),
    update: useMutation({ mutationFn: ({ id, data }) => projectsApi.update(id, data), onSuccess: inv, onError: onErr('Erro.') }),
  }
}

// ── Studio / generations ───────────────────────────────────────
export const useStudio = () => useQuery({ queryKey: keys.studio(), queryFn: studioApi.get })
export const useGenerations = (filters = {}) =>
  useQuery({ queryKey: keys.generations(filters), queryFn: () => generationsApi.list(filters), select: (d) => d.generations })

export function useGenerate() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ kind, params }) => studioApi.generate(kind, params),
    onSuccess: (_data, variables) => {
      qc.invalidateQueries({ queryKey: keys.studio() })
      qc.invalidateQueries({ queryKey: ['generations'] })
      // Activation + the usage-billing meter (carousel/video are metered).
      analytics.track(EVENTS.CREATIVE_GENERATED, { kind: variables?.kind, source: 'studio' })
      toast.success('Geração concluída ✨')
    },
    onError: onErr('Erro ao gerar criativo.'),
  })
}

// ── Social accounts (connected per client) ─────────────────────
export const useSocialAccounts = (clientId) =>
  useQuery({
    queryKey: keys.socialAccounts(clientId),
    queryFn: () => socialApi.list(clientId),
    select: (d) => d.social_accounts,
    enabled: !!clientId,
  })

// Connect opens the network's OAuth flow in a popup. When the popup callback
// posts an 'oauth_connected' message, we close the popup and refresh the client.
export function useSocialAccountMutations(clientId) {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: keys.client(clientId) })

  function openOAuthPopup(url) {
    const w = 600
    const h = 700
    const left = Math.round(window.screenX + (window.outerWidth - w) / 2)
    const top = Math.round(window.screenY + (window.outerHeight - h) / 2)
    const popup = window.open(url, 'oauth_popup', `width=${w},height=${h},left=${left},top=${top},toolbar=no,menubar=no`)

    const onMessage = (e) => {
      if (e.origin !== window.location.origin) return
      if (e.data?.type !== 'oauth_connected') return
      window.removeEventListener('message', onMessage)
      if (popup && !popup.closed) popup.close()
      if (e.data.error) {
        toast.error('Erro ao conectar. Tente novamente.')
      } else {
        inv()
        toast.success('Conta conectada com sucesso!')
      }
    }
    window.addEventListener('message', onMessage)
  }

  return {
    connect: useMutation({
      mutationFn: (network) => socialApi.authorizeUrl(clientId, network),
      onSuccess: (d) => { if (d?.url) openOAuthPopup(d.url) },
      onError: onErr('Não foi possível iniciar a conexão.'),
    }),
    disconnect: useMutation({
      mutationFn: (id) => socialApi.destroy(clientId, id),
      onSuccess: () => { inv(); toast.success('Conta desconectada.') },
      onError: onErr('Erro ao desconectar.'),
    }),
    reconnect: useMutation({
      mutationFn: (id) => socialApi.reconnect(clientId, id),
      onSuccess: () => { inv(); toast.success('Conta reconectada.') },
      onError: onErr('Erro ao reconectar.'),
    }),
  }
}

// ── Meetings ───────────────────────────────────────────────────
export const useMeetings = (filters = {}) =>
  useQuery({ queryKey: keys.meetings(filters), queryFn: () => meetingsApi.list(filters), select: (d) => d.meetings })

export function useMeetingMutations() {
  const qc = useQueryClient()
  const inv = () => { qc.invalidateQueries({ queryKey: ['meetings'] }); qc.invalidateQueries({ queryKey: ['calendar'] }) }
  return {
    create: useMutation({ mutationFn: meetingsApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.MEETING_SCHEDULED); toast.success('Reunião agendada!') }, onError: onErr('Erro.') }),
    update: useMutation({ mutationFn: ({ id, data }) => meetingsApi.update(id, data), onSuccess: inv, onError: onErr('Erro.') }),
    destroy: useMutation({ mutationFn: meetingsApi.destroy, onSuccess: inv, onError: onErr('Erro.') }),
  }
}

// ── Invoices ───────────────────────────────────────────────────
export const useInvoices = (filters = {}) =>
  useQuery({ queryKey: keys.invoices(filters), queryFn: () => invoicesApi.list(filters), select: (d) => d.invoices })

export function useInvoiceMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['invoices'] })
  return {
    create: useMutation({ mutationFn: invoicesApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.INVOICE_CREATED); toast.success('Cobrança criada!') }, onError: onErr('Erro.') }),
    cancel: useMutation({ mutationFn: invoicesApi.cancel, onSuccess: inv, onError: onErr('Erro.') }),
    markPaid: useMutation({ mutationFn: invoicesApi.markPaid, onSuccess: () => { inv(); toast.success('Cobrança marcada como paga.') }, onError: onErr('Erro.') }),
    paymentLink: useMutation({ mutationFn: invoicesApi.paymentLink, onSuccess: () => { inv(); toast.success('Link de pagamento gerado!') }, onError: onErr('Erro ao gerar link.') }),
  }
}

// ── Settings ───────────────────────────────────────────────────
export const useSettings = () => useQuery({ queryKey: keys.settings(), queryFn: settingsApi.get })

export function useGoogleCalendarMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: keys.settings() })

  function openCalendarPopup(url) {
    const w = 600, h = 700
    const left = Math.round(window.screenX + (window.outerWidth - w) / 2)
    const top = Math.round(window.screenY + (window.outerHeight - h) / 2)
    const popup = window.open(url, 'calendar_oauth', `width=${w},height=${h},left=${left},top=${top},toolbar=no,menubar=no`)

    const onMessage = (e) => {
      if (e.origin !== window.location.origin) return
      if (e.data?.type !== 'calendar_connected') return
      window.removeEventListener('message', onMessage)
      if (popup && !popup.closed) popup.close()
      if (e.data.error) {
        toast.error('Erro ao conectar o Google Calendar.')
      } else {
        inv()
        toast.success('Google Calendar conectado!')
      }
    }
    window.addEventListener('message', onMessage)
  }

  return {
    connect: useMutation({
      mutationFn: settingsApi.calendarAuthorizeUrl,
      onSuccess: (d) => { if (d?.url) openCalendarPopup(d.url) },
      onError: onErr('Não foi possível iniciar a conexão.'),
    }),
    disconnect: useMutation({
      mutationFn: settingsApi.calendarDisconnect,
      onSuccess: () => { inv(); toast.success('Google Calendar desconectado.') },
      onError: onErr('Erro ao desconectar.'),
    }),
  }
}

export function useSettingsMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: settingsApi.update,
    onSuccess: () => { qc.invalidateQueries({ queryKey: keys.settings() }); qc.invalidateQueries({ queryKey: keys.me() }); toast.success('Configurações salvas!') },
    onError: onErr('Erro ao salvar.'),
  })
}

// ── Billing ────────────────────────────────────────────────────
export const useBilling = () => useQuery({ queryKey: keys.billing(), queryFn: billingApi.get })
export function useBillingMutations() {
  const qc = useQueryClient()
  const inv = () => { qc.invalidateQueries({ queryKey: keys.billing() }); qc.invalidateQueries({ queryKey: keys.me() }) }
  return {
    changePlan: useMutation({ mutationFn: billingApi.changePlan, onSuccess: (_data, plan) => { inv(); analytics.track(EVENTS.SUBSCRIBE, { plan }); toast.success('Plano atualizado!') }, onError: onErr('Erro.') }),
    cancel: useMutation({ mutationFn: billingApi.cancel, onSuccess: inv, onError: onErr('Erro.') }),
    reactivate: useMutation({ mutationFn: billingApi.reactivate, onSuccess: inv, onError: onErr('Erro.') }),
  }
}

// ── Workspace / members ────────────────────────────────────────
export const useWorkspaceMembers = () =>
  useQuery({ queryKey: keys.workspaceMembers(), queryFn: () => workspaceApi.members(), select: (d) => d.memberships })

export function useWorkspaceMutations() {
  const qc = useQueryClient()
  return {
    switch: useMutation({ mutationFn: workspaceApi.switch, onSuccess: () => window.location.reload() }),
    update: useMutation({ mutationFn: workspaceApi.update, onSuccess: () => { qc.invalidateQueries({ queryKey: keys.me() }); toast.success('Workspace atualizado!') }, onError: onErr('Erro.') }),
    invite: useMutation({ mutationFn: ({ email, role }) => workspaceApi.invite(email, role), onSuccess: (_data, { role }) => { analytics.track(EVENTS.MEMBER_INVITED, { role }); toast.success('Convite gerado!') }, onError: onErr('Erro ao convidar.') }),
  }
}

// ── Connections (authorized external apps / MCP connectors) ────
export const useConnections = () =>
  useQuery({ queryKey: keys.connections(), queryFn: connectionsApi.list, select: (d) => d.connections })

export function useRevokeConnection() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id) => connectionsApi.revoke(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: keys.connections() }); toast.success('Acesso revogado.') },
    onError: onErr('Erro ao revogar acesso.'),
  })
}

// ── Claude connector (tokenized MCP URL) ───────────────────────
export const useMcpConnector = () =>
  useQuery({ queryKey: keys.mcpConnector(), queryFn: connectorApi.get, staleTime: Infinity })

export function useRotateMcpConnector() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: connectorApi.rotate,
    onSuccess: (data) => { qc.setQueryData(keys.mcpConnector(), data); toast.success('Nova URL gerada. A anterior foi invalidada.') },
    onError: onErr('Erro ao gerar nova URL.'),
  })
}
