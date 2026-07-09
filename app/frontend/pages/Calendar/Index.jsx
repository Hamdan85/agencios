import { useCallback, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import {
  CalendarDays, CalendarRange, ChevronLeft, ChevronRight, Radio, SquareCheck, Video,
} from 'lucide-react'
import { useCalendar, useOpenTicket } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { PageHeader } from '@/components/ui/page-header'
import { PageLoader } from '@/components/ui/feedback'
import { Button } from '@/components/ui/button'
import { PageShell, PageTitle, PageContent } from '@/components/ui/page'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { cn } from '@/lib/utils'
import {
  WEEKDAY_LABELS, monthMatrix, monthRangeIso, weekRangeIso, dayRangeIso, weekDays,
  monthLabel, weekLabel, dayLabel, addMonths, addDays, isSameDay, groupEventsByDay, dayKey, startOfDay,
} from '@/components/calendar/calendarUtils'
import { EventChip } from '@/components/calendar/EventChip'
import { EventHoverCard } from '@/components/calendar/EventHoverCard'
import { TimeGrid } from '@/components/calendar/TimeGrid'
import { MeetingDialog } from '@/components/calendar/MeetingDialog'
import TicketDrawer from '@/components/ticket/LazyTicketDrawer'

const BRAND = '#0EA5E9'
const MAX_CHIPS = 3

// Local-time yyyy-mm-dd <-> Date, so the URL date param survives a reload
// without a timezone shift.
function toDateParam(d) {
  const x = new Date(d)
  return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`
}
function fromDateParam(s) {
  if (!s) return null
  const [y, m, d] = s.split('-').map(Number)
  if (!y || !m || !d) return null
  return new Date(y, m - 1, d)
}

// `scope="all_workspaces"` powers the personal "Meu calendário" view (/meu-calendario),
// merging scheduled posts + meetings from every team. Without it, the calendar is
// scoped to the active workspace (/calendario).
export default function CalendarIndex({ scope } = {}) {
  const global = scope === 'all_workspaces'
  const openTicket = useOpenTicket()
  const { data: me } = useCurrentUser()
  const [selected, setSelected] = useState(null) // meeting event for dialog

  // View (month/week), the navigated date, and the open ticket all live in the
  // URL so the calendar is shareable / reload-safe (?view=week&date=2026-07-02&ticket=42).
  const [searchParams, setSearchParams] = useSearchParams()
  const view = ['day', 'week', 'month'].includes(searchParams.get('view')) ? searchParams.get('view') : 'month'
  const cursor = useMemo(
    () => startOfDay(fromDateParam(searchParams.get('date')) || new Date()),
    [searchParams],
  )
  const ticketId = searchParams.get('ticket')

  const patchParams = useCallback(
    (mut, { replace = true } = {}) => {
      setSearchParams(
        (prev) => {
          const sp = new URLSearchParams(prev)
          mut(sp)
          return sp
        },
        { replace },
      )
    },
    [setSearchParams],
  )

  const setView = useCallback((v) => patchParams((sp) => sp.set('view', v)), [patchParams])
  const setCursor = useCallback(
    (next) => patchParams((sp) => {
      const base = startOfDay(fromDateParam(sp.get('date')) || new Date())
      const value = typeof next === 'function' ? next(base) : next
      sp.set('date', toDateParam(value))
    }),
    [patchParams],
  )

  const range = useMemo(
    () => (view === 'month' ? monthRangeIso(cursor) : view === 'day' ? dayRangeIso(cursor) : weekRangeIso(cursor)),
    [view, cursor],
  )

  const { data, isLoading } = useCalendar(global ? { ...range, scope } : range)
  const events = data?.events || []
  const byDay = useMemo(() => groupEventsByDay(events), [events])

  const today = startOfDay(new Date())
  const goToday = () => setCursor(startOfDay(new Date()))
  const step = (dir) =>
    setCursor((c) => (view === 'month' ? addMonths(c, dir) : addDays(c, view === 'day' ? dir : dir * 7)))

  const handleEventClick = (ev) => {
    // Posts, tasks and planned tickets all resolve to a ticket — open it.
    if ((ev?.type === 'post' || ev?.type === 'task' || ev?.type === 'ticket') && ev?.ticket_id) {
      // Another team's event (the cross-team "Meu calendário"): switch into that
      // workspace and hand off to the full page — the drawer can't render a ticket
      // from a different tenant. Same workspace → open it in the drawer.
      if (ev.workspace_id && me?.workspace?.id && ev.workspace_id !== me.workspace.id) {
        openTicket(ev.ticket_id, ev.workspace_id)
        return
      }
      patchParams((sp) => sp.set('ticket', String(ev.ticket_id)), { replace: false })
      return
    }
    setSelected(ev)
  }

  const label = view === 'month' ? monthLabel(cursor) : view === 'day' ? dayLabel(cursor) : weekLabel(cursor)

  return (
    <PageShell className="animate-rise">
      {/* Fixed title band — respiro gutter, like every page's title. Holds the
          header, the view tabs, and the navigation + legend toolbar. */}
      <PageTitle className="pb-4">
        <PageHeader
          className="mb-0"
          eyebrow={global ? 'Você' : 'Planejamento'}
          title={global ? 'Meu calendário' : 'Calendário'}
          icon={global ? CalendarRange : CalendarDays}
          color={BRAND}
          description={global
            ? 'Posts agendados e reuniões de todos os seus times, num só lugar.'
            : 'Posts agendados e reuniões, num só lugar.'}
          actions={
            <Tabs value={view} onValueChange={setView}>
              <TabsList>
                <TabsTrigger value="day">Dia</TabsTrigger>
                <TabsTrigger value="week">Semana</TabsTrigger>
                <TabsTrigger value="month">Mês</TabsTrigger>
              </TabsList>
            </Tabs>
          }
        />

        {/* Navigation + legend */}
        <div className="mt-5 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <div className="flex items-center rounded-xl border border-border bg-surface p-1">
              <Button variant="ghost" size="icon-sm" onClick={() => step(-1)} aria-label="Anterior">
                <ChevronLeft size={18} />
              </Button>
              <Button variant="ghost" size="icon-sm" onClick={() => step(1)} aria-label="Próximo">
                <ChevronRight size={18} />
              </Button>
            </div>
            <Button variant="outline" size="sm" onClick={goToday}>Hoje</Button>
            <h2 className="ml-1 font-display text-lg font-extrabold capitalize tracking-tight text-ink">
              {label}
            </h2>
          </div>
          <Legend />
        </div>
      </PageTitle>

      {/* Content band — the grid runs full-width (wide); day/week views scroll
          inside themselves. */}
      <PageContent wide flush className="pt-1">
        {isLoading ? (
          <PageLoader />
        ) : view === 'month' ? (
          <MonthGrid
            cursor={cursor}
            today={today}
            byDay={byDay}
            showWorkspace={global}
            onEventClick={handleEventClick}
          />
        ) : (
          <TimeGridView
            view={view}
            cursor={cursor}
            today={today}
            byDay={byDay}
            showWorkspace={global}
            onEventClick={handleEventClick}
          />
        )}
      </PageContent>

      <MeetingDialog
        event={selected}
        open={!!selected}
        onOpenChange={(o) => !o && setSelected(null)}
      />

      <TicketDrawer
        ticketId={ticketId}
        open={!!ticketId}
        onOpenChange={(o) => { if (!o) patchParams((sp) => sp.delete('ticket')) }}
      />
    </PageShell>
  )
}

// ── Month grid ─────────────────────────────────────────────────────
function MonthGrid({ cursor, today, byDay, showWorkspace, onEventClick }) {
  const weeks = useMemo(() => monthMatrix(cursor), [cursor])
  const month = cursor.getMonth()

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-[0_1px_2px_rgba(24,18,43,0.04),0_8px_24px_-16px_rgba(24,18,43,0.12)]">
      {/* weekday header */}
      <div className="grid shrink-0 grid-cols-7 border-b border-border bg-surface-muted/50">
        {WEEKDAY_LABELS.map((wd, i) => (
          <div
            key={wd}
            className={cn(
              'px-3 py-2.5 text-center text-[11px] font-bold uppercase tracking-[0.12em] text-ink-muted',
              i >= 5 && 'text-ink-faint',
            )}
          >
            {wd}
          </div>
        ))}
      </div>

      {/* weeks */}
      <div
        className="grid min-h-0 flex-1"
        style={{ gridTemplateRows: `repeat(${weeks.length}, minmax(0, 1fr))` }}
      >
        {weeks.map((days, wi) => (
          <div key={wi} className="grid min-h-0 grid-cols-7">
            {days.map((day) => (
              <DayCell
                key={dayKey(day)}
                day={day}
                inMonth={day.getMonth() === month}
                isToday={isSameDay(day, today)}
                events={byDay.get(dayKey(day)) || []}
                showWorkspace={showWorkspace}
                onEventClick={onEventClick}
              />
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}

function DayCell({ day, inMonth, isToday, events, showWorkspace, onEventClick }) {
  const shown = events.slice(0, MAX_CHIPS)
  const overflow = events.length - shown.length
  const weekend = day.getDay() === 0 || day.getDay() === 6

  return (
    <div
      className={cn(
        'flex min-h-0 flex-col gap-1 overflow-hidden border-b border-r border-border p-1.5 transition-colors last:border-r-0',
        !inMonth && 'bg-surface-muted/40',
        inMonth && weekend && 'bg-surface-muted/20',
        isToday && 'bg-sky/5',
      )}
    >
      <div className="flex shrink-0 items-center justify-between px-0.5">
        <span
          className={cn(
            'grid size-6 place-items-center rounded-full text-[12px] font-bold tabular-nums',
            !inMonth && 'text-ink-faint',
            inMonth && !isToday && 'text-ink-secondary',
            isToday && 'bg-sky text-white shadow-sm',
          )}
        >
          {day.getDate()}
        </span>
        {events.length > 0 && (
          <span className="text-[10px] font-bold text-ink-faint">{events.length}</span>
        )}
      </div>

      <div className="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto">
        {shown.map((ev) => (
          <EventHoverCard key={`${ev.type}-${ev.id}`} event={ev} showWorkspace={showWorkspace}>
            <EventChip event={ev} onClick={onEventClick} showWorkspace={showWorkspace} compact />
          </EventHoverCard>
        ))}
        {overflow > 0 && (
          <span className="px-1.5 text-[10.5px] font-bold text-ink-muted">+{overflow} mais</span>
        )}
      </div>
    </div>
  )
}

// ── Day / week time grid ───────────────────────────────────────────
// Both views share the Google Calendar-style TimeGrid: a 24h vertical axis
// where each event sits at its time; the day view is the same grid with a
// single, centered column.
function TimeGridView({ view, cursor, today, byDay, showWorkspace, onEventClick }) {
  const days = useMemo(() => (view === 'day' ? [cursor] : weekDays(cursor)), [view, cursor])

  return (
    <div className={cn('flex min-h-0 flex-1 flex-col p-1.5', view === 'day' && 'mx-auto w-full max-w-3xl')}>
      <TimeGrid
        days={days}
        today={today}
        byDay={byDay}
        showWorkspace={showWorkspace}
        onEventClick={onEventClick}
      />
    </div>
  )
}

// ── Legend ─────────────────────────────────────────────────────────
function Legend() {
  return (
    <div className="flex flex-wrap items-center gap-3 rounded-xl border border-border bg-surface px-3 py-2">
      <span className="text-[10px] font-bold uppercase tracking-wider text-ink-faint">Legenda</span>
      <LegendItem icon={Radio} color="#7C3AED" label="Posts agendados" />
      <LegendItem icon={Video} color="#14B8A6" label="Reuniões" />
      <LegendItem icon={SquareCheck} color="#F59E0B" label="Tarefas" />
    </div>
  )
}

function LegendItem({ icon: Icon, color, label }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-[12px] font-semibold text-ink-secondary">
      <span className="grid size-4 place-items-center rounded-md" style={{ background: color, color: '#fff' }}>
        <Icon size={9} strokeWidth={2.6} />
      </span>
      {label}
    </span>
  )
}
