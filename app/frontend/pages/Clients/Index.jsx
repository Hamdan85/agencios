import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Users, Plus, Mail, Phone, FileText, MoreHorizontal,
  Pencil, Archive, FolderKanban, Building2, Sparkles,
} from 'lucide-react'
import { useClients, useClientMutations } from '@/hooks/useData'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { FilterBar } from '@/components/ui/filter-bar'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { Page } from '@/components/ui/page'
import { cn } from '@/lib/utils'
import ClientWizard from '@/components/client/ClientWizard'

function ClientCard({ client, onEdit, onArchive }) {
  const navigate = useNavigate()
  const archived = client.status === 'archived'

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => navigate(`/clientes/${client.id}`)}
      onKeyDown={(e) => { if (e.key === 'Enter') navigate(`/clientes/${client.id}`) }}
      className={cn(
        'group relative flex cursor-pointer flex-col rounded-2xl border border-border bg-surface p-5 lift animate-rise',
        archived && 'opacity-75',
      )}
    >
      <div className="flex items-start gap-3.5">
        <Avatar name={client.name} src={client.logo_url} size={48} />
        <div className="min-w-0 flex-1">
          <h3 className="truncate font-display text-base font-bold text-ink">{client.name}</h3>
          {client.company && (
            <p className="mt-0.5 flex items-center gap-1 truncate text-xs font-medium text-ink-muted">
              <Building2 size={12} /> {client.company}
            </p>
          )}
        </div>
        <div onClick={(e) => e.stopPropagation()}>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon-sm" className="text-ink-muted opacity-0 transition group-hover:opacity-100">
                <MoreHorizontal size={18} />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => onEdit(client)}>
                <Pencil /> Editar
              </DropdownMenuItem>
              {!archived && (
                <DropdownMenuItem onSelect={() => onArchive(client)} className="text-danger data-[highlighted]:text-danger">
                  <Archive /> Arquivar
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      <div className="mt-4 space-y-1.5">
        {client.email && (
          <p className="flex items-center gap-2 truncate text-sm text-ink-secondary">
            <Mail size={14} className="shrink-0 text-indigo" /> <span className="truncate">{client.email}</span>
          </p>
        )}
        {client.phone && (
          <p className="flex items-center gap-2 truncate text-sm text-ink-secondary">
            <Phone size={14} className="shrink-0 text-emerald" /> {client.phone}
          </p>
        )}
        {client.document && (
          <p className="flex items-center gap-2 truncate text-sm text-ink-secondary">
            <FileText size={14} className="shrink-0 text-sky" /> <span className="font-mono text-xs">{client.document}</span>
          </p>
        )}
      </div>

      <div className="mt-4 flex items-center justify-between border-t border-border pt-3.5">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-brand-soft px-2.5 py-1 text-xs font-bold text-brand">
          <FolderKanban size={13} /> {client.projects_count ?? 0} {(client.projects_count ?? 0) === 1 ? 'campanha' : 'campanhas'}
        </span>
        <div className="flex items-center gap-2">
          {client.has_positioning && (
            <span className="inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs font-bold" style={{ background: '#6366F116', color: '#6366F1' }} title="Posicionamento definido">
              <Sparkles size={12} /> Posicionado
            </span>
          )}
          <Badge variant={archived ? 'muted' : 'success'}>{archived ? 'Arquivado' : 'Ativo'}</Badge>
        </div>
      </div>
    </div>
  )
}

export default function ClientsIndex() {
  const { data: clients, isLoading } = useClients()
  const { create, update, archive, synthesize, importFromUrl, uploadBrandAssets } = useClientMutations()
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('active')

  const list = clients || []

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return list.filter((c) => {
      const matchesStatus = statusFilter === 'all' || (c.status || 'active') === statusFilter
      if (!matchesStatus) return false
      if (!q) return true
      return [c.name, c.company, c.email].filter(Boolean).some((v) => v.toLowerCase().includes(q))
    })
  }, [list, search, statusFilter])

  const confirm = useConfirm()
  const openCreate = () => { setEditing(null); setDialogOpen(true) }
  const onEdit = (client) => { setEditing(client); setDialogOpen(true) }
  const onArchive = async (client) => {
    const ok = await confirm({
      title: `Arquivar ${client.name}?`,
      description: 'O cliente sai da lista ativa. Você pode reativá-lo depois pelo filtro de arquivados.',
      confirmLabel: 'Arquivar',
      icon: Archive,
      tone: '#F59E0B',
    })
    if (ok) archive.mutate(client.id)
  }

  if (isLoading) return <PageLoader />

  return (
    <Page>
      <PageHeader
        eyebrow="Carteira"
        title="Clientes"
        icon={Users}
        color="#6366F1"
        description="A carteira de clientes da sua agência."
        actions={(
          <Button onClick={openCreate}>
            <Plus size={18} /> Novo cliente
          </Button>
        )}
      />

      <FilterBar
        search
        searchValue={search}
        onSearch={(v) => setSearch(v || '')}
        searchPlaceholder="Buscar por nome, empresa ou e-mail…"
        filters={[
          {
            key: 'status',
            type: 'options',
            label: 'Situação',
            placeholder: 'Ativos',
            options: [
              { value: 'archived', label: 'Arquivados' },
              { value: 'all', label: 'Todos' },
            ],
          },
        ]}
        values={{ status: statusFilter === 'active' ? undefined : statusFilter }}
        onChange={(_key, value) => setStatusFilter(value || 'active')}
        onClear={() => setStatusFilter('active')}
        className="mb-6"
      />

      {filtered.length === 0 ? (
        <EmptyState
          icon={Users}
          color="#6366F1"
          title={list.length === 0 ? 'Nenhum cliente ainda' : 'Nada por aqui'}
          description={list.length === 0 ? 'Adicione o primeiro cliente à carteira da agência.' : 'Tente ajustar a busca ou o filtro de status.'}
          action={list.length === 0 ? (
            <Button onClick={openCreate}><Plus size={18} /> Novo cliente</Button>
          ) : null}
        />
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((c) => (
            <ClientCard key={c.id} client={c} onEdit={onEdit} onArchive={onArchive} />
          ))}
        </div>
      )}

      <ClientWizard
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        editing={editing}
        mutations={{ create, update, synthesize, importFromUrl, uploadBrandAssets }}
      />
    </Page>
  )
}
