import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import {
  Users, Plus, Mail, Phone, FileText, MoreHorizontal,
  Pencil, Archive, ArchiveRestore, FolderKanban, Building2, Sparkles,
} from 'lucide-react'
import { useClients, useClientMutations } from '@/hooks/useData'
import { useUrlFilters } from '@/hooks/useUrlState'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Badge, ColorBadge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { FilterBar } from '@/components/ui/filter-bar'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { Page } from '@/components/ui/page'
import { cn } from '@/lib/utils'
import ClientWizard from '@/components/client/ClientWizard'
import ClientEditDialog from '@/components/client/ClientEditDialog'

// Filters live in the URL so a refreshed / shared / Back-navigated URL keeps the
// listing (business requirement). Stable reference — see useUrlFilters.
const FILTER_KEYS = ['q', 'status']

function ClientCard({ client, onEdit, onArchive, onUnarchive }) {
  const { t } = useTranslation('clients')
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
                <Pencil /> {t('actions.edit')}
              </DropdownMenuItem>
              {archived ? (
                <DropdownMenuItem onSelect={() => onUnarchive(client)}>
                  <ArchiveRestore /> {t('actions.unarchive')}
                </DropdownMenuItem>
              ) : (
                <DropdownMenuItem onSelect={() => onArchive(client)} className="text-danger data-[highlighted]:text-danger">
                  <Archive /> {t('actions.archive')}
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
          <FolderKanban size={13} /> {t('card.campaigns', { count: client.projects_count ?? 0 })}
        </span>
        <div className="flex items-center gap-2">
          {client.has_positioning && (
            <ColorBadge color="#6366F1" tint="16" className="gap-1 px-2 py-1" title={t('card.positionedTitle')}>
              <Sparkles size={12} /> {t('card.positioned')}
            </ColorBadge>
          )}
          <Badge variant={archived ? 'muted' : 'success'}>{archived ? t('status.archived') : t('status.active')}</Badge>
        </div>
      </div>
    </div>
  )
}

export default function ClientsIndex() {
  const { t } = useTranslation('clients')
  const { data: clients, isLoading } = useClients()
  const mutations = useClientMutations()
  const { archive, unarchive } = mutations
  const [createOpen, setCreateOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  // Filters live in the URL so refresh/Back/shared links keep the listing
  // (business requirement). Absent status = the 'active' default.
  const [filters, setFilters] = useUrlFilters(FILTER_KEYS)
  const search = filters.q || ''
  const statusFilter = filters.status || 'active'

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
  // Creating a new client uses the guided wizard; editing an existing one uses the
  // tabbed edit dialog (jump straight to the section you want).
  const openCreate = () => setCreateOpen(true)
  const onEdit = (client) => setEditing(client)
  const onArchive = async (client) => {
    const ok = await confirm({
      title: t('archiveConfirm.title', { name: client.name }),
      description: t('archiveConfirm.description'),
      confirmLabel: t('actions.archive'),
      icon: Archive,
      tone: '#F59E0B',
    })
    if (ok) archive.mutate(client.id)
  }
  // Reactivation is reversible — no confirm. The backend re-checks the plan's
  // active-client limit and answers 402 when the workspace is already full.
  const onUnarchive = (client) => unarchive.mutate(client.id)

  if (isLoading) return <PageLoader />

  return (
    <Page>
      <PageHeader
        eyebrow={t('index.eyebrow')}
        title={t('index.title')}
        icon={Users}
        color="#6366F1"
        description={t('index.description')}
        actions={(
          <Button onClick={openCreate}>
            <Plus size={18} /> {t('index.newClient')}
          </Button>
        )}
      />

      <FilterBar
        search
        searchValue={search}
        onSearch={(v) => setFilters((f) => ({ ...f, q: v || undefined }))}
        searchPlaceholder={t('index.searchPlaceholder')}
        filters={[
          {
            key: 'status',
            type: 'options',
            label: t('index.filters.status'),
            placeholder: t('index.filters.active'),
            options: [
              { value: 'archived', label: t('index.filters.archived') },
              { value: 'all', label: t('index.filters.all') },
            ],
          },
        ]}
        values={{ status: statusFilter === 'active' ? undefined : statusFilter }}
        onChange={(_key, value) => setFilters((f) => ({ ...f, status: value || undefined }))}
        onClear={() => setFilters((f) => ({ ...f, status: undefined }))}
        className="mb-6"
      />

      {filtered.length === 0 ? (
        <EmptyState
          icon={Users}
          color="#6366F1"
          title={list.length === 0 ? t('index.empty.noneTitle') : t('index.empty.filteredTitle')}
          description={list.length === 0 ? t('index.empty.noneDescription') : t('index.empty.filteredDescription')}
          action={list.length === 0 ? (
            <Button onClick={openCreate}><Plus size={18} /> {t('index.newClient')}</Button>
          ) : null}
        />
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((c) => (
            <ClientCard key={c.id} client={c} onEdit={onEdit} onArchive={onArchive} onUnarchive={onUnarchive} />
          ))}
        </div>
      )}

      <ClientWizard
        open={createOpen}
        onOpenChange={setCreateOpen}
        editing={null}
        mutations={mutations}
      />
      <ClientEditDialog
        open={!!editing}
        onOpenChange={(v) => { if (!v) setEditing(null) }}
        client={editing}
        mutations={mutations}
      />
    </Page>
  )
}
