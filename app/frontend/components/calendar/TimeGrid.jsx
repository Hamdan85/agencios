import { useEffect, useMemo, useRef, useState } from 'react'
import { ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import { time } from '@/lib/formatters'
import { eventVisual } from './EventChip'
import { EventHoverCard } from './EventHoverCard'
import {
  MINUTES_IN_DAY, dayKey, isSameDay, layoutDayEvents, minutesOfDay,
} from './calendarUtils'
import i18n from '@/i18n'

const HOUR_PX = 52
const GRID_PX = 24 * HOUR_PX
const GUTTER = '3.25rem'
const NOW_COLOR = '#F43F5E'
const DEFAULT_SCROLL_MIN = 8 * 60
const MAX_ALL_DAY = 3

// Sticky cells (header, all-day band) need an OPAQUE background or the grid
// shows through as it scrolls beneath them — a translucent `bg-sky/10` on top
// of `bg-surface` gets deduped away by tailwind-merge. Mix the today tint into
// the surface color instead.
const TODAY_STICKY_BG = { background: 'color-mix(in srgb, var(--color-sky) 9%, var(--color-surface))' }

// Google Calendar-style time grid shared by the day (1 column) and week
// (7 columns) views: a 24h vertical axis with date-only tasks pinned to an
// all-day band at the top, meetings as duration blocks, and posts as compact
// iconic markers at their exact time. Simultaneous events split the column
// width side by side.
export function TimeGrid({ days, today, byDay, showWorkspace, onEventClick }) {
  const scrollRef = useRef(null)
  const [now, setNow] = useState(() => new Date())
  // The all-day band collapses to MAX_ALL_DAY chips per day (Google
  // Calendar-style) — real workspaces carry dozens of tasks per day.
  const [allDayExpanded, setAllDayExpanded] = useState(false)

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60_000)
    return () => clearInterval(t)
  }, [])

  const { laidByDay, allDayByDay, hasAllDay } = useMemo(() => {
    const laid = new Map()
    const allDay = new Map()
    let any = false
    for (const day of days) {
      const events = byDay.get(dayKey(day)) || []
      // Overdue first, then open, done last — the collapsed band shows what
      // still needs attention.
      const tasks = events
        .filter((ev) => ev.all_day)
        .sort((a, b) => (!!a.done - !!b.done) || (!!b.overdue - !!a.overdue))
      allDay.set(dayKey(day), tasks)
      laid.set(dayKey(day), layoutDayEvents(events))
      if (tasks.length) any = true
    }
    return { laidByDay: laid, allDayByDay: allDay, hasAllDay: any }
  }, [days, byDay])

  const daysSignature = days.map((d) => dayKey(d)).join('|')

  // Open the scroll on the first timed event of the window (capped at 08:00),
  // or on the current time when today is visible and the window is empty.
  useEffect(() => {
    const el = scrollRef.current
    if (!el) return
    const starts = [...laidByDay.values()].flat().map((it) => it.startMin)
    const todayVisible = days.some((d) => isSameDay(d, today))
    const target = starts.length
      ? Math.min(Math.min(...starts), DEFAULT_SCROLL_MIN)
      : todayVisible ? Math.max(minutesOfDay(new Date()) - 90, 0) : DEFAULT_SCROLL_MIN
    el.scrollTop = Math.max((target / MINUTES_IN_DAY) * GRID_PX - 8, 0)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [daysSignature])

  const week = days.length > 1
  const nowMin = minutesOfDay(now)

  return (
    <div
      ref={scrollRef}
      className="scrollbar-subtle min-h-0 flex-1 overflow-auto overscroll-contain rounded-2xl border border-border bg-surface shadow-[0_1px_2px_rgba(24,18,43,0.04),0_8px_24px_-16px_rgba(24,18,43,0.12)]"
    >
      <div
        className={cn('grid', week && 'min-w-216 lg:min-w-0')}
        style={{ gridTemplateColumns: `${GUTTER} repeat(${days.length}, minmax(0, 1fr))` }}
      >
        {/* ── header row (fixed h-12 so the all-day band can stick below it) ── */}
        <div className="sticky left-0 top-0 z-40 h-12 border-b border-border bg-surface" />
        {days.map((day) => (
          <DayHeader
            key={dayKey(day)}
            day={day}
            isToday={isSameDay(day, today)}
            count={(byDay.get(dayKey(day)) || []).length}
            week={week}
          />
        ))}

        {/* ── all-day band: date-only tasks pinned under the header ── */}
        {hasAllDay && (
          <>
            <div className="sticky left-0 top-12 z-40 flex flex-col items-end justify-between border-b border-r border-border bg-surface px-1.5 py-1.5">
              <span className="font-mono text-[9px] font-semibold uppercase tracking-wider text-ink-faint">dia</span>
              {[...allDayByDay.values()].some((list) => list.length > MAX_ALL_DAY) && (
                <button
                  type="button"
                  onClick={() => setAllDayExpanded((v) => !v)}
                  aria-label={allDayExpanded ? 'Recolher tarefas' : 'Expandir tarefas'}
                  className="grid size-5 place-items-center rounded-md text-ink-muted transition-all hover:bg-surface-muted hover:text-ink"
                >
                  <ChevronDown size={13} strokeWidth={2.6} className={cn('transition-transform', allDayExpanded && 'rotate-180')} />
                </button>
              )}
            </div>
            {days.map((day) => {
              const tasks = allDayByDay.get(dayKey(day))
              const shown = allDayExpanded ? tasks : tasks.slice(0, MAX_ALL_DAY)
              const overflow = tasks.length - shown.length
              return (
                <div
                  key={dayKey(day)}
                  className={cn(
                    'scrollbar-subtle sticky top-12 z-30 flex flex-col gap-1 border-b border-r border-border bg-surface p-1 last:border-r-0',
                    allDayExpanded && 'max-h-[32vh] overflow-y-auto',
                  )}
                  style={isSameDay(day, today) ? TODAY_STICKY_BG : undefined}
                >
                  {shown.map((ev) => (
                    <AllDayChip
                      key={`${ev.type}-${ev.id}`}
                      event={ev}
                      onEventClick={onEventClick}
                      showWorkspace={showWorkspace}
                    />
                  ))}
                  {overflow > 0 && (
                    <button
                      type="button"
                      onClick={() => setAllDayExpanded(true)}
                      className="rounded px-1.5 py-0.5 text-left text-[10px] font-bold text-ink-muted transition-colors hover:bg-surface-muted hover:text-ink"
                    >
                      +{overflow} mais
                    </button>
                  )}
                </div>
              )
            })}
          </>
        )}

        {/* ── hour gutter ── */}
        <div className="sticky left-0 z-30 border-r border-border bg-surface" style={{ height: GRID_PX }}>
          <div className="relative h-full">
            {Array.from({ length: 23 }, (_, i) => i + 1).map((h) => (
              <span
                key={h}
                className="absolute right-1.5 -translate-y-1/2 font-mono text-[10px] font-semibold tabular-nums text-ink-faint"
                style={{ top: (h / 24) * GRID_PX }}
              >
                {String(h).padStart(2, '0')}:00
              </span>
            ))}
          </div>
        </div>

        {/* ── day columns ── */}
        {days.map((day) => {
          const isToday = isSameDay(day, today)
          const weekend = day.getDay() === 0 || day.getDay() === 6
          return (
            <div
              key={dayKey(day)}
              className={cn(
                'relative border-r border-border last:border-r-0',
                isToday && 'bg-sky/[0.04]',
                !isToday && weekend && 'bg-surface-muted/25',
              )}
              style={{ height: GRID_PX }}
            >
              {/* hour lines */}
              {Array.from({ length: 24 }, (_, h) => (
                <div key={h} className="border-b border-border/60" style={{ height: HOUR_PX }} />
              ))}

              {/* events */}
              {(laidByDay.get(dayKey(day)) || []).map((item) => (
                <GridEvent
                  key={`${item.event.type}-${item.event.id}`}
                  item={item}
                  onEventClick={onEventClick}
                  showWorkspace={showWorkspace}
                />
              ))}

              {/* current-time indicator */}
              {isToday && (
                <div
                  className="pointer-events-none absolute inset-x-0 z-20"
                  style={{ top: (nowMin / MINUTES_IN_DAY) * GRID_PX }}
                >
                  <div className="relative h-px" style={{ background: NOW_COLOR }}>
                    <span
                      className="absolute -left-1 top-1/2 size-2 -translate-y-1/2 rounded-full"
                      style={{ background: NOW_COLOR }}
                    />
                  </div>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}

function DayHeader({ day, isToday, count, week }) {
  const wd = day.toLocaleDateString(i18n.language, { weekday: week ? 'short' : 'long' }).replace('.', '')
  return (
    <div
      className="sticky top-0 z-30 flex h-12 items-center justify-between gap-2 border-b border-r border-border bg-surface px-2.5 last:border-r-0"
      style={isToday ? TODAY_STICKY_BG : undefined}
    >
      <div className="flex min-w-0 items-center gap-2">
        <span
          className={cn(
            'grid size-7 shrink-0 place-items-center rounded-full font-display text-[13px] font-extrabold tabular-nums',
            isToday ? 'bg-sky text-white shadow-sm' : 'text-ink',
          )}
        >
          {day.getDate()}
        </span>
        <p className={cn('truncate text-[11px] font-bold capitalize', isToday ? 'text-sky' : 'text-ink-muted')}>
          {wd}
        </p>
      </div>
      {count > 0 && (
        <span className="grid size-5 shrink-0 place-items-center rounded-full bg-surface-muted text-[10px] font-bold text-ink-muted">
          {count}
        </span>
      )}
    </div>
  )
}

// A task pinned to the all-day band — slim pill, struck through once done,
// rose-tinged when overdue.
function AllDayChip({ event, onEventClick, showWorkspace }) {
  const { color, Icon } = eventVisual(event)
  return (
    <EventHoverCard event={event} showWorkspace={showWorkspace}>
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onEventClick?.(event) }}
        className={cn(
          'flex w-full items-center gap-1.5 overflow-hidden rounded-md px-1.5 py-0.75 text-left text-[10.5px] font-bold leading-none transition-all hover:brightness-105 hover:saturate-150',
          event.overdue && !event.done && 'ring-1 ring-inset ring-rose-400/50',
        )}
        style={{ background: `${color}1A`, color }}
      >
        <span className="grid size-3.5 shrink-0 place-items-center rounded" style={{ background: color, color: '#fff' }}>
          {Icon && <Icon size={8} strokeWidth={2.8} />}
        </span>
        <span className={cn('truncate', event.done && 'line-through opacity-60')}>{event.title}</span>
      </button>
    </EventHoverCard>
  )
}

function GridEvent({ item, onEventClick, showWorkspace }) {
  const ev = item.event
  const { color, Icon } = eventVisual(ev)
  const label = ev?.title || (ev?.type === 'meeting' ? 'Reunião' : 'Post')
  // Posts have a moment, not a duration — render them as a compact iconic
  // marker pinned at their time; meetings keep the duration block.
  const marker = !ev.end
  const short = item.endMin - item.startMin < 45

  const geometry = {
    top: `${(item.startMin / MINUTES_IN_DAY) * 100}%`,
    left: `calc(${(item.col / item.cols) * 100}% + 2px)`,
    width: `calc(${100 / item.cols}% - 4px)`,
  }

  if (marker) {
    return (
      <EventHoverCard event={ev} showWorkspace={showWorkspace}>
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onEventClick?.(ev) }}
          className="absolute z-10 flex h-5.5 items-center gap-1.5 overflow-hidden rounded-full pl-0.75 pr-2 text-left shadow-sm ring-1 ring-white/40 transition-all hover:z-20 hover:brightness-110 hover:shadow-md"
          style={{ ...geometry, background: color, color: '#fff' }}
        >
          <span className="grid size-4 shrink-0 place-items-center rounded-full bg-white/25">
            {Icon ? <Icon size={9.5} strokeWidth={2.6} /> : <span className="size-1.5 rounded-full bg-white" />}
          </span>
          <span className="shrink-0 font-mono text-[9px] font-bold tabular-nums opacity-90">{time(ev.start)}</span>
          <span className="truncate text-[10.5px] font-bold leading-none">{label}</span>
        </button>
      </EventHoverCard>
    )
  }

  return (
    <EventHoverCard event={ev} showWorkspace={showWorkspace}>
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onEventClick?.(ev) }}
        className={cn(
          'absolute z-10 flex flex-col overflow-hidden rounded-lg border-l-[3px] px-1.5 text-left transition-all hover:z-20 hover:brightness-105 hover:saturate-150 hover:shadow-md',
          short ? 'justify-center py-0.5' : 'py-1',
        )}
        style={{
          ...geometry,
          height: `calc(${((item.endMin - item.startMin) / MINUTES_IN_DAY) * 100}% - 2px)`,
          background: `${color}1F`,
          borderLeftColor: color,
          color,
        }}
      >
        {short ? (
          <span className="flex min-w-0 items-center gap-1 text-[10.5px] font-bold leading-tight">
            {Icon && <Icon size={9} strokeWidth={2.6} className="shrink-0" />}
            <span className="shrink-0 font-mono text-[9.5px] tabular-nums opacity-75">{time(ev.start)}</span>
            <span className="truncate">{label}</span>
          </span>
        ) : (
          <>
            <span className="flex min-w-0 shrink-0 items-center gap-1 font-mono text-[9.5px] font-bold tabular-nums opacity-75">
              {Icon && <Icon size={9} strokeWidth={2.6} className="shrink-0" />}
              <span className="truncate">{`${time(ev.start)} – ${time(ev.end)}`}</span>
            </span>
            <span className="line-clamp-2 text-[11px] font-bold leading-tight">{label}</span>
          </>
        )}
      </button>
    </EventHoverCard>
  )
}
