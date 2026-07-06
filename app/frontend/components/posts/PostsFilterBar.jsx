import { useClients, useProjects } from '@/hooks/useData'

const PROVIDERS = ['instagram', 'facebook', 'tiktok', 'youtube', 'linkedin', 'x', 'threads']
const STATUSES = [['scheduled', 'Agendado'], ['published', 'Publicado'], ['failed', 'Falhou']]
const SELECT = 'rounded-xl border border-border bg-surface px-3 py-2 text-sm text-ink'

// The filter row above the post list. Each control patches the shared `filters`
// object; the page's hooks refetch on change. Single-select for now (the API
// takes arrays, so we wrap the chosen value).
export default function PostsFilterBar({ filters, setFilters }) {
  const { data: clients } = useClients()
  const { data: projects } = useProjects()
  const set = (patch) => setFilters((f) => ({ ...f, ...patch }))

  return (
    <div className="mb-4 flex flex-wrap gap-2">
      <select value={filters.client_id || ''} onChange={(e) => set({ client_id: e.target.value || undefined })} className={SELECT}>
        <option value="">Todos os clientes</option>
        {(clients || []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
      </select>
      <select value={filters.project_id || ''} onChange={(e) => set({ project_id: e.target.value || undefined })} className={SELECT}>
        <option value="">Todas as campanhas</option>
        {(projects || []).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
      </select>
      <select value={filters.providers?.[0] || ''} onChange={(e) => set({ providers: e.target.value ? [e.target.value] : undefined })} className={SELECT}>
        <option value="">Todas as redes</option>
        {PROVIDERS.map((p) => <option key={p} value={p}>{p}</option>)}
      </select>
      <select value={filters.status?.[0] || ''} onChange={(e) => set({ status: e.target.value ? [e.target.value] : undefined })} className={SELECT}>
        <option value="">Todos os status</option>
        {STATUSES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
      <input type="date" value={filters.from || ''} onChange={(e) => set({ from: e.target.value || undefined })} className={SELECT} />
      <input type="date" value={filters.to || ''} onChange={(e) => set({ to: e.target.value || undefined })} className={SELECT} />
    </div>
  )
}
