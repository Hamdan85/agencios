import * as React from 'react'
import {
  addMonths, eachDayOfInterval, endOfMonth, endOfWeek, format, isSameDay,
  isSameMonth, isToday, parse, startOfMonth, startOfWeek, subMonths,
} from 'date-fns'
import { ptBR } from 'date-fns/locale'
import { CalendarDays, ChevronLeft, ChevronRight, Clock, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import {
  Popover, PopoverTrigger, PopoverContent,
} from '@/components/ui/popover'

const WEEKDAYS = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']
const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s)

// Parse a stored value string into a Date, tolerating empties / bad input.
function parseValue(value, withTime) {
  if (!value) return null
  const fmt = withTime ? "yyyy-MM-dd'T'HH:mm" : 'yyyy-MM-dd'
  const slice = withTime ? String(value).slice(0, 16) : String(value).slice(0, 10)
  const parsed = parse(slice, fmt, new Date())
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

const triggerClass = (empty) =>
  cn(
    'flex h-10 w-full items-center gap-2 rounded-xl border border-border bg-surface-muted px-3.5 py-2 text-left text-sm text-ink transition-colors',
    'focus:bg-surface focus:outline-none focus:ring-2 focus:ring-brand/20 focus:border-brand disabled:cursor-not-allowed disabled:opacity-50',
    empty && 'text-ink-faint',
  )

// ── The month grid, shared by both pickers ────────────────────────────────
function MonthGrid({ selected, onPick }) {
  const [view, setView] = React.useState(selected || new Date())

  // Re-center on the selected value whenever it changes (e.g. popover reopens).
  React.useEffect(() => {
    if (selected) setView(selected)
  }, [selected])

  const gridStart = startOfWeek(startOfMonth(view), { weekStartsOn: 0 })
  const gridEnd = endOfWeek(endOfMonth(view), { weekStartsOn: 0 })
  const days = eachDayOfInterval({ start: gridStart, end: gridEnd })

  return (
    <div className="w-64">
      <div className="mb-2 flex items-center justify-between px-1">
        <button
          type="button"
          onClick={() => setView((v) => subMonths(v, 1))}
          className="grid size-7 place-items-center rounded-lg text-ink-muted transition hover:bg-surface-muted hover:text-ink"
          aria-label="Mês anterior"
        >
          <ChevronLeft size={16} />
        </button>
        <span className="text-sm font-bold text-ink">
          {cap(format(view, 'MMMM yyyy', { locale: ptBR }))}
        </span>
        <button
          type="button"
          onClick={() => setView((v) => addMonths(v, 1))}
          className="grid size-7 place-items-center rounded-lg text-ink-muted transition hover:bg-surface-muted hover:text-ink"
          aria-label="Próximo mês"
        >
          <ChevronRight size={16} />
        </button>
      </div>

      <div className="mb-1 grid grid-cols-7">
        {WEEKDAYS.map((d, i) => (
          <span key={i} className="grid h-7 place-items-center text-[11px] font-bold uppercase text-ink-faint">
            {d}
          </span>
        ))}
      </div>

      <div className="grid grid-cols-7 gap-0.5">
        {days.map((day) => {
          const isSelected = selected && isSameDay(day, selected)
          const outside = !isSameMonth(day, view)
          const today = isToday(day)
          return (
            <button
              key={day.toISOString()}
              type="button"
              onClick={() => onPick(day)}
              className={cn(
                'grid size-8 place-items-center rounded-lg text-sm font-medium transition',
                isSelected
                  ? 'bg-brand font-bold text-white shadow-sm'
                  : 'text-ink hover:bg-brand-soft hover:text-brand',
                !isSelected && outside && 'text-ink-faint',
                !isSelected && today && 'ring-1 ring-inset ring-brand/50',
              )}
            >
              {format(day, 'd')}
            </button>
          )
        })}
      </div>
    </div>
  )
}

// ── Date-only picker — value/onChange use the 'yyyy-MM-dd' string ──────────
export function DatePicker({
  value, onChange, placeholder = 'Selecione uma data', id, className, disabled, align = 'start',
}) {
  const [open, setOpen] = React.useState(false)
  const selected = parseValue(value, false)

  const pick = (day) => {
    onChange?.(format(day, 'yyyy-MM-dd'))
    setOpen(false)
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button type="button" id={id} disabled={disabled} className={cn(triggerClass(!selected), className)}>
          <CalendarDays size={16} className="shrink-0 text-ink-muted" />
          <span className="flex-1 truncate">
            {selected ? cap(format(selected, "dd 'de' MMM 'de' yyyy", { locale: ptBR })) : placeholder}
          </span>
          {selected && !disabled && (
            <span
              role="button"
              tabIndex={-1}
              aria-label="Limpar data"
              onClick={(e) => { e.stopPropagation(); onChange?.('') }}
              className="grid size-5 place-items-center rounded-md text-ink-faint transition hover:bg-surface-muted hover:text-ink"
            >
              <X size={13} />
            </span>
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent align={align}>
        <MonthGrid selected={selected} onPick={pick} />
      </PopoverContent>
    </Popover>
  )
}

// ── Date + time picker — value/onChange use the 'yyyy-MM-ddTHH:mm' string ──
export function DateTimePicker({
  value, onChange, placeholder = 'Selecione data e hora', id, className, disabled, align = 'start',
}) {
  const [open, setOpen] = React.useState(false)
  const selected = parseValue(value, true)
  const hh = selected ? format(selected, 'HH') : '09'
  const mm = selected ? format(selected, 'mm') : '00'

  const emit = (day, h, m) => onChange?.(`${format(day, 'yyyy-MM-dd')}T${h}:${m}`)

  const pickDay = (day) => emit(day, hh, mm)

  const setTime = (h, m) => {
    const base = selected || new Date()
    emit(base, h, m)
  }

  const clampPad = (raw, max) => {
    const n = Math.max(0, Math.min(max, parseInt(String(raw).replace(/\D/g, ''), 10) || 0))
    return String(n).padStart(2, '0')
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button type="button" id={id} disabled={disabled} className={cn(triggerClass(!selected), className)}>
          <CalendarDays size={16} className="shrink-0 text-ink-muted" />
          <span className="flex-1 truncate">
            {selected ? cap(format(selected, "dd MMM yyyy 'às' HH:mm", { locale: ptBR })) : placeholder}
          </span>
          {selected && !disabled && (
            <span
              role="button"
              tabIndex={-1}
              aria-label="Limpar data"
              onClick={(e) => { e.stopPropagation(); onChange?.('') }}
              className="grid size-5 place-items-center rounded-md text-ink-faint transition hover:bg-surface-muted hover:text-ink"
            >
              <X size={13} />
            </span>
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent align={align}>
        <MonthGrid selected={selected} onPick={pickDay} />
        <div className="mt-3 flex items-center gap-2 border-t border-border pt-3">
          <Clock size={15} className="text-ink-muted" />
          <span className="text-xs font-semibold text-ink-muted">Horário</span>
          <div className="ml-auto flex items-center gap-1">
            <input
              inputMode="numeric"
              value={hh}
              onChange={(e) => setTime(clampPad(e.target.value, 23), mm)}
              className="h-9 w-12 rounded-lg border border-border bg-surface-muted text-center text-sm font-bold text-ink focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20"
              aria-label="Hora"
            />
            <span className="font-bold text-ink-muted">:</span>
            <input
              inputMode="numeric"
              value={mm}
              onChange={(e) => setTime(hh, clampPad(e.target.value, 59))}
              className="h-9 w-12 rounded-lg border border-border bg-surface-muted text-center text-sm font-bold text-ink focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand/20"
              aria-label="Minuto"
            />
          </div>
        </div>
        <div className="mt-2 flex justify-end">
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="rounded-lg bg-brand px-3 py-1.5 text-xs font-bold text-white transition hover:brightness-105"
          >
            Concluir
          </button>
        </div>
      </PopoverContent>
    </Popover>
  )
}

export default DatePicker
