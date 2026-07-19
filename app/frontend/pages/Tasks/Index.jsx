import { useEffect, useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import {
  ListChecks, ListTodo, Search, CheckCircle2, Circle, AlarmClock, Inbox,
  ArrowUpRight, CalendarClock, PartyPopper, Building2,
} from 'lucide-react'
import { useTasks, useTaskMutations, useOpenTicket } from '@/hooks/useData'
import { useUrlFilters } from '@/hooks/useUrlState'
import { useInfiniteScroll } from '@/hooks/useInfiniteScroll'
import { PageHeader } from '@/components/ui/page-header'
import { Badge, ColorBadge } from '@/components/ui/badge'
import { EmptyState, Spinner } from '@/components/ui/feedback'
import { SearchInput } from '@/components/ui/search-input'
import { Page } from '@/components/ui/page'
import { cn } from '@/lib/utils'
import { relativeDay, shortDt } from '@/lib/formatters'

const HERO = '#F59E0B'

const TABS = [
  { key: 'pending', countKey: 'pending', color: '#0EA5E9' },
  { key: 'overdue', countKey: 'overdue', color: '#F43F5E' },
  { key: 'completed', countKey: 'completed', color: '#10B981' },
]

const EMPTY_ICON = {
  pending: CheckCircle2,
  overdue: PartyPopper,
  completed: Inbox,
}

// Tab + search live in the URL so refresh/Back/shared links keep the listing
// (business requirement). Absent tab = 'pending'. Stable ref — see useUrlFilters.
const FILTER_KEYS = ['tab', 'q']

function isOverdue(task) {
  if (task.done || !task.due_date) return false
  return new Date(task.due_date) < new Date(new Date().setHours(0, 0, 0, 0))
}

// `scope="all_workspaces"` powers the personal "Minhas tarefas" view (/minhas-tarefas),
// aggregating the user's subtasks across every team. Without it, the page is scoped
// to the active workspace (/tarefas).
export default function TasksIndex({ scope } = {}) {
  const { t } = useTranslation('tasks')
  const global = scope === 'all_workspaces'
  const [urlFilters, setUrlFilters] = useUrlFilters(FILTER_KEYS)
  const tab = TABS.some((tabItem) => tabItem.key === urlFilters.tab) ? urlFilters.tab : 'pending'
  const q = urlFilters.q || ''
  const setTab = (v) => setUrlFilters((f) => ({ ...f, tab: v === 'pending' ? undefined : v }))
  const [query, setQuery] = useState(q)
  const mutate = useTaskMutations()
  const openTicket = useOpenTicket()

  // Keep the input in sync when the URL changes from outside (Back button).
  useEffect(() => { setQuery(q) }, [q])
  // Debounce the text search into the URL (which drives the server query key).
  useEffect(() => {
    const id = setTimeout(() => {
      const next = query.trim()
      if (next !== q) setUrlFilters((f) => ({ ...f, q: next || undefined }))
    }, 300)
    return () => clearTimeout(id)
  }, [query, q, setUrlFilters])

  const filters = { tab, ...(q ? { q } : {}), ...(global ? { scope } : {}) }
  const { data, isLoading, hasNextPage, isFetchingNextPage, fetchNextPage } = useTasks(filters)

  const tasks = useMemo(() => (data?.pages || []).flatMap((p) => p.tasks || []), [data])
  const counts = data?.pages?.[0]?.counts || { pending: 0, overdue: 0, completed: 0 }

  const toggle = (task) => mutate.mutate({ id: task.id, data: { done: !task.done } })

  const sentinelRef = useInfiniteScroll({ hasNextPage, isFetchingNextPage, fetchNextPage, deps: [tasks.length] })

  const emptyIcon = EMPTY_ICON[tab]

  return (
    <Page className="animate-rise">
      <PageHeader
        eyebrow={global ? t('header.eyebrowGlobal') : t('header.eyebrowTeam')}
        title={t('header.title')}
        icon={global ? ListTodo : ListChecks}
        color={HERO}
        description={global ? t('header.descriptionGlobal') : t('header.descriptionTeam')}
        actions={
          <span className="inline-flex items-center gap-2 rounded-xl bg-amber/15 px-3.5 py-2 font-display text-sm font-extrabold text-[#B45309]">
            <AlarmClock size={16} strokeWidth={2.4} />
            {t('header.pendingCount', { count: counts.pending })}
          </span>
        }
      />

      {/* Tab pills + search — one row */}
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          {TABS.map((tabItem) => {
            const active = tab === tabItem.key
            const count = counts[tabItem.countKey] ?? 0
            return (
              <button
                key={tabItem.key}
                type="button"
                onClick={() => setTab(tabItem.key)}
                className={cn(
                  'inline-flex items-center gap-2 rounded-full border px-3.5 py-1.5 text-sm font-bold transition-all',
                  active
                    ? 'border-transparent text-white shadow-sm'
                    : 'border-border bg-surface text-ink-secondary hover:border-strong hover:text-ink',
                )}
                style={active ? { background: tabItem.color } : undefined}
              >
                {t(`tabs.${tabItem.key}`)}
                <span
                  className={cn(
                    'grid min-w-5 place-items-center rounded-full px-1 text-[11px] tabular-nums',
                    active ? 'bg-white/25 text-white' : 'bg-surface-muted text-ink-muted',
                  )}
                >
                  {count}
                </span>
              </button>
            )
          })}
        </div>

        <SearchInput value={query} onChange={setQuery} placeholder={t('searchPlaceholder')} className="w-full sm:w-64" />
      </div>

      {/* Task list */}
      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner size={28} /></div>
      ) : tasks.length === 0 ? (
        q ? (
          <EmptyState icon={Search} color={HERO} title={t('noResults.title')} description={t('noResults.description', { query: q })} />
        ) : (
          <EmptyState icon={emptyIcon} color={TABS.find((tabItem) => tabItem.key === tab)?.color} title={t(`empty.${tab}.title`)} description={t(`empty.${tab}.description`)} />
        )
      ) : (
        <>
          <div className="space-y-2.5">
            {tasks.map((task) => (
              <TaskRow key={task.id} task={task} overdue={isOverdue(task)} showWorkspace={global} onOpenTicket={openTicket} onToggle={() => toggle(task)} />
            ))}
          </div>
          <div ref={sentinelRef} aria-hidden className="h-1" />
          {isFetchingNextPage && <div className="flex justify-center py-4"><Spinner size={20} /></div>}
        </>
      )}
    </Page>
  )
}

// ── Task row ───────────────────────────────────────────────────────
function TaskRow({ task, overdue, showWorkspace, onOpenTicket, onToggle }) {
  const { t } = useTranslation('tasks')
  const done = !!task.done
  const projectColor = task.project_color || '#7C3AED'
  const due = relativeDay(task.due_date)
  const canOpen = !!task.ticket_id
  // The whole row is the affordance: clicking anywhere (but the checkbox) opens
  // the parent ticket — switching teams first when it lives in another workspace.
  const open = () => onOpenTicket?.(task.ticket_id, task.workspace_id)

  return (
    <div
      onClick={canOpen ? open : undefined}
      onKeyDown={canOpen ? (e) => { if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); open() } } : undefined}
      role={canOpen ? 'button' : undefined}
      tabIndex={canOpen ? 0 : undefined}
      aria-label={canOpen ? t('row.openAria', { title: task.ticket_title || t('row.ticketFallbackLower') }) : undefined}
      className={cn(
        'group relative flex items-center gap-3.5 overflow-hidden rounded-2xl border bg-surface p-3.5 transition-all lift',
        canOpen && 'cursor-pointer focus:outline-none focus-visible:ring-2 focus-visible:ring-brand/30',
        overdue ? 'border-danger/30' : 'border-border',
        done && 'opacity-70',
      )}
    >
      {/* danger accent for overdue */}
      {overdue && <span className="absolute inset-y-0 left-0 w-1 bg-danger" />}

      {/* checkbox */}
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onToggle() }}
        aria-pressed={done}
        aria-label={done ? t('row.reopen') : t('row.complete')}
        className={cn(
          'grid size-7 shrink-0 place-items-center rounded-xl border-2 transition-all active:scale-90',
          done
            ? 'border-emerald bg-emerald text-white'
            : 'border-border text-transparent hover:border-emerald hover:text-emerald/40',
        )}
      >
        {done ? <CheckCircle2 size={18} strokeWidth={2.6} /> : <Circle size={16} strokeWidth={2.6} className="opacity-0" />}
      </button>

      {/* body */}
      <div className="min-w-0 flex-1">
        <p className={cn('truncate font-display text-[15px] font-semibold leading-snug text-ink', done && 'text-ink-muted line-through')}>
          {task.title || t('row.untitled')}
        </p>
        <div className="mt-1.5 flex flex-wrap items-center gap-2">
          {showWorkspace && task.workspace_name && (
            <Badge variant="muted" className="max-w-[11rem] gap-1.5 truncate px-2 text-[11px] tracking-normal text-ink-secondary">
              <Building2 size={11} strokeWidth={2.6} className="shrink-0 text-ink-muted" />
              <span className="truncate">{task.workspace_name}</span>
            </Badge>
          )}
          {task.project_name && (
            <ColorBadge color={projectColor} tint="16" className="max-w-[12rem] truncate px-2 text-[11px]">
              <span className="size-1.5 shrink-0 rounded-full" style={{ background: projectColor }} />
              <span className="truncate">{task.project_name}</span>
            </ColorBadge>
          )}
          {task.ticket_id && (
            // Non-interactive label — the whole row is the click target (opens the
            // ticket, switching teams first for cross-workspace items).
            <Badge variant="muted" className="max-w-[16rem] truncate px-2 text-[11px] tracking-normal group-hover:bg-brand-soft group-hover:text-brand">
              <span className="truncate">{task.ticket_title || t('row.ticketBadge')}</span>
              <ArrowUpRight size={11} strokeWidth={2.6} className="shrink-0" />
            </Badge>
          )}
        </div>
      </div>

      {/* due date */}
      {task.due_date && (
        <div className="flex shrink-0 flex-col items-end gap-0.5">
          <span
            className={cn(
              'inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] font-bold',
              done
                ? 'bg-surface-muted text-ink-faint'
                : overdue
                  ? 'bg-danger/12 text-danger'
                  : due?.tone === 'warning'
                    ? 'bg-amber/15 text-[#B45309]'
                    : 'bg-surface-muted text-ink-muted',
            )}
          >
            <CalendarClock size={11} strokeWidth={2.6} />
            {!done && due ? due.text : shortDt(task.due_date)}
          </span>
          {task.estimate_hours != null && (
            <span className="text-[10.5px] font-semibold text-ink-muted">{t('row.hours', { count: task.estimate_hours })}</span>
          )}
        </div>
      )}
    </div>
  )
}
