import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Video, Plus, CalendarClock, History, Calendar } from 'lucide-react'
import { useMeetings, useMeetingMutations } from '@/hooks/useData'
import { useUrlFilters } from '@/hooks/useUrlState'
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

// Filters live in the URL so a refreshed / shared / Back-navigated URL keeps the
// listing (business requirement). Stable reference — see useUrlFilters.
const FILTER_KEYS = ['q', 'client_id']

export default function MeetingsIndex() {
  const { t } = useTranslation('meetings')
  const [filters, setFilters] = useUrlFilters(FILTER_KEYS)
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
      title: t('cancelConfirm.title', { title: m.title }),
      description: t('cancelConfirm.description'),
      confirmLabel: t('cancelConfirm.confirmLabel'),
      cancelLabel: t('cancelConfirm.cancelLabel'),
      destructive: true,
    })
    if (ok) destroy.mutate(m.id)
  }

  return (
    <Page>
      <PageHeader
        eyebrow={t('header.eyebrow')}
        title={t('header.title')}
        icon={Video}
        color="#14B8A6"
        description={t('header.description')}
        actions={<Button onClick={openCreate}><Plus size={18} /> {t('header.schedule')}</Button>}
      />

      {/* Meetings live on the USER's Google Calendar — nudge until connected. */}
      {me?.user && !calendarConnected && (
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-sky/30 bg-sky/8 px-4 py-3">
          <p className="flex items-center gap-2 text-sm font-medium text-ink-secondary">
            <Calendar size={16} className="shrink-0 text-sky" />
            {t('calendarNudge.message')}
          </p>
          <Button asChild size="sm" variant="outline">
            <Link to="/conta/conexoes">{t('calendarNudge.connect')}</Link>
          </Button>
        </div>
      )}

      <FilterBar
        search
        searchValue={filters.q || ''}
        onSearch={(v) => setFilters((f) => ({ ...f, q: v }))}
        searchPlaceholder={t('filters.searchPlaceholder')}
        filters={[{ key: 'client_id', type: 'client', label: t('filters.client') }]}
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
          title={hasFilters ? t('emptyState.filteredTitle') : t('emptyState.title')}
          description={hasFilters
            ? t('emptyState.filteredDescription')
            : t('emptyState.description')}
          action={hasFilters ? undefined : <Button onClick={openCreate}><Plus size={18} /> {t('header.schedule')}</Button>}
        />
      ) : (
        <div className="space-y-8">
          <section>
            <div className="mb-3 flex items-center gap-2">
              <CalendarClock size={18} className="text-teal" />
              <h2 className="font-display text-lg font-bold text-ink">{t('sections.upcoming')}</h2>
              <Badge variant="muted" className="bg-teal/12 px-2 text-teal tracking-normal">{upcoming.length}</Badge>
            </div>
            {upcoming.length === 0 ? (
              <p className="rounded-2xl border border-dashed border-border bg-surface/60 px-5 py-8 text-center text-sm text-ink-muted">
                {t('sections.noUpcoming')}
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
                <h2 className="font-display text-lg font-bold text-ink">{t('sections.past')}</h2>
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
