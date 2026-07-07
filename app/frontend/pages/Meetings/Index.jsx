import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Video, Plus, CalendarClock, History, Calendar } from 'lucide-react'
import { useMeetings, useMeetingMutations } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { PageHeader } from '@/components/ui/page-header'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import { FilterBar } from '@/components/ui/filter-bar'
import { MeetingCard } from '@/components/meeting/MeetingCard'
import { MeetingFormDialog } from '@/components/meeting/MeetingFormDialog'

export default function MeetingsIndex() {
  const [filters, setFilters] = useState({})
  const { data: meetings, isLoading } = useMeetings(filters)
  const { create, update, destroy } = useMeetingMutations()
  const { data: me } = useCurrentUser()
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState(null)

  const list = meetings || []
  const hasFilters = !!(filters.q || filters.client_id)
  const myId = me?.user?.id
  const calendarConnected = !!me?.user?.google_calendar_connected

  const { upcoming, past } = useMemo(() => {
    const now = Date.now()
    const sorted = [...list].sort((a, b) => new Date(a.starts_at) - new Date(b.starts_at))
    return {
      upcoming: sorted.filter((m) => new Date(m.starts_at).getTime() >= now),
      past: sorted.filter((m) => new Date(m.starts_at).getTime() < now).reverse(),
    }
  }, [list])

  const confirm = useConfirm()
  const openCreate = () => { setEditing(null); setOpen(true) }
  const onEdit = (m) => { setEditing(m); setOpen(true) }
  const onCancel = async (m) => {
    const ok = await confirm({
      title: `Cancelar "${m.title}"?`,
      description: 'A reunião será removida da agenda e do Google Calendar.',
      confirmLabel: 'Cancelar reunião',
      cancelLabel: 'Voltar',
      destructive: true,
    })
    if (ok) destroy.mutate(m.id)
  }

  return (
    <Page>
      <PageHeader
        eyebrow="Agenda"
        title="Reuniões"
        icon={Video}
        color="#14B8A6"
        description="Suas reuniões — as que você marcou e as que te incluíram."
        actions={<Button onClick={openCreate}><Plus size={18} /> Agendar reunião</Button>}
      />

      {/* Meetings live on the USER's Google Calendar — nudge until connected. */}
      {me?.user && !calendarConnected && (
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-sky/30 bg-sky/8 px-4 py-3">
          <p className="flex items-center gap-2 text-sm font-medium text-ink-secondary">
            <Calendar size={16} className="shrink-0 text-sky" />
            Conecte seu Google Calendar para criar eventos reais com link do Meet e convites automáticos.
          </p>
          <Button asChild size="sm" variant="outline">
            <Link to="/conta/conexoes">Conectar</Link>
          </Button>
        </div>
      )}

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
              <Badge variant="muted" className="bg-teal/12 px-2 text-teal tracking-normal">{upcoming.length}</Badge>
            </div>
            {upcoming.length === 0 ? (
              <p className="rounded-2xl border border-dashed border-border bg-surface/60 px-5 py-8 text-center text-sm text-ink-muted">
                Nenhuma reunião futura.
              </p>
            ) : (
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {upcoming.map((m) => (
                  <MeetingCard key={m.id} meeting={m} canEdit={m.user_id === myId} showOwner={m.user_id !== myId} onEdit={onEdit} onCancel={onCancel} />
                ))}
              </div>
            )}
          </section>

          {past.length > 0 && (
            <section>
              <div className="mb-3 flex items-center gap-2">
                <History size={18} className="text-ink-muted" />
                <h2 className="font-display text-lg font-bold text-ink">Anteriores</h2>
                <Badge variant="muted" className="px-2 tracking-normal">{past.length}</Badge>
              </div>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                {past.map((m) => (
                  <MeetingCard key={m.id} meeting={m} past canEdit={m.user_id === myId} showOwner={m.user_id !== myId} onEdit={onEdit} onCancel={onCancel} />
                ))}
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
