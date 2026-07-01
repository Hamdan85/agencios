import { useState } from 'react'
import { useQuery, useInfiniteQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  dashboardApi, calendarApi, tasksApi, ticketsApi, clientsApi, projectsApi, reportsApi, studioApi,
  generationsApi, creativesApi, socialApi, meetingsApi, invoicesApi, settingsApi, billingApi,
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
    importFromUrl: useMutation({ mutationFn: clientsApi.extractFromUrl, onError: onErr('Não foi possível ler a landing page.') }),
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
    finalize: useMutation({ mutationFn: projectsApi.finalize, onSuccess: () => { inv(); toast.success('Projeto finalizado! Gerando o relatório…') }, onError: onErr('Erro ao finalizar o projeto.') }),
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
      qc.invalidateQueries({ queryKey: ['creatives'] })
      qc.invalidateQueries({ queryKey: ['tickets'] })
      // Activation + the usage-billing meter (carousel/video are metered).
      analytics.track(EVENTS.CREATIVE_GENERATED, { kind: variables?.kind, source: 'studio' })
      toast.success('Geração concluída ✨')
    },
    onError: onErr('Erro ao gerar criativo.'),
  })
}

// ── Workspace creatives (Studio gallery) ──────────────────────
export const useWorkspaceCreatives = (filters = {}) =>
  useQuery({
    queryKey: keys.creatives(filters),
    queryFn: () => creativesApi.list(filters),
    placeholderData: keepPreviousData,
  })

export function useCreativeMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['creatives'] })
  return {
    update: useMutation({
      mutationFn: ({ id, ...data }) => creativesApi.update(id, data),
      onSuccess: () => { inv(); toast.success('Criativo atualizado.') },
      onError: onErr('Erro ao atualizar criativo.'),
    }),
    destroy: useMutation({
      mutationFn: (id) => creativesApi.destroy(id),
      onSuccess: () => { inv(); toast.success('Criativo removido.') },
      onError: onErr('Erro ao remover criativo.'),
    }),
  }
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
  const [connecting, setConnecting] = useState(false)

  // The popup MUST be opened synchronously inside the click handler — browsers
  // block `window.open()` that isn't tied to a live user gesture, and the
  // authorize_url fetch resolves a tick later, so opening it in the mutation
  // callback was being silently blocked (the "nothing happens" bug). We open a
  // blank popup on click and only point it at the OAuth URL once it arrives.
  function openBlankPopup() {
    const w = 600
    const h = 700
    const left = Math.round(window.screenX + (window.outerWidth - w) / 2)
    const top = Math.round(window.screenY + (window.outerHeight - h) / 2)
    return window.open('about:blank', 'oauth_popup', `width=${w},height=${h},left=${left},top=${top},toolbar=no,menubar=no`)
  }

  // Facebook's OAuth hop can sever the popup's `window.opener` (COOP), so the
  // popup can't reliably postMessage us or close itself. We listen on
  // same-origin side channels that survive that — BroadcastChannel + a
  // localStorage ping — plus the legacy postMessage, and WE close the popup
  // (the opener keeps the reference). A poll on `popup.closed` is the backstop.
  function trackOAuthPopup(popup) {
    let done = false
    const bc = 'BroadcastChannel' in window ? new BroadcastChannel('agencios_oauth') : null

    function cleanup() {
      window.removeEventListener('message', onMessage)
      window.removeEventListener('storage', onStorage)
      if (bc) bc.close()
      if (poll) window.clearInterval(poll)
    }

    function finish(payload) {
      if (done) return
      done = true
      cleanup()
      try { if (popup && !popup.closed) popup.close() } catch { /* cross-origin */ }
      if (payload?.error) {
        toast.error(payload.error === 'no_instagram'
          ? 'Esta Página não tem uma conta Instagram Business vinculada.'
          : 'Erro ao conectar. Tente novamente.')
      } else {
        inv()
        toast.success('Conta conectada com sucesso!')
      }
    }

    const onMessage = (e) => {
      if (e.origin !== window.location.origin) return
      if (e.data?.type === 'oauth_connected') finish(e.data)
    }
    const onStorage = (e) => {
      if (e.key !== 'agencios_oauth' || !e.newValue) return
      try { finish(JSON.parse(e.newValue)) } catch { /* ignore */ }
    }

    window.addEventListener('message', onMessage)
    window.addEventListener('storage', onStorage)
    if (bc) bc.onmessage = (e) => { if (e.data?.type === 'oauth_connected') finish(e.data) }

    // Backstop: if the popup is closed manually (or the channels are blocked),
    // stop listening and refresh so a completed connection still shows up.
    const poll = window.setInterval(() => {
      if (popup && popup.closed) { cleanup(); if (!done) { done = true; inv() } }
    }, 800)
  }

  function connect(network) {
    const popup = openBlankPopup()
    setConnecting(true)
    socialApi.authorizeUrl(clientId, network)
      .then((d) => {
        if (!d?.url) throw new Error('missing authorize url')
        if (popup) { popup.location.href = d.url; trackOAuthPopup(popup) }
        else window.open(d.url, '_blank') // popup blocked: best-effort new tab
      })
      .catch((err) => {
        try { popup?.close() } catch { /* cross-origin */ }
        toast.error(err?.error || 'Não foi possível iniciar a conexão.')
      })
      .finally(() => setConnecting(false))
  }

  return {
    connect,
    connecting,
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

export function useSettingsBrandAssetsMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: settingsApi.uploadBrandAssets,
    onSuccess: () => { qc.invalidateQueries({ queryKey: keys.settings() }); qc.invalidateQueries({ queryKey: keys.me() }) },
    onError: onErr('Erro ao enviar o logo.'),
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
    // The backend already pointed the session at the new workspace; hard-load the
    // dashboard so the whole SPA re-bootstraps inside the fresh tenant.
    create: useMutation({
      mutationFn: workspaceApi.create,
      onSuccess: (data) => {
        analytics.track(EVENTS.WORKSPACE_CREATED, { plan: data?.workspace?.plan })
        toast.success('Workspace criado!')
        window.location.assign('/painel')
      },
      onError: onErr('Erro ao criar workspace.'),
    }),
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
