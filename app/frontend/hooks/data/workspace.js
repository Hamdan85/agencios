import { useQuery, useInfiniteQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { toast } from 'sonner'
import { dashboardApi, calendarApi, tasksApi, subtasksApi, workspaceApi, connectionsApi, connectorApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'
import { onErr } from './shared'

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
