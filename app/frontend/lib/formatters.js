// Display formatters. Backend sends ISO 8601 dates + money in cents — format here.
const LOCALE = 'pt-BR'

export function dt(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString(LOCALE, {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  })
}

export function shortDt(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString(LOCALE, { day: '2-digit', month: 'short' })
}

export function date(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString(LOCALE, { day: '2-digit', month: 'long', year: 'numeric' })
}

export function time(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString(LOCALE, { hour: '2-digit', minute: '2-digit' })
}

export function brl(cents) {
  const value = (Number(cents) || 0) / 100
  return value.toLocaleString(LOCALE, { style: 'currency', currency: 'BRL' })
}

// Currency input mask: free-typed digits → "1.234,56" (BR money). Drives a
// controlled <Input>; pair with centsFromMasked() to read the value back.
export function maskCurrency(value) {
  const digits = String(value ?? '').replace(/\D/g, '')
  if (!digits) return ''
  const cents = parseInt(digits, 10)
  return (cents / 100).toLocaleString(LOCALE, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

// Integer cents from a masked currency string ("1.234,56" → 123456).
export function centsFromMasked(value) {
  const digits = String(value ?? '').replace(/\D/g, '')
  return digits ? parseInt(digits, 10) : 0
}

export function compact(n) {
  return Number(n || 0).toLocaleString(LOCALE, { notation: 'compact', maximumFractionDigits: 1 })
}

// Human file size: 0 B, 12 KB, 3,4 MB, 1,1 GB.
export function fileSize(bytes) {
  const b = Number(bytes) || 0
  if (b < 1024) return `${b} B`
  const units = ['KB', 'MB', 'GB', 'TB']
  let value = b / 1024
  let i = 0
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024
    i += 1
  }
  return `${value.toLocaleString(LOCALE, { maximumFractionDigits: value < 10 ? 1 : 0 })} ${units[i]}`
}

// "há 3 dias", "em 2 dias", "hoje"
export function relativeDay(iso) {
  if (!iso) return null
  const diff = Math.round((new Date(iso) - new Date()) / 86400000)
  if (diff === 0) return { text: 'hoje', tone: 'danger' }
  if (diff === 1) return { text: 'amanhã', tone: 'warning' }
  if (diff === -1) return { text: 'ontem', tone: 'muted' }
  if (diff < 0) return { text: `${Math.abs(diff)}d atraso`, tone: 'danger' }
  if (diff <= 3) return { text: `em ${diff}d`, tone: 'warning' }
  return { text: `em ${diff}d`, tone: 'muted' }
}
