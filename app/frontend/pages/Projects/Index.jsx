import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  FolderKanban, Plus, ListChecks, Wallet, CalendarRange, Check, Sparkles,
} from 'lucide-react'
import { useProjects, useProjectMutations } from '@/hooks/useData'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { ClientSelect } from '@/components/ui/entity-select'
import { SearchInput } from '@/components/ui/search-input'
import { FilterSheet, FilterField } from '@/components/ui/filter-sheet'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'
import { DatePicker } from '@/components/ui/date-picker'
import { Page } from '@/components/ui/page'
import { brl, date, maskCurrency, centsFromMasked } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const PALETTE = ['#7C3AED', '#EC4899', '#0EA5E9', '#10B981', '#F59E0B', '#6366F1', '#F43F5E', '#14B8A6']

const STATUS_OPTIONS = [
  { value: 'draft', label: 'Rascunho', variant: 'muted' },
  { value: 'active', label: 'Ativa', variant: 'success' },
  { value: 'paused', label: 'Pausada', variant: 'warning' },
  { value: 'archived', label: 'Arquivada', variant: 'muted' },
  { value: 'completed', label: 'Finalizada', variant: 'soft' },
]
const statusMeta = (s) => STATUS_OPTIONS.find((o) => o.value === s) || STATUS_OPTIONS[1]

const EMPTY_FORM = {
  client_id: '', name: '', description: '', color: PALETTE[0],
  status: 'draft', starts_on: '', ends_on: '', budget: '',
}

function ProjectFormDialog({ open, onOpenChange, mutation, onCreated }) {
  const [form, setForm] = useState(EMPTY_FORM)
  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }))

  const submit = (e) => {
    e.preventDefault()
    if (!form.name.trim() || !form.client_id) return
    const payload = {
      client_id: form.client_id,
      name: form.name.trim(),
      description: form.description,
      color: form.color,
      status: form.status,
      starts_on: form.starts_on || null,
      ends_on: form.ends_on || null,
      budget_cents: form.budget ? centsFromMasked(form.budget) : null,
    }
    mutation.mutate(payload, {
      onSuccess: (d) => { setForm(EMPTY_FORM); onOpenChange(false); onCreated?.(d?.project) },
    })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) setForm(EMPTY_FORM) }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: '#10B98116', color: '#10B981' }}>
            <Sparkles size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>Nova campanha</DialogTitle>
          <DialogDescription>Agrupe tickets sob uma campanha de um cliente.</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3.5">
          <div className="space-y-1.5">
            <Label>Cliente</Label>
            <ClientSelect
              variant="field"
              value={form.client_id}
              onChange={(v) => set('client_id')(v || '')}
              placeholder="Selecione o cliente"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pj-name">Nome</Label>
            <Input id="pj-name" required value={form.name} onChange={(e) => set('name')(e.target.value)} placeholder="Ex: Campanha de verão" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pj-desc">Descrição</Label>
            <Textarea id="pj-desc" value={form.description} onChange={(e) => set('description')(e.target.value)} placeholder="Objetivo e escopo da campanha…" />
          </div>
          <div className="space-y-2">
            <Label>Cor</Label>
            <div className="flex flex-wrap gap-2">
              {PALETTE.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => set('color')(c)}
                  className={cn(
                    'flex size-9 items-center justify-center rounded-xl transition-transform hover:scale-110',
                    form.color === c && 'ring-2 ring-offset-2 ring-offset-surface',
                  )}
                  style={{ background: c, '--tw-ring-color': c }}
                  aria-label={`Cor ${c}`}
                >
                  {form.color === c && <Check size={16} className="text-white" strokeWidth={3} />}
                </button>
              ))}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Status</Label>
              <Select value={form.status} onValueChange={set('status')}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {STATUS_OPTIONS.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pj-budget">Orçamento (R$)</Label>
              <Input id="pj-budget" inputMode="decimal" value={form.budget} onChange={(e) => set('budget')(maskCurrency(e.target.value))} placeholder="0,00" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="pj-start">Início</Label>
              <DatePicker id="pj-start" value={form.starts_on} onChange={set('starts_on')} placeholder="Data de início" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pj-end">Fim</Label>
              <DatePicker id="pj-end" value={form.ends_on} onChange={set('ends_on')} placeholder="Data de fim" />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">Cancelar</Button></DialogClose>
            <Button type="submit" disabled={mutation.isPending || !form.client_id}>
              {mutation.isPending ? 'Salvando…' : 'Criar campanha'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function ProjectCard({ project }) {
  const navigate = useNavigate()
  const color = project.color || '#7C3AED'
  const st = statusMeta(project.status)
  const hasRange = project.starts_on || project.ends_on

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => navigate(`/campanhas/${project.id}`)}
      onKeyDown={(e) => { if (e.key === 'Enter') navigate(`/campanhas/${project.id}`) }}
      className="group flex cursor-pointer flex-col overflow-hidden rounded-2xl border border-border bg-surface lift animate-rise"
    >
      <div className="h-2 w-full" style={{ background: color }} />
      <div className="flex flex-1 flex-col p-5">
        <div className="flex items-start justify-between gap-2">
          <h3 className="font-display text-base font-bold text-ink">{project.name}</h3>
          <Badge variant={st.variant}>{st.label}</Badge>
        </div>
        {project.client_name && (
          <p className="mt-0.5 text-sm font-medium text-ink-muted">{project.client_name}</p>
        )}
        {project.description && (
          <p className="mt-2 line-clamp-2 text-sm text-ink-secondary">{project.description}</p>
        )}

        <div className="mt-4 flex flex-wrap items-center gap-2">
          <span className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-bold" style={{ background: `${color}14`, color }}>
            <ListChecks size={13} /> {project.tickets_count ?? 0} tickets
          </span>
          {project.budget_cents != null && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald/12 px-2.5 py-1 text-xs font-bold text-emerald">
              <Wallet size={13} /> {brl(project.budget_cents)}
            </span>
          )}
        </div>

        {hasRange && (
          <p className="mt-3 flex items-center gap-1.5 border-t border-border pt-3 text-xs font-medium text-ink-muted">
            <CalendarRange size={13} />
            {date(project.starts_on)}{project.ends_on ? ` → ${date(project.ends_on)}` : ''}
          </p>
        )}
      </div>
    </div>
  )
}

export default function ProjectsIndex() {
  const navigate = useNavigate()
  const { data: projects, isLoading } = useProjects()
  const { create } = useProjectMutations()
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [clientFilter, setClientFilter] = useState('all')
  const [statusFilter, setStatusFilter] = useState('all')

  const list = projects || []
  const q = search.trim().toLowerCase()

  const filtered = useMemo(() => list.filter((p) => {
    if (clientFilter !== 'all' && String(p.client_id) !== clientFilter) return false
    if (statusFilter !== 'all' && (p.status || 'active') !== statusFilter) return false
    if (q && !`${p.name || ''} ${p.client_name || ''}`.toLowerCase().includes(q)) return false
    return true
  }), [list, clientFilter, statusFilter, q])

  const clientFilterProps = {
    value: clientFilter === 'all' ? undefined : clientFilter,
    onChange: (v) => setClientFilter(v || 'all'),
    placeholder: 'Todos os clientes',
  }
  const statusSelect = (className) => (
    <Select value={statusFilter} onValueChange={setStatusFilter}>
      <SelectTrigger className={className}><SelectValue placeholder="Status" /></SelectTrigger>
      <SelectContent>
        <SelectItem value="all">Todos os status</SelectItem>
        {STATUS_OPTIONS.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
      </SelectContent>
    </Select>
  )
  const filterCount = (clientFilter !== 'all' ? 1 : 0) + (statusFilter !== 'all' ? 1 : 0)
  const clearFilters = () => { setClientFilter('all'); setStatusFilter('all') }

  if (isLoading) return <PageLoader />

  return (
    <Page>
      <PageHeader
        eyebrow="Trabalho"
        title="Campanhas"
        icon={FolderKanban}
        color="#10B981"
        description="Cada campanha agrupa os tickets de um cliente."
        actions={<Button onClick={() => setOpen(true)}><Plus size={18} /> Nova campanha</Button>}
      />

      {/* Search + filters — search always visible; filters inline on desktop,
          condensed into a bottom sheet on mobile. */}
      <div className="mb-6 flex items-center gap-2.5 lg:gap-3">
        <SearchInput
          value={search}
          onChange={setSearch}
          placeholder="Buscar campanha…"
          className="min-w-0 flex-1 lg:w-64 lg:flex-none"
        />
        <div className="hidden flex-wrap items-center gap-3 lg:flex">
          <ClientSelect {...clientFilterProps} width="w-52" />
          {statusSelect('w-44')}
        </div>
        <FilterSheet count={filterCount} onClear={clearFilters} className="lg:hidden">
          <FilterField label="Cliente"><ClientSelect {...clientFilterProps} variant="field" /></FilterField>
          <FilterField label="Status">{statusSelect('w-full')}</FilterField>
        </FilterSheet>
      </div>

      {filtered.length === 0 ? (
        <EmptyState
          icon={FolderKanban}
          color="#10B981"
          title={list.length === 0 ? 'Nenhuma campanha ainda' : 'Nada por aqui'}
          description={list.length === 0 ? 'Crie a primeira campanha para organizar o trabalho da agência.' : 'Ajuste os filtros para ver campanhas.'}
          action={list.length === 0 ? <Button onClick={() => setOpen(true)}><Plus size={18} /> Nova campanha</Button> : null}
        />
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((p) => <ProjectCard key={p.id} project={p} />)}
        </div>
      )}

      <ProjectFormDialog
        open={open}
        onOpenChange={setOpen}
        mutation={create}
        onCreated={(project) => { if (project?.id) navigate(`/campanhas/${project.id}?planejar=1`) }}
      />
    </Page>
  )
}
