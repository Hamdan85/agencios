import { useMemo, useState } from 'react'
import {
  Video, Plus, CalendarClock, Users2, ExternalLink, MoreHorizontal,
  Pencil, Trash2, StickyNote, Building2, History, CalendarPlus,
} from 'lucide-react'
import { useMeetings, useMeetingMutations } from '@/hooks/useData'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card } from '@/components/ui/card'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { ClientSelect } from '@/components/ui/entity-select'
import { FilterBar } from '@/components/ui/filter-bar'
import { DateTimePicker } from '@/components/ui/date-picker'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { dt, time } from '@/lib/formatters'

const EMPTY_FORM = { title: '', starts_at: '', ends_at: '', client_id: '', client_name: '', notes: '' }

function attendeeCount(attendees) {
  if (Array.isArray(attendees)) return attendees.length
  if (attendees && typeof attendees === 'object') return Object.keys(attendees).length
  return 0
}

function MeetingFormDialog({ open, onOpenChange, editing, createMutation, updateMutation }) {
  const isEdit = !!editing
  const mutation = isEdit ? updateMutation : createMutation
  const [form, setForm] = useState(EMPTY_FORM)
  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }))

  const key = `${open}:${editing?.id ?? 'new'}`
  const [syncedKey, setSyncedKey] = useState(null)
  if (open && key !== syncedKey) {
    setSyncedKey(key)
    setForm(isEdit
      ? {
          title: editing.title || '',
          starts_at: editing.starts_at ? editing.starts_at.slice(0, 16) : '',
          ends_at: editing.ends_at ? editing.ends_at.slice(0, 16) : '',
          client_id: editing.client_id ? String(editing.client_id) : '',
          client_name: editing.client_name || '',
          notes: editing.notes || '',
        }
      : EMPTY_FORM)
  }

  const submit = (e) => {
    e.preventDefault()
    if (!form.title.trim() || !form.starts_at) return
    const payload = {
      title: form.title.trim(),
      starts_at: new Date(form.starts_at).toISOString(),
      ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
      client_id: form.client_id || null,
      notes: form.notes,
    }
    const onSuccess = () => { setSyncedKey(null); onOpenChange(false) }
    if (isEdit) mutation.mutate({ id: editing.id, data: payload }, { onSuccess })
    else mutation.mutate(payload, { onSuccess })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: '#14B8A616', color: '#14B8A6' }}>
            <CalendarPlus size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>{isEdit ? 'Editar reunião' : 'Agendar reunião'}</DialogTitle>
          <DialogDescription>Reuniões aparecem no calendário com o link do Meet.</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3.5">
          <div className="space-y-1.5">
            <Label htmlFor="mt-title">Título</Label>
            <Input id="mt-title" autoFocus required value={form.title} onChange={(e) => set('title')(e.target.value)} placeholder="Ex: Alinhamento mensal" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="mt-start">Início</Label>
              <DateTimePicker id="mt-start" value={form.starts_at} onChange={set('starts_at')} placeholder="Início" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="mt-end">Fim</Label>
              <DateTimePicker id="mt-end" value={form.ends_at} onChange={set('ends_at')} placeholder="Fim (opcional)" />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Cliente (opcional)</Label>
            <ClientSelect
              variant="field"
              clearable
              value={form.client_id}
              onChange={(v, opt) => setForm((f) => ({ ...f, client_id: v || '', client_name: opt?.label || '' }))}
              placeholder="Sem cliente"
              initialOption={form.client_id ? { value: form.client_id, label: form.client_name } : null}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mt-notes">Notas</Label>
            <Textarea id="mt-notes" value={form.notes} onChange={(e) => set('notes')(e.target.value)} placeholder="Pauta da reunião…" />
          </div>
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">Cancelar</Button></DialogClose>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending ? 'Salvando…' : isEdit ? 'Salvar' : 'Agendar'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function MeetingCard({ meeting, past, onEdit, onCancel }) {
  const count = attendeeCount(meeting.attendees)
  return (
    <Card className="group flex flex-col overflow-hidden lift animate-rise">
      <div className="h-1.5 w-full" style={{ background: past ? '#94A3B8' : '#14B8A6' }} />
      <div className="flex flex-1 flex-col p-5">
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-start gap-3">
            <div className="flex size-10 shrink-0 items-center justify-center rounded-xl" style={{ background: past ? '#94A3B814' : '#14B8A614', color: past ? '#64748B' : '#14B8A6' }}>
              <Video size={20} strokeWidth={2.2} />
            </div>
            <div>
              <h3 className="font-display text-base font-bold text-ink">{meeting.title}</h3>
              <p className="mt-0.5 flex items-center gap-1.5 text-xs font-medium text-ink-muted">
                <CalendarClock size={13} />
                {dt(meeting.starts_at)}{meeting.ends_at ? ` – ${time(meeting.ends_at)}` : ''}
              </p>
            </div>
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon-sm" className="text-ink-muted opacity-0 transition group-hover:opacity-100">
                <MoreHorizontal size={18} />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => onEdit(meeting)}><Pencil /> Editar</DropdownMenuItem>
              <DropdownMenuItem onSelect={() => onCancel(meeting)} className="text-danger data-[highlighted]:text-danger">
                <Trash2 /> Cancelar
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          {meeting.client_name && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-indigo/12 px-2.5 py-1 text-xs font-bold text-indigo">
              <Building2 size={12} /> {meeting.client_name}
            </span>
          )}
          {meeting.project_name && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-brand-soft px-2.5 py-1 text-xs font-bold text-brand">
              {meeting.project_name}
            </span>
          )}
          {count > 0 && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-muted px-2.5 py-1 text-xs font-bold text-ink-muted">
              <Users2 size={12} /> {count} {count === 1 ? 'participante' : 'participantes'}
            </span>
          )}
        </div>

        {meeting.notes && (
          <p className="mt-3 flex items-start gap-1.5 text-sm text-ink-secondary">
            <StickyNote size={14} className="mt-0.5 shrink-0 text-amber" />
            <span className="line-clamp-2">{meeting.notes}</span>
          </p>
        )}

        {meeting.meet_url && (
          <div className="mt-4">
            {past ? (
              <Button asChild variant="outline" size="sm">
                <a href={meeting.meet_url} target="_blank" rel="noopener noreferrer">
                  <Video size={16} /> Abrir gravação <ExternalLink size={14} />
                </a>
              </Button>
            ) : (
              <Button
                asChild
                size="sm"
                className="text-white shadow-[0_8px_20px_-8px_rgba(20,184,166,0.6)] hover:brightness-105"
                style={{ background: 'linear-gradient(135deg, #14B8A6, #0EA5E9)' }}
              >
                <a href={meeting.meet_url} target="_blank" rel="noopener noreferrer">
                  <Video size={16} /> Entrar no Meet <ExternalLink size={14} />
                </a>
              </Button>
            )}
          </div>
        )}
      </div>
    </Card>
  )
}

export default function MeetingsIndex() {
  const [filters, setFilters] = useState({})
  const { data: meetings, isLoading } = useMeetings(filters)
  const { create, update, destroy } = useMeetingMutations()
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState(null)

  const list = meetings || []
  const hasFilters = !!(filters.q || filters.client_id)

  const { upcoming, past } = useMemo(() => {
    const now = Date.now()
    const sorted = [...list].sort((a, b) => new Date(a.starts_at) - new Date(b.starts_at))
    return {
      upcoming: sorted.filter((m) => new Date(m.starts_at).getTime() >= now),
      past: sorted.filter((m) => new Date(m.starts_at).getTime() < now).reverse(),
    }
  }, [list])

  const openCreate = () => { setEditing(null); setOpen(true) }
  const onEdit = (m) => { setEditing(m); setOpen(true) }
  const onCancel = (m) => { if (window.confirm(`Cancelar "${m.title}"?`)) destroy.mutate(m.id) }

  return (
    <Page>
      <PageHeader
        eyebrow="Agenda"
        title="Reuniões"
        icon={Video}
        color="#14B8A6"
        description="Reuniões com clientes via Google Meet."
        actions={<Button onClick={openCreate}><Plus size={18} /> Agendar reunião</Button>}
      />

      <FilterBar
        search
        searchValue={filters.q || ''}
        onSearch={(v) => setFilters((f) => ({ ...f, q: v }))}
        searchPlaceholder="Buscar reunião…"
        filters={[{ key: 'client_id', type: 'client', label: 'Cliente' }]}
        values={filters}
        onChange={(key, value) => setFilters((f) => ({ ...f, [key]: value }))}
        onClear={() => setFilters((f) => ({ ...f, client_id: undefined }))}
      />

      {isLoading ? (
        <PageLoader />
      ) : list.length === 0 ? (
        <EmptyState
          icon={Video}
          color="#14B8A6"
          title={hasFilters ? 'Nenhuma reunião encontrada' : 'Nenhuma reunião agendada'}
          description={hasFilters
            ? 'Ajuste a busca ou o filtro de cliente.'
            : 'Agende a primeira reunião com um cliente — ela aparecerá aqui e no calendário.'}
          action={hasFilters ? undefined : <Button onClick={openCreate}><Plus size={18} /> Agendar reunião</Button>}
        />
      ) : (
        <div className="space-y-8">
          <section>
            <div className="mb-3 flex items-center gap-2">
              <CalendarClock size={18} className="text-teal" />
              <h2 className="font-display text-lg font-bold text-ink">Próximas</h2>
              <span className="rounded-full bg-teal/12 px-2 py-0.5 text-xs font-bold text-teal">{upcoming.length}</span>
            </div>
            {upcoming.length === 0 ? (
              <p className="rounded-2xl border border-dashed border-border bg-surface/60 px-5 py-8 text-center text-sm text-ink-muted">
                Nenhuma reunião futura.
              </p>
            ) : (
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {upcoming.map((m) => <MeetingCard key={m.id} meeting={m} onEdit={onEdit} onCancel={onCancel} />)}
              </div>
            )}
          </section>

          {past.length > 0 && (
            <section>
              <div className="mb-3 flex items-center gap-2">
                <History size={18} className="text-ink-muted" />
                <h2 className="font-display text-lg font-bold text-ink">Anteriores</h2>
                <span className="rounded-full bg-surface-muted px-2 py-0.5 text-xs font-bold text-ink-muted">{past.length}</span>
              </div>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {past.map((m) => <MeetingCard key={m.id} meeting={m} past onEdit={onEdit} onCancel={onCancel} />)}
              </div>
            </section>
          )}
        </div>
      )}

      <MeetingFormDialog
        open={open}
        onOpenChange={setOpen}
        editing={editing}
        createMutation={create}
        updateMutation={update}
      />
    </Page>
  )
}
