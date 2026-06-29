// Date math + formatting helpers for the calendar grid.
// Week starts on Monday (Mon–Sun). All math is local-time, defensive.

export const WEEKDAY_LABELS = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']

export function startOfDay(d) {
  const x = new Date(d)
  x.setHours(0, 0, 0, 0)
  return x
}

export function isSameDay(a, b) {
  if (!a || !b) return false
  const x = new Date(a)
  const y = new Date(b)
  return x.getFullYear() === y.getFullYear() && x.getMonth() === y.getMonth() && x.getDate() === y.getDate()
}

export function addMonths(date, n) {
  const x = new Date(date.getFullYear(), date.getMonth() + n, 1)
  return x
}

export function addDays(date, n) {
  const x = new Date(date)
  x.setDate(x.getDate() + n)
  return x
}

// Monday-based weekday index (0 = Mon … 6 = Sun)
function mondayIndex(date) {
  return (date.getDay() + 6) % 7
}

// All days rendered for a month grid, including leading/trailing days
// from neighbouring months (so every week has 7 cells). 6 weeks max.
export function monthMatrix(viewDate) {
  const year = viewDate.getFullYear()
  const month = viewDate.getMonth()
  const first = new Date(year, month, 1)
  const gridStart = addDays(startOfDay(first), -mondayIndex(first))

  const weeks = []
  let cursor = gridStart
  // Always render full weeks until we've passed the month; cap at 6 weeks.
  for (let w = 0; w < 6; w++) {
    const days = []
    for (let d = 0; d < 7; d++) {
      days.push(cursor)
      cursor = addDays(cursor, 1)
    }
    weeks.push(days)
    // Stop early after 5 weeks if the next week is entirely in the next month.
    if (w >= 4 && cursor.getMonth() !== month) break
  }
  return weeks
}

// The visible ISO window for a given month grid (first cell → last cell, end exclusive).
export function monthRangeIso(viewDate) {
  const weeks = monthMatrix(viewDate)
  const first = weeks[0][0]
  const last = addDays(weeks[weeks.length - 1][6], 1)
  return { from: startOfDay(first).toISOString(), to: startOfDay(last).toISOString() }
}

// The Mon–Sun week that contains the given date.
export function weekDays(viewDate) {
  const start = addDays(startOfDay(viewDate), -mondayIndex(viewDate))
  return Array.from({ length: 7 }, (_, i) => addDays(start, i))
}

export function weekRangeIso(viewDate) {
  const days = weekDays(viewDate)
  return { from: startOfDay(days[0]).toISOString(), to: startOfDay(addDays(days[6], 1)).toISOString() }
}

export function monthLabel(date) {
  const raw = date.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

export function weekLabel(date) {
  const days = weekDays(date)
  const a = days[0]
  const b = days[6]
  const sameMonth = a.getMonth() === b.getMonth()
  const fmtDay = (d) => d.toLocaleDateString('pt-BR', { day: '2-digit', month: sameMonth ? undefined : 'short' })
  const month = b.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })
  return `${fmtDay(a)} – ${fmtDay(b)} · ${month.charAt(0).toUpperCase() + month.slice(1)}`
}

// Group calendar events by local day key (YYYY-M-D).
export function dayKey(d) {
  const x = new Date(d)
  return `${x.getFullYear()}-${x.getMonth()}-${x.getDate()}`
}

export function groupEventsByDay(events = []) {
  const map = new Map()
  for (const ev of events) {
    if (!ev?.start) continue
    const key = dayKey(ev.start)
    if (!map.has(key)) map.set(key, [])
    map.get(key).push(ev)
  }
  // Sort each day's events chronologically.
  for (const list of map.values()) {
    list.sort((a, b) => new Date(a.start) - new Date(b.start))
  }
  return map
}
