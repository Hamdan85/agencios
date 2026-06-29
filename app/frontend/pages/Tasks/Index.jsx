import { useMemo, useState } from 'react'
import {
  ListChecks, ListTodo, Search, CheckCircle2, Circle, AlarmClock, Inbox,
  ArrowUpRight, CalendarClock, PartyPopper, Building2,
} from 'lucide-react'
import { useTasks, useTaskMutations, useOpenTicket } from '@/hooks/useData'
import { PageHeader } from '@/components/ui/page-header'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Input } from '@/components/ui/input'
import { cn } from '@/lib/utils'
import { relativeDay, shortDt } from '@/lib/formatters'

const HERO = '#F59E0B'

const TABS = [
  { key: 'pending', label: 'Pendentes', countKey: 'pending', color: '#0EA5E9' },
  { key: 'overdue', label: 'Vencidas', countKey: 'overdue', color: '#F43F5E' },
  { key: 'completed', label: 'Concluídas', countKey: 'completed', color: '#10B981' },
]

const EMPTY = {
  pending: { icon: CheckCircle2, title: 'Tudo em dia!', description: 'Você não tem tarefas pendentes. Bom trabalho.' },
  overdue: { icon: PartyPopper, title: 'Nenhuma tarefa vencida', description: 'Sem atrasos por aqui — continue assim.' },
  completed: { icon: Inbox, title: 'Nada concluído ainda', description: 'As tarefas que você finalizar aparecem aqui.' },
}

function isOverdue(task) {
  if (task.done || !task.due_date) return false
  return new Date(task.due_date) < new Date(new Date().setHours(0, 0, 0, 0))
}

// `scope="all_workspaces"` powers the personal "Minhas tarefas" view (/minhas-tarefas),
// aggregating the user's subtasks across every team. Without it, the page is scoped
// to the active workspace (/tarefas).
export default function TasksIndex({ scope } = {}) {
  const global = scope === 'all_workspaces'
  const [tab, setTab] = useState('pending')
  const [query, setQuery] = useState('')
  const { data, isLoading } = useTasks(global ? { scope } : {})
  const mutate = useTaskMutations()
  const openTicket = useOpenTicket()

  const counts = data?.counts || { pending: 0, overdue: 0, completed: 0 }
  const pendingTasks = data?.tasks || []
  const completedTasks = data?.completed || []

  const lists = useMemo(() => ({
    pending: pendingTasks.filter((t) => !isOverdue(t)),
    overdue: pendingTasks.filter((t) => isOverdue(t)),
    completed: completedTasks,
  }), [pendingTasks, completedTasks])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    const base = lists[tab] || []
    if (!q) return base
    return base.filter((t) =>
      (t.title || '').toLowerCase().includes(q) ||
      (t.ticket_title || '').toLowerCase().includes(q) ||
      (t.project_name || '').toLowerCase().includes(q),
    )
  }, [lists, tab, query])

  const toggle = (task) => mutate.mutate({ id: task.id, data: { done: !task.done } })

  if (isLoading) return <PageLoader />

  const emptyMeta = EMPTY[tab]

  return (
    <div className="animate-rise">
      <PageHeader
        eyebrow={global ? 'Você' : 'Gestão'}
        title="Minhas tarefas"
        icon={global ? ListTodo : ListChecks}
        color={HERO}
        description={global
          ? 'Tudo o que está atribuído a você, em todos os seus times.'
          : 'Suas subtarefas em todos os tickets deste time.'}
        actions={
          <span className="inline-flex items-center gap-2 rounded-xl bg-amber/15 px-3.5 py-2 font-display text-sm font-extrabold text-[#B45309]">
            <AlarmClock size={16} strokeWidth={2.4} />
            {counts.pending} pendente{counts.pending === 1 ? '' : 's'}
          </span>
        }
      />

      {/* Filter pills + search */}
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          {TABS.map((t) => {
            const active = tab === t.key
            const count = counts[t.countKey] ?? (lists[t.key]?.length || 0)
            return (
              <button
                key={t.key}
                type="button"
                onClick={() => setTab(t.key)}
                className={cn(
                  'inline-flex items-center gap-2 rounded-full border px-3.5 py-1.5 text-sm font-bold transition-all',
                  active
                    ? 'border-transparent text-white shadow-sm'
                    : 'border-border bg-surface text-ink-secondary hover:border-strong hover:text-ink',
                )}
                style={active ? { background: t.color } : undefined}
              >
                {t.label}
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

        <div className="relative w-full sm:w-64">
          <Search size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Buscar tarefas…"
            className="pl-9"
          />
        </div>
      </div>

      {/* Task list */}
      {filtered.length === 0 ? (
        query.trim() ? (
          <EmptyState icon={Search} color={HERO} title="Nenhum resultado" description={`Nada encontrado para “${query}”.`} />
        ) : (
          <EmptyState icon={emptyMeta.icon} color={TABS.find((t) => t.key === tab)?.color} title={emptyMeta.title} description={emptyMeta.description} />
        )
      ) : (
        <div className="space-y-2.5">
          {filtered.map((task) => (
            <TaskRow key={task.id} task={task} overdue={isOverdue(task)} showWorkspace={global} onOpenTicket={openTicket} onToggle={() => toggle(task)} />
          ))}
        </div>
      )}
    </div>
  )
}

// ── Task row ───────────────────────────────────────────────────────
function TaskRow({ task, overdue, showWorkspace, onOpenTicket, onToggle }) {
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
      aria-label={canOpen ? `Abrir ${task.ticket_title || 'ticket'}` : undefined}
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
        aria-label={done ? 'Reabrir tarefa' : 'Concluir tarefa'}
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
          {task.title || 'Sem título'}
        </p>
        <div className="mt-1.5 flex flex-wrap items-center gap-2">
          {showWorkspace && task.workspace_name && (
            <span className="inline-flex max-w-[11rem] items-center gap-1.5 truncate rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-bold text-ink-secondary">
              <Building2 size={11} strokeWidth={2.6} className="shrink-0 text-ink-muted" />
              <span className="truncate">{task.workspace_name}</span>
            </span>
          )}
          {task.project_name && (
            <span
              className="inline-flex max-w-[12rem] items-center gap-1.5 truncate rounded-full px-2 py-0.5 text-[11px] font-bold"
              style={{ background: `${projectColor}16`, color: projectColor }}
            >
              <span className="size-1.5 shrink-0 rounded-full" style={{ background: projectColor }} />
              <span className="truncate">{task.project_name}</span>
            </span>
          )}
          {task.ticket_id && (
            // Non-interactive label — the whole row is the click target (opens the
            // ticket, switching teams first for cross-workspace items).
            <span className="inline-flex max-w-[16rem] items-center gap-1 truncate rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-bold text-ink-muted transition-colors group-hover:bg-brand-soft group-hover:text-brand">
              <span className="truncate">{task.ticket_title || 'Ticket'}</span>
              <ArrowUpRight size={11} strokeWidth={2.6} className="shrink-0" />
            </span>
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
        </div>
      )}
    </div>
  )
}
